//
//  Hand.kt
//
//  Handwriting, as data. The Kotlin twin of Sources/HandKit/Hand.swift, and
//  it reads the very same hand.json.
//
//  A font is a file of outlines somebody else drew. A hand is the pen
//  strokes you drew yourself, letter by letter, on the drawing page (which
//  is on the iPad: see the README). The pen (Handwriting) writes a line with
//  those strokes, in the order and the direction you made them, which is what
//  makes it look written and not set.
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
//  uses that piece wherever those letters meet (see `piecesOf`).
//
//  Words can be crossed out. Text between two pairs of tildes, as in
//  "you looked ~~nice~~ incredible", is written and then struck through, the
//  way a second thought looks on paper (see `struck`). The tildes themselves
//  are never written.
//
//  Units. Everything is measured in x-heights: the height of a lower-case
//  "x". The baseline is y = 0 and y grows downwards, so the body of an "a"
//  runs from -1 to 0, a "d" reaches up to about -1.8 and a "g" hangs down to
//  about 0.8. x starts at the left edge of the ink. Storing it this way means
//  the drawing can be shown at any size.
//
//  A hand is plain JSON:
//
//      { "glyphs": { "a": [ { "strokes": [[x0, y0, x1, y1, ...]], "advance": 0.8 } ] } }
//
//  A stroke can also carry its own colour and its own thickness ("colors"
//  and "widths", one entry per stroke). Both are left out of the file when
//  the drawing is all ordinary ink in the usual line.
//
//  For a Java person: two immutable value classes (a Kotlin `data class` is a
//  Java record), with @Serializable where Jackson would have its
//  annotations. Nothing in this file knows about Android: it is plain Kotlin
//  and is tested on the JVM (src/test).
//
//  One difference from the Swift file. Swift's `Character` is a whole
//  "grapheme" (an emoji made of several code points is one Character). Kotlin
//  has no such type, so here a character is a String holding one Unicode code
//  point. For every letter a hand can actually hold that is the same thing.
//

package com.juettner.handkit

import java.text.Normalizer
import java.util.Locale
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** A place on the page. Plain numbers, so the arithmetic can be tested without a screen. */
data class Point(val x: Double, val y: Double)

@Serializable
data class Glyph(
    /** Each stroke is one pen-down to pen-up, flattened to x0, y0, x1, y1, ... */
    val strokes: List<List<Double>>,
    /** The width of the ink, in x-heights. */
    val advance: Double,
    /**
     * A drawing for now and then, not for every time: an "i" dotted with a
     * heart, an "o" drawn as one. Left out of the file for ordinary drawings.
     */
    val rare: Boolean? = null,
    /**
     * A drawing for some of the time: more than rare, less than usual. Left
     * out of the file unless set. (`rare` wins if a file has both.)
     */
    val occasional: Boolean? = null,
    /**
     * The colour of each stroke as 0xRRGGBB, in the same order as `strokes`,
     * with -1 for ordinary ink. Left out when the whole drawing is in ink.
     */
    val colors: List<Int>? = null,
    /**
     * How thick each stroke is, in the same order as `strokes`, as a multiple
     * of the pen's usual line (`Pen.nib`): 1 is the usual line, 0.5 half as
     * thick, 2 twice. Left out when the whole drawing is in the usual line,
     * so files drawn before this existed read as they always did.
     */
    val widths: List<Double>? = null,
) {
    val isRare: Boolean get() = rare == true

    /**
     * How often the pen reaches for a drawing, when a letter has several.
     *
     *   usual       the everyday ones. The pen picks between them evenly.
     *   occasional  variety: takes a usual one's place some of the time.
     *   rare        a surprise: takes its place only once in a long while.
     *
     * The odds are `Pen.occasionalChance` and `Pen.rareChance`.
     */
    enum class Frequency { USUAL, OCCASIONAL, RARE }

    /** Read from the two flags above, so files drawn before "occasional" existed still read correctly. */
    val frequency: Frequency
        get() = if (rare == true) Frequency.RARE else if (occasional == true) Frequency.OCCASIONAL else Frequency.USUAL

    /** The same drawing, used that often. (A data class is not changed; a changed copy is made.) */
    fun with(frequency: Frequency): Glyph = copy(
        rare = if (frequency == Frequency.RARE) true else null,
        occasional = if (frequency == Frequency.OCCASIONAL) true else null,
    )

    /** The colour a stroke was drawn in as 0xRRGGBB, or null for ordinary ink. */
    fun colorOf(stroke: Int): Int? {
        val color = colors?.getOrNull(stroke) ?: return null
        return if (color >= 0) color else null
    }

    /** How thick a stroke is, as a multiple of the pen's usual line. 1 unless the stroke was drawn finer or bolder. */
    fun widthOf(stroke: Int): Double {
        val width = widths?.getOrNull(stroke) ?: return 1.0
        return if (width > 0) width else 1.0
    }

    /** The thickest line in the drawing, as a multiple of the usual one. For working out how much room the ink takes. */
    val thickest: Double get() = strokes.indices.maxOfOrNull { widthOf(it) } ?: 1.0

    /**
     * The strokes as points. `by lazy` works it out the first time it is
     * asked for and keeps the answer; the JSON mapping leaves it alone.
     */
    val points: List<List<Point>> by lazy {
        strokes.map { flat -> (0 until flat.size - 1 step 2).map { Point(flat[it], flat[it + 1]) } }
    }
}

@Serializable
data class Hand(
    /** Keyed by what the drawing stands for: one character, or letters written joined. */
    val glyphs: Map<String, List<Glyph>>,
) {
    /** A hand with nothing drawn. */
    constructor() : this(emptyMap())

    val isEmpty: Boolean get() = glyphs.isEmpty()

    /**
     * The hand as the text of a hand.json. Keys are sorted, so the same hand
     * always gives the same file and a commit shows only what changed.
     */
    fun json(): String = sorted(format.encodeToJsonElement(serializer(), this)).toString()

    /** Every drawing kept under a name. Empty if there are none. */
    fun drawingsNamed(name: String): List<Glyph> = glyphs[drawingKey(name)] ?: emptyList()

    /**
     * The drawings to use for a character, or null if it has never been drawn.
     * Curly quotes and long dashes use the plain ones, accents are dropped,
     * and a missing capital borrows the small letter (and the other way round).
     */
    fun drawingsFor(character: String): List<Glyph>? {
        val key = plain(character)
        glyphs[key]?.takeIf { it.isNotEmpty() }?.let { return it }
        glyphs[key.lowercase(Locale.ROOT)]?.takeIf { it.isNotEmpty() }?.let { return it }
        glyphs[key.uppercase(Locale.ROOT)]?.takeIf { it.isNotEmpty() }?.let { return it }
        return null
    }

    /** One piece of a word as the pen writes it: its drawings, and how many characters it stands for. */
    data class Piece(val drawings: List<Glyph>, val count: Int)

    /**
     * How many characters the longest joined piece has ("th" is 2). Named
     * drawings are not writing, so their (long) keys are left out.
     */
    private val longest: Int by lazy {
        glyphs.keys.filter { !it.startsWith(drawingPrefix) }.maxOfOrNull { it.characters().size } ?: 1
    }

    /**
     * A word cut into the pieces the pen will write. Letters you draw joined
     * ("th") are taken first, longest first, so "the" comes out as "th" then
     * "e"; everything else is one character at a time.
     *
     * Null if some character has never been drawn, unless `skippingUnknown`
     * is set: then that character is left out and the rest is written. Text
     * somebody typed (an emoji, a letter from another alphabet) is better
     * written with a gap than not at all.
     */
    fun piecesOf(word: String, skippingUnknown: Boolean = false): List<Piece>? {
        val letters = word.characters().flatMap { plain(it).characters() }
        val out = ArrayList<Piece>()
        var at = 0
        while (at < letters.size) {
            var taken = false
            if (longest > 1 && letters.size - at > 1) {
                for (length in minOf(longest, letters.size - at) downTo 2) {
                    val joined = glyphs[letters.subList(at, at + length).joinToString("")]
                    if (!joined.isNullOrEmpty()) {
                        out.add(Piece(joined, length))
                        at += length
                        taken = true
                        break
                    }
                }
            }
            if (taken) continue
            val single = drawingsFor(letters[at])
            if (single != null) {
                out.add(Piece(single, 1))
            } else if (!skippingUnknown) {
                return null
            }
            at += 1
        }
        return out
    }

    /** True when every word of the text can be written. */
    fun covers(text: String): Boolean {
        val words = spelled(unstruck(text)).wordsBetweenSpaces()
        return words.isNotEmpty() && words.all { piecesOf(it) != null }
    }

    /**
     * The characters of the text that have never been drawn, each once, in
     * the order they turn up. Empty when the whole text can be written. For
     * telling somebody, while they type, what the pen will leave out.
     */
    fun missingIn(text: String): List<String> {
        val seen = HashSet<String>()
        val out = ArrayList<String>()
        for (character in spelled(unstruck(text)).characters()) {
            if (character.isBlank()) continue
            // A character can fold to more than one: all must be drawn.
            val drawn = plain(character).characters().all { drawingsFor(it) != null }
            if (!drawn && seen.add(character)) out.add(character)
        }
        return out
    }

    /** A stretch of text, and whether it is crossed out. */
    data class Part(val text: String, val struck: Boolean)

    // A `companion object` holds what Java would make `static`.
    companion object {
        private val format = Json { ignoreUnknownKeys = true }

        /** A hand from the text of a hand.json, or null if it is not one. */
        fun from(json: String): Hand? = try {
            format.decodeFromString(serializer(), json)
        } catch (_: Exception) {
            null
        }

        /** A hand from the bytes of a hand.json, or null if they are not one. */
        fun from(bytes: ByteArray): Hand? = from(String(bytes, Charsets.UTF_8))

        /**
         * The key that scribbles are kept under: hearts, stars, whatever you
         * doodle. Now and then one is drawn after a line. It is an ordinary
         * character (a heart outline), so a text that contains it gets one too.
         */
        const val scribble = "♡"

        /**
         * Drawings that are not writing at all: a picture kept under a name,
         * such as "envelope-sealed". They live in the same file as the
         * letters and are shown with `GlyphView`. Their keys start with this
         * character, which no keyboard types (it is from Unicode's private
         * use area), so the pen never mistakes one for text.
         */
        const val drawingPrefix = ""

        /** The name the app's icon is kept under. */
        const val icon = "app-icon"

        /** The key a named drawing is kept under. */
        fun drawingKey(name: String): String = drawingPrefix + name

        /** The name of a named drawing, given its key; null if the key is for writing. */
        fun drawingName(key: String): String? =
            if (key.startsWith(drawingPrefix)) key.substring(drawingPrefix.length) else null

        /** The text as the pen will write it: an ellipsis becomes three full stops. */
        fun spelled(text: String): String = text.replace("…", "...")

        /** The mark that opens and closes a crossing-out: "~~nice~~". */
        const val strike = "~~"

        /**
         * The text cut at its crossing-out marks: each piece, and whether it
         * is crossed out. The marks themselves are gone. A mark with no
         * partner is not a mark: it is left in the text as it was typed.
         *
         *     Hand.struck("you looked ~~nice~~ incredible")
         *     // ("you looked ", false), ("nice", true), (" incredible", false)
         */
        fun struck(text: String): List<Part> {
            val parts = text.split(strike).toMutableList()
            // Marks come in pairs, so a well-formed text cuts into an odd number of parts.
            // An even number means the last mark never closed: put it back.
            if (parts.size % 2 == 0) {
                val tail = parts.removeAt(parts.size - 1)
                parts[parts.size - 1] = parts[parts.size - 1] + strike + tail
            }
            val out = ArrayList<Part>()
            for ((index, part) in parts.withIndex()) {
                if (part.isNotEmpty()) out.add(Part(part, index % 2 == 1))
            }
            return out
        }

        /**
         * The text with its crossing-out marks taken away and the words kept:
         * what to read aloud, or to show where nothing can be struck through.
         */
        fun unstruck(text: String): String = struck(text).joinToString("") { it.text }

        private val accents = Regex("\\p{Mn}+")

        /**
         * The key a character is looked up under: curly quotes and long dashes
         * become the plain ones, and accents are dropped.
         */
        fun plain(character: String): String = when (character) {
            "‘", "’" -> "'"
            "“", "”" -> "\""
            "–", "—" -> "-"
            else ->
                // Plain ASCII has no accents to drop; that is nearly every letter of nearly every note.
                if (character.length == 1 && character[0].code < 0x80) character
                // NFD pulls a letter and its accent apart ("é" becomes "e" and a loose accent); then the accents are dropped.
                else Normalizer.normalize(character, Normalizer.Form.NFD).replace(accents, "")
        }

        /** The same JSON with every object's keys in order. */
        private fun sorted(element: JsonElement): JsonElement = when (element) {
            is JsonObject -> JsonObject(element.toSortedMap().mapValues { sorted(it.value) })
            is JsonArray -> JsonArray(element.map { sorted(it) })
            else -> element
        }
    }
}

/** The words of a text: what is left when it is cut at every run of white space. */
internal fun String.wordsBetweenSpaces(): List<String> {
    val out = ArrayList<String>()
    val word = StringBuilder()
    for (character in this) {
        if (!character.isWhitespace()) {
            word.append(character)
        } else if (word.isNotEmpty()) {
            out.add(word.toString())
            word.clear()
        }
    }
    if (word.isNotEmpty()) out.add(word.toString())
    return out
}

/**
 * A string as its characters, each a String of one Unicode code point.
 *
 * Kotlin's own `String.toList()` gives UTF-16 units, which cuts an emoji in
 * two. (An `internal` function is visible inside this library and nowhere else.)
 */
internal fun String.characters(): List<String> {
    val out = ArrayList<String>(length)
    var index = 0
    while (index < length) {
        val point = codePointAt(index)
        val size = Character.charCount(point)
        out.add(substring(index, index + size))
        index += size
    }
    return out
}
