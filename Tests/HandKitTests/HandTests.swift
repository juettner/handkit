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
}
