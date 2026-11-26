//
//  Kept.kt
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
//      Handwriting(text = note.text, hand = hand, onKept = { save(it) })   // the first time
//      Handwriting(text = note.text, hand = Hand(), kept = kept)          // every time after
//
//  (The text is still given the second time: TalkBack reads it.)
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
//  colour as 0xRRGGBB (left out for ordinary ink).
//
//  A kept line does not reflow. It was broken for the page it was first
//  written on, and on a wider page it keeps those lines, as a letter on
//  paper would. On a narrower page it is drawn smaller, so that it fits.
//
//  THIS FILE AND Kept.swift MUST AGREE: a line kept on an Android phone is
//  shown on an iPhone, and the other way round.
//

package com.juettner.handkit

import kotlin.math.max
import kotlin.math.round
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class Kept(
    /** The version of this shape, for the day it changes. */
    val v: Int = VERSION,
    /** How much room the ink takes: its widest row, and the height of all its rows. */
    val size: List<Double>,
    /** How long the whole line takes, in beats. */
    val beats: Double,
    /** How many letters it counts as: with a speed in letters per second, that turns beats into seconds. */
    val letters: Int,
    /** The beat each word starts on. */
    val words: List<Double>,
    val marks: List<Stroke>,
) {
    /** One pen stroke. */
    @Serializable
    data class Stroke(val p: List<Double>, val s: Double, val d: Double, val i: Double, val w: Double, val c: Int? = null)

    /** True when there is nothing in it to draw. */
    val isEmpty: Boolean get() = marks.isEmpty()

    /** The kept line as JSON. */
    fun json(): String = format.encodeToString(serializer(), this)

    /**
     * The x-height to draw it at on a page of that width, when `xHeight` was
     * asked for: as asked if it fits, and smaller if the page is narrower
     * than the one it was written on.
     */
    fun fitted(xHeight: Double, width: Double): Double {
        val widest = size.firstOrNull() ?: 0.0
        if (widest <= 0 || width <= 0 || width == Double.MAX_VALUE || widest * xHeight <= width) return xHeight
        return width / widest
    }

    /** The strokes back on a page, at that x-height: what `Written` is made from. */
    internal fun laid(xHeight: Double): Laid = Laid(
        strokes = marks.map { stroke ->
            Laid.Stroke(
                points = (0 until stroke.p.size - 1 step 2).map { Point(stroke.p[it] * xHeight, stroke.p[it + 1] * xHeight) },
                start = stroke.s,
                beats = stroke.d,
                ink = stroke.i,
                width = stroke.w * xHeight,
                color = stroke.c,
            )
        },
        starts = words,
        beats = beats,
        letters = letters,
        size = Extent((size.firstOrNull() ?: 0.0) * xHeight, (size.lastOrNull() ?: 0.0) * xHeight),
        xHeight = xHeight,
    )

    companion object {
        const val VERSION = 1

        // encodeDefaults writes `v` although it has its usual value; explicitNulls = false leaves out a colour that is not there.
        private val format = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            explicitNulls = false
        }

        /**
         * A kept line from its JSON, or null if the text is not one, or is one
         * from a newer version of this file than this app knows how to draw.
         */
        fun from(json: String): Kept? = try {
            format.decodeFromString(serializer(), json).takeIf { it.v == VERSION && it.size.size == 2 }
        } catch (_: Exception) {
            null
        }

        /**
         * Numbers are kept to a thousandth of an x-height (and beats to a ten
         * thousandth): far finer than a screen can show, and a third of the
         * size of writing every digit a Double has.
         */
        private fun rounded(value: Double, places: Double = 1000.0): Double = round(value * places) / places

        /** The line as it was laid down, measured in x-heights. */
        internal fun of(laid: Laid): Kept {
            val unit = max(laid.xHeight, 0.0001)
            return Kept(
                size = listOf(rounded(laid.size.width / unit), rounded(laid.size.height / unit)),
                beats = rounded(laid.beats, 10000.0),
                letters = laid.letters,
                words = laid.starts.map { rounded(it, 10000.0) },
                marks = laid.strokes.map { stroke ->
                    Stroke(
                        p = stroke.points.flatMap { listOf(rounded(it.x / unit), rounded(it.y / unit)) },
                        s = rounded(stroke.start, 10000.0),
                        d = rounded(stroke.beats, 10000.0),
                        i = rounded(stroke.ink),
                        w = rounded(stroke.width / unit, 10000.0),
                        c = stroke.color,
                    )
                },
            )
        }
    }
}
