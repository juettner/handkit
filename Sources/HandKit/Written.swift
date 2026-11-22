//
//  Written.swift
//
//  Where every pen stroke goes, and when. Pure arithmetic, no views.
//
//  `Written` breaks a text into lines at the page width, picks a drawing for
//  each letter, nudges it slightly so no two are placed alike, and gives
//  every stroke a start time and a duration. The view (Handwriting.swift)
//  only has to draw what this worked out, up to "now".
//
//  The rhythm is a hand's: time spent on a stroke follows its length, the
//  pen lifts briefly between strokes, a little longer between letters, longer
//  between words, and rests after a comma or a full stop.
//
//  Two things keep it from reading as a font. A drawing marked rare takes
//  the place of the usual one only now and then (an "i" dotted with a
//  heart), never twice in a word. And now and then a scribble, a heart or
//  whatever was doodled, follows the line. Lines that should stay plain turn
//  both off with `playful`.
//
//  The same line is always written the same way (a seeded generator keyed on
//  the text), so nothing shimmers when the page redraws.
//
//  `Pen` holds the numbers. Tools/hand_font.py reads them out of this file
//  by name, so the font it makes matches the pen: keep each one on a line of
//  the form `public static let name: CGFloat = 0.0`.
//

import SwiftUI

/// How the pen behaves. Sizes are in x-heights, times in seconds.
public enum Pen {
    /// Letters per second, on average, pauses included.
    public static let lettersPerSecond: Double = 15
    /// The x-height as a share of the type size, so a written headline sits
    /// about as large as the typed one of the same size.
    public static let xHeightPerSize: CGFloat = 0.52
    /// Stroke thickness.
    public static let nib: CGFloat = 0.13
    /// Space between letters, between words, and from one baseline to the next.
    public static let letterGap: CGFloat = 0.2
    public static let wordGap: CGFloat = 0.62
    public static let lineHeight: CGFloat = 2.9
    /// Room above the first baseline for tall letters, and below the last for tails.
    public static let ascent: CGFloat = 1.95
    public static let descent: CGFloat = 0.95
    /// How often a rare drawing takes the place of a usual one, each time its
    /// letter comes up. At most one per word.
    public static let rareChance: Double = 0.12
    /// How often a scribble follows a line.
    public static let scribbleChance: Double = 0.2
    /// How long ink takes to dry.
    public static let dryTime: TimeInterval = 0.7
}

/// One pen stroke, placed on the page and on the clock.
struct Mark {
    let path: Path
    let start: TimeInterval
    let duration: TimeInterval
    /// The stroke's darkness once dry. 1 is full ink.
    let ink: Double
    let width: CGFloat
    /// The colour the stroke was drawn in, or nil for ordinary ink.
    let color: Color?
}

/// A whole line, worked out for one page width.
public struct Written {
    var marks: [Mark] = []
    /// How much room the line takes: its widest row, and the height of all its rows.
    public private(set) var size: CGSize = .zero
    /// When the last stroke ends.
    public private(set) var duration: TimeInterval = 0
    /// When each word starts, for the haptic ticks.
    public private(set) var wordStarts: [TimeInterval] = []

    /// `playful` allows the rare drawings and the scribbles; without it the
    /// line is written plainly. `seed` changes which drawings are picked, for
    /// writing the same text a different way.
    public init(_ text: String, hand: Hand, xHeight: CGFloat, width: CGFloat, lettersPerSecond: Double, playful: Bool = true, seed: Int = 0) {
        var random = Seeded(seed == 0 ? text : "\(text)#\(seed)")
        // Words are split at any white space. A line break in the text is kept:
        // the word after it starts a new line on the page.
        var words: [String] = []
        var breaks = Set<Int>()
        for line in Hand.spelled(text).split(whereSeparator: \.isNewline) {
            let found = line.split(whereSeparator: \.isWhitespace).map { String($0) }
            if !words.isEmpty && !found.isEmpty { breaks.insert(words.count) }
            words.append(contentsOf: found)
        }
        // Now and then a scribble follows the line, written as one more word.
        let scribbles = random.unit() < Pen.scribbleChance
        if playful && scribbles && !words.isEmpty && !(hand.glyphs[Hand.scribble] ?? []).isEmpty {
            words.append(Hand.scribble)
        }

        var x: CGFloat = 0
        var baseline = Pen.ascent * xHeight
        var widest: CGFloat = 0
        // The clock runs in arbitrary beats first and is scaled to seconds at the end.
        var clock: Double = 0
        var letterCount = 0
        var previous: Character? = nil
        /// True when the text had a line break before the word about to be placed.
        var broken = false
        var pending: [(points: [CGPoint], start: Double, beats: Double, ink: Double, width: CGFloat, color: Color?)] = []
        var starts: [Double] = []

        for (number, word) in words.enumerated() {
            // Pick the drawings first, so the word's width is known before it is placed.
            // A character that was never drawn is left out; the rest of the word is still written.
            let pieces = hand.pieces(of: word, skippingUnknown: true) ?? []
            // Remembered until a word is really placed, in case this one turns out to be empty.
            if breaks.contains(number) { broken = true }
            if pieces.isEmpty { continue }
            var rareUsed = false
            let letters: [Glyph] = pieces.map { piece in
                // Both numbers are always drawn, so one letter's luck never shifts the next one's.
                let roll = random.unit()
                let pick = random.unit()
                let usual = piece.drawings.filter { !$0.isRare }
                let rare = piece.drawings.filter { $0.isRare }
                var pool = usual.isEmpty ? rare : usual
                if playful && !rareUsed && !usual.isEmpty && !rare.isEmpty && roll < Pen.rareChance {
                    pool = rare
                    rareUsed = true
                }
                return pool[Int(pick * Double(pool.count)) % pool.count]
            }
            let wordWidth = letters.reduce(0) { $0 + CGFloat($1.advance) * xHeight }
                + CGFloat(max(0, letters.count - 1)) * Pen.letterGap * xHeight

            if x > 0 {
                x += Pen.wordGap * xHeight
                if broken || x + wordWidth > width {
                    x = 0
                    baseline += Pen.lineHeight * xHeight
                }
            }

            broken = false

            // The breath before a word, and the rest after punctuation.
            if let previous {
                clock += 1.6
                if ",;:".contains(previous) { clock += 3 }
                if ".?!".contains(previous) { clock += 6 }
            }
            starts.append(clock)
            // The ribbon idea carried over: a whole word leans a little faint or heavy.
            let lean = random.between(-0.1, 0.02)

            for (index, glyph) in letters.enumerated() {
                let advance = CGFloat(glyph.advance) * xHeight
                // A word longer than the page breaks where it must.
                if x > 0 && x + advance > width {
                    x = 0
                    baseline += Pen.lineHeight * xHeight
                }
                if index > 0 { clock += 0.45 }

                // No hand puts a letter down the same way twice.
                let lift = CGFloat(random.between(-0.05, 0.05)) * xHeight
                let scale = CGFloat(random.between(0.96, 1.04))
                let tilt = CGFloat(random.between(-0.035, 0.035))
                let ink = min(1, max(0.72, 0.93 + lean + random.between(-0.07, 0.07)))
                let nib = Pen.nib * xHeight * CGFloat(random.between(0.92, 1.08))
                let origin = CGPoint(x: x, y: baseline + lift)
                let pivot = CGPoint(x: CGFloat(glyph.advance) / 2, y: -0.5)

                for (strokeIndex, stroke) in glyph.points.enumerated() where !stroke.isEmpty {
                    if strokeIndex > 0 { clock += 0.3 }
                    var length: CGFloat = 0
                    for i in 1..<max(1, stroke.count) {
                        length += hypot(stroke[i].x - stroke[i - 1].x, stroke[i].y - stroke[i - 1].y)
                    }
                    // Long strokes are made faster than short ones, as a hand does.
                    let beats = 0.25 + 0.5 * pow(Double(length), 0.75)
                    let placed = stroke.map { point -> CGPoint in
                        let dx = (point.x - pivot.x) * scale
                        let dy = (point.y - pivot.y) * scale
                        let rx = dx * cos(tilt) - dy * sin(tilt) + pivot.x
                        let ry = dx * sin(tilt) + dy * cos(tilt) + pivot.y
                        return CGPoint(x: origin.x + rx * xHeight, y: origin.y + ry * xHeight)
                    }
                    pending.append((placed, clock, beats, ink, nib, glyph.color(of: strokeIndex)))
                    clock += beats
                }

                x += advance
                widest = max(widest, x)
                if index < letters.count - 1 { x += Pen.letterGap * xHeight }
                // Joined letters count as the letters they stand for, so they are not rushed.
                letterCount += pieces[index].count
            }
            previous = word.last
        }

        // Scale the beats so the line takes as long as that many letters should.
        let seconds = clock > 0 && lettersPerSecond > 0
            ? max(0.4, Double(letterCount) / lettersPerSecond) / clock
            : 0
        marks = pending.map {
            Mark(path: Written.smooth($0.points), start: $0.start * seconds, duration: $0.beats * seconds, ink: $0.ink, width: $0.width, color: $0.color)
        }
        wordStarts = starts.map { $0 * seconds }
        duration = clock * seconds
        size = CGSize(width: widest, height: baseline + Pen.descent * xHeight)
    }

    /// A finger leaves a trail of points. Joining them with straight lines
    /// shows every corner, so the curve runs through the midpoints with the
    /// points themselves as the pull (a quadratic Bezier chain).
    public static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            // A dot: a line of no length still draws its round ends.
            path.addLine(to: first)
            return path
        }
        for i in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

/// A small random number generator that always gives the same numbers for
/// the same seed, so a line is written the same way every time it is drawn.
/// (Java's `new Random(seed)`, keyed on a string. The mixing is SplitMix64.)
struct Seeded {
    private var state: UInt64

    init(_ seed: String) {
        // FNV-1a: turns the string into one 64-bit number.
        var hash: UInt64 = 14695981039346656037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        state = hash
    }

    /// A value from 0 up to, but not including, 1.
    mutating func unit() -> Double {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / 9007199254740992 // 2^53
    }

    mutating func between(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * unit()
    }
}
