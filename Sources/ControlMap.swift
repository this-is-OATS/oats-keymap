import SwiftUI
import CoreMIDI

// MARK: - Controller mapping (MIDI Learn)
//
// A second MIDI input — any external controller (pad bank, fader box, foot switch) —
// drives the app's own buttons. Nothing it sends is remapped or passed to the organ.
// Mapping is done on site: hit LEARN, tap a control on screen, move the hardware.
// Bindings live on this device (UserDefaults), not in the instrument file, so the
// same show file works with whatever controller is on the desk today.

struct CtlTrigger: Codable, Hashable {
    enum Kind: String, Codable { case note, cc, pc }
    var kind: Kind
    var ch: Int          // 1...16
    var num: Int         // note / CC number / program

    var text: String {
        switch kind {
        case .note: return "NOTE \(num) ch\(ch)"
        case .cc:   return "CC \(num) ch\(ch)"
        case .pc:   return "PC \(num) ch\(ch)"
        }
    }
}

enum CtlTarget: Codable, Hashable {
    case pad(Int)            // touchpad slot, 0-based
    case rank(String)        // relay board — toggles PULL / OUT
    case gel(Int)            // arm out channel 1...16
    case panic
    case arm
    case clearLatches

    func title(_ m: AppModel) -> String {
        switch self {
        case .pad(let slot):
            let name = m.pads.first { $0.padSlot == slot }?.name ?? ""
            return "Pad \(slot + 1)" + (name.isEmpty ? "" : " · \(name)")
        case .rank(let board):
            let name = m.km.organ.ranks.first { $0.board == board }?.name ?? "Bd \(board)"
            return "Pull · \(name)"
        case .gel(let c):     return "Arm out ch \(c)"
        case .panic:          return "Panic"
        case .arm:            return "Arm / disarm remap"
        case .clearLatches:   return "Clear pad lights"
        }
    }
}

struct CtlBinding: Codable, Hashable, Identifiable {
    var id = UUID()
    var trigger: CtlTrigger
    var target: CtlTarget
}

enum ControlStore {
    static let key = "oats.keymap.ctlBindings"
    static func load() -> [CtlBinding] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let b = try? JSONDecoder().decode([CtlBinding].self, from: d) else { return [] }
        return b
    }
    static func save(_ b: [CtlBinding]) {
        if let d = try? JSONEncoder().encode(b) { UserDefaults.standard.set(d, forKey: key) }
    }
}

// MARK: - Learn overlay

struct Learnable: ViewModifier {
    @ObservedObject var m: AppModel
    let target: CtlTarget

    func body(content: Content) -> some View {
        let bound = m.binding(for: target)
        let hot = m.learning == target
        return content.overlay {
            if m.learnMode {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Deck.armed.opacity(hot ? 0.30 : 0.06))
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Deck.armed, lineWidth: hot ? 3 : 1)
                    Text(hot ? "MOVE A CONTROL" : (bound?.trigger.text ?? "LEARN"))
                        .font(.system(size: UI.f(8), weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .foregroundColor(.black)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background((bound != nil || hot) ? Deck.armed : Deck.dim)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .padding(3)
                }
                .contentShape(Rectangle())
                .onTapGesture { m.learning = hot ? nil : target }
            }
        }
    }
}

extension View {
    func learnable(_ m: AppModel, _ t: CtlTarget) -> some View { modifier(Learnable(m: m, target: t)) }
}

// MARK: - Header toggle

struct LearnButton: View {
    @ObservedObject var m: AppModel
    var body: some View {
        Button {
            m.learnMode.toggle()
            if !m.learnMode { m.learning = nil }
        } label: {
            Text(m.learnMode ? "DONE" : "LEARN")
                .font(.system(size: UI.f(9), weight: .bold, design: .monospaced)).tracking(1.3)
                .foregroundColor(m.learnMode ? .black : Deck.armed)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(m.learnMode ? Deck.armed : Deck.panel2)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.armed.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Controller card

struct ControllerCard: View {
    @ObservedObject var m: AppModel
    @ObservedObject var e: MIDIEngine

    var body: some View {
        Card(title: "Controller", trailing: e.lastCtl) {
            HStack(spacing: 8) {
                Lbl("Ctl in").frame(width: 100, alignment: .leading)
                BigPicker(value: Binding(get: { e.selectedCtlSource },
                                         set: { e.chooseController($0) }),
                          options: [(MIDIEndpointRef(0), "— none —")] + e.sources.map { ($0.id, $0.name) })
            }

            LearnButton(m: m)

            Text(m.learnMode
                 ? "Tap anything outlined in amber, then press, hit or move a control. Tap it again to cancel. Hit DONE when finished."
                 : "Pads, PULL buttons, channel gels, ARM, PANIC and pad-clear can all be fired from the controller. Buttons, pads, keys, program changes or any CC crossing half-way.")
                .font(.system(size: UI.f(10), design: .monospaced))
                .foregroundColor(m.learnMode ? Deck.armed : Deck.dim)
                .fixedSize(horizontal: false, vertical: true)

            if !m.ctlBindings.isEmpty {
                VStack(spacing: 5) {
                    ForEach(m.ctlBindings) { b in
                        HStack(spacing: 8) {
                            Text(b.trigger.text)
                                .font(.system(size: UI.f(10), weight: .bold, design: .monospaced))
                                .foregroundColor(Deck.armed)
                                .frame(width: 150, alignment: .leading)
                            Text(b.target.title(m))
                                .font(.system(size: UI.f(10), design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Button { m.unbind(b) } label: {
                                Text("×").font(.system(size: UI.f(13), design: .monospaced))
                                    .foregroundColor(Deck.bad)
                                    .frame(width: 32, height: 32)
                                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Deck.rule, lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                TBtn(t: "Clear all bindings", danger: true) { m.clearBindings() }
            }
        }
    }
}
