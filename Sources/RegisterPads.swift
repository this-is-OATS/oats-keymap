import SwiftUI

// MARK: - Register pad strip
//
// Twelve touchpads across the top. Each fires one register's trigger note — which on
// this organ is a key in the lowest octave. A pad is that key, mirrored to the screen.
// Tap fires a note pulse; the lit state is the operator's reminder, not the organ's
// real state (relay organs don't report back).

struct RegisterPads: View {
    @ObservedObject var m: AppModel

    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Lbl("Registers — tap to fire · these mirror the lowest-octave keys")
                Spacer()
                if m.padAssignMode {
                    Text("ASSIGN MODE — set each pad's note & channel, then verify on the console")
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(Deck.bad)
                }
                Lbl("Clear")
                Button { m.clearPadLatches() } label: {
                    Text("○").font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Deck.ink).frame(width: 30, height: 24)
                        .background(Deck.panel2)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
                }.buttonStyle(.plain)
                Seg(value: $m.padAssignMode, options: [(false, "Play"), (true, "Assign")])
            }

            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(m.pads) { reg in
                    if m.padAssignMode { PadAssign(m: m, reg: reg) }
                    else { Pad(m: m, reg: reg) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
        .background(Deck.panel)
        Divider().background(Deck.rule)
    }
}

// MARK: Play pad

struct Pad: View {
    @ObservedObject var m: AppModel
    let reg: Register

    private var tint: Color { Gel.color(reg.channel) }

    var body: some View {
        Button { m.tapPad(reg) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(reg.latched ? tint : Color.clear)
                        .overlay(Circle().stroke(reg.known ? tint : Deck.bad, lineWidth: 1.4))
                        .frame(width: 9, height: 9)
                    Text("\(reg.number)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Deck.dim)
                    Spacer()
                    Text(reg.note.map { Notes.name($0) } ?? "—")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(reg.known ? tint : Deck.bad)
                }
                if let slot = reg.padSlot {
                    Text("Bd 214 · pin \(RegisterBank.pin(slot))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Deck.dim)
                }
                Text(reg.name)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(reg.latched ? .black : (reg.known ? Deck.ink : Deck.dim2))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .background(reg.latched ? tint.opacity(0.9) : Deck.deck)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(reg.latched ? tint : (reg.known ? Deck.rule : Deck.bad.opacity(0.5)),
                        lineWidth: reg.latched ? 2 : 1))
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .disabled(!reg.known)
    }
}

// MARK: Assign pad

struct PadAssign: View {
    @ObservedObject var m: AppModel
    let reg: Register

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("name", text: Binding(
                get: { reg.name },
                set: { m.setPadName(reg, $0) }))
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Deck.ink)

            HStack(spacing: 4) {
                Button { m.setPadNote(reg, max(0, (reg.note ?? 36) - 1)) } label: {
                    Text("−").frame(width: 24, height: 24).background(Deck.panel2)
                }.buttonStyle(.plain)
                Text(reg.note.map { "\($0) \(Notes.name($0))" } ?? "—")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Deck.armed)
                    .frame(maxWidth: .infinity).frame(height: 24).background(Deck.deck)
                Button { m.setPadNote(reg, min(127, (reg.note ?? 36) + 1)) } label: {
                    Text("+").frame(width: 24, height: 24).background(Deck.panel2)
                }.buttonStyle(.plain)
            }
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Picker("", selection: Binding(
                get: { reg.channel },
                set: { m.setPadChannel(reg, $0) })) {
                ForEach(1...16, id: \.self) { Text("CH \($0)").tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .background(Gel.color(reg.channel).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(Deck.deck)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Deck.armed.opacity(0.4), lineWidth: 1))
    }
}
