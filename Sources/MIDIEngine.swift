import CoreMIDI
import Foundation
import Combine

// MARK: - MIDIEngine
//
// Keystation ──USB──▶ [input port] ──▶ remap (stacked) ──▶ [virtual source "OATS KEYMAP"]
//                                                       └──▶ [optional hardware destination]
//
// The virtual source means Logic / Ableton / MA3 / anything just sees a MIDI device
// called OATS KEYMAP in its input list. No IAC bus, no loopback driver, no routing hacks.
//
// Remapping happens on CoreMIDI's own high-priority thread. Everything that thread
// touches lives behind `lock`; the @Published mirrors exist only for the UI.

struct Port: Identifiable, Hashable {
    let id: MIDIEndpointRef
    let name: String
}

private struct OutSpec {
    let note: UInt8
    let ch: UInt8            // 1...16
    let vel: UInt8?          // nil = pass through
    let mute: Bool
    let label: String
}

final class MIDIEngine: ObservableObject {

    // UI-facing
    @Published private(set) var sources: [Port] = []
    @Published private(set) var destinations: [Port] = []
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var flash: Int? = nil          // key that just fired
    @Published var status: String = "Starting"

    @Published var selectedSource: MIDIEndpointRef = 0 { didSet { connect(selectedSource) } }
    @Published var selectedDest: MIDIEndpointRef = 0     { didSet { sync { _dest = selectedDest } } }
    @Published var armed = false {
        didSet {
            sync { _armed = armed }
            if !armed { panic() }
            status = armed ? "Armed" : "Idle"
        }
    }
    @Published var inChannel = 1 { didSet { sync { _inCh = UInt8(min(16, max(1, inChannel))) } } }

    struct LogLine: Identifiable { let id = UUID(); let text: String }

    // CoreMIDI
    private var client    = MIDIClientRef()
    private var inPort    = MIDIPortRef()
    private var outPort   = MIDIPortRef()
    private var virtualSrc = MIDIEndpointRef()
    private var connected: MIDIEndpointRef = 0

    // engine-thread state
    private let lock = NSLock()
    private var _table = [[OutSpec]?](repeating: nil, count: 128)
    private var _held  = [[(UInt8, UInt8)]?](repeating: nil, count: 128)   // (noteOffStatus, note)
    private var _inCh: UInt8 = 1
    private var _armed = false
    private var _dest: MIDIEndpointRef = 0
    private var runningStatus: UInt8 = 0

    private func sync(_ body: () -> Void) { lock.lock(); body(); lock.unlock() }

    // MARK: Lifecycle

    init() {
        var st = MIDIClientCreateWithBlock("OATS KEYMAP" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        guard st == noErr else { status = "MIDI client failed (\(st))"; return }

        st = MIDIInputPortCreateWithBlock(client, "OATS IN" as CFString, &inPort) { [weak self] listPtr, _ in
            self?.read(listPtr)
        }
        guard st == noErr else { status = "Input port failed (\(st))"; return }

        MIDIOutputPortCreate(client, "OATS OUT" as CFString, &outPort)

        // The app's own published endpoint. This is the whole point.
        st = MIDISourceCreate(client, "OATS KEYMAP" as CFString, &virtualSrc)
        if st != noErr { status = "Virtual source failed (\(st))" }

        refresh()
        status = "Idle"
    }

    deinit {
        if virtualSrc != 0 { MIDIEndpointDispose(virtualSrc) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: Ports

    func refresh() {
        var s: [Port] = [], d: [Port] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let ep = MIDIGetSource(i)
            if ep == virtualSrc { continue }                 // never feed ourselves
            s.append(Port(id: ep, name: Self.displayName(ep)))
        }
        for i in 0..<MIDIGetNumberOfDestinations() {
            let ep = MIDIGetDestination(i)
            d.append(Port(id: ep, name: Self.displayName(ep)))
        }
        sources = s
        destinations = d
        if !s.contains(where: { $0.id == selectedSource }) { selectedSource = s.first?.id ?? 0 }
        if !d.contains(where: { $0.id == selectedDest })   { selectedDest = 0 }
    }

    private func connect(_ ep: MIDIEndpointRef) {
        if connected != 0 { MIDIPortDisconnectSource(inPort, connected); connected = 0 }
        guard ep != 0 else { return }
        if MIDIPortConnectSource(inPort, ep, nil) == noErr { connected = ep }
    }

    static func displayName(_ ep: MIDIEndpointRef) -> String {
        var cf: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(ep, kMIDIPropertyDisplayName, &cf) == noErr,
              let s = cf?.takeRetainedValue() else { return "Unknown" }
        return s as String
    }

    // MARK: Map

    /// Flatten the document's stacks into the 128-slot lookup the MIDI thread reads.
    func load(_ map: [Int: [Assignment]]) {
        var t = [[OutSpec]?](repeating: nil, count: 128)
        for (n, stack) in map where (0...127).contains(n) {
            t[n] = stack.map {
                OutSpec(note: UInt8(min(127, max(0, $0.note))),
                        ch:   UInt8(min(16, max(1, $0.ch))),
                        vel:  $0.vel.map { UInt8(min(127, max(1, $0))) },
                        mute: $0.mute,
                        label: $0.label)
            }
        }
        sync { _table = t }
    }

    // MARK: Read

    private func read(_ listPtr: UnsafePointer<MIDIPacketList>) {
        for packet in listPtr.unsafeSequence() {
            let len = Int(packet.pointee.length)
            guard len > 0 else { continue }
            withUnsafeBytes(of: packet.pointee.data) { raw in
                var bytes = [UInt8]()
                bytes.reserveCapacity(len)
                for i in 0..<min(len, raw.count) { bytes.append(raw[i]) }
                parse(bytes)
            }
        }
    }

    /// Split a packet into channel-voice messages. Handles running status.
    /// System messages (SysEx, clock) are ignored — a Keystation doesn't send them.
    private func parse(_ b: [UInt8]) {
        var i = 0
        while i < b.count {
            let status: UInt8
            if b[i] & 0x80 != 0 {
                guard b[i] < 0xF0 else { runningStatus = 0; return }
                status = b[i]
                runningStatus = status
                i += 1
            } else {
                guard runningStatus != 0 else { return }
                status = runningStatus
            }
            let kind = status & 0xF0
            let need = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
            guard i + need <= b.count else { return }
            let d1 = b[i]
            let d2 = need == 2 ? b[i + 1] : 0
            i += need
            handle(status, d1, d2)
        }
    }

    // MARK: The remap

    private func handle(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
        let kind = status & 0xF0
        let ch = (status & 0x0F) + 1

        lock.lock()
        let inCh = _inCh
        let live = _armed
        let specs: [OutSpec]? = (d1 < 128) ? _table[Int(d1)] : nil
        lock.unlock()

        // Not a note, or the wrong channel — hand it straight through untouched.
        guard kind == 0x90 || kind == 0x80, ch == inCh else {
            if live { emit([status, d1, d2]) }
            return
        }

        let n = Int(d1)
        let isOn = (kind == 0x90 && d2 > 0)

        guard let stack = specs, !stack.isEmpty else {
            if live { emit([status, d1, d2]) }
            if isOn { report(n, lines: nil) }
            return
        }

        if isOn {
            var fired: [(UInt8, UInt8)] = []
            var seen = Set<UInt16>()
            var lines: [String] = []

            for s in stack where !s.mute {
                let tag = UInt16(s.ch) << 8 | UInt16(s.note)
                if seen.contains(tag) { continue }          // never double-fire one target
                seen.insert(tag)
                let v = s.vel ?? d2
                if live { emit([0x90 | (s.ch - 1), s.note, v]) }
                fired.append((0x80 | (s.ch - 1), s.note))
                lines.append("\(s.note) \(Notes.name(Int(s.note))) ch\(s.ch) v\(v)"
                             + (s.label.isEmpty ? "" : " · \(s.label)"))
            }

            lock.lock()
            let stale = _held[n] ?? []
            _held[n] = fired
            lock.unlock()

            if live { for (st, note) in stale { emit([st, note, 0]) } }   // retrigger safety
            report(n, lines: lines)

        } else {
            lock.lock()
            let open = _held[n] ?? []
            _held[n] = nil
            lock.unlock()

            // Release exactly what was pressed, even if the map changed mid-note.
            if live { for (st, note) in open { emit([st, note, 0]) } }
        }
    }

    // MARK: Send

    private func emit(_ bytes: [UInt8]) {
        guard bytes.count > 0, bytes.count <= 3 else { return }
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = UInt16(bytes.count)
        withUnsafeMutableBytes(of: &packet.data) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
        }
        var list = MIDIPacketList(numPackets: 1, packet: packet)

        if virtualSrc != 0 { MIDIReceived(virtualSrc, &list) }

        lock.lock(); let dest = _dest; lock.unlock()
        if dest != 0 { MIDISend(outPort, dest, &list) }
    }

    /// Fire a message by hand — used for registers/stops, which are just held notes.
    func sendRaw(_ bytes: [UInt8]) { emit(bytes) }

    /// Kill everything that is currently sounding, then All Notes Off on all 16 channels.
    func panic() {
        lock.lock()
        let all = _held
        _held = [[(UInt8, UInt8)]?](repeating: nil, count: 128)
        lock.unlock()

        for group in all { for (st, n) in group ?? [] { emit([st, n, 0]) } }
        for ch in 0..<16 {
            emit([0xB0 | UInt8(ch), 123, 0])                 // All Notes Off
            emit([0xB0 | UInt8(ch), 121, 0])                 // Reset All Controllers
        }
    }

    // MARK: UI feedback (main thread, note-on only)

    private func report(_ inNote: Int, lines: [String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flash = inNote
            let head = "\(inNote) \(Notes.name(inNote)) → "
            let body: String
            if let lines {
                body = lines.isEmpty ? "all layers muted" : lines.joined(separator: "  +  ")
            } else {
                body = "unmapped, passed"
            }
            self.log.insert(LogLine(text: head + body), at: 0)
            if self.log.count > 60 { self.log.removeLast() }
        }
    }
}
