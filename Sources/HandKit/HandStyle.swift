//
//  HandStyle.swift
//
//  The few colours and the one typeface the drawing page (HandEditor) uses,
//  so it can look like the app it is in. The pen itself needs only an ink
//  colour, which `Handwriting` takes directly.
//
//  `journal` is the look these came from: white paper, near-black ink, warm
//  greys. Pass your own to change any of it:
//
//      var style = HandStyle.journal
//      style.font = { .custom("SpecialElite-Regular", size: $0) }
//      HandEditor(style: style)
//

import SwiftUI

public struct HandStyle {
    /// The page.
    public var paper: Color
    /// Ink: the letter being drawn, the word you can tap.
    public var ink: Color
    /// Quiet text: a count, a hint. Also the baseline of the ruled square.
    public var grey: Color
    /// A quiet word you can tap.
    public var muted: Color
    /// The option you did not pick; the dashed middle line.
    public var faint: Color
    /// The lightest ruled lines.
    public var rule: Color
    /// The border of the square, and the pale neighbouring letters.
    public var edge: Color
    /// Where the colour picker starts: a heart's red.
    public var heart: Color
    /// The typeface for the page's own words, at a size in points.
    public var font: (CGFloat) -> Font

    public init(
        paper: Color = Color(hex: 0xFFFFFF),
        ink: Color = Color(hex: 0x1E1A17),
        grey: Color = Color(hex: 0x9A9088),
        muted: Color = Color(hex: 0x6B625A),
        faint: Color = Color(hex: 0xC4BCB2),
        rule: Color = Color(hex: 0xF1EEE9),
        edge: Color = Color(hex: 0xE6E1DA),
        heart: Color = Color(hex: 0xC8322B),
        font: @escaping (CGFloat) -> Font = { .system(size: $0, design: .serif) }
    ) {
        self.paper = paper
        self.ink = ink
        self.grey = grey
        self.muted = muted
        self.faint = faint
        self.rule = rule
        self.edge = edge
        self.heart = heart
        self.font = font
    }

    /// White paper, near-black ink, the system serif.
    public static let journal = HandStyle()
}
