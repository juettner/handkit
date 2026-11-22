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
            let strokes = glyph.points
            let every = strokes.flatMap { $0 }
            guard let left = every.map(\.x).min(), let right = every.map(\.x).max(),
                  let top = every.map(\.y).min(), let bottom = every.map(\.y).max() else { return }
            let width = max(right - left, 0.01)
            let height = max(bottom - top, 0.01)
            // A little air round the edge, so the round ends of the line are not cut off.
            let scale = min(size.width / width, size.height / height) * 0.92
            let line = max(minimumLine, Pen.nib * scale)
            let dx = (size.width - width * scale) / 2 - left * scale
            let dy = (size.height - height * scale) / 2 - top * scale
            for (number, stroke) in strokes.enumerated() where !stroke.isEmpty {
                let placed = stroke.map { CGPoint(x: $0.x * scale + dx, y: $0.y * scale + dy) }
                graphics.stroke(
                    Written.smooth(placed),
                    with: .color(glyph.color(of: number) ?? ink),
                    style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}
