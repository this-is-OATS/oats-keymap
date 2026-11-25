import SwiftUI
import Combine

enum Tool: String, CaseIterable { case edit = "Edit", paint = "Paint", range = "Range" }
enum Brush: String, CaseIterable { case set = "Set", stack = "Stack" }

final class AppModel: ObservableObject {

    @Published var km = Keymap()          { didSet { engine.load(km.map) } }
    @Published var armedCh = 10
    @Published var tool: Tool = .edit
    @Published var brush: Brush = .set
    @Published var sel: Int? = nil
    @Published var rangeA: Int? = nil
    @Published var rangeB: Int? = nil
    @Published var rangeBase = 36
    @Published var layerOffset = 12
    @Published var naming: NoteNaming = .c5 { didSet { Notes.naming = naming; objectWillChange.send() } }
    @Published var lastAction = ""
    @Published var padAssignMode = false

    // Controller mapping
    @Published var learnMode = false
    @Published var learning: CtlTarget? = nil
    @Published var ctlBindings: [CtlBinding] = ControlStore.load() { didSet { ControlStore.save(ctlBindings) } }

    private var bag = Set<AnyCancellable>()

    let engine = MIDIEngine()

    init() {
        Notes.naming = .c5
        engine.inChannel = km.inChannel
        engine.load(km.map)

        engine.onControl = { [weak self] t in self?.handleControl(t) }

        // Edit follows the hands: press a key on the Keystation and the editor jumps to it.
        engine.$flash
            .compactMap { $0 }
            .sink { [weak self] n in
                guard let self, self.tool == .edit else { return }
                self.sel = n
            }
            .store(in: &bag)
    }

    // MARK: Controller mapping

    func binding(for t: CtlTarget) -> CtlBinding? { ctlBindings.first { $0.target == t } }

    func handleControl(_ t: CtlTrigger) {
        if learnMode {
            guard let target = learning else { return }
            ctlBindings.removeAll { $0.target == target || $0.trigger == t }
            ctlBindings.append(CtlBinding(trigger: t, target: target))
            lastAction = "Mapped \(t.text) → \(target.title(self))"
            learning = nil
            return
        }
        for b in ctlBindings where b.trigger == t { perform(b.target) }
    }

    func perform(_ t: CtlTarget) {
        switch t {
        case .pad(let slot):
            if let r = pads.first(where: { $0.padSlot == slot }), r.known { tapPad(r) }
        case .rank(let board):
            if let r = km.organ.ranks.first(where: { $0.board == board }) { isPulled(r) ? drop(r) : pull(r) }
        case .gel(let c):
            armedCh = min(16, max(1, c))
        case .panic:
            engine.panic()
        case .arm:
            engine.armed.toggle()
        case .clearLatches:
            clearPadLatches()
        }
    }

    func unbind(_ b: CtlBinding) { ctlBindings.removeAll { $0.id == b.id } }
    func clearBindings() { ctlBindings.removeAll() }

    var bed: Keybed { Keybed(low: km.plot.low, high: km.high) }
    var collisions: [Collision] { km.collisions() }
    var collidingKeys: Set<Int> { km.collidingKeys }

    func stack(_ n: Int) -> [Assignment] { km.map[n] ?? [] }

    // MARK: Mutation

    private func touched() { engine.load(km.map); objectWillChange.send() }

    func apply(to n: Int) {
        switch brush {
        case .stack:
            let base = km.map[n]?.first?.note ?? n
            km.map[n, default: []].append(Assignment(note: base, ch: armedCh))
        case .set:
            let base = km.map[n]?.first?.note ?? n
            km.map[n] = [Assignment(note: base, ch: armedCh)]
        }
        touched()
    }

    func addLayer(to n: Int) {
        let base = km.map[n]?.last?.note ?? n
        km.map[n, default: []].append(Assignment(note: base, ch: armedCh))
        touched()
    }

    func removeLayer(_ i: Int, from n: Int) {
        guard var s = km.map[n], s.indices.contains(i) else { return }
        s.remove(at: i)
        if s.isEmpty { km.map[n] = nil } else { km.map[n] = s }
        if km.map[n] == nil && sel == n { sel = nil }
        touched()
    }

    func update(_ n: Int, _ i: Int, _ change: (inout Assignment) -> Void) {
        guard var s = km.map[n], s.indices.contains(i) else { return }
        change(&s[i])
        km.map[n] = s
        touched()
    }

    func identity() {
        for n in km.plot.low...km.high { km.map[n] = [Assignment(note: n, ch: armedCh)] }
        touched()
    }

    func clearAll() {
        km.map.removeAll(); sel = nil; rangeA = nil; rangeB = nil
        touched()
    }

    /// Add one layer to every mapped key, offset from its layer-1 note. +12 = octave double.
    func stackLayerEverywhere() {
        for (n, s) in km.map {
            guard let first = s.first else { continue }
            km.map[n]?.append(Assignment(note: first.note + layerOffset, ch: armedCh))
        }
        touched()
    }

    func dropTopLayer() {
        for (n, s) in km.map where s.count > 1 { km.map[n] = Array(s.dropLast()) }
        touched()
    }

    // MARK: Range

    func mapRangeAscending() {
        guard let a = rangeA, let b = rangeB else { return }
        let lo = min(a, b), hi = max(a, b)
        for (k, n) in (lo...hi).enumerated() {
            let asn = Assignment(note: rangeBase + k, ch: armedCh)
            if brush == .stack { km.map[n, default: []].append(asn) } else { km.map[n] = [asn] }
        }
        touched()
    }

    func clearRange() {
        guard let a = rangeA, let b = rangeB else { return }
        for n in min(a, b)...max(a, b) { km.map[n] = nil }
        rangeA = nil; rangeB = nil
        touched()
    }

    // MARK: Touch routing from the plot

    func hit(_ n: Int, dragging: Bool) {
        switch tool {
        case .paint:
            apply(to: n)
        case .edit:
            guard !dragging else { return }
            sel = (sel == n) ? nil : n
        case .range:
            guard !dragging else { return }
            if rangeA == nil || rangeB != nil { rangeA = n; rangeB = nil } else { rangeB = n }
        }
    }

    var rangeContains: ClosedRange<Int>? {
        guard let a = rangeA, let b = rangeB else { return nil }
        return min(a, b)...max(a, b)
    }

    // MARK: Ranks — pulling and dropping stops

    /// Pull a stop: add a layer on every plot key the rank actually has a pipe for.
    /// Keys outside the rank's compass get nothing, because the organ would do nothing.
    func pull(_ r: Rank) {
        var added = 0
        for n in km.plot.low...km.high where r.covers(n) {
            let already = (km.map[n] ?? []).contains { $0.board == r.board }
            guard !already else { continue }
            km.map[n, default: []].append(
                Assignment(note: n, ch: r.channel, label: r.name, board: r.board))
            added += 1
        }
        lastAction = added > 0 ? "Pulled \(r.name) — \(added) keys" : "\(r.name) already pulled"
        touched()
    }

    func drop(_ r: Rank) {
        for (n, s) in km.map {
            let kept = s.filter { $0.board != r.board }
            km.map[n] = kept.isEmpty ? nil : kept
        }
        lastAction = "Dropped \(r.name)"
        touched()
    }

    func isPulled(_ r: Rank) -> Bool {
        km.map.values.contains { $0.contains { $0.board == r.board } }
    }

    /// How many keys on the plot would fire a pipe on this rank right now.
    func speaking(_ r: Rank) -> Int {
        km.map.reduce(0) { acc, kv in
            acc + (kv.value.contains { $0.board == r.board && !$0.mute && r.covers($0.note) } ? 1 : 0)
        }
    }

    /// Keys that are mapped but land outside every rank on their channel — silent keys.
    var deadKeys: Set<Int> {
        var out = Set<Int>()
        for (n, stack) in km.map {
            let anySpeaks = stack.contains { a in
                !a.mute && (!km.organ.ranksSpeaking(note: a.note, channel: a.ch).isEmpty
                            || (a.ch == 10 && km.organ.percussion.contains { $0.note == a.note }))
            }
            if !anySpeaks { out.insert(n) }
        }
        return out
    }

    // MARK: Registers

    func fireRegister(_ reg: Register) {
        guard let note = reg.note else { lastAction = "Register \(reg.number) has no note yet"; return }
        engine.sendRaw([0x90 | UInt8(max(0, reg.channel - 1)), UInt8(note), 100])
        engine.sendRaw([0x80 | UInt8(max(0, reg.channel - 1)), UInt8(note), 0])
        lastAction = "Fired register \(reg.number) — \(reg.name)"
    }

    // MARK: Touchpads — the twelve register stops, mirrored to the screen

    /// Registers that hold a pad slot, ordered by slot. This is the top strip.
    var pads: [Register] {
        km.organ.registers
            .filter { $0.padSlot != nil }
            .sorted { ($0.padSlot ?? 0) < ($1.padSlot ?? 0) }
    }

    /// Tap a pad: fire its trigger note as a pulse, and flip the operator's visual latch.
    /// The organ can't be read back, so `latched` is a reminder, not ground truth.
    func tapPad(_ reg: Register) {
        guard let i = km.organ.registers.firstIndex(where: { $0.id == reg.id }) else { return }
        fireRegister(reg)
        km.organ.registers[i].latched.toggle()
        touched()
    }

    func setPadNote(_ reg: Register, _ note: Int?) {
        guard let i = km.organ.registers.firstIndex(where: { $0.id == reg.id }) else { return }
        km.organ.registers[i].note = note
        touched()
    }

    func setPadChannel(_ reg: Register, _ ch: Int) {
        guard let i = km.organ.registers.firstIndex(where: { $0.id == reg.id }) else { return }
        km.organ.registers[i].channel = min(16, max(1, ch))
        touched()
    }

    func setPadName(_ reg: Register, _ name: String) {
        guard let i = km.organ.registers.firstIndex(where: { $0.id == reg.id }) else { return }
        km.organ.registers[i].name = name
        touched()
    }

    /// Reset every lit pad — send nothing, just clear the operator's visual state.
    func clearPadLatches() {
        for i in km.organ.registers.indices { km.organ.registers[i].latched = false }
        touched()
    }

    func setRegisterNote(_ i: Int, _ note: Int?) {
        guard km.organ.registers.indices.contains(i) else { return }
        km.organ.registers[i].note = note
        touched()
    }

    // MARK: Hookup sheet — the thing an organ tech reads

    func hookupSheet() -> String {
        var out = ["OATS MIDI KEYMAP v\(APP_VERSION) — HOOKUP",
                   km.name,
                   km.organ.name + " · " + km.organ.revision,
                   "Keystation in on ch \(engine.inChannel), board at octave \(km.board.octaveShift)",
                   ""]
        if !km.organ.unconfirmed.isEmpty {
            out.append("!! UNCONFIRMED RANKS — DO NOT WIRE FROM THESE:")
            for r in km.organ.unconfirmed { out.append("   Bd \(r.board)  \(r.name)  —  \(r.caveat)") }
            out.append("")
        }
        out.append("KEY    IN   L  OUT  NOTE   CH   BOARD / PIN                    LABEL")
        out.append("-----  ---  -  ---  -----  ---  -----------------------------  -----")
        for n in km.map.keys.sorted() {
            for (i, a) in (km.map[n] ?? []).enumerated() {
                let hook = km.organ.hookup(note: a.note, channel: a.ch)
                let key = i == 0 ? Notes.name(n).padding(toLength: 5, withPad: " ", startingAt: 0) : "     "
                let inn = i == 0 ? String(n).padding(toLength: 3, withPad: " ", startingAt: 0) : "   "
                out.append("\(key)  \(inn)  \(i+1)  "
                    + String(a.note).padding(toLength: 3, withPad: " ", startingAt: 0) + "  "
                    + Notes.name(a.note).padding(toLength: 5, withPad: " ", startingAt: 0) + "  "
                    + String(a.ch).padding(toLength: 3, withPad: " ", startingAt: 0) + "  "
                    + hook.padding(toLength: 29, withPad: " ", startingAt: 0) + "  "
                    + (a.mute ? "MUTED " : "") + a.label)
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: Documents

    func load(_ new: Keymap) {
        km = new
        naming = NoteNaming(rawValue: new.noteConvention) ?? .c5
        Notes.naming = naming
        engine.inChannel = new.inChannel
        engine.load(new.map)
        sel = nil; rangeA = nil; rangeB = nil
    }

    func encoded() throws -> Data {
        var out = km
        out.noteConvention = naming.rawValue
        out.inChannel = engine.inChannel
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(out)
    }
}
