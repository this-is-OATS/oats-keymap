import SwiftUI
import UniformTypeIdentifiers
import CoreMIDI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Shell

struct ContentView: View {
    @StateObject private var m = AppModel()
    @State private var importing = false
    @State private var exporting = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Header(m: m, importing: $importing, exporting: $exporting)
                RegisterPads(m: m)
                GelRail(m: m)
                PlotPanel(m: m)
                Workbench(m: m)
                ToolRail(m: m, e: m.engine)
            }
            Divider().background(Deck.rule)
            Side(m: m)
                .frame(width: 440)
        }
        .background(Deck.deck)
        .foregroundColor(Deck.ink)
        .font(.system(size: UI.f(12), design: .monospaced))
        #if os(macOS)
        .frame(minWidth: 1280, minHeight: 760)
        #endif
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let km = try? JSONDecoder().decode(Keymap.self, from: data) else { return }
            m.load(km)
        }
        .fileExporter(isPresented: $exporting,
                      document: JSONDoc(data: (try? m.encoded()) ?? Data()),
                      contentType: .json,
                      defaultFilename: m.km.name) { _ in }
    }
}

struct JSONDoc: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Chrome bits

struct Lbl: View {
    let t: String
    init(_ t: String) { self.t = t }
    var body: some View {
        Text(t.uppercased())
            .font(.system(size: UI.f(9), weight: .regular, design: .monospaced))
            .tracking(1.6)
            .foregroundColor(Deck.dim)
            .fixedSize()
    }
}

struct Card<C: View>: View {
    let title: String
    var trailing: String = ""
    @ViewBuilder let content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Lbl(title); Spacer(); if !trailing.isEmpty { Lbl(trailing) } }
            content
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        Divider().background(Deck.rule)
    }
}

struct Seg<T: Hashable>: View {
    @Binding var value: T
    let options: [(T, String)]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { opt in
                Button { value = opt.0 } label: {
                    Text(opt.1.uppercased())
                        .font(.system(size: UI.f(9), weight: value == opt.0 ? .bold : .regular, design: .monospaced))
                        .tracking(1.3)
                        .foregroundColor(value == opt.0 ? .black : Deck.ink)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(value == opt.0 ? Deck.armed : Deck.panel2)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct TBtn: View {
    let t: String
    var danger = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(t.uppercased())
                .font(.system(size: UI.f(9), design: .monospaced)).tracking(1.3)
                .foregroundColor(danger ? Deck.bad : Deck.ink)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(Deck.panel2)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(danger ? Deck.bad.opacity(0.4) : Deck.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// Dropdown that honours the 14pt floor. Stock Picker on macOS ignores .font().
struct BigPicker<T: Hashable>: View {
    @Binding var value: T
    let options: [(T, String)]
    var tint: Color? = nil

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i].1) { value = options[i].0 }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first(where: { $0.0 == value })?.1 ?? "—")
                    .font(.system(size: UI.floor, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("▾")
                    .font(.system(size: UI.floor, design: .monospaced))
                    .foregroundColor(Deck.dim)
            }
            .foregroundColor(Deck.ink)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(tint.map { $0.opacity(0.35) } ?? Deck.panel2)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

struct Stepper2: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String = ""
    var body: some View {
        HStack(spacing: 8) {
            Lbl(label).frame(width: 100, alignment: .leading)
            HStack(spacing: 0) {
                Button { value = max(range.lowerBound, value - 1) } label: {
                    Text("−").frame(width: 42, height: 40).background(Deck.panel2)
                }.buttonStyle(.plain)
                Text("\(value)")
                    .font(.system(size: UI.f(12), weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity).frame(height: 40).background(Deck.deck)
                if !suffix.isEmpty {
                    Text(suffix).font(.system(size: UI.f(9), design: .monospaced))
                        .foregroundColor(Deck.dim).lineLimit(1).fixedSize().padding(.trailing, 8)
                        .frame(height: 40).background(Deck.deck)
                }
                Button { value = min(range.upperBound, value + 1) } label: {
                    Text("+").frame(width: 42, height: 40).background(Deck.panel2)
                }.buttonStyle(.plain)
            }
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

// MARK: - Header

struct Header: View {
    @ObservedObject var m: AppModel
    @Binding var importing: Bool
    @Binding var exporting: Bool
    @State private var hookup = false

    var body: some View {
        HStack(spacing: 12) {
            Text("OATS MIDI KEYMAP")
                .font(.system(size: UI.f(12), weight: .bold, design: .monospaced)).tracking(3)
                .lineLimit(1).fixedSize()
            Text("v\(APP_VERSION)")
                .font(.system(size: UI.f(9), design: .monospaced)).foregroundColor(Deck.dim)

            TextField("Instrument", text: $m.km.name)
                .textFieldStyle(.plain)
                .padding(7)
                .background(Deck.deck)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
                .frame(minWidth: 150, maxWidth: 420)

            Spacer()
            TBtn(t: "Open")  { importing = true }.frame(width: 96)
            TBtn(t: "Save")  { exporting = true }.frame(width: 96)
            TBtn(t: "Hookup") { hookup = true }.frame(width: 96)
            LearnButton(m: m).frame(width: 96)
            TBtn(t: "Panic", danger: true) { m.engine.panic() }.frame(width: 96)
                .learnable(m, .panic)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Deck.panel)
        .sheet(isPresented: $hookup) { HookupSheet(m: m) }
        Divider().background(Deck.rule)
    }
}

struct HookupSheet: View {
    @ObservedObject var m: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Lbl("Hookup sheet")
                Spacer()
                TBtn(t: "Copy") {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(m.hookupSheet(), forType: .string)
                    #else
                    UIPasteboard.general.string = m.hookupSheet()
                    #endif
                }.frame(width: 116)
                TBtn(t: "Close") { dismiss() }.frame(width: 116)
            }
            .padding(12).background(Deck.panel)

            ScrollView([.horizontal, .vertical]) {
                Text(m.hookupSheet())
                    .font(.system(size: UI.f(11), design: .monospaced))
                    .foregroundColor(Deck.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Deck.deck)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Deck.deck)
    }
}

// MARK: - Gel rail

struct GelRail: View {
    @ObservedObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 14) {
                Lbl("Out channel — arm one, then drag the keys")
                Spacer()
                Lbl("Brush")
                Seg(value: $m.brush, options: Brush.allCases.map { ($0, $0.rawValue) })
            }
            HStack(spacing: 5) {
                ForEach(1...16, id: \.self) { c in
                    Button { m.armedCh = c } label: {
                        ZStack(alignment: .bottom) {
                            Gel.color(c)
                            Text("\(c)")
                                .font(.system(size: UI.f(10), weight: .bold, design: .monospaced))
                                .foregroundColor(.black).padding(.bottom, 3)
                        }
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .stroke(Deck.armed, lineWidth: m.armedCh == c ? 2 : 0))
                        .offset(y: m.armedCh == c ? -3 : 0)
                    }
                    .buttonStyle(.plain)
                    .learnable(m, .gel(c))
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
        Divider().background(Deck.rule)
    }
}

// MARK: - Plot

struct PlotPanel: View {
    @ObservedObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 14) {
                Lbl("\(m.km.plot.keys)-key plot · notes \(m.km.plot.low)–\(m.km.high) · \(m.km.map.count) keys / \(m.km.assignmentCount) assignments")
                Text("Board reaches \(m.km.boardLow)–\(m.km.boardHigh) (octave \(m.km.board.octaveShift > 0 ? "+" : "")\(m.km.board.octaveShift))")
                    .font(.system(size: UI.f(9), design: .monospaced)).foregroundColor(Deck.armed)
                if !m.collisions.isEmpty {
                    Text("⚠ \(m.collisions.count) collision\(m.collisions.count > 1 ? "s" : "")")
                        .font(.system(size: UI.f(9), design: .monospaced)).foregroundColor(Deck.bad)
                }
                Spacer()
            }
            PlotView(m: m, engine: m.engine)
                .frame(height: UI.keybedHeight)
                .padding(8)
                .background(Deck.ebony)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - Workbench
// The room the oversized keybed used to take. Editors live here, at reading size.

struct Workbench: View {
    @ObservedObject var m: AppModel
    var body: some View {
        Divider().background(Deck.rule)
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    KeyCard(m: m)
                    if m.tool == .range { RangeCard(m: m) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                Divider().background(Deck.rule)
                VStack(spacing: 0) {
                    LayerCard(m: m)
                    PlotCard(m: m)
                    if !m.collisions.isEmpty { ClashCard(m: m) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                Divider().background(Deck.rule)
                VStack(spacing: 0) {
                    LiveCard(m: m, e: m.engine)
                    MonitorCard(m: m, e: m.engine)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Deck.panel)
    }
}

// MARK: - Tool rail

struct ToolRail: View {
    @ObservedObject var m: AppModel
    @ObservedObject var e: MIDIEngine
    var body: some View {
        Divider().background(Deck.rule)
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 16) {
            Lbl("Tool")
            Seg(value: $m.tool, options: Tool.allCases.map { ($0, $0.rawValue) })

            Lbl("In ch")
            BigPicker(value: $e.inChannel, options: (1...16).map { ($0, "CH \($0)") })
                .frame(width: 120)

            Lbl("Names")
            Seg(value: $m.naming, options: NoteNaming.allCases.map { ($0, $0.rawValue) })

            Spacer()
            TBtn(t: "Identity") { m.identity() }.frame(width: 136)
            TBtn(t: "Clear all", danger: true) { m.clearAll() }.frame(width: 136)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        }
        .background(Deck.panel)
    }
}

// MARK: - Sidebar

struct Side: View {
    @ObservedObject var m: AppModel
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ControllerCard(m: m, e: m.engine)
                RankCard(m: m)
                RegisterCard(m: m)
                PercussionCard(m: m)
            }
        }
        .background(Deck.panel)
    }
}

// MARK: The assignment stack

struct KeyCard: View {
    @ObservedObject var m: AppModel
    var body: some View {
        Card(title: "Key", trailing: m.sel.map { "IN \($0) · \(Notes.name($0))" } ?? "—") {
            if let n = m.sel {
                VStack(spacing: 8) {
                    ForEach(Array(m.stack(n).enumerated()), id: \.element.id) { i, a in
                        LayerRow(m: m, note: n, index: i, a: a)
                    }
                    Button { m.addLayer(to: n) } label: {
                        Text("+ ADD ASSIGNMENT ON CH \(m.armedCh)")
                            .font(.system(size: UI.f(9), design: .monospaced)).tracking(1.4)
                            .foregroundColor(Deck.dim)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Deck.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Press a key on the Keystation, or tap one on the plot.")
                    .font(.system(size: UI.f(11), design: .monospaced)).foregroundColor(Deck.dim2)
            }
        }
    }
}

struct LayerRow: View {
    @ObservedObject var m: AppModel
    let note: Int
    let index: Int
    let a: Assignment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Gel.color(a.ch)).frame(width: 18, height: 18)
                Lbl("Layer \(index + 1)")
                Spacer()
                Button { m.removeLayer(index, from: note) } label: {
                    Text("×").font(.system(size: UI.f(13), design: .monospaced)).foregroundColor(Deck.bad)
                        .frame(width: 32, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Deck.rule, lineWidth: 1))
                }.buttonStyle(.plain)
            }

            Stepper2(label: "Note",
                     value: Binding(get: { a.note },
                                    set: { v in m.update(note, index) { $0.note = min(127, max(0, v)) } }),
                     range: 0...127, suffix: Notes.name(a.note))

            HStack(spacing: 8) {
                Lbl("Channel").frame(width: 100, alignment: .leading)
                BigPicker(value: Binding(get: { a.ch },
                                         set: { v in m.update(note, index) { $0.ch = v } }),
                          options: (1...16).map { ($0, "CH \($0)") },
                          tint: Gel.color(a.ch))
            }

            Stepper2(label: "Velocity",
                     value: Binding(get: { a.vel ?? 0 },
                                    set: { v in m.update(note, index) { $0.vel = v == 0 ? nil : v } }),
                     range: 0...127, suffix: a.vel == nil ? "pass" : "fixed")

            HStack(spacing: 8) {
                Lbl("Label").frame(width: 100, alignment: .leading)
                TextField("kick / cue 12 / sub octave",
                          text: Binding(get: { a.label },
                                        set: { v in m.update(note, index) { $0.label = v } }))
                    .textFieldStyle(.plain).padding(7).background(Deck.deck)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
            }

            HStack(spacing: 6) {
                Text(m.km.organ.hookup(note: a.note, channel: a.ch))
                    .font(.system(size: UI.f(10), weight: .bold, design: .monospaced))
                    .foregroundColor(m.km.organ.hookup(note: a.note, channel: a.ch) == "no pipe"
                                     ? Deck.bad : Gel.color(a.ch))
                Spacer()
            }

            TBtn(t: a.mute ? "Muted" : "Mute", danger: a.mute) {
                m.update(note, index) { $0.mute.toggle() }
            }
        }
        .padding(10)
        .background(Deck.deck)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
    }
}

// MARK: Range

struct RangeCard: View {
    @ObservedObject var m: AppModel
    var label: String {
        guard let a = m.rangeA else { return "click first key" }
        guard let b = m.rangeB else { return "\(Notes.name(a)) → click last key" }
        return "\(Notes.name(min(a,b)))–\(Notes.name(max(a,b))) · \(abs(b-a)+1) keys"
    }
    var body: some View {
        Card(title: "Range", trailing: label) {
            Stepper2(label: "From note", value: $m.rangeBase, range: 0...127, suffix: Notes.name(m.rangeBase))
            HStack(spacing: 6) {
                TBtn(t: "Map ascending") { m.mapRangeAscending() }
                TBtn(t: "Clear", danger: true) { m.clearRange() }
            }
        }
    }
}

// MARK: Bulk layers

struct LayerCard: View {
    @ObservedObject var m: AppModel
    var body: some View {
        Card(title: "Stack a layer", trailing: "every mapped key") {
            Stepper2(label: "Offset", value: $m.layerOffset, range: -48...48, suffix: "semitones")
            TBtn(t: "Add layer on ch \(m.armedCh)") { m.stackLayerEverywhere() }
            TBtn(t: "Drop top layer", danger: true) { m.dropTopLayer() }
        }
    }
}

// MARK: Plot config

struct PlotCard: View {
    @ObservedObject var m: AppModel
    var body: some View {
        Card(title: "Plot") {
            HStack(spacing: 8) {
                Lbl("Keys").frame(width: 100, alignment: .leading)
                BigPicker(value: $m.km.plot.keys,
                          options: [25, 37, 49, 61, 76, 81, 88, 128].map { ($0, "\($0) keys") })
            }
            Stepper2(label: "Low note", value: $m.km.plot.low, range: 0...127, suffix: Notes.name(m.km.plot.low))
            Stepper2(label: "Board oct", value: $m.km.board.octaveShift, range: -3...3, suffix: "shift")
            Text("Dim keys sit outside the 61es keybed at this octave shift — the board can't reach them.")
                .font(.system(size: UI.f(10), design: .monospaced)).foregroundColor(Deck.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Collisions

struct ClashCard: View {
    @ObservedObject var m: AppModel
    var body: some View {
        Card(title: "Collisions", trailing: "\(m.collisions.count)") {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(m.collisions) { c in
                    Text(c.text)
                        .font(.system(size: UI.f(10), design: .monospaced)).foregroundColor(Deck.bad)
                }
                Text("Same channel + note from two live sources. First note-off kills both.")
                    .font(.system(size: UI.f(10), design: .monospaced)).foregroundColor(Deck.dim)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
        }
    }
}

// MARK: Live

struct LiveCard: View {
    @ObservedObject var m: AppModel
    @ObservedObject var e: MIDIEngine
    var body: some View {
        Card(title: "Live engine", trailing: e.status) {
            HStack(spacing: 8) {
                Lbl("MIDI in").frame(width: 100, alignment: .leading)
                BigPicker(value: $e.selectedSource,
                          options: e.sources.map { ($0.id, $0.name) })
            }
            HStack(spacing: 8) {
                Lbl("Also to").frame(width: 100, alignment: .leading)
                BigPicker(value: $e.selectedDest,
                          options: [(MIDIEndpointRef(0), "— none —")] + e.destinations.map { ($0.id, $0.name) })
            }
            Text("Output always appears as a MIDI device called OATS MIDI KEYMAP. Pick it as the input in Logic — no IAC bus needed.")
                .font(.system(size: UI.f(10), design: .monospaced)).foregroundColor(Deck.dim)
                .fixedSize(horizontal: false, vertical: true)

            Button { e.armed.toggle() } label: {
                Text(e.armed ? "DISARM" : "ARM REMAP")
                    .font(.system(size: UI.f(10), weight: .bold, design: .monospaced)).tracking(1.6)
                    .foregroundColor(e.armed ? .black : Deck.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(e.armed ? Deck.armed : Deck.panel2)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
            }
            .buttonStyle(.plain).clipShape(RoundedRectangle(cornerRadius: 3))
            .learnable(m, .arm)

            TBtn(t: "Rescan ports") { e.refresh() }
        }
    }
}

// MARK: Monitor

struct MonitorCard: View {
    @ObservedObject var m: AppModel
    @ObservedObject var e: MIDIEngine
    var body: some View {
        Card(title: "Monitor") {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if e.log.isEmpty {
                        Text("No traffic.").font(.system(size: UI.f(10), design: .monospaced))
                            .foregroundColor(Deck.dim2)
                    }
                    ForEach(e.log) { line in
                        Text(line.text)
                            .font(.system(size: UI.f(10), design: .monospaced))
                            .foregroundColor(Deck.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 160)
            .padding(8)
            .background(Deck.deck)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
        }
    }
}
