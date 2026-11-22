//
//  Hand.swift
//
//  Handwriting, as data.
//
//  A font is a file of outlines somebody else drew. A hand is the pen
//  strokes you drew yourself, letter by letter, on the drawing page
//  (HandEditor). The pen (Handwriting) writes a line with those strokes, in
//  the order and the direction you made them, which is what makes it look
//  written and not set.
//
//  The shapes:
//
//    Glyph   one drawing of one character: its pen strokes and how wide it is
//    Hand    every character you have drawn, each with one or more drawings
//            (two or three of a letter stop repeated letters looking stamped)
//
//  Two things keep it from looking like a font. A drawing can be marked
//  rare: it is then used only now and then, in place of the usual ones (an
//  "i" with a heart for a dot). And scribbles, kept under their own key, are
//  small drawings that stand for no letter and sometimes follow a line.
//
//  A drawing does not have to be one character. Letters you write joined,
//  "th" say, can be drawn as one piece under the key "th", and the pen then
//  uses that piece wherever those letters meet (see `pieces(of:)`).
//
//  Words can be crossed out. Text between two pairs of tildes, as in
//  "you looked ~~nice~~ incredible", is written and then struck through, the
//  way a second thought looks on paper (see `struck(_:)`). The tildes
//  themselves are never written.
//
//  Units. Everything is measured in x-heights: the height of a lower-case
//  "x". The baseline is y = 0 and y grows downwards, so the body of an "a"
//  runs from -1 to 0, a "d" reaches up to about -1.8 and a "g" hangs down to
//  about 0.8. x starts at the left edge of the ink. Storing it this way means
//  the drawing can be shown at any size.
//
//  A hand is plain JSON (both types are Codable), so it can be shipped
//  inside an app as hand.json, saved on the phone, or sent over a network:
//
//      { "glyphs": { "a": [ { "strokes": [[x0, y0, x1, y1, ...]], "advance": 0.8 } ] } }
//
//  A stroke can also carry its own colour and its own thickness ("colors"
//  and "widths", one entry per stroke). Both are left out of the file when
//  the drawing is all ordinary ink in the usual line.
//
//  For a Java person: two immutable-ish value classes with Jackson
//  annotations. `Codable` is the annotation; the compiler writes the
//  serializer.
//

import Foundation
import SwiftUI

public struct Glyph: Codable, Equatable {
    /// Each stroke is one pen-down to pen-up, flattened to x0, y0, x1, y1, ...
    public var strokes: [[Double]]
    /// The width of the ink, in x-heights.
    public var advance: Double
    /// A drawing for now and then, not for every time: an "i" dotted with a
    /// heart, an "o" drawn as one. Left out of the file for ordinary drawings.
    public var rare: Bool?
    /// A drawing for some of the time: more than rare, less than usual. Left
    /// out of the file unless set. (`rare` wins if a file has both.)
    public var occasional: Bool?

    /// The colour of each stroke as 0xRRGGBB, in the same order as `strokes`,
    /// with -1 for ordinary ink. Left out when the whole drawing is in ink.
    public var colors: [Int]?

    /// How thick each stroke is, in the same order as `strokes`, as a multiple
    /// of the pen's usual line (`Pen.nib`): 1 is the usual line, 0.5 half as
    /// thick, 2 twice. Left out when the whole drawing is in the usual line,
    /// so files drawn before this existed read as they always did.
    public var widths: [Double]?

    public init(strokes: [[Double]], advance: Double, rare: Bool? = nil, occasional: Bool? = nil, colors: [Int]? = nil, widths: [Double]? = nil) {
        self.widths = widths
        self.occasional = occasional
        self.strokes = strokes
        self.advance = advance
        self.rare = rare
        self.colors = colors
    }

    public var isRare: Bool { rare == true }

    /// How often the pen reaches for a drawing, when a letter has several.
    ///
    ///   usual       the everyday ones. The pen picks between them evenly.
    ///   occasional  variety: takes a usual one's place some of the time.
    ///   rare        a surprise: takes its place only once in a long while.
    ///
    /// The odds are `Pen.occasionalChance` and `Pen.rareChance`.
    public enum Frequency: String, CaseIterable {
        case usual, occasional, rare
    }

    /// Read from, and written to, the two flags above, so files drawn before
    /// "occasional" existed still read correctly.
    public var frequency: Frequency {
        get { rare == true ? .rare : occasional == true ? .occasional : .usual }
        set {
            rare = newValue == .rare ? true : nil
            occasional = newValue == .occasional ? true : nil
        }
    }

    /// The colour a stroke was drawn in, or nil for ordinary ink.
    public func color(of stroke: Int) -> Color? {
        guard let colors, colors.indices.contains(stroke), colors[stroke] >= 0 else { return nil }
        return Color(hex: UInt32(colors[stroke]))
    }

    /// How thick a stroke is, as a multiple of the pen's usual line. 1 unless
    /// the stroke was drawn with a finer or a bolder line.
    public func width(of stroke: Int) -> CGFloat {
        guard let widths, widths.indices.contains(stroke), widths[stroke] > 0 else { return 1 }
        return CGFloat(widths[stroke])
    }

    /// The thickest line in the drawing, as a multiple of the usual one. For
    /// working out how much room the ink takes.
    public var thickest: CGFloat {
        strokes.indices.map { width(of: $0) }.max() ?? 1
    }

    /// The strokes as points.
    public var points: [[CGPoint]] {
        strokes.map { flat in
            stride(from: 0, to: flat.count - 1, by: 2).map { CGPoint(x: flat[$0], y: flat[$0 + 1]) }
        }
    }
}

public struct Hand: Codable, Equatable {
    /// Keyed by what the drawing stands for: one character, or letters written joined.
    public var glyphs: [String: [Glyph]]

    public init(glyphs: [String: [Glyph]] = [:]) {
        self.glyphs = glyphs
    }

    /// A hand from the bytes of a hand.json, or nil if they are not one.
    public init?(data: Data) {
        guard let hand = try? JSONDecoder().decode(Hand.self, from: data) else { return nil }
        self = hand
    }

    /// A hand from a hand.json file, or nil if there is no such file or it is not a hand.
    public init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    /// The hand as the bytes of a hand.json. Keys are sorted, so the same hand
    /// always gives the same file and a commit shows only what changed.
    public func data() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    public var isEmpty: Bool { glyphs.isEmpty }

    /// The key that scribbles are kept under: hearts, stars, whatever you
    /// doodle. Now and then one is drawn after a line. It is an ordinary
    /// character (a heart outline), so a text that contains it gets one too.
    public static let scribble = "\u{2661}"

    /// Drawings that are not writing at all: a picture kept under a name, such
    /// as "envelope-sealed". They live in the same file as the letters, are
    /// drawn on the same page, and are shown with `GlyphView`. Their keys
    /// start with this character, which no keyboard types (it is from
    /// Unicode's private use area), so the pen never mistakes one for text.
    public static let drawingPrefix = "\u{E000}"

    /// The name the app's icon is kept under. It is a named drawing like any
    /// other, drawn on the drawing page's "app icon" entry, with one
    /// difference: its points are measured from the left edge of the square
    /// it was drawn in, not from the left edge of its own ink, so its place
    /// in the icon is kept as well as its shape.
    public static let icon = "app-icon"

    /// The key a named drawing is kept under.
    public static func drawingKey(_ name: String) -> String { drawingPrefix + name }

    /// The name of a named drawing, given its key; nil if the key is for writing.
    public static func drawingName(of key: String) -> String? {
        key.hasPrefix(drawingPrefix) ? String(key.dropFirst(drawingPrefix.count)) : nil
    }

    /// Every drawing kept under a name. Empty if there are none.
    public func drawings(named name: String) -> [Glyph] {
        glyphs[Hand.drawingKey(name)] ?? []
    }

    /// The drawings to use for a character, or nil if it has never been drawn.
    /// Curly quotes and long dashes use the plain ones, accents are dropped,
    /// and a missing capital borrows the small letter (and the other way round).
    public func drawings(for character: Character) -> [Glyph]? {
        let key = Hand.plain(character)
        if let found = glyphs[key], !found.isEmpty { return found }
        if let found = glyphs[key.lowercased()], !found.isEmpty { return found }
        if let found = glyphs[key.uppercased()], !found.isEmpty { return found }
        return nil
    }

    /// A word cut into the pieces the pen will write, each with its drawings
    /// and how many characters it stands for. Letters you draw joined ("th")
    /// are taken first, longest first, so "the" comes out as "th" then "e";
    /// everything else is one character at a time.
    ///
    /// Nil if some character has never been drawn, unless `skippingUnknown`
    /// is set: then that character is left out and the rest is written. Text
    /// somebody typed (an emoji, a letter from another alphabet) is better
    /// written with a gap than not at all.
    public func pieces(of word: String, skippingUnknown: Bool = false) -> [(drawings: [Glyph], count: Int)]? {
        let letters = Array(word.map { Hand.plain($0) }.joined())
        // Named drawings are not writing, so their (long) keys are left out of the search for joined letters.
        let longest = glyphs.keys.filter { !$0.hasPrefix(Hand.drawingPrefix) }.map(\.count).max() ?? 1
        var out: [(drawings: [Glyph], count: Int)] = []
        var at = 0
        while at < letters.count {
            var taken = false
            if longest > 1 && letters.count - at > 1 {
                for length in stride(from: min(longest, letters.count - at), through: 2, by: -1) {
                    if let joined = glyphs[String(letters[at..<at + length])], !joined.isEmpty {
                        out.append((joined, length))
                        at += length
                        taken = true
                        break
                    }
                }
            }
            if taken { continue }
            if let single = drawings(for: letters[at]) {
                out.append((single, 1))
            } else if !skippingUnknown {
                return nil
            }
            at += 1
        }
        return out
    }

    /// True when every word of the text can be written.
    public func covers(_ text: String) -> Bool {
        let words = Hand.spelled(Hand.unstruck(text)).split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.allSatisfy { pieces(of: String($0)) != nil }
    }

    /// The characters of the text that have never been drawn, each once, in
    /// the order they turn up. Empty when the whole text can be written. For
    /// telling somebody, while they type, what the pen will leave out.
    public func missing(in text: String) -> [Character] {
        var seen = Set<Character>()
        var out: [Character] = []
        for character in Hand.spelled(Hand.unstruck(text)) where !character.isWhitespace {
            // A character can fold to more than one ("ß" does not, but be safe): all must be drawn.
            let drawn = Hand.plain(character).allSatisfy { drawings(for: $0) != nil }
            if !drawn && seen.insert(character).inserted { out.append(character) }
        }
        return out
    }

    /// The text as the pen will write it: an ellipsis becomes three full stops.
    public static func spelled(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2026}", with: "...")
    }

    /// The mark that opens and closes a crossing-out: "~~nice~~".
    public static let strike = "~~"

    /// The text cut at its crossing-out marks: each piece, and whether it is
    /// crossed out. The marks themselves are gone. A mark with no partner is
    /// not a mark: it is left in the text as it was typed.
    ///
    ///     Hand.struck("you looked ~~nice~~ incredible")
    ///     // ("you looked ", false), ("nice", true), (" incredible", false)
    public static func struck(_ text: String) -> [(text: String, struck: Bool)] {
        var parts = text.components(separatedBy: strike)
        // Marks come in pairs, so a well-formed text cuts into an odd number of parts.
        // An even number means the last mark never closed: put it back.
        if parts.count % 2 == 0 {
            let tail = parts.removeLast()
            parts[parts.count - 1] += strike + tail
        }
        var out: [(text: String, struck: Bool)] = []
        for (index, part) in parts.enumerated() where !part.isEmpty {
            out.append((part, index % 2 == 1))
        }
        return out
    }

    /// The text with its crossing-out marks taken away and the words kept:
    /// what to read aloud, or to show where nothing can be struck through.
    public static func unstruck(_ text: String) -> String {
        struck(text).map(\.text).joined()
    }

    /// The key a character is looked up under: curly quotes and long dashes
    /// become the plain ones, and accents are dropped.
    public static func plain(_ character: Character) -> String {
        switch character {
        case "\u{2018}", "\u{2019}": return "'"
        case "\u{201C}", "\u{201D}": return "\""
        case "\u{2013}", "\u{2014}": return "-"
        default: return String(character).folding(options: .diacriticInsensitive, locale: nil)
        }
    }
}

extension Color {
    /// A colour from 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
