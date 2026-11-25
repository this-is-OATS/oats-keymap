import SwiftUI
import CoreMIDI

// MARK: - Voices — the PLAY screen
//
// The organ, as played: Bass & Melody is always under the hands. Each voice button
// adds its rank as a layer on the same keys you're already playing. Mix freely.
// A voice is one or more relay boards, plus any register stops to fire when it
// turns on / off (the organ's own switch between two ranks on one board).

struct Voice: Identifiable, Hashable {
    let id: String
    let name: String
    let boards: [String]
    var onFire: [Int] = []       // register numbers fired when the voice turns on
    var offFire: [Int] = []      // … and when it turns off
    var locked = false           // always on
    var gel: Int                 // colour, 1…16
    var note: String? = nil      // operator caveat shown on the button

    /// Gene's Pipe Organ. Boards and register numbers from the spec sheet.
    static let gene: [Voice] = [
        Voice(id: "bass",     name: "Bass & Melody",  boards: ["214"], locked: true, gel: 1),
        Voice(id: "glock",    name: "Glockenspiel",   boards: ["332"], onFire: [7], offFire: [8], gel: 9,
              note: "Fires Glock On / Off — verify on the console"),
        Voice(id: "xylo",     name: "Xylophone",      boards: ["332"], gel: 3),
        Voice(id: "brass",    name: "Brass Pan Pipe", boards: ["331"], gel: 14,
              note: "Shares ch 2 with Xylophone — Bd 331 unconfirmed"),
        Voice(id: "trumpets", name: "Trumpets",       boards: ["329"], gel: 2),
        Voice(id: "piccolos", name: "Piccolos",       boards: ["346"], gel: 12),
    ]
}

enum Screen { case play, setup }

extension AppModel {
    /// Voices whose boards all exist on the loaded organ.
    var voices: [Voice] {
        Voice.gene.filter { v in v.boards.allSatisfy { b in km.organ.ranks.contains { $0.board == b } } }
    }

    func isVoiceOn(_ v: Voice) -> Bool { v.locked || activeVoices.contains(v.id) }

    func toggleVoice(_ v: Voice) {
        guard !v.locked else { return }
        if activeVoices.contains(v.id) {
            activeVoices.remove(v.id)
            fireRegisters(v.offFire)
            lastAction = "\(v.name) off"
        } else {
            activeVoices.insert(v.id)
            fireRegisters(v.onFire)
            lastAction = "\(v.name) on"
        }
        syncVoiceLayers()
    }

    /// Make the map match the voice buttons: a board is layered iff some lit voice needs it.
    func syncVoiceLayers() {
        let keep = lastAction
        defer { lastAction = keep }
        let needed = Set(voices.filter { isVoiceOn($0) }.flatMap(\.boards))
        for r in km.organ.ranks {
            let pulled = isPulled(r)
            if needed.contains(r.board) && !pulled { pull(r) }
            else if !needed.contains(r.board) && pulled { drop(r) }
        }
    }

    func voiceDetail(_ v: Voice) -> String {
        v.boards.compactMap { b in km.organ.ranks.first { $0.board == b } }
            .map { "Bd \($0.board) · ch \($0.channel) · \($0.low)–\($0.high)" }
            .joined(separator: "  +  ")
    }

    private func fireRegisters(_ numbers: [Int]) {
        for n in numbers {
            if let reg = km.organ.registers.first(where: { $0.number == n }) { fireRegister(reg) }
        }
    }
}

// MARK: - Play screen

struct PlayView: View {
    @ObservedObject var m: AppModel
    @ObservedObject var e: MIDIEngine

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            PlayBar(m: m, e: e)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Lbl("Voices — tap to layer onto every key you play")
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(m.voices) { v in
                            VoiceButton(m: m, v: v).learnable(m, .voice(v.id))
                        }
                    }
                }
                .padding(16)
                Divider().background(Deck.rule)
                RegisterPads(m: m)
            }
            Divider().background(Deck.rule)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Lbl("Sounding layers")
                    Spacer()
                    if !m.lastAction.isEmpty {
                        Text(m.lastAction)
                            .font(.system(size: UI.floor, design: .monospaced))
                            .foregroundColor(Deck.armed)
                    }
                }
                PlotView(m: m, engine: e)
                    .frame(height: 110)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Deck.panel)
        }
    }
}

struct PlayBar: View {
    @ObservedObject var m: AppModel
    @ObservedObject var e: MIDIEngine

    var body: some View {
        HStack(spacing: 12) {
            Text("OATS MIDI KEYMAP")
                .font(.system(size: UI.f(12), weight: .bold, design: .monospaced)).tracking(3)
                .lineLimit(1).fixedSize()
            Text("v\(APP_VERSION)")
                .font(.system(size: UI.floor, design: .monospaced)).foregroundColor(Deck.dim)
                .fixedSize()
            Spacer()
            Lbl("Keys")
            BigPicker(value: $e.selectedSource, options: e.sources.map { ($0.id, $0.name) })
                .frame(width: 190)
            Lbl("Ctl")
            BigPicker(value: Binding(get: { e.selectedCtlSource }, set: { e.chooseController($0) }),
                      options: [(MIDIEndpointRef(0), "— none —")] + e.sources.map { ($0.id, $0.name) })
                .frame(width: 190)
            Button { e.armed.toggle() } label: {
                Text(e.armed ? "LIVE" : "ARM")
                    .font(.system(size: UI.f(10), weight: .bold, design: .monospaced)).tracking(1.6)
                    .foregroundColor(e.armed ? .black : Deck.ink)
                    .frame(width: 100, height: 40)
                    .background(e.armed ? Deck.armed : Deck.panel2)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .learnable(m, .arm)
            LearnButton(m: m).frame(width: 100)
            TBtn(t: "Panic", danger: true) { e.panic() }.frame(width: 100)
                .learnable(m, .panic)
            TBtn(t: "Setup ▸") { m.screen = .setup }.frame(width: 100)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Deck.panel)
        Divider().background(Deck.rule)
    }
}

struct VoiceButton: View {
    @ObservedObject var m: AppModel
    let v: Voice

    var body: some View {
        let on = m.isVoiceOn(v)
        let tint = Gel.color(v.gel)
        Button { m.toggleVoice(v) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(on ? Color.black.opacity(0.75) : tint)
                        .frame(width: 16, height: 16)
                    Spacer()
                    Text(v.locked ? "ALWAYS ON" : (on ? "ON" : "OFF"))
                        .font(.system(size: UI.floor, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                }
                Spacer(minLength: 0)
                Text(v.name)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(m.voiceDetail(v))
                    .font(.system(size: UI.floor, design: .monospaced))
                    .opacity(0.75)
                    .lineLimit(1)
                if let note = v.note {
                    Text(note)
                        .font(.system(size: UI.floor, design: .monospaced))
                        .foregroundColor(on ? .black : Deck.bad)
                        .lineLimit(2)
                }
            }
            .foregroundColor(on ? .black : Deck.ink)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(on ? tint : Deck.deck)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? tint : Deck.rule, lineWidth: on ? 3 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
