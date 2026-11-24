//
//  Written.kt
//
//  Where every pen stroke goes, and when. Pure arithmetic, no screen. The
//  Kotlin twin of Sources/HandKit/Written.swift.
//
//  `Written` breaks a text into lines at the page width, picks a drawing for
//  each letter, nudges it slightly so no two are placed alike, and gives
//  every stroke a start time and a duration. The view (Handwriting.kt) only
//  has to draw what this worked out, up to "now".
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
//  THIS FILE AND Written.swift MUST AGREE, number for number and in the
//  order the random numbers are asked for. The generator is the same on both
//  sides, so as long as they agree, a note is written with the same drawings
//  of the same letters, nudged the same way, on an iPhone and on an Android
//  phone. Change one and change the other.
//

package com.juettner.handkit

import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** How the pen behaves. Sizes are in x-heights, times in seconds. The same numbers as `Pen` in Written.swift. */
object Pen {
    /** Letters per second, on average, pauses included. */
    const val lettersPerSecond: Double = 15.0
    /** The x-height as a share of the type size, so a written headline sits about as large as the typed one of the same size. */
    const val xHeightPerSize: Double = 0.52
    /** Stroke thickness: the usual line. A stroke drawn finer or bolder is a multiple of this (`Glyph.widths`). */
    const val nib: Double = 0.13
    /** Space between letters, between words, and from one baseline to the next. */
    const val letterGap: Double = 0.2
    const val wordGap: Double = 0.62
    const val lineHeight: Double = 2.9
    /** Room above the first baseline for tall letters, and below the last for tails. */
    const val ascent: Double = 1.95
    const val descent: Double = 0.95
    /** How often a rare drawing takes the place of a usual one, each time its letter comes up: about once in thirty. At most one per word. */
    const val rareChance: Double = 0.035
    /** How often an occasional drawing does: about once in five. */
    const val occasionalChance: Double = 0.2
    /** How often a scribble follows a line. */
    const val scribbleChance: Double = 0.2
    /** How long ink takes to dry. */
    const val dryTime: Double = 0.7
    /** How much wider a stroke is while its ink is wet, as a share of its width. */
    const val wetSpread: Double = 0.12
    /** Where the line through a crossed-out word runs, above the baseline. */
    const val strikeHeight: Double = 0.48
    /** How much slower than a letter a signature is made. A signature is one long flourish; at the pace of the letters it would be over in a blink. */
    const val signatureCare: Double = 4.0
    /** The space between the last line of writing and the top of the signature. */
    const val signatureGap: Double = 0.6

    /** Ink written in the rain runs: how far down the page, at most, and over how many seconds. */
    const val runLength: Double = 0.55
    const val runTime: Double = 5.0
    /** Ink read in the sun has faded: how much of its darkness is left once it is dry. */
    const val sunFade: Double = 0.5
}

/** What the weather has done to the ink. `word` is how it is written down when it is kept. */
enum class Weathering(val word: String) {
    /** Nothing: ordinary ink. */
    DRY("dry"),

    /** The ink runs a little way down the page behind the pen, as it does on wet paper. */
    RAIN("rain"),

    /** The ink dries pale, as if the page had been left on a windowsill. */
    SUN("sun");

    companion object {
        fun of(word: String?): Weathering = entries.firstOrNull { it.word == word } ?: DRY
    }
}

/** One pen stroke, placed on the page and on the clock. */
data class Mark(
    /** The points the stroke runs through, on the page. The view joins them with a curve (`smooth` in Handwriting.kt). */
    val points: List<Point>,
    val start: Double,
    val duration: Double,
    /** The stroke's darkness once dry. 1 is full ink. */
    val ink: Double,
    val width: Double,
    /** The colour the stroke was drawn in as 0xRRGGBB, or null for ordinary ink. */
    val color: Int?,
)

/** How much room a line takes: its widest row, and the height of all its rows. */
data class Extent(val width: Double, val height: Double)

/**
 * A whole line, worked out for one page width.
 *
 * `playful` allows the rare drawings and the scribbles; without it the line
 * is written plainly. `seed` changes which drawings are picked, for writing
 * the same text a different way. `looseness` is how unevenly the letters are
 * put down (1 is the usual hand, 0 a ruler), and `slant` how far they lean
 * forward, in x-heights sideways per x-height up.
 *
 * `signatures` are drawings of one person's signature (made on SignaturePad).
 * One of them is put under the writing, on the left, after everything else.
 * Which one depends on the text and the seed, so the same note is always
 * signed the same way and two notes usually are not. The text may be empty:
 * then the signature is all there is.
 *
 * For a Java person: everything happens in the constructor (`init`), and
 * what is left afterwards is four read-only results. The sizes are in
 * whatever unit `xHeight` and `pageWidth` are given in (the view gives pixels).
 */
class Written(
    text: String,
    hand: Hand,
    xHeight: Double,
    pageWidth: Double,
    lettersPerSecond: Double,
    playful: Boolean = true,
    seed: Int = 0,
    looseness: Double = 1.0,
    slant: Double = 0.0,
    signatures: List<Glyph> = emptyList(),
) {
    val marks: List<Mark>
    val size: Extent
    /** When the last stroke ends. */
    val duration: Double
    /** When each word starts, for the haptic ticks. */
    val wordStarts: List<Double>

    /**
     * The moment up to which the pen may write when it is allowed `count`
     * words: the start of the word after them. All of time, once every word
     * is allowed. (A scribble and a signature each count as a word.)
     */
    fun momentAfterWords(count: Int): Double =
        if (count < wordStarts.size) wordStarts[max(0, count)] else Double.POSITIVE_INFINITY

    /** A stroke before the beats are turned into seconds. */
    private class Pending(val points: List<Point>, val start: Double, val beats: Double, val ink: Double, val width: Double, val color: Int?)

    /** Where the ink of crossed-out words runs on one row. */
    private class Run(val from: Double, var to: Double, val baseline: Double)

    init {
        val random = Seeded(if (seed == 0) text else "$text#$seed")
        val cut = wordsOf(text)
        val words = cut.words.toMutableList()
        val breaks = cut.breaks
        // Now and then a scribble follows the line, written as one more word.
        val scribbles = random.unit() < Pen.scribbleChance
        if (playful && scribbles && words.isNotEmpty() && !hand.glyphs[Hand.scribble].isNullOrEmpty()) {
            words.add(Hand.scribble)
        }

        var x = 0.0
        var baseline = Pen.ascent * xHeight
        var widest = 0.0
        // The clock runs in arbitrary beats first and is scaled to seconds at the end.
        var clock = 0.0
        var letterCount = 0
        var previous: String? = null
        // True when the text had a line break before the word about to be placed.
        var broken = false
        val pending = ArrayList<Pending>()
        val starts = ArrayList<Double>()
        // The words crossed out and not yet struck through: where their ink runs, row by row.
        val toStrike = ArrayList<Run>()

        // Draws the line through the words waiting in `toStrike`: one stroke
        // for each row they are on, a little unsteady, as a quick line is.
        // (A function inside a function; it can read and change the variables above.)
        fun strikeThrough() {
            for ((row, run) in toStrike.withIndex()) {
                // The second thought: the pen stops before it goes back.
                clock += if (row == 0) 3.0 else 0.6
                val from = run.from - 0.12 * xHeight
                val to = run.to + 0.12 * xHeight
                val length = (to - from) / xHeight
                val height = run.baseline - (Pen.strikeHeight + random.between(-0.06, 0.06)) * xHeight
                // It climbs or falls a little from one end to the other.
                val rise = random.between(-0.09, 0.09) * xHeight
                val steps = max(2, (length / 0.7).toInt())
                val points = ArrayList<Point>()
                for (step in 0..steps) {
                    val along = step.toDouble() / steps.toDouble()
                    val wobble = random.between(-0.035, 0.035) * xHeight
                    points.add(Point(from + (to - from) * along, height + rise * (along - 0.5) + wobble))
                }
                // One quick stroke: faster than a letter of the same length.
                val beats = 0.25 + 0.3 * max(0.0, length).pow(0.75)
                pending.add(Pending(points, clock, beats, 0.95, Pen.nib * xHeight, null))
                clock += beats
            }
            toStrike.clear()
        }

        for ((number, word) in words.withIndex()) {
            // Pick the drawings first, so the word's width is known before it is placed.
            // A character that was never drawn is left out; the rest of the word is still written.
            val pieces = hand.piecesOf(word, skippingUnknown = true) ?: emptyList()
            // Remembered until a word is really placed, in case this one turns out to be empty.
            if (number in breaks) broken = true
            if (pieces.isEmpty()) continue
            val crossedOut = number in cut.struck
            // The words before this one were crossed out and this one is not: strike them now, before going on.
            if (!crossedOut && toStrike.isNotEmpty()) strikeThrough()
            var rareUsed = false
            val letters: List<Glyph> = pieces.map { piece ->
                // Both numbers are always drawn, so one letter's luck never shifts the next one's.
                val roll = random.unit()
                val pick = random.unit()
                val usual = piece.drawings.filter { it.frequency == Glyph.Frequency.USUAL }
                val occasional = piece.drawings.filter { it.frequency == Glyph.Frequency.OCCASIONAL }
                val rare = piece.drawings.filter { it.frequency == Glyph.Frequency.RARE }
                // A letter with no usual drawing is written with the next most common kind it has.
                var pool = if (usual.isNotEmpty()) usual else if (occasional.isNotEmpty()) occasional else rare
                if (playful && usual.isNotEmpty()) {
                    // One roll decides: the lowest numbers are the rare drawing, the next band the occasional one.
                    if (rare.isNotEmpty() && !rareUsed && roll < Pen.rareChance) {
                        pool = rare
                        rareUsed = true
                    } else if (occasional.isNotEmpty() && roll < Pen.rareChance + Pen.occasionalChance) {
                        pool = occasional
                    }
                }
                pool[(pick * pool.size).toInt() % pool.size]
            }
            val wordWidth = letters.sumOf { it.advance * xHeight } + max(0, letters.size - 1) * Pen.letterGap * xHeight

            if (x > 0) {
                x += Pen.wordGap * xHeight
                if (broken || x + wordWidth > pageWidth) {
                    x = 0.0
                    baseline += Pen.lineHeight * xHeight
                }
            }

            broken = false

            // The breath before a word, and the rest after punctuation.
            if (previous != null) {
                clock += 1.6
                if (previous in ",;:") clock += 3.0
                if (previous in ".?!") clock += 6.0
            }
            starts.add(clock)
            // A whole word leans a little faint or heavy.
            val lean = random.between(-0.1, 0.02)

            for ((index, glyph) in letters.withIndex()) {
                val advance = glyph.advance * xHeight
                // A word longer than the page breaks where it must.
                if (x > 0 && x + advance > pageWidth) {
                    x = 0.0
                    baseline += Pen.lineHeight * xHeight
                }
                if (index > 0) clock += 0.45

                // No hand puts a letter down the same way twice.
                val lift = random.between(-0.05, 0.05) * looseness * xHeight
                val scale = 1 + random.between(-0.04, 0.04) * looseness
                val tilt = random.between(-0.035, 0.035) * looseness
                val ink = min(1.0, max(0.72, 0.93 + lean + random.between(-0.07, 0.07)))
                val nib = Pen.nib * xHeight * random.between(0.92, 1.08)
                val originX = x
                val originY = baseline + lift
                val pivotX = glyph.advance / 2
                val pivotY = -0.5

                for ((strokeIndex, stroke) in glyph.points.withIndex()) {
                    if (stroke.isEmpty()) continue
                    if (strokeIndex > 0) clock += 0.3
                    val length = lengthOf(stroke)
                    // Long strokes are made faster than short ones, as a hand does.
                    val beats = 0.25 + 0.5 * length.pow(0.75)
                    val placed = stroke.map { point ->
                        val dx = (point.x - pivotX) * scale
                        val dy = (point.y - pivotY) * scale
                        val ry = dx * sin(tilt) + dy * cos(tilt) + pivotY
                        // The slant: the higher above the baseline (y is negative there), the further forward.
                        val rx = dx * cos(tilt) - dy * sin(tilt) + pivotX - ry * slant
                        Point(originX + rx * xHeight, originY + ry * xHeight)
                    }
                    pending.add(Pending(placed, clock, beats, ink, nib * glyph.widthOf(strokeIndex), glyph.colorOf(strokeIndex)))
                    clock += beats
                }

                if (crossedOut) {
                    // The line will run through every letter of the word, and on through the next word if that is on the same row.
                    val last = toStrike.lastOrNull()
                    if (last != null && last.baseline == baseline) {
                        last.to = x + advance
                    } else {
                        toStrike.add(Run(x, x + advance, baseline))
                    }
                }
                x += advance
                widest = max(widest, x)
                if (index < letters.size - 1) x += Pen.letterGap * xHeight
                // Joined letters count as the letters they stand for, so they are not rushed.
                letterCount += pieces[index].count
            }
            previous = word.characters().lastOrNull()
        }
        // The text ended on a crossed-out word.
        if (toStrike.isNotEmpty()) strikeThrough()

        // The signature, under everything. Its random number is asked for last,
        // so having one never changes how the letters above it come out.
        var signedTo: Double? = null
        val signable = signatures.filter { glyph -> glyph.points.any { it.isNotEmpty() } }
        if (signable.isNotEmpty()) {
            val glyph = signable[(random.unit() * signable.size).toInt() % signable.size]
            val every = glyph.points.flatten()
            val left = every.minOf { it.x }
            val right = every.maxOf { it.x }
            val top = every.minOf { it.y }
            val bottom = every.maxOf { it.y }
            // Drawn at the size it was signed, against the letters; smaller only if the page is too narrow for it.
            val natural = max(right - left, 0.01) * xHeight
            val unit = xHeight * min(1.0, pageWidth / natural)
            val nib = Pen.nib * unit
            // The room left round the ink is for the boldest line in it.
            val edge = nib * glyph.thickest
            val written = pending.isNotEmpty()
            val above = if (written) baseline + (Pen.descent + Pen.signatureGap) * xHeight else edge
            // `top` is how far the ink reaches above its own baseline (a negative number).
            val base = above - top * unit

            if (written) clock += 6.0
            starts.add(clock)
            val began = clock
            for ((strokeIndex, stroke) in glyph.points.withIndex()) {
                if (stroke.isEmpty()) continue
                if (strokeIndex > 0) clock += 0.3 * Pen.signatureCare
                val length = lengthOf(stroke)
                val beats = (0.25 + 0.5 * length.pow(0.75)) * Pen.signatureCare
                val placed = stroke.map { Point((it.x - left) * unit, base + it.y * unit) }
                pending.add(Pending(placed, clock, beats, 0.95, nib * glyph.widthOf(strokeIndex), glyph.colorOf(strokeIndex)))
                clock += beats
            }
            // A letter takes about two beats, pauses included. Counting the
            // signature as that many letters keeps the writing above it at its usual pace.
            letterCount += max(4, Math.round((clock - began) / 2).toInt())
            widest = max(widest, (right - left) * unit)
            signedTo = base + bottom * unit + edge
        }

        // Scale the beats so the line takes as long as that many letters should.
        val seconds = if (clock > 0 && lettersPerSecond > 0) max(0.4, letterCount / lettersPerSecond) / clock else 0.0
        marks = pending.map { Mark(it.points, it.start * seconds, it.beats * seconds, it.ink, it.width, it.color) }
        wordStarts = starts.map { it * seconds }
        duration = clock * seconds
        size = Extent(widest, signedTo ?: (baseline + Pen.descent * xHeight))
    }

    /** The words of a text, the numbers of the ones crossed out, and the numbers of the ones that follow a line break. */
    data class Cut(val words: List<String>, val struck: Set<Int>, val breaks: Set<Int>)

    companion object {
        /**
         * The text as words: split at any white space, with the crossing-out
         * marks taken out. `struck` holds the numbers of the words that are
         * crossed out, and `breaks` the numbers of the words that follow a
         * line break in the text (each starts a new line on the page).
         */
        fun wordsOf(text: String): Cut {
            val words = ArrayList<String>()
            val struck = HashSet<Int>()
            val breaks = HashSet<Int>()
            val word = StringBuilder()
            var wordStruck = false
            var lineBroke = false
            // A space after the last character makes the loop end every word the same way.
            val parts = Hand.struck(Hand.spelled(text)) + Hand.Part(" ", false)
            for (part in parts) {
                for (character in part.text) {
                    if (!character.isWhitespace()) {
                        word.append(character)
                        // Crossed out in part is crossed out: a line through half a word reads as a slip of the pen.
                        if (part.struck) wordStruck = true
                        continue
                    }
                    if (word.isNotEmpty()) {
                        if (lineBroke && words.isNotEmpty()) breaks.add(words.size)
                        if (wordStruck) struck.add(words.size)
                        words.add(word.toString())
                        word.clear()
                        wordStruck = false
                        lineBroke = false
                    }
                    if (character in newlines) lineBroke = true
                }
            }
            return Cut(words, struck, breaks)
        }

        private const val newlines = "\n\r\u000B\u000C\u0085  "

        /** How long a stroke is, point to point. */
        internal fun lengthOf(stroke: List<Point>): Double {
            var length = 0.0
            for (i in 1 until stroke.size) {
                length += hypot(stroke[i].x - stroke[i - 1].x, stroke[i].y - stroke[i - 1].y)
            }
            return length
        }
    }
}

/**
 * A small random number generator that always gives the same numbers for
 * the same seed, so a line is written the same way every time it is drawn,
 * and the same way on every phone. (Java's `new Random(seed)`, keyed on a
 * string. The mixing is SplitMix64, the hashing FNV-1a.)
 *
 * `ULong` is an unsigned 64-bit number, which Java does not have. Its
 * arithmetic wraps round on overflow, which is exactly what this wants.
 */
internal class Seeded(seed: String) {
    private var state: ULong

    init {
        // FNV-1a: turns the string into one 64-bit number.
        var hash = 14695981039346656037uL
        for (byte in seed.toByteArray(Charsets.UTF_8)) {
            hash = hash xor (byte.toULong() and 0xFFuL)
            hash *= 1099511628211uL
        }
        state = hash
    }

    /** A value from 0 up to, but not including, 1. */
    fun unit(): Double {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        z = z xor (z shr 31)
        return (z shr 11).toDouble() / 9007199254740992.0 // 2^53
    }

    fun between(low: Double, high: Double): Double = low + (high - low) * unit()
}
