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

    /// The colour of each stroke as 0xRRGGBB, in the same order as `strokes`,
    /// with -1 for ordinary ink. Left out when the whole drawing is in ink.
    public var colors: [Int]?

    public init(strokes: [[Double]], advance: Double, rare: Bool? = nil, colors: [Int]? = nil) {
        self.strokes = strokes
        self.advance = advance
        self.rare = rare
        self.colors = colors
    }

    public var isRare: Bool { rare == true }

    /// The colour a stroke was drawn in, or nil for ordinary ink.
    public func color(of stroke: Int) -> Color? {
        guard let colors, colors.indices.contains(stroke), colors[stroke] >= 0 else { return nil }
        return Color(hex: UInt32(colors[stroke]))
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
        let words = Hand.spelled(text).split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.allSatisfy { pieces(of: String($0)) != nil }
    }

    /// The characters of the text that have never been drawn, each once, in
    /// the order they turn up. Empty when the whole text can be written. For
    /// telling somebody, while they type, what the pen will leave out.
    public func missing(in text: String) -> [Character] {
        var seen = Set<Character>()
        var out: [Character] = []
        for character in Hand.spelled(text) where !character.isWhitespace {
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
