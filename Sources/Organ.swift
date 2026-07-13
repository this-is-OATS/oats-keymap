import Foundation

// MARK: - Rank
//
// A rank is a board full of pipes. The board listens on one MIDI channel and
// converts an incoming note into a pin: pin = note − pinOffset.
// If the note falls outside [low, high] there is no pipe, and nothing happens.
//
// Two ranks can share a channel (Gene's Bd 331 and Bd 332 are both ch 2).
// Which of them actually speaks is decided by the REGISTERS, not by MIDI.

struct Rank: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var board: String                 // relay board number, e.g. "214"
    var channel: Int                  // 1...16
    var low: Int                      // lowest note with a pipe
    var high: Int                     // highest note with a pipe
    var pinOffset: Int                // pin = note − pinOffset
    var confirmed: Bool = false       // false = read off a photo. Do not wire from it.
    var caveat: String = ""

    enum CodingKeys: String, CodingKey { case name, board, channel, low, high, pinOffset, confirmed, caveat }

    var pipes: Int { max(0, high - low + 1) }
    var pinLow: Int { low - pinOffset }
    var pinHigh: Int { high - pinOffset }

    func covers(_ note: Int) -> Bool { note >= low && note <= high }
    func pin(_ note: Int) -> Int? { covers(note) ? note - pinOffset : nil }
}

// MARK: - Register
//
// A stop. On these relay organs a register is just a MIDI note held on a channel —
// it latches a rank in or out. The note numbers are NOT on the photo; fill them in
// from the console or a clean scan and the app will fire them.

struct Register: Identifiable, Codable, Hashable {
    var id = UUID()
    var number: Int
    var name: String
    var channel: Int = 1
    var note: Int? = nil              // nil = unknown, cannot fire
    var latched: Bool = false

    enum CodingKeys: String, CodingKey { case number, name, channel, note }
    var known: Bool { note != nil }
}

// MARK: - Organ profile

struct OrganProfile: Codable {
    var name: String = "Gene's Pipe Organ"
    var revision: String = "chart last revised 2/12/2011"
    var ranks: [Rank] = []
    var registers: [Register] = []
    var percussion: [PercussionHit] = []
}

struct PercussionHit: Identifiable, Codable, Hashable {
    var id = UUID()
    var pin: Int
    var name: String
    var note: Int?                    // nil = could not read it off the photo
    var channel: Int = 10
    enum CodingKeys: String, CodingKey { case pin, name, note, channel }
    var known: Bool { note != nil }
}

// MARK: - Gene's organ, as read off the laminated chart
//
// Every rank below was cross-checked: the printed note letters agree with the printed
// MIDI numbers under pin = note − offset, across the full column. Where that check
// could not be run, confirmed = false and the app paints it red.

enum Gene {
    static var profile: OrganProfile {
        OrganProfile(
            name: "Gene's Pipe Organ",
            revision: "chart rev 2/12/2011 · Bd 333 swapped out for Bd 268, 6/8/2007",
            ranks: [
                Rank(name: "Main Melody / Acc / Bass & Reg", board: "214", channel: 1,
                     low: 28, high: 91, pinOffset: 27, confirmed: true,
                     caveat: "64 pipes, pins 1–64. Verified across the whole column."),

                Rank(name: "Pan Flutes / Counter Melody", board: "331", channel: 2,
                     low: 48, high: 69, pinOffset: 47, confirmed: false,
                     caveat: "22 pipes is certain — the range is not. My read (48–69) overlaps Bd 332 at 67–69, which is either a coupled register or a misread. Do not wire from this. Pins 23–32 on this board are spare."),

                Rank(name: "Xylophone / Glockenspiel", board: "332", channel: 2,
                     low: 67, high: 91, pinOffset: 59, confirmed: true,
                     caveat: "Pins 8–32. Pins 1–7 (notes 60–66) are the unwired ADDT'L PERCUSSION (FUTURE) block."),

                Rank(name: "Trumpets", board: "329", channel: 3,
                     low: 55, high: 86, pinOffset: 54, confirmed: true,
                     caveat: "32 pipes, pins 1–32. Verified across the whole column."),

                Rank(name: "Piccolos", board: "346", channel: 10,
                     low: 82, high: 101, pinOffset: 69, confirmed: true,
                     caveat: "Pins 13–32. Pins 1–12 on this board are the percussion, which is a lookup, not an offset.")
            ],
            registers: [
                // Names read clean off the chart. Note numbers are NOT on it.
                Register(number: 1,  name: "Pan Flutes"),
                Register(number: 2,  name: "Countermelody Bourdons"),
                Register(number: 3,  name: "Glock / Xylophone"),
                Register(number: 4,  name: "Double Bourdon Celeste"),
                Register(number: 5,  name: "Clarabellas"),
                Register(number: 6,  name: "(blank on chart)"),
                Register(number: 7,  name: "Glock On"),
                Register(number: 8,  name: "Glock Off"),
                Register(number: 9,  name: "(not listed)"),
                Register(number: 10, name: "(not listed)"),
                Register(number: 11, name: "Tambourine"),
                Register(number: 12, name: "Castanets / Maracas")
            ],
            percussion: [
                PercussionHit(pin: 1,  name: "Bass Drum",    note: 36),
                PercussionHit(pin: 2,  name: "Snare 1",      note: 38),
                PercussionHit(pin: 3,  name: "Snare 2",      note: 40),
                PercussionHit(pin: 4,  name: "Sleigh Bells?", note: nil),   // handwritten on the chart
                PercussionHit(pin: 5,  name: "(blank)",      note: nil),
                PercussionHit(pin: 6,  name: "Ride Cymbal",  note: nil),
                PercussionHit(pin: 7,  name: "Crash Cymbal", note: nil),
                PercussionHit(pin: 8,  name: "Block 1 High", note: nil),
                PercussionHit(pin: 9,  name: "Block 2 Low",  note: nil),
                PercussionHit(pin: 10, name: "Ship's Bell",  note: nil),
                PercussionHit(pin: 11, name: "Tambourine",   note: nil),
                PercussionHit(pin: 12, name: "Castanets",    note: nil)
            ]
        )
    }
}

// MARK: - Lookup helpers

extension OrganProfile {
    /// Every rank that would speak for a given note on a given channel.
    func ranksSpeaking(note: Int, channel: Int) -> [Rank] {
        ranks.filter { $0.channel == channel && $0.covers(note) }
    }

    /// "Bd 214 · pin 33"  — the string an organ tech can actually use.
    func hookup(note: Int, channel: Int) -> String {
        let hits = ranksSpeaking(note: note, channel: channel)
        if hits.isEmpty {
            if channel == 10, let p = percussion.first(where: { $0.note == note }) {
                return "Bd 346 · pin \(p.pin) · \(p.name)"
            }
            return "no pipe"
        }
        return hits.map { r in "Bd \(r.board) · pin \(r.pin(note)!)" }.joined(separator: " + ")
    }

    var unconfirmed: [Rank] { ranks.filter { !$0.confirmed } }
}
