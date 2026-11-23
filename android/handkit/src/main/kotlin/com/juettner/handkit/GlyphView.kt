//
//  GlyphView.kt
//
//  One drawing, shown as a picture.
//
//  `Handwriting` writes text. This shows a single drawing, fitted to
//  whatever size it is given: an envelope, a heart, anything that was drawn
//  on the drawing page under a name.
//
//      hand.drawingsNamed("envelope-sealed").firstOrNull()?.let { envelope ->
//          GlyphView(envelope, Modifier.size(44.dp))
//      }
//
//  The drawing keeps its proportions, is centred, and keeps the colours its
//  strokes were drawn in. The line is as thick, against the drawing, as the
//  pen was on the ruled square, so a picture shown small has a fine line and
//  one shown large a bold one, as if the paper had been scaled. A stroke
//  drawn with a finer or a bolder line keeps that too.
//
//  `Sketch` is the same picture, drawn: the pen makes it stroke by stroke,
//  in the order and direction it was drawn, the way `Handwriting` writes a
//  line. For a doodle in the margin that should arrive, not just be there.
//
//      Sketch(doodle, Modifier.size(60.dp), duration = 1.4)
//
//  The Kotlin twin of Sources/HandKit/GlyphView.swift.
//

package com.juettner.handkit

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min

/** A drawing moved and scaled to sit centred in a space, and how thick a medium line is at that scale. */
class Fitted(val strokes: List<List<Point>>, val line: Double)

/**
 * The drawing's strokes moved and scaled to sit centred in a space `width`
 * by `height`, and how thick a medium line is at that scale (a stroke drawn
 * finer or bolder multiplies it by `glyph.widthOf`). Null for a drawing with
 * no points. The strokes keep their numbers, so the colour and the width of
 * each can still be looked up.
 */
fun fit(glyph: Glyph, width: Double, height: Double): Fitted? {
    val strokes = glyph.points
    val every = strokes.flatten()
    if (every.isEmpty()) return null
    val left = every.minOf { it.x }
    val right = every.maxOf { it.x }
    val top = every.minOf { it.y }
    val bottom = every.maxOf { it.y }
    val inkWidth = max(right - left, 0.01)
    val inkHeight = max(bottom - top, 0.01)
    // A little air round the edge, so the round ends of the line are not cut off.
    val scale = min(width / inkWidth, height / inkHeight) * 0.92
    val dx = (width - inkWidth * scale) / 2 - left * scale
    val dy = (height - inkHeight * scale) / 2 - top * scale
    val placed = strokes.map { stroke -> stroke.map { Point(it.x * scale + dx, it.y * scale + dy) } }
    return Fitted(placed, Pen.nib * scale)
}

/**
 * @param minimumLine the least the line may be, so a small picture does not fade away.
 */
@Composable
fun GlyphView(glyph: Glyph, modifier: Modifier = Modifier, ink: Color = HandStyle.journal.ink, minimumLine: Dp = 1.2.dp) {
    // `Canvas` is the drawing surface: the block is handed its size (`size`, in pixels) and draws.
    Canvas(modifier) {
        val fitted = fit(glyph, size.width.toDouble(), size.height.toDouble()) ?: return@Canvas
        for ((number, stroke) in fitted.strokes.withIndex()) {
            if (stroke.isEmpty()) continue
            drawPath(
                path = smooth(stroke),
                color = glyph.colorOf(number)?.let { inkColor(it) } ?: ink,
                style = Stroke(
                    width = max(minimumLine.toPx(), (fitted.line * glyph.widthOf(number)).toFloat()),
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round,
                ),
            )
        }
    }
}

/**
 * One drawing, made by the pen while you watch.
 *
 * @param duration how long the whole drawing takes, in seconds. Zero or less shows it finished.
 * @param delay how long the pen waits before it starts.
 */
@Composable
fun Sketch(
    glyph: Glyph,
    modifier: Modifier = Modifier,
    ink: Color = HandStyle.journal.ink,
    duration: Double = 1.4,
    delay: Double = 0.0,
    minimumLine: Dp = 1.2.dp,
) {
    val reduceMotion = reducesMotion()
    // True once the drawing is finished; the clock is then not running.
    var still by remember { mutableStateOf(duration <= 0 || reduceMotion) }
    var elapsed by remember { mutableDoubleStateOf(0.0) }

    LaunchedEffect(glyph) {
        if (reduceMotion || duration <= 0) {
            still = true
            return@LaunchedEffect
        }
        still = false
        val began = withFrameNanos { it }
        while (elapsed < delay + duration + 0.1) {
            elapsed = (withFrameNanos { it } - began) / 1_000_000_000.0
        }
        still = true
    }

    // A doodle is decoration: TalkBack has nothing to say about it.
    Canvas(modifier.clearAndSetSemantics {}) {
        val fitted = fit(glyph, size.width.toDouble(), size.height.toDouble()) ?: return@Canvas
        // How far through the whole drawing the pen is, from 0 to 1.
        val done = if (still || duration <= 0) 1.0 else ((elapsed - delay) / duration).coerceIn(0.0, 1.0)
        // Each stroke takes a share of the time in proportion to its length.
        val lengths = fitted.strokes.map { Written.lengthOf(it) }
        val total = max(lengths.sum(), 0.01)
        var before = 0.0
        for ((number, stroke) in fitted.strokes.withIndex()) {
            if (stroke.isEmpty()) continue
            val share = lengths[number] / total
            // A dot has no length and so no share: it appears when the pen reaches it.
            val progress = if (share > 0) (done - before) / share else if (done >= before) 1.0 else 0.0
            before += share
            if (progress <= 0) continue
            val whole = smooth(stroke)
            val path = if (progress < 1) {
                val measure = PathMeasure().apply { setPath(whole, false) }
                Path().also { measure.getSegment(0f, (measure.length * progress).toFloat(), it, true) }
            } else {
                whole
            }
            drawPath(
                path = path,
                color = glyph.colorOf(number)?.let { inkColor(it) } ?: ink,
                style = Stroke(
                    width = max(minimumLine.toPx(), (fitted.line * glyph.widthOf(number)).toFloat()),
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round,
                ),
            )
        }
    }
}
