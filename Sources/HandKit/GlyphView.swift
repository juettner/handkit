//
//  GlyphView.swift
//
//  One drawing, shown as a picture.
//
//  `Handwriting` writes text. This shows a single drawing, fitted to
//  whatever frame it is given: an envelope, a heart, anything that was drawn
//  on the drawing page under a name.
//
//      if let envelope = hand.drawings(named: "envelope-sealed").first {
//          GlyphView(envelope).frame(width: 44, height: 44)
//      }
//
//  The drawing keeps its proportions, is centred, and keeps the colours its
//  strokes were drawn in. The line is as thick, against the drawing, as the
//  pen was on the ruled square, so a picture shown small has a fine line and
//  one shown large a bold one, as if the paper had been scaled.
//
//  `Sketch` is the same picture, drawn: the pen makes it stroke by stroke,
//  in the order and direction it was drawn, the way `Handwriting` writes a
//  line. For a doodle in the margin that should arrive, not just be there.
//
//      Sketch(doodle, duration: 1.4)
//          .frame(width: 60, height: 60)
//

import SwiftUI

public struct GlyphView: View {
    let glyph: Glyph
    var ink: Color
    /// The least the line may be, in points, so a small picture does not fade away.
    var minimumLine: CGFloat

    public init(_ glyph: Glyph, ink: Color = HandStyle.journal.ink, minimumLine: CGFloat = 1.2) {
        self.glyph = glyph
        self.ink = ink
        self.minimumLine = minimumLine
    }

    public var body: some View {
        Canvas { graphics, size in
            guard let fitted = GlyphView.fit(glyph, in: size, minimumLine: minimumLine) else { return }
            for (number, stroke) in fitted.strokes.enumerated() where !stroke.isEmpty {
                graphics.stroke(
                    Written.smooth(stroke),
                    with: .color(glyph.color(of: number) ?? ink),
                    style: StrokeStyle(lineWidth: fitted.line, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    /// The drawing's strokes moved and scaled to sit centred in `size`, and
    /// how thick to draw them. Nil for a drawing with no points. The strokes
    /// keep their numbers, so the colour of each can still be looked up.
    static func fit(_ glyph: Glyph, in size: CGSize, minimumLine: CGFloat) -> (strokes: [[CGPoint]], line: CGFloat)? {
        let strokes = glyph.points
        let every = strokes.flatMap { $0 }
        guard let left = every.map(\.x).min(), let right = every.map(\.x).max(),
              let top = every.map(\.y).min(), let bottom = every.map(\.y).max() else { return nil }
        let width = max(right - left, 0.01)
        let height = max(bottom - top, 0.01)
        // A little air round the edge, so the round ends of the line are not cut off.
        let scale = min(size.width / width, size.height / height) * 0.92
        let dx = (size.width - width * scale) / 2 - left * scale
        let dy = (size.height - height * scale) / 2 - top * scale
        let placed = strokes.map { stroke in stroke.map { CGPoint(x: $0.x * scale + dx, y: $0.y * scale + dy) } }
        return (placed, max(minimumLine, Pen.nib * scale))
    }
}

/// One drawing, made by the pen while you watch.
public struct Sketch: View {
    let glyph: Glyph
    var ink: Color
    /// How long the whole drawing takes, in seconds. Zero or less shows it finished.
    var duration: TimeInterval
    /// How long the pen waits before it starts.
    var delay: TimeInterval
    var minimumLine: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var began = Date()
    /// True once the drawing is finished; pauses the redraw.
    @State private var still = false

    public init(_ glyph: Glyph, ink: Color = HandStyle.journal.ink, duration: TimeInterval = 1.4, delay: TimeInterval = 0, minimumLine: CGFloat = 1.2) {
        self.glyph = glyph
        self.ink = ink
        self.duration = duration
        self.delay = delay
        self.minimumLine = minimumLine
    }

    public var body: some View {
        TimelineView(.animation(paused: still)) { context in
            Canvas { graphics, size in
                guard let fitted = GlyphView.fit(glyph, in: size, minimumLine: minimumLine) else { return }
                // How far through the whole drawing the pen is, from 0 to 1.
                let done: Double = still || duration <= 0 ? 1 : min(1, max(0, (context.date.timeIntervalSince(began) - delay) / duration))
                // Each stroke takes a share of the time in proportion to its length.
                let lengths = fitted.strokes.map { Sketch.length(of: $0) }
                let total = max(lengths.reduce(0, +), 0.01)
                var before: Double = 0
                for (number, stroke) in fitted.strokes.enumerated() where !stroke.isEmpty {
                    let share = Double(lengths[number] / total)
                    // A dot has no length and so no share: it appears when the pen reaches it.
                    let progress = share > 0 ? (done - before) / share : (done >= before ? 1 : 0)
                    before += share
                    if progress <= 0 { continue }
                    let whole = Written.smooth(stroke)
                    graphics.stroke(
                        progress < 1 ? whole.trimmedPath(from: 0, to: progress) : whole,
                        with: .color(glyph.color(of: number) ?? ink),
                        style: StrokeStyle(lineWidth: fitted.line, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .task { await draw() }
        // A doodle is decoration: VoiceOver has nothing to say about it.
        .accessibilityHidden(true)
    }

    private func draw() async {
        if reduceMotion || duration <= 0 {
            still = true
            return
        }
        began = Date()
        still = false
        try? await Task.sleep(for: .seconds(delay + duration + 0.1))
        if !Task.isCancelled { still = true }
    }

    private static func length(of stroke: [CGPoint]) -> CGFloat {
        var length: CGFloat = 0
        for i in 1..<max(1, stroke.count) {
            length += hypot(stroke[i].x - stroke[i - 1].x, stroke[i].y - stroke[i - 1].y)
        }
        return length
    }
}
