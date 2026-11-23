//
//  HandTests.swift
//
//  The arithmetic, without a screen: how a word is cut into drawings, what a
//  hand can and cannot write, and where the pen puts a line.
//
//  Run with `swift test` on a Mac, or Product > Test in Xcode.
//  For a Java person: XCTest is JUnit. A method named test... is a @Test.
//

import XCTest
@testable import HandKit

final class HandTests: XCTestCase {
    /// A straight line one x-height wide: enough of a drawing to lay out.
    private func stroke(_ advance: Double = 1) -> Glyph {
        Glyph(strokes: [[0, 0, advance, 0]], advance: advance)
    }

    private func hand(_ keys: String...) -> Hand {
        Hand(glyphs: Dictionary(uniqueKeysWithValues: keys.map { ($0, [stroke()]) }))
    }

    func testJoinedLettersAreTakenFirst() {
        let pieces = hand("t", "h", "e", "th").pieces(of: "the")
        XCTAssertEqual(pieces?.map(\.count), [2, 1])
    }

    func testAMissingLetterMeansTheWordCannotBeWritten() {
        XCTAssertNil(hand("t", "h").pieces(of: "the"))
        XCTAssertFalse(hand("t", "h").covers("the"))
        XCTAssertTrue(hand("t", "h", "e").covers("the the"))
    }

    func testSkippingUnknownLeavesOutOnlyWhatWasNeverDrawn() {
        let pieces = hand("h", "i").pieces(of: "hi🙂", skippingUnknown: true)
        XCTAssertEqual(pieces?.count, 2)
    }

    func testCapitalsBorrowSmallLettersAndCurlyQuotesBorrowPlainOnes() {
        let h = hand("a", "'")
        XCTAssertNotNil(h.drawings(for: "A"))
        XCTAssertNotNil(h.drawings(for: "\u{2019}"))
        XCTAssertNotNil(h.drawings(for: "á"))
        XCTAssertNil(h.drawings(for: "b"))
    }

    func testMissingListsEachUndrawnCharacterOnce() {
        XCTAssertEqual(hand("a").missing(in: "abba cab"), ["b", "c"])
        XCTAssertEqual(hand("a").missing(in: "a a"), [])
    }

    func testAHandSurvivesBeingSavedAndRead() throws {
        var original = hand("a")
        original.glyphs["i"] = [Glyph(strokes: [[0, -1, 0, 0], [0, -1.4]], advance: 0.2, rare: true, colors: [-1, 0xC8322B])]
        let data = try XCTUnwrap(original.data())
        XCTAssertEqual(Hand(data: data), original)
        XCTAssertNil(Hand(data: Data("not a hand".utf8)))
    }

    func testAHeldPenMayWriteUpToTheStartOfTheNextWord() {
        let h = hand("a")
        let line = Written("aa aa aa", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15, playful: false)
        XCTAssertEqual(line.wordStarts.count, 3)
        // Allowed no words, the pen may not start. Allowed one, it stops where the second begins.
        XCTAssertEqual(line.moment(afterWords: 0), 0)
        XCTAssertEqual(line.moment(afterWords: 1), line.wordStarts[1])
        XCTAssertGreaterThan(line.moment(afterWords: 2), line.moment(afterWords: 1))
        // Allowed every word, or more, nothing holds it.
        XCTAssertEqual(line.moment(afterWords: 3), .infinity)
        XCTAssertEqual(line.moment(afterWords: 99), .infinity)
    }

    func testALineWrapsAtThePageWidth() {
        let h = hand("a")
        let one = Written("aa aa", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15, playful: false)
        let two = Written("aa aa", hand: h, xHeight: 10, width: 30, lettersPerSecond: 15, playful: false)
        XCTAssertGreaterThan(two.size.height, one.size.height)
        XCTAssertEqual(one.wordStarts.count, 2)
        XCTAssertGreaterThan(one.duration, 0)
    }

    func testALineBreakInTheTextStartsANewLine() {
        let h = hand("a")
        let flat = Written("aa aa", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15, playful: false)
        let broken = Written("aa\naa", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15, playful: false)
        XCTAssertGreaterThan(broken.size.height, flat.size.height)
    }

    func testTheSameTextIsAlwaysWrittenTheSameWay() {
        let h = Hand(glyphs: ["a": [stroke(1), stroke(0.5), stroke(0.7)]])
        let first = Written("aaaa aaaa", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15)
        let second = Written("aaaa aaaa", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15)
        XCTAssertEqual(first.size, second.size)
        XCTAssertEqual(first.duration, second.duration)
    }

    func testAnUndrawnWordIsLeftOutNotCrashedOn() {
        let written = Written("zz aa", hand: hand("a"), xHeight: 10, width: 1000, lettersPerSecond: 15, playful: false)
        XCTAssertEqual(written.wordStarts.count, 1)
    }

    func testCrossingOutMarksAreCutOutOfTheText() {
        let parts = Hand.struck("you looked ~~nice~~ incredible")
        XCTAssertEqual(parts.map(\.text), ["you looked ", "nice", " incredible"])
        XCTAssertEqual(parts.map(\.struck), [false, true, false])
        XCTAssertEqual(Hand.unstruck("you looked ~~nice~~ incredible"), "you looked nice incredible")
        // A mark that never closes is not a mark.
        XCTAssertEqual(Hand.struck("almost ~~there").map(\.text), ["almost ~~there"])
        XCTAssertEqual(Hand.struck("~~a~~ b ~~c").map(\.struck), [true, false])
        XCTAssertEqual(Hand.unstruck("no marks at all"), "no marks at all")
        XCTAssertTrue(Hand.struck("").isEmpty)
    }

    func testTheMarksAreNotLettersTheHandIsMissing() {
        let h = hand("a", "b")
        XCTAssertEqual(h.missing(in: "a ~~b~~ a"), [])
        XCTAssertTrue(h.covers("a ~~b~~ a"))
    }

    func testWordsKnowWhichOfThemAreCrossedOutAndWhereLinesBreak() {
        let cut = Written.words(of: "aa ~~bb cc~~ dd\nee")
        XCTAssertEqual(cut.words, ["aa", "bb", "cc", "dd", "ee"])
        XCTAssertEqual(cut.struck, [1, 2])
        XCTAssertEqual(cut.breaks, [4])
        // Crossed out in part is crossed out.
        XCTAssertEqual(Written.words(of: "un~~do~~").struck, [0])
        XCTAssertEqual(Written.words(of: "\n\naa  \n bb").breaks, [1])
    }

    func testACrossedOutWordIsWrittenAndThenStruckThrough() {
        let h = hand("a", "b")
        let plain = Written("aa bb", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15, playful: false)
        let struck = Written("~~aa~~ bb", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15, playful: false)
        // One more stroke: the line through it. The page is no bigger for it.
        XCTAssertEqual(struck.marks.count, plain.marks.count + 1)
        XCTAssertEqual(struck.size, plain.size)
        XCTAssertEqual(struck.wordStarts.count, 2)
        // The line is drawn after the word it crosses out and before the next word starts.
        let line = struck.marks[2]
        XCTAssertGreaterThan(line.start, struck.marks[1].start)
        XCTAssertLessThan(line.start, struck.marks[3].start)
        // Two words crossed out together share one line; on two rows they need two.
        let together = Written("~~aa bb~~", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15, playful: false)
        XCTAssertEqual(together.marks.count, plain.marks.count + 1)
        let wrapped = Written("~~aa bb~~", hand: h, xHeight: 10, width: 30, lettersPerSecond: 15, playful: false)
        XCTAssertEqual(wrapped.marks.count, plain.marks.count + 2)
    }

    func testLoosenessAndSlantChangeTheMoodNotTheLayout() {
        let h = hand("a")
        let usual = Written("aa aa", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15, playful: false)
        let hurried = Written("aa aa", hand: h, xHeight: 10, width: 1000, lettersPerSecond: 15, playful: false, looseness: 1.6, slant: 0.15)
        XCTAssertEqual(usual.size, hurried.size)
        XCTAssertEqual(usual.marks.count, hurried.marks.count)
        XCTAssertEqual(usual.duration, hurried.duration, accuracy: 0.0001)
    }

    func testNamedDrawingsAreKeptApartFromWriting() {
        var h = hand("a", "b")
        h.glyphs[Hand.drawingKey("envelope-sealed")] = [stroke(), stroke()]
        XCTAssertEqual(h.drawings(named: "envelope-sealed").count, 2)
        XCTAssertTrue(h.drawings(named: "nothing").isEmpty)
        XCTAssertEqual(Hand.drawingName(of: Hand.drawingKey("envelope-sealed")), "envelope-sealed")
        XCTAssertNil(Hand.drawingName(of: "th"))
        // The long key must not be taken for joined letters.
        XCTAssertEqual(h.pieces(of: "ab")?.map(\.count), [1, 1])
    }

    func testFrequencyReadsOldFilesAndWritesBothFlags() throws {
        var glyph = Glyph(strokes: [[0, 0, 1, 0]], advance: 1, rare: true)
        XCTAssertEqual(glyph.frequency, .rare)
        glyph.frequency = .occasional
        XCTAssertNil(glyph.rare)
        XCTAssertEqual(glyph.occasional, true)
        glyph.frequency = .usual
        XCTAssertNil(glyph.occasional)
        // A file from before "occasional" existed.
        let old = try XCTUnwrap(Hand(data: Data(#"{"glyphs":{"a":[{"strokes":[[0,0,1,0]],"advance":1}]}}"#.utf8)))
        XCTAssertEqual(old.glyphs["a"]?.first?.frequency, .usual)
    }

    func testOccasionalTurnsUpMoreThanRareAndLessThanUsual() {
        // Three drawings told apart by their width.
        let h = Hand(glyphs: ["a": [
            Glyph(strokes: [[0, 0, 1, 0]], advance: 1),
            Glyph(strokes: [[0, 0, 2, 0]], advance: 2, occasional: true),
            Glyph(strokes: [[0, 0, 3, 0]], advance: 3, rare: true),
        ]])
        var widths: [Int: Int] = [:]
        // One letter per word, so "at most one rare per word" does not come into it.
        for seed in 1...4000 {
            let written = Written("a", hand: h, xHeight: 1, width: 1000, lettersPerSecond: 15, seed: seed)
            widths[Int(written.size.width.rounded()), default: 0] += 1
        }
        let usual = widths[1] ?? 0, occasional = widths[2] ?? 0, rare = widths[3] ?? 0
        XCTAssertGreaterThan(usual, occasional)
        XCTAssertGreaterThan(occasional, rare)
        XCTAssertGreaterThan(rare, 0)
        print("usual \(usual), occasional \(occasional), rare \(rare) of 4000")
    }

    // MARK: - Signing

    /// A signature two x-heights wide that reaches three above its line and one below.
    private var signature: Glyph {
        Glyph(strokes: [[0, -3, 2, 1]], advance: 2)
    }

    func testASignatureIsPutUnderTheWritingAndAfterIt() {
        let plain = Written("hi", hand: hand("h", "i"), xHeight: 10, width: 500, lettersPerSecond: 10, playful: false)
        let signed = Written("hi", hand: hand("h", "i"), xHeight: 10, width: 500, lettersPerSecond: 10, playful: false, signatures: [signature])
        XCTAssertEqual(signed.marks.count, plain.marks.count + 1)
        // Its ink starts below the room the writing took, and the page grows to hold it.
        let ink = signed.marks.last!.path.boundingRect
        XCTAssertGreaterThanOrEqual(ink.minY, plain.size.height)
        XCTAssertGreaterThan(signed.size.height, ink.maxY)
        // The pen signs after the last letter, and takes longer over it.
        XCTAssertGreaterThan(signed.marks.last!.start, signed.marks[plain.marks.count - 1].start)
        XCTAssertGreaterThan(signed.duration, plain.duration)
    }

    func testASignatureCanStandAlone() {
        let alone = Written("", hand: Hand(), xHeight: 10, width: 500, lettersPerSecond: 10, signatures: [signature])
        XCTAssertEqual(alone.marks.count, 1)
        XCTAssertEqual(alone.size.width, 20, accuracy: 0.001)
        // Four x-heights of ink and the thickness of the pen above and below.
        XCTAssertEqual(alone.size.height, 40 + 2 * Pen.nib * 10, accuracy: 0.001)
        XCTAssertGreaterThan(alone.duration, 0)
    }

    // MARK: - Line thickness

    func testAStrokeKeepsTheLineItWasDrawnWith() throws {
        // Two strokes: the first bold, the second in the usual line.
        let bold = Glyph(strokes: [[0, 0, 1, 0], [0, -1, 1, -1]], advance: 1, widths: [2, 1])
        XCTAssertEqual(bold.width(of: 0), 2)
        XCTAssertEqual(bold.width(of: 1), 1)
        XCTAssertEqual(bold.thickest, 2)
        // It travels in the file, and the pen writes with it.
        let h = Hand(glyphs: ["a": [bold]])
        let back = try XCTUnwrap(Hand(data: try XCTUnwrap(h.data())))
        XCTAssertEqual(back, h)
        let written = Written("a", hand: back, xHeight: 10, width: 500, lettersPerSecond: 10, playful: false)
        XCTAssertEqual(written.marks.count, 2)
        XCTAssertEqual(written.marks[0].width, written.marks[1].width * 2, accuracy: 0.001)
    }

    func testADrawingWithNoWidthsIsInTheUsualLine() throws {
        // A file from before line thickness existed.
        let old = try XCTUnwrap(Hand(data: Data(#"{"glyphs":{"a":[{"strokes":[[0,0,1,0]],"advance":1}]}}"#.utf8)))
        let glyph = try XCTUnwrap(old.glyphs["a"]?.first)
        XCTAssertNil(glyph.widths)
        XCTAssertEqual(glyph.width(of: 0), 1)
        XCTAssertEqual(glyph.thickest, 1)
        // And nothing about thickness is written back into it.
        XCTAssertFalse(String(decoding: try XCTUnwrap(old.data()), as: UTF8.self).contains("widths"))
        // A list that is too short, or holds nonsense, falls back to the usual line.
        let odd = Glyph(strokes: [[0, 0, 1, 0], [0, 0, 1, 0]], advance: 1, widths: [0])
        XCTAssertEqual(odd.width(of: 0), 1)
        XCTAssertEqual(odd.width(of: 1), 1)
    }

    func testABoldSignatureIsGivenTheRoomItsLineTakes() {
        let bold = Glyph(strokes: [[0, -3, 2, 1]], advance: 2, widths: [2])
        let alone = Written("", hand: Hand(), xHeight: 10, width: 500, lettersPerSecond: 10, signatures: [bold])
        XCTAssertEqual(alone.marks[0].width, 2 * Pen.nib * 10, accuracy: 0.001)
        XCTAssertEqual(alone.size.height, 40 + 2 * 2 * Pen.nib * 10, accuracy: 0.001)
    }

    func testASignatureShrinksToFitANarrowPage() {
        let narrow = Written("", hand: Hand(), xHeight: 10, width: 10, lettersPerSecond: 10, signatures: [signature])
        XCTAssertEqual(narrow.size.width, 10, accuracy: 0.001)
    }

    func testTheSameNoteIsAlwaysSignedTheSameWayAndTheLettersAreUntouched() {
        let two = [signature, Glyph(strokes: [[0, 0, 5, 0]], advance: 5)]
        func write(_ signatures: [Glyph]) -> Written {
            Written("hi", hand: hand("h", "i"), xHeight: 10, width: 500, lettersPerSecond: 10, signatures: signatures)
        }
        XCTAssertEqual(write(two).size, write(two).size)
        // The letters are placed exactly as they are with no signature at all.
        let plain = write([])
        XCTAssertEqual(write(two).marks.prefix(plain.marks.count).map(\.path.boundingRect), plain.marks.map(\.path.boundingRect))
        // An empty drawing is not a signature.
        XCTAssertEqual(write([Glyph(strokes: [], advance: 1)]).marks.count, plain.marks.count)
    }
}
