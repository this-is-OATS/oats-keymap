import SwiftUI

let APP_VERSION = "0.9.0"

// MARK: - UI scale
// One knob for every font in the chrome. 1.0 was the v0.7 look (too small at FOH).
enum UI {
    static let s: CGFloat = 1.4
    /// No text in the app goes below 14pt. Headings scale past it.
    static let floor: CGFloat = 14
    static func f(_ base: CGFloat) -> CGFloat { max(floor, base * s) }
    /// Keybed height. The plot is a reference strip, not the main event.
    static let keybedHeight: CGFloat = 190
}

// MARK: - Gels
// Sixteen MIDI channels, sixteen colours. Colour is the only thing in this app
// that carries information rather than chrome.

enum Gel {
    static let swatch: [Color] = [
        "ff2d3f","ff7a18","ffb020","f5de3c","b6e04a","57cc4a","10b981","14b8b0",
        "22c3e6","2e7df7","5c5cf0","9b6bf5","c455e8","f03cc0","ff5c97","ffa8a8"
    ].map { Color(hex: $0) }

    static func color(_ ch: Int) -> Color { swatch[min(16, max(1, ch)) - 1] }
}

enum Deck {
    static let deck   = Color(hex: "14161a")
    static let panel  = Color(hex: "1b1e23")
    static let panel2 = Color(hex: "22262c")
    static let rule   = Color(hex: "2e333b")
    static let ivory  = Color(hex: "e6e2d6")
    static let ebony  = Color(hex: "0b0c0e")
    static let ink    = Color(hex: "cdd2d9")
    static let dim    = Color(hex: "737b85")
    static let dim2   = Color(hex: "474e56")
    static let armed  = Color(hex: "ffb338")
    static let bad    = Color(hex: "ff4d4d")
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255,
                  opacity: 1)
    }

    /// Wash a gel over a key face.
    func gelled(onBlack: Bool) -> Color {
        onBlack ? self.mix(with: Deck.ebony, by: 0.42)
                : self.mix(with: Deck.ivory, by: 0.14)
    }

    func mix(with other: Color, by t: Double) -> Color {
        #if canImport(UIKit)
        let a = UIColor(self).rgba, b = UIColor(other).rgba
        #else
        let a = NSColor(self).usingColorSpace(.sRGB)!.rgba, b = NSColor(other).usingColorSpace(.sRGB)!.rgba
        #endif
        return Color(.sRGB,
                     red:   a.r + (b.r - a.r) * t,
                     green: a.g + (b.g - a.g) * t,
                     blue:  a.b + (b.b - a.b) * t,
                     opacity: 1)
    }
}

#if canImport(UIKit)
extension UIColor {
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}
#else
extension NSColor {
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        (Double(redComponent), Double(greenComponent), Double(blueComponent), Double(alphaComponent))
    }
}
#endif

// MARK: - Notes

enum NoteNaming: String, CaseIterable, Codable {
    case c3 = "C3=60"      // Keystation silkscreen
    case c4 = "C4=60"      // most DAWs
    case c5 = "C5=60"      // Gene's console — spec sheet: C5 is Middle C

    var octaveOffset: Int {           // subtracted from n/12 to get the printed octave
        switch self { case .c3: return 2; case .c4: return 1; case .c5: return 0 }
    }
}

enum Notes {
    static let pc = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    static var naming: NoteNaming = .c5

    static func name(_ n: Int) -> String {
        pc[((n % 12) + 12) % 12] + String(n / 12 - naming.octaveOffset)
    }
    static func isBlack(_ n: Int) -> Bool { [1,3,6,8,10].contains(((n % 12) + 12) % 12) }
}

// MARK: - Keybed geometry
// Precomputed once per plot range; the view does pure arithmetic on it.

struct Keybed {
    struct BlackKey { let note: Int; let afterWhite: Int }

    let low: Int
    let high: Int
    private(set) var whiteNotes: [Int] = []
    private(set) var blackKeys: [BlackKey] = []

    var whiteCount: Int { whiteNotes.count }

    init(low: Int, high: Int) {
        self.low = low
        self.high = high
        var w = 0
        for n in low...max(low, high) {
            if Notes.isBlack(n) { blackKeys.append(BlackKey(note: n, afterWhite: w - 1)) }
            else { whiteNotes.append(n); w += 1 }
        }
    }

    func whiteWidth(in width: CGFloat) -> CGFloat { width / CGFloat(max(1, whiteCount)) }

    /// Hit-test: black keys sit on top for the upper 60% of the bed.
    func note(at p: CGPoint, size: CGSize) -> Int? {
        let kw = whiteWidth(in: size.width)
        let bw = kw * 0.62
        if p.y <= size.height * 0.6 {
            for b in blackKeys where b.afterWhite >= 0 {
                let x = CGFloat(b.afterWhite + 1) * kw - bw / 2
                if p.x >= x && p.x <= x + bw { return b.note }
            }
        }
        let i = Int(floor(p.x / kw))
        return (i >= 0 && i < whiteNotes.count) ? whiteNotes[i] : nil
    }
}
