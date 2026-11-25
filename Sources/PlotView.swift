import SwiftUI

struct PlotView: View {
    @ObservedObject var m: AppModel
    @ObservedObject var engine: MIDIEngine
    @State private var lastPainted: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let bed = m.bed
            let size = geo.size

            Canvas { ctx, sz in draw(ctx, sz, bed) }
                .background(Deck.ebony)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard let n = bed.note(at: v.location, size: size) else { return }
                            let dragging = v.translation != .zero
                            if m.tool == .paint {
                                guard n != lastPainted else { return }
                                lastPainted = n
                                m.hit(n, dragging: dragging)
                            } else if lastPainted == nil {
                                lastPainted = n
                                m.hit(n, dragging: false)
                            }
                        }
                        .onEnded { _ in lastPainted = nil }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Deck.rule, lineWidth: 1))
    }

    // MARK: Draw

    private func draw(_ ctx: GraphicsContext, _ sz: CGSize, _ bed: Keybed) {
        guard bed.whiteCount > 0 else { return }
        let kw = bed.whiteWidth(in: sz.width)
        let bw = kw * 0.62
        let bh = sz.height * 0.6
        let clashes = m.collidingKeys
        let range = m.rangeContains

        for (i, n) in bed.whiteNotes.enumerated() {
            let r = CGRect(x: CGFloat(i) * kw + 0.5, y: 0, width: max(1, kw - 1), height: sz.height)
            key(ctx, r, note: n, black: false, clash: clashes.contains(n), range: range)
        }
        for b in bed.blackKeys where b.afterWhite >= 0 {
            let x = CGFloat(b.afterWhite + 1) * kw - bw / 2
            let r = CGRect(x: x, y: 0, width: bw, height: bh)
            key(ctx, r, note: b.note, black: true, clash: clashes.contains(b.note), range: range)
        }
    }

    private func key(_ ctx: GraphicsContext, _ r: CGRect, note n: Int, black: Bool,
                     clash: Bool, range: ClosedRange<Int>?) {

        let stack = m.stack(n)
        let reachable = (n >= m.km.boardLow && n <= m.km.boardHigh)
        let path = Path(roundedRect: r, cornerSize: CGSize(width: 2, height: 2))

        // face
        if stack.isEmpty {
            ctx.fill(path, with: .color(black ? Deck.ebony : Deck.ivory))
        } else {
            ctx.fill(path, with: .color(black ? Deck.ebony : Deck.ivory))
            // one horizontal band per layer, top to bottom
            let h = r.height / CGFloat(stack.count)
            for (i, a) in stack.enumerated() {
                let band = CGRect(x: r.minX, y: r.minY + CGFloat(i) * h, width: r.width, height: h)
                var sub = ctx
                sub.clip(to: path)
                sub.fill(Path(band), with: .color(Gel.color(a.ch).gelled(onBlack: black)))
            }
        }

        if !reachable {
            ctx.fill(path, with: .color(Deck.deck.opacity(0.62)))       // outside the 61-key bed
        }
        if engine.flash == n {
            ctx.fill(path, with: .color(.white.opacity(0.38)))
        }

        // text — dropped as soon as it won't fit
        let ink: Color = black ? Deck.ivory : Deck.ebony
        if r.width >= 27 {
            let top = stack.first
            let big = top.map { "\($0.note)" + (stack.count > 1 ? " ×\(stack.count)" : "") } ?? "\(n)"
            ctx.draw(Text(big)
                        .font(.system(size: UI.floor, weight: .bold, design: .monospaced))
                        .foregroundColor(ink.opacity(stack.isEmpty ? 0.28 : 1)),
                     at: CGPoint(x: r.midX, y: r.maxY - 26), anchor: .center)
        }
        if r.width >= 44 {
            let sub = stack.isEmpty
                ? Notes.name(n)
                : (stack.count == 1
                    ? "CH\(stack[0].ch)" + (stack[0].vel.map { " v\($0)" } ?? "")
                    : stack.map { "\($0.ch)" }.joined(separator: "·"))
            ctx.draw(Text(sub)
                        .font(.system(size: UI.floor, design: .monospaced))
                        .foregroundColor(ink.opacity(0.66)),
                     at: CGPoint(x: r.midX, y: r.maxY - 10), anchor: .center)
        }

        // overlays
        if clash {
            ctx.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 3)), with: .color(Deck.bad))
        }
        if let range, range.contains(n) {
            ctx.stroke(path, with: .color(Deck.armed), lineWidth: 1)
        }
        if m.sel == n {
            ctx.stroke(path, with: .color(Deck.armed), lineWidth: 2.5)
        }
        if stack.count > 0 && stack.allSatisfy(\.mute) {
            var hatch = Path()
            var x = r.minX - r.height
            while x < r.maxX {
                hatch.move(to: CGPoint(x: x, y: r.maxY))
                hatch.addLine(to: CGPoint(x: x + r.height, y: r.minY))
                x += 6
            }
            var sub = ctx
            sub.clip(to: path)
            sub.stroke(hatch, with: .color(.black.opacity(0.45)), lineWidth: 1)
        }
    }
}
