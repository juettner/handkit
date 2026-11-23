//
//  HandTests.kt
//
//  The arithmetic, without a screen: how a word is cut into drawings, what a
//  hand can and cannot write, and where the pen puts a line.
//
//  These are Tests/HandKitTests/HandTests.swift, test for test, so the two
//  sides are held to the same behaviour. Run with `./gradlew :handkit:test`
//  from handkit/android. They are plain JUnit on the JVM: no phone, no
//  emulator.
//

package com.juettner.handkit

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HandTests {
    /** A straight line one x-height wide: enough of a drawing to lay out. */
    private fun stroke(advance: Double = 1.0) = Glyph(strokes = listOf(listOf(0.0, 0.0, advance, 0.0)), advance = advance)

    private fun hand(vararg keys: String) = Hand(keys.associateWith { listOf(stroke()) })

    /** The box round a stroke's points. */
    private class Box(mark: Mark) {
        val minX = mark.points.minOf { it.x }
        val maxX = mark.points.maxOf { it.x }
        val minY = mark.points.minOf { it.y }
        val maxY = mark.points.maxOf { it.y }
        fun corners() = listOf(minX, minY, maxX, maxY)
    }

    private fun written(
        text: String,
        hand: Hand,
        xHeight: Double = 10.0,
        width: Double = 1000.0,
        lettersPerSecond: Double = 15.0,
        playful: Boolean = false,
        seed: Int = 0,
        looseness: Double = 1.0,
        slant: Double = 0.0,
        signatures: List<Glyph> = emptyList(),
    ) = Written(text, hand, xHeight, width, lettersPerSecond, playful, seed, looseness, slant, signatures)

    @Test
    fun joinedLettersAreTakenFirst() {
        val pieces = hand("t", "h", "e", "th").piecesOf("the")
        assertEquals(listOf(2, 1), pieces?.map { it.count })
    }

    @Test
    fun aMissingLetterMeansTheWordCannotBeWritten() {
        assertNull(hand("t", "h").piecesOf("the"))
        assertFalse(hand("t", "h").covers("the"))
        assertTrue(hand("t", "h", "e").covers("the the"))
    }

    @Test
    fun skippingUnknownLeavesOutOnlyWhatWasNeverDrawn() {
        val pieces = hand("h", "i").piecesOf("hi🙂", skippingUnknown = true)
        assertEquals(2, pieces?.size)
    }

    @Test
    fun capitalsBorrowSmallLettersAndCurlyQuotesBorrowPlainOnes() {
        val h = hand("a", "'")
        assertNotNull(h.drawingsFor("A"))
        assertNotNull(h.drawingsFor("’"))
        assertNotNull(h.drawingsFor("á"))
        assertNull(h.drawingsFor("b"))
    }

    @Test
    fun missingListsEachUndrawnCharacterOnce() {
        assertEquals(listOf("b", "c"), hand("a").missingIn("abba cab"))
        assertEquals(emptyList<String>(), hand("a").missingIn("a a"))
        // An emoji is one character, not the two halves Kotlin stores it as.
        assertEquals(listOf("🙂"), hand("a").missingIn("a 🙂 🙂"))
    }

    @Test
    fun aHandSurvivesBeingSavedAndRead() {
        val original = Hand(
            hand("a").glyphs + ("i" to listOf(Glyph(strokes = listOf(listOf(0.0, -1.0, 0.0, 0.0), listOf(0.0, -1.4)), advance = 0.2, rare = true, colors = listOf(-1, 0xC8322B)))),
        )
        assertEquals(original, Hand.from(original.json()))
        assertNull(Hand.from("not a hand"))
        // What is not set is not written: the file stays as small as the Swift side makes it.
        assertFalse(original.json().contains("occasional"))
        assertFalse(original.json().contains("widths"))
    }

    @Test
    fun aLineWrapsAtThePageWidth() {
        val h = hand("a")
        val one = written("aa aa", h)
        val two = written("aa aa", h, width = 30.0)
        assertTrue(two.size.height > one.size.height)
        assertEquals(2, one.wordStarts.size)
        assertTrue(one.duration > 0)
    }

    @Test
    fun aLineBreakInTheTextStartsANewLine() {
        val h = hand("a")
        val flat = written("aa aa", h)
        val broken = written("aa\naa", h)
        assertTrue(broken.size.height > flat.size.height)
    }

    @Test
    fun theSameTextIsAlwaysWrittenTheSameWay() {
        val h = Hand(mapOf("a" to listOf(stroke(1.0), stroke(0.5), stroke(0.7))))
        val first = written("aaaa aaaa", h, playful = true)
        val second = written("aaaa aaaa", h, playful = true)
        assertEquals(first.size, second.size)
        assertEquals(first.duration, second.duration, 0.0)
        assertEquals(first.marks, second.marks)
    }

    @Test
    fun anUndrawnWordIsLeftOutNotCrashedOn() {
        assertEquals(1, written("zz aa", hand("a")).wordStarts.size)
    }

    @Test
    fun crossingOutMarksAreCutOutOfTheText() {
        val parts = Hand.struck("you looked ~~nice~~ incredible")
        assertEquals(listOf("you looked ", "nice", " incredible"), parts.map { it.text })
        assertEquals(listOf(false, true, false), parts.map { it.struck })
        assertEquals("you looked nice incredible", Hand.unstruck("you looked ~~nice~~ incredible"))
        // A mark that never closes is not a mark.
        assertEquals(listOf("almost ~~there"), Hand.struck("almost ~~there").map { it.text })
        assertEquals(listOf(true, false), Hand.struck("~~a~~ b ~~c").map { it.struck })
        assertEquals("no marks at all", Hand.unstruck("no marks at all"))
        assertTrue(Hand.struck("").isEmpty())
    }

    @Test
    fun theMarksAreNotLettersTheHandIsMissing() {
        val h = hand("a", "b")
        assertEquals(emptyList<String>(), h.missingIn("a ~~b~~ a"))
        assertTrue(h.covers("a ~~b~~ a"))
    }

    @Test
    fun wordsKnowWhichOfThemAreCrossedOutAndWhereLinesBreak() {
        val cut = Written.wordsOf("aa ~~bb cc~~ dd\nee")
        assertEquals(listOf("aa", "bb", "cc", "dd", "ee"), cut.words)
        assertEquals(setOf(1, 2), cut.struck)
        assertEquals(setOf(4), cut.breaks)
        // Crossed out in part is crossed out.
        assertEquals(setOf(0), Written.wordsOf("un~~do~~").struck)
        assertEquals(setOf(1), Written.wordsOf("\n\naa  \n bb").breaks)
    }

    @Test
    fun aCrossedOutWordIsWrittenAndThenStruckThrough() {
        val h = hand("a", "b")
        val plain = written("aa bb", h)
        val struck = written("~~aa~~ bb", h)
        // One more stroke: the line through it. The page is no bigger for it.
        assertEquals(plain.marks.size + 1, struck.marks.size)
        assertEquals(plain.size, struck.size)
        assertEquals(2, struck.wordStarts.size)
        // The line is drawn after the word it crosses out and before the next word starts.
        val line = struck.marks[2]
        assertTrue(line.start > struck.marks[1].start)
        assertTrue(line.start < struck.marks[3].start)
        // Two words crossed out together share one line; on two rows they need two.
        val together = written("~~aa bb~~", h)
        assertEquals(plain.marks.size + 1, together.marks.size)
        val wrapped = written("~~aa bb~~", h, width = 30.0)
        assertEquals(plain.marks.size + 2, wrapped.marks.size)
    }

    @Test
    fun loosenessAndSlantChangeTheMoodNotTheLayout() {
        val h = hand("a")
        val usual = written("aa aa", h)
        val hurried = written("aa aa", h, looseness = 1.6, slant = 0.15)
        assertEquals(usual.size, hurried.size)
        assertEquals(usual.marks.size, hurried.marks.size)
        assertEquals(usual.duration, hurried.duration, 0.0001)
    }

    @Test
    fun namedDrawingsAreKeptApartFromWriting() {
        val h = Hand(hand("a", "b").glyphs + (Hand.drawingKey("envelope-sealed") to listOf(stroke(), stroke())))
        assertEquals(2, h.drawingsNamed("envelope-sealed").size)
        assertTrue(h.drawingsNamed("nothing").isEmpty())
        assertEquals("envelope-sealed", Hand.drawingName(Hand.drawingKey("envelope-sealed")))
        assertNull(Hand.drawingName("th"))
        // The long key must not be taken for joined letters.
        assertEquals(listOf(1, 1), h.piecesOf("ab")?.map { it.count })
    }

    @Test
    fun frequencyReadsOldFilesAndWritesBothFlags() {
        var glyph = Glyph(strokes = listOf(listOf(0.0, 0.0, 1.0, 0.0)), advance = 1.0, rare = true)
        assertEquals(Glyph.Frequency.RARE, glyph.frequency)
        glyph = glyph.with(Glyph.Frequency.OCCASIONAL)
        assertNull(glyph.rare)
        assertEquals(true, glyph.occasional)
        glyph = glyph.with(Glyph.Frequency.USUAL)
        assertNull(glyph.occasional)
        // A file from before "occasional" existed.
        val old = Hand.from("""{"glyphs":{"a":[{"strokes":[[0,0,1,0]],"advance":1}]}}""")
        assertEquals(Glyph.Frequency.USUAL, old?.glyphs?.get("a")?.first()?.frequency)
    }

    @Test
    fun occasionalTurnsUpMoreThanRareAndLessThanUsual() {
        // Three drawings told apart by their width.
        val h = Hand(
            mapOf(
                "a" to listOf(
                    Glyph(strokes = listOf(listOf(0.0, 0.0, 1.0, 0.0)), advance = 1.0),
                    Glyph(strokes = listOf(listOf(0.0, 0.0, 2.0, 0.0)), advance = 2.0, occasional = true),
                    Glyph(strokes = listOf(listOf(0.0, 0.0, 3.0, 0.0)), advance = 3.0, rare = true),
                ),
            ),
        )
        val widths = HashMap<Int, Int>()
        // One letter per word, so "at most one rare per word" does not come into it.
        for (seed in 1..4000) {
            val line = written("a", h, xHeight = 1.0, playful = true, seed = seed)
            widths.merge(Math.round(line.size.width).toInt(), 1, Int::plus)
        }
        val usual = widths[1] ?: 0
        val occasional = widths[2] ?: 0
        val rare = widths[3] ?: 0
        assertTrue(usual > occasional)
        assertTrue(occasional > rare)
        assertTrue(rare > 0)
        println("usual $usual, occasional $occasional, rare $rare of 4000")
    }

    // Signing

    /** A signature two x-heights wide that reaches three above its line and one below. */
    private val signature = Glyph(strokes = listOf(listOf(0.0, -3.0, 2.0, 1.0)), advance = 2.0)

    @Test
    fun aSignatureIsPutUnderTheWritingAndAfterIt() {
        val plain = written("hi", hand("h", "i"), width = 500.0, lettersPerSecond = 10.0)
        val signed = written("hi", hand("h", "i"), width = 500.0, lettersPerSecond = 10.0, signatures = listOf(signature))
        assertEquals(plain.marks.size + 1, signed.marks.size)
        // Its ink starts below the room the writing took, and the page grows to hold it.
        val ink = Box(signed.marks.last())
        assertTrue(ink.minY >= plain.size.height)
        assertTrue(signed.size.height > ink.maxY)
        // The pen signs after the last letter, and takes longer over it.
        assertTrue(signed.marks.last().start > signed.marks[plain.marks.size - 1].start)
        assertTrue(signed.duration > plain.duration)
    }

    @Test
    fun aSignatureCanStandAlone() {
        val alone = written("", Hand(), width = 500.0, lettersPerSecond = 10.0, playful = true, signatures = listOf(signature))
        assertEquals(1, alone.marks.size)
        assertEquals(20.0, alone.size.width, 0.001)
        // Four x-heights of ink and the thickness of the pen above and below.
        assertEquals(40 + 2 * Pen.nib * 10, alone.size.height, 0.001)
        assertTrue(alone.duration > 0)
    }

    // Line thickness

    @Test
    fun aStrokeKeepsTheLineItWasDrawnWith() {
        // Two strokes: the first bold, the second in the usual line.
        val bold = Glyph(strokes = listOf(listOf(0.0, 0.0, 1.0, 0.0), listOf(0.0, -1.0, 1.0, -1.0)), advance = 1.0, widths = listOf(2.0, 1.0))
        assertEquals(2.0, bold.widthOf(0), 0.0)
        assertEquals(1.0, bold.widthOf(1), 0.0)
        assertEquals(2.0, bold.thickest, 0.0)
        // It travels in the file, and the pen writes with it.
        val h = Hand(mapOf("a" to listOf(bold)))
        val back = Hand.from(h.json())!!
        assertEquals(h, back)
        val line = written("a", back, width = 500.0, lettersPerSecond = 10.0)
        assertEquals(2, line.marks.size)
        assertEquals(line.marks[1].width * 2, line.marks[0].width, 0.001)
    }

    @Test
    fun aDrawingWithNoWidthsIsInTheUsualLine() {
        // A file from before line thickness existed.
        val old = Hand.from("""{"glyphs":{"a":[{"strokes":[[0,0,1,0]],"advance":1}]}}""")!!
        val glyph = old.glyphs["a"]!!.first()
        assertNull(glyph.widths)
        assertEquals(1.0, glyph.widthOf(0), 0.0)
        assertEquals(1.0, glyph.thickest, 0.0)
        // And nothing about thickness is written back into it.
        assertFalse(old.json().contains("widths"))
        // A list that is too short, or holds nonsense, falls back to the usual line.
        val odd = Glyph(strokes = listOf(listOf(0.0, 0.0, 1.0, 0.0), listOf(0.0, 0.0, 1.0, 0.0)), advance = 1.0, widths = listOf(0.0))
        assertEquals(1.0, odd.widthOf(0), 0.0)
        assertEquals(1.0, odd.widthOf(1), 0.0)
    }

    @Test
    fun aBoldSignatureIsGivenTheRoomItsLineTakes() {
        val bold = Glyph(strokes = listOf(listOf(0.0, -3.0, 2.0, 1.0)), advance = 2.0, widths = listOf(2.0))
        val alone = written("", Hand(), width = 500.0, lettersPerSecond = 10.0, playful = true, signatures = listOf(bold))
        assertEquals(2 * Pen.nib * 10, alone.marks[0].width, 0.001)
        assertEquals(40 + 2 * 2 * Pen.nib * 10, alone.size.height, 0.001)
    }

    @Test
    fun aSignatureShrinksToFitANarrowPage() {
        val narrow = written("", Hand(), width = 10.0, lettersPerSecond = 10.0, playful = true, signatures = listOf(signature))
        assertEquals(10.0, narrow.size.width, 0.001)
    }

    @Test
    fun theSameNoteIsAlwaysSignedTheSameWayAndTheLettersAreUntouched() {
        val two = listOf(signature, Glyph(strokes = listOf(listOf(0.0, 0.0, 5.0, 0.0)), advance = 5.0))
        fun write(signatures: List<Glyph>) = written("hi", hand("h", "i"), width = 500.0, lettersPerSecond = 10.0, playful = true, signatures = signatures)
        assertEquals(write(two).size, write(two).size)
        // The letters are placed exactly as they are with no signature at all.
        val plain = write(emptyList())
        assertEquals(plain.marks.map { Box(it).corners() }, write(two).marks.take(plain.marks.size).map { Box(it).corners() })
        // An empty drawing is not a signature.
        assertEquals(plain.marks.size, write(listOf(Glyph(strokes = emptyList(), advance = 1.0))).marks.size)
    }

    // The same on every phone

    /**
     * The generator, checked against numbers worked out independently (in
     * Python, with whole-number arithmetic of any size) from the algorithm in
     * Written.swift. If these hold, Kotlin's unsigned 64-bit arithmetic is
     * doing what Swift's does, and the two pens pick alike.
     */
    @Test
    fun theGeneratorGivesTheNumbersTheSwiftOneDoes() {
        fun first(seed: String): List<Double> = Seeded(seed).let { random -> List(4) { random.unit() } }
        assertEquals(listOf(0.609794426847556, 0.7824400354753983, 0.3599910055956336, 0.8588309775155089), first("good morning, love"))
        assertEquals(listOf(0.7636945250957473, 0.06269613950347463, 0.3311103232963081, 0.17342484163636518), first(""))
        // Letters outside ASCII are hashed as their UTF-8 bytes, as Swift's `seed.utf8` is.
        assertEquals(listOf(0.799117642975938, 0.8546757230086068, 0.4025007878226726, 0.1532227461276563), first("café ♡#7"))
    }

    /**
     * `Pen`'s numbers are written down twice, once in Written.swift and once
     * in Written.kt. This reads the Swift ones out of their file and holds
     * the Kotlin ones to them, so the two cannot quietly drift apart.
     */
    @Test
    fun thePensNumbersAreTheOnesInTheSwiftFile() {
        // Tests run with the module's folder (android/handkit) as the working directory.
        val swift = java.io.File("../../Sources/HandKit/Written.swift")
        assertTrue("Written.swift was not found at ${swift.absolutePath}", swift.exists())
        // Only real declarations: a line that starts with one. (The file's header has one in a comment, as an example.)
        val declared = Regex("""(?m)^\s+public static let (\w+): \w+ = ([0-9.]+)""").findAll(swift.readText()).associate { it.groupValues[1] to it.groupValues[2].toDouble() }
        val kotlin = mapOf(
            "lettersPerSecond" to Pen.lettersPerSecond, "xHeightPerSize" to Pen.xHeightPerSize, "nib" to Pen.nib,
            "letterGap" to Pen.letterGap, "wordGap" to Pen.wordGap, "lineHeight" to Pen.lineHeight,
            "ascent" to Pen.ascent, "descent" to Pen.descent, "rareChance" to Pen.rareChance,
            "occasionalChance" to Pen.occasionalChance, "scribbleChance" to Pen.scribbleChance, "dryTime" to Pen.dryTime,
            "wetSpread" to Pen.wetSpread, "strikeHeight" to Pen.strikeHeight, "signatureCare" to Pen.signatureCare,
            "signatureGap" to Pen.signatureGap,
        )
        assertEquals(declared, kotlin)
    }
}
