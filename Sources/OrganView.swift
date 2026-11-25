import SwiftUI

// MARK: - Ranks (stops)

struct RankCard: View {
    @ObservedObject var m: AppModel

    var body: some View {
        Card(title: "Ranks", trailing: m.km.organ.name) {
            VStack(spacing: 7) {
                ForEach(m.km.organ.ranks) { r in
                    RankRow(m: m, rank: r)
                }
            }

            if !m.km.organ.unconfirmed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(m.km.organ.unconfirmed) { r in
                        Text("Bd \(r.board) unconfirmed — \(r.caveat)")
                            .font(.system(size: UI.f(10), design: .monospaced))
                            .foregroundColor(Deck.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            }

            if !m.deadKeys.isEmpty {
                Text("\(m.deadKeys.count) mapped key\(m.deadKeys.count == 1 ? "" : "s") land outside every rank on their channel. They will make no sound.")
                    .font(.system(size: UI.f(10), design: .monospaced))
                    .foregroundColor(Deck.armed)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}

struct RankRow: View {
    @ObservedObject var m: AppModel
    let rank: Rank

    var pulled: Bool { m.isPulled(rank) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Gel.color(rank.channel))
                    .frame(width: 18, height: 18)
                    .opacity(rank.confirmed ? 1 : 0.35)

                VStack(alignment: .leading, spacing: 1) {
                    Text(rank.name)
                        .font(.system(size: UI.f(11), weight: .bold, design: .monospaced))
                        .foregroundColor(rank.confirmed ? Deck.ink : Deck.bad)
                    Text("Bd \(rank.board) · ch \(rank.channel) · \(rank.low)–\(rank.high) · pins \(rank.pinLow)–\(rank.pinHigh)")
                        .font(.system(size: UI.f(9), design: .monospaced))
                        .foregroundColor(Deck.dim)
                }
                Spacer()

                Button { pulled ? m.drop(rank) : m.pull(rank) } label: {
                    Text(pulled ? "OUT" : "PULL")
                        .font(.system(size: UI.f(9), weight: .bold, design: .monospaced)).tracking(1.2)
                        .foregroundColor(pulled ? .black : Deck.ink)
                        .frame(width: 76, height: 40)
                        .background(pulled ? Gel.color(rank.channel) : Deck.panel2)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .learnable(m, .rank(rank.board))
            }

            if pulled {
                Text("\(m.speaking(rank)) keys speaking")
                    .font(.system(size: UI.f(9), design: .monospaced))
                    .foregroundColor(Gel.color(rank.channel))
            }
        }
        .padding(9)
        .background(Deck.deck)
        .overlay(RoundedRectangle(cornerRadius: 3)
            .stroke(rank.confirmed ? Deck.rule : Deck.bad.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Registers (the stops the organ itself gates with)

struct RegisterCard: View {
    @ObservedObject var m: AppModel

    var body: some View {
        Card(title: "Registers", trailing: "\(m.km.organ.registers.filter(\.known).count)/12 known") {
            Text("Two ranks share channel 2. MIDI cannot choose between them — the register does. Until these note numbers are filled in, pulling a stop in this app changes nothing on the pipes.")
                .font(.system(size: UI.f(10), design: .monospaced))
                .foregroundColor(Deck.armed)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 5) {
                ForEach(Array(m.km.organ.registers.enumerated()), id: \.element.id) { i, reg in
                    HStack(spacing: 7) {
                        Text("\(reg.number)")
                            .font(.system(size: UI.f(10), weight: .bold, design: .monospaced))
                            .foregroundColor(Deck.dim)
                            .frame(width: 28, alignment: .trailing)

                        Text(reg.name)
                            .font(.system(size: UI.f(10), design: .monospaced))
                            .foregroundColor(reg.known ? Deck.ink : Deck.dim2)
                            .lineLimit(1)

                        Spacer()

                        TextField("note", text: Binding(
                            get: { reg.note.map(String.init) ?? "" },
                            set: { m.setRegisterNote(i, Int($0)) }))
                            .textFieldStyle(.plain)
                            .font(.system(size: UI.f(10), design: .monospaced))
                            .multilineTextAlignment(.center)
                            .frame(width: 64, height: 34)
                            .background(Deck.deck)
                            .overlay(RoundedRectangle(cornerRadius: 2)
                                .stroke(reg.known ? Deck.rule : Deck.bad.opacity(0.45), lineWidth: 1))

                        Button { m.fireRegister(reg) } label: {
                            Text("FIRE")
                                .font(.system(size: UI.f(9), weight: .bold, design: .monospaced))
                                .foregroundColor(reg.known ? Deck.ink : Deck.dim2)
                                .frame(width: 64, height: 34)
                                .background(Deck.panel2)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Deck.rule, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(!reg.known)
                    }
                }
            }
        }
    }
}

// MARK: - Percussion (ch 10, pins 1–12 — a lookup, not an offset)

struct PercussionCard: View {
    @ObservedObject var m: AppModel

    var body: some View {
        Card(title: "Percussion", trailing: "Bd 346 · ch 10") {
            VStack(spacing: 4) {
                ForEach(m.km.organ.percussion) { p in
                    HStack(spacing: 8) {
                        Text("pin \(p.pin)")
                            .font(.system(size: UI.f(10), design: .monospaced))
                            .foregroundColor(Deck.dim)
                            .frame(width: 66, alignment: .leading)
                        Text(p.name)
                            .font(.system(size: UI.f(10), design: .monospaced))
                            .foregroundColor(p.known ? Deck.ink : Deck.bad)
                        Spacer()
                        Text(p.note.map { "\($0)  \(Notes.name($0))" } ?? "unread")
                            .font(.system(size: UI.f(10), weight: p.known ? .bold : .regular, design: .monospaced))
                            .foregroundColor(p.known ? Gel.color(10) : Deck.bad)
                    }
                }
            }
            Text("Pins 1–3 verified off the chart. The rest need a flat scan — a wrong pin fires the wrong relay.")
                .font(.system(size: UI.f(10), design: .monospaced))
                .foregroundColor(Deck.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
