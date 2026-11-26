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
//  A word between crossing-out marks ("~~nice~~", see `Hand.struck`) is
//  written like any other, and then, after a moment's second thought, a line
//  is drawn through it.
//
//  `looseness` and `slant` change the mood of the hand without changing the
//  drawings: a loose hand puts its letters down less evenly, and a slanted
//  one leans forward, as writing does in a hurry.
//
//  The same line is always written the same way (a seeded generator keyed on
//  the text), so nothing shimmers when the page redraws.
//
//  A line that has been written can be kept, stroke for stroke, and shown
//  again later without the hand it was written in: see Kept.swift. That is
//  why the strokes are held here as they were laid down (`Laid`, in beats)
//  as well as ready to draw (`Mark`, in seconds).
//
//  `Pen` holds the numbers. Tools/hand_font.py reads them out of this file
//  by name, so the font it makes matches the pen: keep each one on a line of
//  the form `public static let name: CGFloat = 0.0`.
//
//  THIS FILE AND android/.../Written.kt MUST AGREE, number for number and in
//  the order the random numbers are asked for. The generator is the same on
//  both sides, so as long as they agree, a note is written with the same
//  drawings of the same letters, nudged the same way, on an iPhone and on an
//  Android phone. Change one and change the other. (The Android tests read
//  `Pen`'s numbers out of this file and fail if the two have drifted.)
//

import SwiftUI

/// How the pen behaves. Sizes are in x-heights, times in seconds.
public enum Pen {
    /// Letters per second, on average, pauses included.
    public static let lettersPerSecond: Double = 15
    /// The x-height as a share of the type size, so a written headline sits
    /// about as large as the typed one of the same size.
    public static let xHeightPerSize: CGFloat = 0.52
    /// Stroke thickness: the usual line. A stroke drawn finer or bolder on the
    /// drawing page is a multiple of this (`Glyph.widths`).
    public static let nib: CGFloat = 0.13
    /// Space between letters, between words, and from one baseline to the next.
    public static let letterGap: CGFloat = 0.2
    public static let wordGap: CGFloat = 0.62
    public static let lineHeight: CGFloat = 2.9
    /// Room above the first baseline for tall letters, and below the last for tails.
    public static let ascent: CGFloat = 1.95
    public static let descent: CGFloat = 0.95
    /// How often a rare drawing takes the place of a usual one, each time its
    /// letter comes up: about once in thirty. At most one per word.
    public static let rareChance: Double = 0.035
    /// How often an occasional drawing does: about once in five.
    public static let occasionalChance: Double = 0.2
    /// How often a scribble follows a line.
    public static let scribbleChance: Double = 0.2
    /// How long ink takes to dry.
    public static let dryTime: TimeInterval = 0.7
    /// How much wider a stroke is while its ink is wet, as a share of its width.
    public static let wetSpread: CGFloat = 0.12
    /// Where the line through a crossed-out word runs, above the baseline.
    public static let strikeHeight: CGFloat = 0.48
    /// How much slower than a letter a signature is made. A signature is one
    /// long flourish; at the pace of the letters it would be over in a blink.
    public static let signatureCare: Double = 4
    /// The space between the last line of writing and the top of the signature.
    public static let signatureGap: CGFloat = 0.6
    /// Ink written in the rain runs: how far down the page, at most, and over how many seconds.
    public static let runLength: CGFloat = 0.55
    public static let runTime: TimeInterval = 5
    /// Ink read in the sun has faded: how much of its darkness is left once it is dry.
    public static let sunFade: Double = 0.5
}

/// What the weather has done to the ink.
public enum Weathering: String, Sendable {
    /// Nothing: ordinary ink.
    case dry
    /// The ink runs a little way down the page behind the pen, as it does on wet paper.
    case rain
    /// The ink dries pale, as if the page had been left on a windowsill.
    case sun
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

/// One pen stroke as it was laid down, before the clock is turned into
/// seconds: its points on the page, the beat it starts on and how many it
/// takes. A line is kept (Kept.swift) from these.
struct Laid {
    let points: [CGPoint]
    let start: Double
    let beats: Double
    let ink: Double
    let width: CGFloat
    /// The colour the stroke was drawn in as 0xRRGGBB, or nil for ordinary ink.
    let hex: Int?
}

/// A whole line, worked out for one page width.
public struct Written {
    var marks: [Mark] = []
    /// The strokes as they were laid down, and the clock they were laid down on, in beats.
    var laid: [Laid] = []
    var beatStarts: [Double] = []
    var beats: Double = 0
    /// How many letters the line counts as. With a speed in letters per second, that turns beats into seconds.
    var letters = 0
    /// The x-height the strokes were placed at, in points.
    var xHeight: CGFloat = 1
    /// How much room the line takes: its widest row, and the height of all its rows.
    public internal(set) var size: CGSize = .zero
    /// When the last stroke ends.
    public private(set) var duration: TimeInterval = 0
    /// When each word starts, for the haptic ticks.
    public private(set) var wordStarts: [TimeInterval] = []

    /// Nothing written yet. A line that was kept starts from this (Kept.swift).
    init() {}

    /// The text as words: split at any white space, with the crossing-out
    /// marks taken out. `struck` holds the numbers of the words that are
    /// crossed out, and `breaks` the numbers of the words that follow a line
    /// break in the text (each starts a new line on the page).
    static func words(of text: String) -> (words: [String], struck: Set<Int>, breaks: Set<Int>) {
        var words: [String] = []
        var struck = Set<Int>()
        var breaks = Set<Int>()
        var word = ""
        var wordStruck = false
        var lineBroke = false
        // A space after the last character makes the loop end every word the same way.
        let parts = Hand.struck(Hand.spelled(text)) + [(text: " ", struck: false)]
        for part in parts {
            for character in part.text {
                if !character.isWhitespace {
                    word.append(character)
                    // Crossed out in part is crossed out: a line through half a word reads as a slip of the pen.
                    if part.struck { wordStruck = true }
                    continue
                }
                if !word.isEmpty {
                    if lineBroke && !words.isEmpty { breaks.insert(words.count) }
                    if wordStruck { struck.insert(words.count) }
                    words.append(word)
                    word = ""
                    wordStruck = false
                    lineBroke = false
                }
                if character.isNewline { lineBroke = true }
            }
        }
        return (words, struck, breaks)
    }

    /// `playful` allows the rare drawings and the scribbles; without it the
    /// line is written plainly. `seed` changes which drawings are picked, for
    /// writing the same text a different way. `looseness` is how unevenly
    /// the letters are put down (1 is the usual hand, 0 a ruler), and `slant`
    /// how far they lean forward, in x-heights sideways per x-height up.
    ///
    /// `signatures` are drawings of one person's signature (made on
    /// SignaturePad). One of them is put under the writing, on the left, after
    /// everything else. Which one depends on the text and the seed, so the
    /// same note is always signed the same way and two notes usually are not.
    /// The text may be empty: then the signature is all there is.
    public init(
        _ text: String,
        hand: Hand,
        xHeight: CGFloat,
        width: CGFloat,
        lettersPerSecond: Double,
        playful: Bool = true,
        seed: Int = 0,
        looseness: Double = 1,
        slant: Double = 0,
        signatures: [Glyph] = []
    ) {
        var random = Seeded(seed == 0 ? text : "\(text)#\(seed)")
        let cut = Written.words(of: text)
        var words = cut.words
        let breaks = cut.breaks
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
        var pending: [(points: [CGPoint], start: Double, beats: Double, ink: Double, width: CGFloat, color: Int?)] = []
        var starts: [Double] = []
        /// The words crossed out and not yet struck through: where their ink runs, row by row.
        var toStrike: [(from: CGFloat, to: CGFloat, baseline: CGFloat)] = []

        /// Draws the line through the words waiting in `toStrike`: one stroke
        /// for each row they are on, a little unsteady, as a quick line is.
        func strikeThrough() {
            for (row, run) in toStrike.enumerated() {
                // The second thought: the pen stops before it goes back.
                clock += row == 0 ? 3 : 0.6
                let from = run.from - 0.12 * xHeight
                let to = run.to + 0.12 * xHeight
                let length = Double((to - from) / xHeight)
                let height = run.baseline - (Pen.strikeHeight + CGFloat(random.between(-0.06, 0.06))) * xHeight
                // It climbs or falls a little from one end to the other.
                let rise = CGFloat(random.between(-0.09, 0.09)) * xHeight
                let steps = max(2, Int(length / 0.7))
                var points: [CGPoint] = []
                for step in 0...steps {
                    let along = CGFloat(step) / CGFloat(steps)
                    let wobble = CGFloat(random.between(-0.035, 0.035)) * xHeight
                    points.append(CGPoint(x: from + (to - from) * along, y: height + rise * (along - 0.5) + wobble))
                }
                // One quick stroke: faster than a letter of the same length.
                let beats = 0.25 + 0.3 * pow(max(0, length), 0.75)
                pending.append((points, clock, beats, 0.95, Pen.nib * xHeight, nil))
                clock += beats
            }
            toStrike = []
        }

        for (number, word) in words.enumerated() {
            // Pick the drawings first, so the word's width is known before it is placed.
            // A character that was never drawn is left out; the rest of the word is still written.
            let pieces = hand.pieces(of: word, skippingUnknown: true) ?? []
            // Remembered until a word is really placed, in case this one turns out to be empty.
            if breaks.contains(number) { broken = true }
            if pieces.isEmpty { continue }
            let crossedOut = cut.struck.contains(number)
            // The words before this one were crossed out and this one is not: strike them now, before going on.
            if !crossedOut && !toStrike.isEmpty { strikeThrough() }
            var rareUsed = false
            let letters: [Glyph] = pieces.map { piece in
                // Both numbers are always drawn, so one letter's luck never shifts the next one's.
                let roll = random.unit()
                let pick = random.unit()
                let usual = piece.drawings.filter { $0.frequency == .usual }
                let occasional = piece.drawings.filter { $0.frequency == .occasional }
                let rare = piece.drawings.filter { $0.frequency == .rare }
                // A letter with no usual drawing is written with the next most common kind it has.
                var pool = !usual.isEmpty ? usual : !occasional.isEmpty ? occasional : rare
                if playful && !usual.isEmpty {
                    // One roll decides: the lowest numbers are the rare drawing, the next band the occasional one.
                    if !rare.isEmpty && !rareUsed && roll < Pen.rareChance {
                        pool = rare
                        rareUsed = true
                    } else if !occasional.isEmpty && roll < Pen.rareChance + Pen.occasionalChance {
                        pool = occasional
                    }
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
                let lift = CGFloat(random.between(-0.05, 0.05) * looseness) * xHeight
                let scale = CGFloat(1 + random.between(-0.04, 0.04) * looseness)
                let tilt = CGFloat(random.between(-0.035, 0.035) * looseness)
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
                        let ry = dx * sin(tilt) + dy * cos(tilt) + pivot.y
                        // The slant: the higher above the baseline (y is negative there), the further forward.
                        let rx = dx * cos(tilt) - dy * sin(tilt) + pivot.x - ry * CGFloat(slant)
                        return CGPoint(x: origin.x + rx * xHeight, y: origin.y + ry * xHeight)
                    }
                    pending.append((placed, clock, beats, ink, nib * glyph.width(of: strokeIndex), glyph.hex(of: strokeIndex)))
                    clock += beats
                }

                if crossedOut {
                    // The line will run through every letter of the word, and on through the next word if that is on the same row.
                    if let last = toStrike.last, last.baseline == baseline {
                        toStrike[toStrike.count - 1].to = x + advance
                    } else {
                        toStrike.append((x, x + advance, baseline))
                    }
                }
                x += advance
                widest = max(widest, x)
                if index < letters.count - 1 { x += Pen.letterGap * xHeight }
                // Joined letters count as the letters they stand for, so they are not rushed.
                letterCount += pieces[index].count
            }
            previous = word.last
        }
        // The text ended on a crossed-out word.
        if !toStrike.isEmpty { strikeThrough() }

        // The signature, under everything. Its random number is asked for last,
        // so having one never changes how the letters above it come out.
        var signedTo: CGFloat? = nil
        let signable = signatures.filter { glyph in glyph.points.contains { !$0.isEmpty } }
        if !signable.isEmpty {
            let glyph = signable[Int(random.unit() * Double(signable.count)) % signable.count]
            let every = glyph.points.flatMap { $0 }
            let left = every.map(\.x).min() ?? 0
            let right = every.map(\.x).max() ?? 0
            let top = every.map(\.y).min() ?? 0
            let bottom = every.map(\.y).max() ?? 0
            // Drawn at the size it was signed, against the letters; smaller only if the page is too narrow for it.
            let natural = max(right - left, 0.01) * xHeight
            let unit = xHeight * min(1, width / natural)
            let nib = Pen.nib * unit
            // The room left round the ink is for the boldest line in it.
            let edge = nib * glyph.thickest
            let written = !pending.isEmpty
            let above = written ? baseline + (Pen.descent + Pen.signatureGap) * xHeight : edge
            // `top` is how far the ink reaches above its own baseline (a negative number).
            let base = above - top * unit

            if written { clock += 6 }
            starts.append(clock)
            let began = clock
            for (strokeIndex, stroke) in glyph.points.enumerated() where !stroke.isEmpty {
                if strokeIndex > 0 { clock += 0.3 * Pen.signatureCare }
                var length: CGFloat = 0
                for i in 1..<max(1, stroke.count) {
                    length += hypot(stroke[i].x - stroke[i - 1].x, stroke[i].y - stroke[i - 1].y)
                }
                let beats = (0.25 + 0.5 * pow(Double(length), 0.75)) * Pen.signatureCare
                let placed = stroke.map { CGPoint(x: ($0.x - left) * unit, y: base + $0.y * unit) }
                pending.append((placed, clock, beats, 0.95, nib * glyph.width(of: strokeIndex), glyph.hex(of: strokeIndex)))
                clock += beats
            }
            // A letter takes about two beats, pauses included. Counting the
            // signature as that many letters keeps the writing above it at its usual pace.
            letterCount += max(4, Int(((clock - began) / 2).rounded()))
            widest = max(widest, (right - left) * unit)
            signedTo = base + bottom * unit + edge
        }

        laid = pending.map { Laid(points: $0.points, start: $0.start, beats: $0.beats, ink: $0.ink, width: $0.width, hex: $0.color) }
        beatStarts = starts
        self.beats = clock
        self.letters = letterCount
        self.xHeight = xHeight
        size = CGSize(width: widest, height: signedTo ?? baseline + Pen.descent * xHeight)
        settle(lettersPerSecond)
    }

    /// Turns the beats into seconds, so the line takes as long as that many
    /// letters should, and makes the strokes ready to draw. The last step of
    /// working a line out, whether from a text or from a line that was kept.
    mutating func settle(_ lettersPerSecond: Double) {
        let seconds = beats > 0 && lettersPerSecond > 0
            ? max(0.4, Double(letters) / lettersPerSecond) / beats
            : 0
        marks = laid.map {
            Mark(path: Written.smooth($0.points), start: $0.start * seconds, duration: $0.beats * seconds, ink: $0.ink, width: $0.width, color: $0.hex.map { Color(hex: UInt32($0)) })
        }
        wordStarts = beatStarts.map { $0 * seconds }
        duration = beats * seconds
    }

    /// The moment up to which the pen may write when it is allowed `count`
    /// words: the start of the word after them. All of time, once every word
    /// is allowed. (A scribble and a signature each count as a word.)
    public func moment(afterWords count: Int) -> TimeInterval {
        count < wordStarts.count ? wordStarts[max(0, count)] : .infinity
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
