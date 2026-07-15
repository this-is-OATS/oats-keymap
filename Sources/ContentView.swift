import SwiftUI
import UniformTypeIdentifiers
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
                ToolRail(m: m, e: m.engine)
            }
            Divider().background(Deck.rule)
            Side(m: m)
                .frame(width: 348)
        }
        .background(Deck.deck)
        .foregroundColor(Deck.ink)
        .font(.system(size: 12, design: .monospaced))
        #if os(macOS)
        .frame(minWidth: 1140, minHeight: 700)
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
            .font(.system(size: 9, weight: .regular, design: .monospaced))
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
                        .font(.system(size: 9, weight: value == opt.0 ? .bold : .regular, design: .monospaced))
                        .tracking(1.3)
                        .foregroundColor(value == opt.0 ? .black : Deck.ink)
                        .padding(.horizontal, 11).padding(.vertical, 7)
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
                .font(.system(size: 9, design: .monospaced)).tracking(1.3)
                .foregroundColor(danger ? Deck.bad : Deck.ink)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Deck.panel2)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(danger ? Deck.bad.opacity(0.4) : Deck.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct Stepper2: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String = ""
    var body: some View {
        HStack(spacing: 8) {
            Lbl(label).frame(width: 62, alignment: .leading)
            HStack(spacing: 0) {
                Button { value = max(range.lowerBound, value - 1) } label: {
                    Text("−").frame(width: 32, height: 30).background(Deck.panel2)
                }.buttonStyle(.plain)
                Text("\(value)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity).frame(height: 30).background(Deck.deck)
                if !suffix.isEmpty {
                    Text(suffix).font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Deck.dim).padding(.trailing, 8)
                        .frame(height: 30).background(Deck.deck)
                }
                Button { value = min(range.upperBound, value + 1) } label: {
                    Text("+").frame(width: 32, height: 30).background(Deck.panel2)
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
            Text("OATS KEYMAP")
                .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(3)
            Text("v\(APP_VERSION)")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(Deck.dim)

            TextField("Instrument", text: $m.km.name)
                .textFieldStyle(.plain)
                .padding(7)
                .background(Deck.deck)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
                .frame(maxWidth: 320)

            Spacer()
            TBtn(t: "Open")  { importing = true }.frame(width: 84)
            TBtn(t: "Save")  { exporting = true }.frame(width: 84)
            TBtn(t: "Hookup") { hookup = true }.frame(width: 84)
            TBtn(t: "Panic", danger: true) { m.engine.panic() }.frame(width: 84)
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
                }.frame(width: 84)
                TBtn(t: "Close") { dismiss() }.frame(width: 84)
            }
            .padding(12).background(Deck.panel)

            ScrollView([.horizontal, .vertical]) {
                Text(m.hookupSheet())
                    .font(.system(size: 11, design: .monospaced))
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
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.black).padding(.bottom, 3)
                        }
                        .frame(height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .stroke(Deck.armed, lineWidth: m.armedCh == c ? 2 : 0))
                        .offset(y: m.armedCh == c ? -3 : 0)
                    }
                    .buttonStyle(.plain)
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
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(Deck.armed)
                if !m.collisions.isEmpty {
                    Text("⚠ \(m.collisions.count) collision\(m.collisions.count > 1 ? "s" : "")")
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(Deck.bad)
                }
                Spacer()
            }
            PlotView(m: m, engine: m.engine)
                .padding(8)
                .background(Deck.ebony)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Tool rail

struct ToolRail: View {
    @ObservedObject var m: AppModel
    @ObservedObject var e: MIDIEngine
    var body: some View {
        Divider().background(Deck.rule)
        HStack(spacing: 16) {
            Lbl("Tool")
            Seg(value: $m.tool, options: Tool.allCases.map { ($0, $0.rawValue) })

            Lbl("In ch")
            Picker("", selection: $e.inChannel) {
                ForEach(1...16, id: \.self) { Text("CH \($0)").tag($0) }
            }
            .labelsHidden().frame(width: 92)

            Lbl("Names")
            Seg(value: $m.middleC3, options: [(true, "C3=60"), (false, "C4=60")])

            Spacer()
            TBtn(t: "Identity") { m.identity() }.frame(width: 96)
            TBtn(t: "Clear all", danger: true) { m.clearAll() }.frame(width: 96)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Deck.panel)
    }
}

// MARK: - Sidebar

struct Side: View {
    @ObservedObject var m: AppModel
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                RankCard(m: m)
                RegisterCard(m: m)
                KeyCard(m: m)
                if m.tool == .range { RangeCard(m: m) }
                LayerCard(m: m)
                PercussionCard(m: m)
                PlotCard(m: m)
                if !m.collisions.isEmpty { ClashCard(m: m) }
                LiveCard(m: m, e: m.engine)
                MonitorCard(m: m, e: m.engine)
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
                            .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                            .foregroundColor(Deck.dim)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Deck.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Switch to Edit and click a key.")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(Deck.dim2)
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
                RoundedRectangle(cornerRadius: 2).fill(Gel.color(a.ch)).frame(width: 14, height: 14)
                Lbl("Layer \(index + 1)")
                Spacer()
                Button { m.removeLayer(index, from: note) } label: {
                    Text("×").font(.system(size: 13, design: .monospaced)).foregroundColor(Deck.bad)
                        .frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Deck.rule, lineWidth: 1))
                }.buttonStyle(.plain)
            }

            Stepper2(label: "Note",
                     value: Binding(get: { a.note },
                                    set: { v in m.update(note, index) { $0.note = min(127, max(0, v)) } }),
                     range: 0...127, suffix: Notes.name(a.note))

            HStack(spacing: 8) {
                Lbl("Channel").frame(width: 62, alignment: .leading)
                Picker("", selection: Binding(get: { a.ch },
                                              set: { v in m.update(note, index) { $0.ch = v } })) {
                    ForEach(1...16, id: \.self) { Text("CH \($0)").tag($0) }
                }
                .labelsHidden()
                .background(Gel.color(a.ch).opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Stepper2(label: "Velocity",
                     value: Binding(get: { a.vel ?? 0 },
                                    set: { v in m.update(note, index) { $0.vel = v == 0 ? nil : v } }),
                     range: 0...127, suffix: a.vel == nil ? "pass" : "fixed")

            HStack(spacing: 8) {
                Lbl("Label").frame(width: 62, alignment: .leading)
                TextField("kick / cue 12 / sub octave",
                          text: Binding(get: { a.label },
                                        set: { v in m.update(note, index) { $0.label = v } }))
                    .textFieldStyle(.plain).padding(7).background(Deck.deck)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
            }

            HStack(spacing: 6) {
                Text(m.km.organ.hookup(note: a.note, channel: a.ch))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                Lbl("Keys").frame(width: 62, alignment: .leading)
                Picker("", selection: $m.km.plot.keys) {
                    ForEach([25, 37, 49, 61, 76, 81, 88, 128], id: \.self) { Text("\($0) keys").tag($0) }
                }.labelsHidden()
            }
            Stepper2(label: "Low note", value: $m.km.plot.low, range: 0...127, suffix: Notes.name(m.km.plot.low))
            Stepper2(label: "Board oct", value: $m.km.board.octaveShift, range: -3...3, suffix: "shift")
            Text("Dim keys sit outside the 61es keybed at this octave shift — the board can't reach them.")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(Deck.dim)
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
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(Deck.bad)
                }
                Text("Same channel + note from two live sources. First note-off kills both.")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(Deck.dim)
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
                Lbl("MIDI in").frame(width: 62, alignment: .leading)
                Picker("", selection: $e.selectedSource) {
                    ForEach(e.sources) { Text($0.name).tag($0.id) }
                }.labelsHidden()
            }
            HStack(spacing: 8) {
                Lbl("Also to").frame(width: 62, alignment: .leading)
                Picker("", selection: $e.selectedDest) {
                    Text("— none —").tag(MIDIEndpointRef(0))
                    ForEach(e.destinations) { Text($0.name).tag($0.id) }
                }.labelsHidden()
            }
            Text("Output always appears as a MIDI device called OATS KEYMAP. Pick it as the input in Logic — no IAC bus needed.")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(Deck.dim)
                .fixedSize(horizontal: false, vertical: true)

            Button { e.armed.toggle() } label: {
                Text(e.armed ? "DISARM" : "ARM REMAP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.6)
                    .foregroundColor(e.armed ? .black : Deck.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(e.armed ? Deck.armed : Deck.panel2)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
            }
            .buttonStyle(.plain).clipShape(RoundedRectangle(cornerRadius: 3))

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
                        Text("No traffic.").font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Deck.dim2)
                    }
                    ForEach(e.log) { line in
                        Text(line.text)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Deck.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 130)
            .padding(8)
            .background(Deck.deck)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
        }
    }
}
