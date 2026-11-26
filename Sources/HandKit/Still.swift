//
//  Still.swift
//
//  A line the pen wrote, as a picture: for sending a note to somebody who
//  does not have the app, or saving it with the photographs.
//
//      let picture = Handwriting.image(text: "good morning, love", hand: hand, width: 320)
//
//  `Handwriting` is a view, and a view only exists on a screen. This does the
//  same arithmetic (Written) and draws the finished, dry line into an image
//  with Core Graphics, the drawing library underneath SwiftUI. The same text,
//  hand, size, width and seed give the same line the view shows, because both
//  ask Written where every stroke goes.
//
//  What a picture cannot keep: the writing itself (it is already written),
//  the wet ink behind the nib, and the weather.
//
//  iOS only: it uses UIKit's image renderer, as the drawing page's icon does.
//

#if os(iOS)
import SwiftUI
import UIKit

public extension Handwriting {
    /// The finished line as a picture, or nil if there is nothing to draw (no
    /// text, or no letter of it in the hand).
    ///
    /// - Parameters:
    ///   - width: how wide the writing may run before it turns to a new line, in points.
    ///   - paper: what is behind the ink. Nil leaves the picture see-through.
    ///   - margin: the paper left around the writing on every side, in points.
    ///   - scale: pixels per point. 3 is a current iPhone's screen.
    ///
    /// The others are `Handwriting`'s own.
    @MainActor
    static func image(
        text: String,
        hand: Hand,
        size: CGFloat = 30,
        width: CGFloat,
        ink: Color = HandStyle.journal.ink,
        paper: Color? = HandStyle.journal.paper,
        margin: CGFloat = 24,
        playful: Bool = true,
        seed: Int = 0,
        looseness: Double = 1,
        slant: Double = 0,
        signatures: [Glyph] = [],
        scale: CGFloat = 3
    ) -> UIImage? {
        // A speed of zero: every stroke is down from the start.
        let written = Written(
            text, hand: hand, xHeight: size * Pen.xHeightPerSize, width: width, lettersPerSecond: 0,
            playful: playful, seed: seed, looseness: looseness, slant: slant, signatures: signatures
        )
        guard !written.marks.isEmpty, written.size.width > 0, written.size.height > 0 else { return nil }

        // The paper is as wide as the page the line was broken for, so a short
        // last line does not make a narrow picture.
        let page = CGSize(
            width: (max(width, written.size.width) + 2 * margin).rounded(.up),
            height: (written.size.height + 2 * margin).rounded(.up)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = paper != nil
        return UIGraphicsImageRenderer(size: page, format: format).image { context in
            if let paper {
                UIColor(paper).setFill()
                context.fill(CGRect(origin: .zero, size: page))
            }
            let pen = context.cgContext
            pen.translateBy(x: margin, y: margin)
            pen.setLineCap(.round)
            pen.setLineJoin(.round)
            for mark in written.marks {
                pen.setLineWidth(mark.width)
                // `mark.ink` is the stroke's own shade once dry: no two letters are quite as dark.
                pen.setStrokeColor(UIColor(mark.color ?? ink).withAlphaComponent(CGFloat(mark.ink)).cgColor)
                pen.addPath(mark.path.cgPath)
                pen.strokePath()
            }
        }
    }
}
#endif
