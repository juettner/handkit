//
//  Kept.swift
//
//  A line the pen wrote, kept stroke for stroke.
//
//  The pen decides a good deal as it writes: which drawing of each letter,
//  how each one is nudged, where the lines break on this page. Give it the
//  same words again with a different hand, a wider page, a larger text size
//  or a newer version of its own arithmetic, and they come out differently.
//  Usually that is what you want. For a note somebody has read it is not:
//  what they saw that morning should be what they see in ten years.
//
//  So a line can be kept. `Kept` is every stroke of a `Written`, where it
//  went and when, and nothing else: no text, no hand. Shown again, it is
//  drawn from those strokes and from nothing else.
//
//      Handwriting(text: note.text, hand: hand, onKept: { kept in save(kept) })   // the first time
//      Handwriting(text: note.text, kept: kept)                                    // every time after
//
//  (The text is still given the second time: VoiceOver reads it.)
//
//  The shapes. Everything is measured in x-heights, so a kept line can be
//  drawn at any size, and its clock is in the pen's own beats, so it can be
//  written out again at any speed, or simply be there.
//
//      { "v": 1, "size": [w, h], "beats": 40.5, "letters": 12, "words": [0, 9.1],
//        "marks": [ { "p": [x0, y0, x1, y1, ...], "s": 0, "d": 1.2, "i": 0.93, "w": 0.13, "c": 13120043 } ] }
//
//  The names are short because there are thousands of strokes in a long
//  note. `p` points, `s` the beat it starts on, `d` how many beats it takes,
//  `i` how dark the ink is once dry, `w` the thickness of the line, `c` its
//  color as 0xRRGGBB (left out for ordinary ink).
//
//  A kept line does not reflow. It was broken for the page it was first
//  written on, and on a wider page it keeps those lines, as a letter on
//  paper would. On a narrower page it is drawn smaller, so that it fits.
//
//  THIS FILE AND android/.../Kept.kt MUST AGREE: a line kept on an iPhone is
//  shown on an Android phone, and the other way round.
//

import SwiftUI

public struct Kept: Codable, Equatable, Sendable {
    /// The version of this shape, for the day it changes.
    public static let version = 1

    public var v: Int
    /// How much room the ink takes: its widest row, and the height of all its rows.
    public var size: [Double]
    /// How long the whole line takes, in beats.
    public var beats: Double
    /// How many letters it counts as: with a speed in letters per second, that turns beats into seconds.
    public var letters: Int
    /// The beat each word starts on.
    public var words: [Double]
    public var marks: [Stroke]

    /// One pen stroke.
    public struct Stroke: Codable, Equatable, Sendable {
        public var p: [Double]
        public var s: Double
        public var d: Double
        public var i: Double
        public var w: Double
        public var c: Int?

        public init(p: [Double], s: Double, d: Double, i: Double, w: Double, c: Int? = nil) {
            self.p = p
            self.s = s
            self.d = d
            self.i = i
            self.w = w
            self.c = c
        }
    }

    public init(size: [Double], beats: Double, letters: Int, words: [Double], marks: [Stroke]) {
        v = Kept.version
        self.size = size
        self.beats = beats
        self.letters = letters
        self.words = words
        self.marks = marks
    }

    /// A kept line from its JSON, or nil if the bytes are not one, or are one
    /// from a newer version of this file than this app knows how to draw.
    public init?(data: Data) {
        guard let kept = try? JSONDecoder().decode(Kept.self, from: data), kept.v == Kept.version, kept.size.count == 2 else { return nil }
        self = kept
    }

    /// The kept line as JSON.
    public func data() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// True when there is nothing in it to draw.
    public var isEmpty: Bool { marks.isEmpty }

    /// The x-height to draw it at on a page of that width, when `xHeight` was
    /// asked for: as asked if it fits, and smaller if the page is narrower
    /// than the one it was written on.
    public func fitted(xHeight: CGFloat, width: CGFloat) -> CGFloat {
        let widest = CGFloat(size.first ?? 0)
        guard widest > 0, width.isFinite, width > 0, widest * xHeight > width else { return xHeight }
        return width / widest
    }
}

/// Numbers are kept to a thousandth of an x-height (and beats to a ten
/// thousandth): far finer than a screen can show, and a third of the size of
/// writing every digit a Double has.
private func rounded(_ value: Double, to places: Double = 1000) -> Double {
    (value * places).rounded() / places
}

public extension Written {
    /// The line as it was written, to be kept. Nothing about the page it was
    /// written on is in it but where the strokes went.
    var kept: Kept {
        let unit = Double(max(xHeight, 0.0001))
        return Kept(
            size: [rounded(Double(size.width) / unit), rounded(Double(size.height) / unit)],
            beats: rounded(beats, to: 10000),
            letters: letters,
            words: beatStarts.map { rounded($0, to: 10000) },
            marks: laid.map { stroke in
                Kept.Stroke(
                    p: stroke.points.flatMap { [rounded(Double($0.x) / unit), rounded(Double($0.y) / unit)] },
                    s: rounded(stroke.start, to: 10000),
                    d: rounded(stroke.beats, to: 10000),
                    i: rounded(stroke.ink),
                    w: rounded(Double(stroke.width) / unit, to: 10000),
                    c: stroke.hex
                )
            }
        )
    }

    /// A line that was kept, ready to draw again at this size and speed.
    /// No hand is asked for: the strokes are all there is.
    init(kept: Kept, xHeight: CGFloat, lettersPerSecond: Double) {
        self.init()
        laid = kept.marks.map { stroke in
            Laid(
                points: stride(from: 0, to: stroke.p.count - 1, by: 2).map { CGPoint(x: CGFloat(stroke.p[$0]) * xHeight, y: CGFloat(stroke.p[$0 + 1]) * xHeight) },
                start: stroke.s,
                beats: stroke.d,
                ink: stroke.i,
                width: CGFloat(stroke.w) * xHeight,
                hex: stroke.c
            )
        }
        beatStarts = kept.words
        beats = kept.beats
        letters = kept.letters
        self.xHeight = xHeight
        size = CGSize(width: CGFloat(kept.size.first ?? 0) * xHeight, height: CGFloat(kept.size.last ?? 0) * xHeight)
        settle(lettersPerSecond)
    }
}
