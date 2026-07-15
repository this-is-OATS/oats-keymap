import Foundation

// MARK: - Assignment
// One output from one physical key. A key holds a stack of these.

struct Assignment: Codable, Identifiable, Hashable {
    var id = UUID()
    var note: Int = 60
    var ch: Int = 1
    var vel: Int? = nil          // nil = pass the played velocity through
    var label: String = ""
    var mute: Bool = false
    var board: String? = nil          // which relay board this layer was pulled for

    enum CodingKeys: String, CodingKey { case note, ch, vel, label, mute, board }

    init(note: Int, ch: Int, vel: Int? = nil, label: String = "", mute: Bool = false, board: String? = nil) {
        self.note = min(127, max(0, note))
        self.ch = min(16, max(1, ch))
        self.vel = vel
        self.label = label
        self.mute = mute
        self.board = board
    }
}

// MARK: - Keymap
// Wire-compatible with OATS KEYMAP web v0.2.0 JSON. v0.1.0 files migrate on load.

struct Keymap: Codable {
    struct Plot: Codable  { var low = 21;  var keys = 88 }
    struct Board: Codable { var model = "M-Audio Keystation 61es"; var keys = 61; var octaveShift = 0 }

    var app = "oats-keymap"
    var version = APP_VERSION
    var name = "Untitled instrument"
    var inChannel = 1
    var noteConvention = "C3=60"
    var plot = Plot()
    var board = Board()
    var organ = Gene.profile
    var map: [Int: [Assignment]] = [:]

    var high: Int { min(127, plot.low + plot.keys - 1) }
    var boardLow: Int  { 36 + board.octaveShift * 12 }
    var boardHigh: Int { boardLow + board.keys - 1 }
    var assignmentCount: Int { map.values.reduce(0) { $0 + $1.count } }

    init() {}

    enum CodingKeys: String, CodingKey {
        case app, version, name, inChannel, noteConvention, plot, board, organ, map
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app            = try c.decodeIfPresent(String.self, forKey: .app) ?? "oats-keymap"
        version        = try c.decodeIfPresent(String.self, forKey: .version) ?? "0.0.0"
        name           = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled instrument"
        inChannel      = try c.decodeIfPresent(Int.self,    forKey: .inChannel) ?? 1
        noteConvention = try c.decodeIfPresent(String.self, forKey: .noteConvention) ?? "C3=60"
        plot           = try c.decodeIfPresent(Plot.self,   forKey: .plot) ?? Plot()
        board          = try c.decodeIfPresent(Board.self,  forKey: .board) ?? Board()
        organ          = try c.decodeIfPresent(OrganProfile.self, forKey: .organ) ?? Gene.profile

        // v0.2.0: map values are arrays.  v0.1.0: map values are single objects.
        var built: [Int: [Assignment]] = [:]
        if let stacked = try? c.decodeIfPresent([String: [Assignment]].self, forKey: .map) {
            for (k, v) in stacked ?? [:] { if let n = Int(k) { built[n] = v } }
        } else if let flat = try? c.decodeIfPresent([String: Assignment].self, forKey: .map) {
            for (k, v) in flat ?? [:] { if let n = Int(k) { built[n] = [v] } }
        }
        map = built
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(app, forKey: .app)
        try c.encode(APP_VERSION, forKey: .version)
        try c.encode(name, forKey: .name)
        try c.encode(inChannel, forKey: .inChannel)
        try c.encode(noteConvention, forKey: .noteConvention)
        try c.encode(plot, forKey: .plot)
        try c.encode(board, forKey: .board)
        try c.encode(organ, forKey: .organ)
        var out: [String: [Assignment]] = [:]
        for (k, v) in map { out[String(k)] = v }
        try c.encode(out, forKey: .map)
    }
}

// MARK: - Collision detection
// Two live assignments on the same channel + note = a stuck note. First note-off kills both.

struct Collision: Identifiable {
    let id = UUID()
    let ch: Int
    let note: Int
    let sources: [(inNote: Int, layer: Int)]
    var text: String {
        "ch\(ch) note \(note)  ←  " +
        sources.map { "\(Notes.name($0.inNote))/L\($0.layer)" }.joined(separator: " + ")
    }
}

extension Keymap {
    func collisions() -> [Collision] {
        var targets: [Int: [(Int, Int)]] = [:]                 // (ch<<8|note) -> [(inNote, layer)]
        for (inNote, stack) in map {
            for (i, a) in stack.enumerated() where !a.mute {
                targets[a.ch << 8 | a.note, default: []].append((inNote, i + 1))
            }
        }
        return targets.compactMap { key, srcs in
            guard srcs.count > 1 else { return nil }
            return Collision(ch: key >> 8, note: key & 0xFF,
                             sources: srcs.sorted { $0.0 < $1.0 }.map { (inNote: $0.0, layer: $0.1) })
        }.sorted { $0.ch == $1.ch ? $0.note < $1.note : $0.ch < $1.ch }
    }

    var collidingKeys: Set<Int> {
        Set(collisions().flatMap { $0.sources.map(\.inNote) })
    }
}
