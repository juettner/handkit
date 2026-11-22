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

    // The colours are spelled out as red, green and blue because a default
    // value in a public initializer may only use things that are public too.
    public init(
        paper: Color = Color(red: 255 / 255, green: 255 / 255, blue: 255 / 255),
        ink: Color = Color(red: 30 / 255, green: 26 / 255, blue: 23 / 255),
        grey: Color = Color(red: 154 / 255, green: 144 / 255, blue: 136 / 255),
        muted: Color = Color(red: 107 / 255, green: 98 / 255, blue: 90 / 255),
        faint: Color = Color(red: 196 / 255, green: 188 / 255, blue: 178 / 255),
        rule: Color = Color(red: 241 / 255, green: 238 / 255, blue: 233 / 255),
        edge: Color = Color(red: 230 / 255, green: 225 / 255, blue: 218 / 255),
        heart: Color = Color(red: 200 / 255, green: 50 / 255, blue: 43 / 255),
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
