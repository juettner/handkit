//
//  Handwriting.kt
//
//  A line written onto the page with a pen, in a hand.
//
//      Handwriting(text = "good morning", hand = hand)
//
//  A typewriter puts a whole letter down at once. A pen does not: the line
//  grows from the nib, stroke by stroke, and that is what "flow" means here.
//  The arithmetic is in Written.kt; this file is the part that touches the
//  screen. It is the Kotlin twin of Sources/HandKit/Handwriting.swift.
//
//  For someone new to Jetpack Compose (Android's SwiftUI):
//
//    @Composable   marks a function that describes a piece of screen. It is
//                  not called once: Compose calls it again whenever something
//                  it read has changed, and works out what to redraw. You
//                  never tell a label to update; you change the data.
//    remember      keeps a value between those calls (a field, in effect).
//    mutableStateOf  a value Compose watches: writing to it is what causes
//                  the function to be called again. (SwiftUI's @State.)
//    Modifier      a chain of "and also": size, padding, drawing, taps. They
//                  apply in the order written, outermost first.
//    LaunchedEffect  starts a coroutine (a cheap thread that can wait
//                  without blocking) when the composable appears, and cancels
//                  it when it goes away or its key changes. (SwiftUI's .task.)
//
//  Three pieces live in this file:
//
//    the measuring   tells Compose how tall the line is at a given width. A
//                    Text does this by itself; drawn strokes do not, so the
//                    same arithmetic is asked for the height.
//    the drawing     an immediate-mode drawing surface, like a Java
//                    Graphics2D in paintComponent. Finished strokes are
//                    drawn whole; the stroke in progress is drawn up to where
//                    the nib has got to.
//    the clock       a loop that wakes once per screen frame while the pen
//                    is moving, and stops when the ink has dried.
//
//  Fresh ink is wet: at full strength and a touch wider. It dries to the
//  letter's own shade over `dryTime`, so with a long drying time the line
//  visibly settles into the paper behind the nib.
//  Tapping finishes the line at once. With animations switched off in the
//  phone's settings the line is simply there. The phone ticks as each word
//  starts. TalkBack reads the text as ordinary text.
//
//  The view writes whatever it is given. A character the hand has no
//  drawing for is left out, so check `hand.covers(text)` first if a line
//  must be complete (and show it another way when it is not), or
//  `hand.missingIn(text)` to say which characters those are.
//
//  Three things an app can ask of the pen beyond writing:
//
//    mirrored   the line is written backwards, right to left, to be read in
//               a mirror.
//    weather    what the sky has done to the ink (Weathering): in the rain it
//               runs a little down the page, in the sun it dries pale.
//    words      the pen is held: it writes only as many words as this, and
//               waits, nib on the paper, until the number goes up. The app
//               counts something (steps, say) and passes the count. While
//               the pen is held a tap does not finish the line.
//
//  A line can be kept as it was written, and shown again from that alone
//  (see Kept.kt). `onKept` hands over the line once it is on the page,
//  exactly as it was laid out for this page; give that back as `kept` and
//  the same strokes are drawn, whatever has become of the hand since:
//
//      Handwriting(text = text, hand = hand, onKept = { save(it) })
//      Handwriting(text = text, hand = Hand(), kept = kept)
//
//  It can also sign. Give it `signatures` (drawings made on SignaturePad) and
//  the pen puts one under the writing when the words are done. With an empty
//  text and an empty hand it writes the signature alone, which is how an app
//  signs a note it has set in type:
//
//      Handwriting(text = "", hand = Hand(), signatures = signatures)
//

package com.juettner.handkit

import android.graphics.BlurMaskFilter
import android.provider.Settings
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.IntrinsicMeasurable
import androidx.compose.ui.layout.IntrinsicMeasureScope
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasurePolicy
import androidx.compose.ui.layout.MeasureResult
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * @param size the type size a typed line of the same height would have. `dp`
 *   is Android's point: a length that is the same on every screen.
 * @param ink the colour of ordinary ink. Strokes drawn in a colour of their own keep it.
 * @param speed letters per second, on average. Zero or less writes nothing: the line is just there.
 * @param haptics tick as each word starts.
 * @param playful allows the rare drawings and the scribbles. Off for lines that should stay plain.
 * @param seed picks the drawings differently for the same text. Zero is the usual way.
 * @param looseness how unevenly the letters are put down. 1 is the usual hand; more is looser.
 * @param slant how far the letters lean forward. 0 is as drawn; 0.15 is a hurry.
 * @param dryTime how long the ink stays wet, in seconds.
 * @param signatures one person's signature, drawn one or more times (see
 *   SignaturePad). The pen signs under the writing with one of them.
 * @param mirrored written backwards, to be read in a mirror.
 * @param weather what the weather has done to the ink.
 * @param words how many words the pen may write so far, or null for a pen that is not held.
 * @param tappable whether a tap finishes the line. Off where the tap belongs to something else (a label on a card).
 * @param followsTextSize whether the writing grows with the text size chosen in the phone's settings, as type does.
 * @param onWord called as the pen starts each word (the moment of the tick). Not called for a line that is simply there.
 * @param onDone called once the whole line is on the page (written or tapped through).
 * @param kept a line that was kept (see Kept.kt). When given, it is what is drawn: the hand is not used, and the text is only read aloud.
 * @param keptSigned for a line shown from `kept`: whether it was signed, so TalkBack can say so.
 * @param onKept called once with the line as it was written for this page, when it is on the page. Not called for a line shown from `kept`.
 */
@Composable
fun Handwriting(
    text: String,
    hand: Hand,
    modifier: Modifier = Modifier,
    size: Dp = 30.dp,
    ink: Color = HandStyle.journal.ink,
    speed: Double = Pen.lettersPerSecond,
    haptics: Boolean = true,
    playful: Boolean = true,
    seed: Int = 0,
    looseness: Double = 1.0,
    slant: Double = 0.0,
    dryTime: Double = Pen.dryTime,
    signatures: List<Glyph> = emptyList(),
    mirrored: Boolean = false,
    weather: Weathering = Weathering.DRY,
    words: Int? = null,
    tappable: Boolean = true,
    followsTextSize: Boolean = true,
    onWord: (() -> Unit)? = null,
    onDone: (() -> Unit)? = null,
    kept: Kept? = null,
    keptSigned: Boolean = false,
    onKept: ((Kept) -> Unit)? = null,
) {
    val density = LocalDensity.current
    val view = LocalView.current
    val reduceMotion = reducesMotion()
    // The x-height in pixels: dp to pixels, then the share of the type size, then the text size from Settings.
    val xHeight = with(density) { size.toPx() } * Pen.xHeightPerSize * (if (followsTextSize) density.fontScale else 1f)

    // Everything that decides where the strokes go, in one value: when any of it changes, the line is worked out again.
    val recipe = Recipe(text, hand, xHeight, speed, playful, seed, looseness, slant, signatures, kept)
    val cache = remember { LineCache() }

    // True once nothing is moving or drying; the clock below is then not running.
    // (`remember(text)` starts these three afresh when the text changes: a new text is a new line.)
    var still by remember(text) { mutableStateOf(speed <= 0 || reduceMotion) }
    // True once the line was tapped through.
    var skipped by remember(text) { mutableStateOf(false) }
    // Seconds since the pen started. Written once per frame by the clock; the drawing reads it.
    var elapsed by remember(text) { mutableDoubleStateOf(0.0) }
    // The newest `onDone`, without restarting the clock when the caller hands over a new function object.
    val done by rememberUpdatedState(onDone)
    val word by rememberUpdatedState(onWord)
    val keep by rememberUpdatedState(onKept)
    // The newest count of words a held pen is allowed, read by the clock on every frame.
    val allowed by rememberUpdatedState(words)

    // Hands the line over to be kept, as it was laid out for this page. The page's width is known once the
    // line has been measured, which can be a frame or two after this is asked (a line that is simply there
    // is "done" at once), so this waits for it, for a second or so at most.
    suspend fun handBack() {
        val wanted = keep ?: return
        if (kept != null) return
        repeat(60) {
            val line = cache.laidOut(recipe)
            if (line != null) {
                if (line.marks.isNotEmpty()) wanted(line.kept())
                return
            }
            withFrameNanos { }
        }
    }

    // The clock. Starts when the view appears, and again when the text changes.
    LaunchedEffect(text) {
        skipped = false
        // Timing does not depend on where the lines break, so any width will do here.
        val plan = recipe.written(Double.MAX_VALUE)
        if (reduceMotion || speed <= 0 || plan.marks.isEmpty()) {
            still = true
            done?.invoke()
            handBack()
            return@LaunchedEffect
        }
        elapsed = 0.0
        still = false
        if (words != null) {
            // A held pen. An ordinary clock would run on while the pen waits, and the next word would
            // then appear all at once. This one only moves while the pen is allowed to: it adds up the
            // time between frames, and stops at the start of the first word it may not write yet.
            var time = 0.0
            var last = withFrameNanos { it }
            var ticked = 0
            var told = false
            while (true) {
                val now = withFrameNanos { it }
                val may = allowed ?: Int.MAX_VALUE
                time = min(time + (now - last) / 1_000_000_000.0, plan.momentAfterWords(may))
                last = now
                elapsed = time
                // A word has started if the pen is allowed it and the clock has reached it.
                while (ticked < plan.wordStarts.size && ticked < may && time >= plan.wordStarts[ticked]) {
                    if (haptics) Haptic.tick(view)
                    word?.invoke()
                    ticked += 1
                }
                if (!told && time >= plan.duration) {
                    told = true
                    done?.invoke()
                    handBack()
                }
                if (time >= plan.duration + dryTime + 0.1) break
            }
            still = true
            return@LaunchedEffect
        }
        // `withFrameNanos` waits for the next screen frame and says what time it is.
        val began = withFrameNanos { it }
        var nextWord = 0
        var told = false
        while (true) {
            val now = (withFrameNanos { it } - began) / 1_000_000_000.0
            if (skipped) break
            elapsed = now
            while (nextWord < plan.wordStarts.size && plan.wordStarts[nextWord] <= now) {
                if (haptics) Haptic.tick(view)
                word?.invoke()
                nextWord += 1
            }
            if (!told && now >= plan.duration) {
                told = true
                done?.invoke()
                handBack()
            }
            // Let the last strokes dry, then stop redrawing.
            if (now >= plan.duration + dryTime + 0.1) break
        }
        still = true
        if (!told) {
            done?.invoke()
            handBack()
        }
    }

    // The strokes mean nothing to TalkBack; the words do (without the marks that cross some of them out).
    val words = Hand.unstruck(text)
    val spoken = if (signatures.isEmpty() && !keptSigned) words else if (words.isEmpty()) "Signature" else "$words. Signed."

    var shaped = modifier.clearAndSetSemantics { contentDescription = spoken }
    if (tappable) {
        // The whole line, dry, now. A held pen is not hurried by a tap: the app holding it decides when it may write.
        shaped = shaped.pointerInput(Unit) {
            detectTapGestures {
                if (allowed == null) {
                    skipped = true
                    still = true
                }
            }
        }
    }

    Layout(
        // `Layout` with no children: a box whose size is worked out by the measure policy below.
        content = {},
        measurePolicy = remember(recipe) { WritingMeasure(recipe, cache) },
        modifier = shaped.drawBehind {
            val now = if (still) Double.POSITIVE_INFINITY else elapsed
            val strokes = cache.strokes(recipe, this.size.width.toDouble())
            // Mirrored: flip the page left to right about its middle, and draw as usual.
            scale(scaleX = if (mirrored) -1f else 1f, scaleY = 1f) {
                for (stroke in strokes) {
                    val mark = stroke.mark
                    val age = now - mark.start
                    if (age <= 0) continue
                    // How much of the stroke is down. It eases out, so the pen slows into the end of a stroke.
                    val progress = if (mark.duration > 0) min(1.0, age / mark.duration) else 1.0
                    val eased = 1 - (1 - progress).pow(1.6)
                    // 1 while the stroke is being made, 0 once it has dried.
                    val wet = if (dryTime > 0) (1 - (age - mark.duration) / dryTime).coerceIn(0.0, 1.0) else 0.0
                    // In the sun the ink goes down dark like any other and loses its strength as it dries.
                    val strength = if (weather == Weathering.SUN) Pen.sunFade + (1 - Pen.sunFade) * wet else 1.0
                    val colour = mark.color?.let { inkColor(it) } ?: ink
                    drawPath(
                        path = if (eased < 1) stroke.upTo(eased) else stroke.path,
                        color = colour.copy(alpha = colour.alpha * ((mark.ink + (1 - mark.ink) * wet) * strength).toFloat()),
                        // Wet ink stands a little proud of the paper, and sinks in as it dries.
                        style = Stroke(width = (mark.width * (1 + Pen.wetSpread * wet)).toFloat(), cap = StrokeCap.Round, join = StrokeJoin.Round),
                    )
                }
                if (weather == Weathering.RAIN) drawRun(strokes, now, ink, recipe.xHeight)
            }
        },
    )
}

/**
 * Rain: behind the pen, each stroke bleeds a little way down the page. The
 * run is drawn as three soft copies of the stroke, each lower and fainter
 * than the last, over the writing.
 *
 * Compose's own drawing calls have no blur for a single stroke, so this goes
 * one level down, to the Android canvas Compose itself draws on, whose paint
 * can carry a "mask filter" that softens whatever it draws.
 */
private fun DrawScope.drawRun(strokes: List<DrawnStroke>, now: Double, ink: Color, xHeight: Double) {
    val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
        style = android.graphics.Paint.Style.STROKE
        strokeCap = android.graphics.Paint.Cap.ROUND
        strokeJoin = android.graphics.Paint.Join.ROUND
        maskFilter = BlurMaskFilter(max(0.5f, (xHeight * 0.07).toFloat()), BlurMaskFilter.Blur.NORMAL)
    }
    drawIntoCanvas { canvas ->
        val paper = canvas.nativeCanvas
        for ((index, stroke) in strokes.withIndex()) {
            val mark = stroke.mark
            // The run starts when the stroke is finished, and takes `runTime` to get where it is going.
            val age = now - mark.start - mark.duration
            if (age <= 0) continue
            val soaked = min(1.0, age / Pen.runTime)
            // Not every stroke runs the same distance. The stroke's number is scrambled into
            // a share between 0 and 1, the same one every time, so the page does not shimmer.
            val luck = ((index.toLong() * 2_654_435_761L) % 97) / 97.0
            val run = xHeight * Pen.runLength * soaked * (0.25 + 0.75 * luck)
            val colour = mark.color?.let { inkColor(it) } ?: ink
            paint.strokeWidth = (mark.width * 1.3).toFloat()
            for (step in 1..3) {
                val part = step / 3.0
                paint.color = colour.copy(alpha = (mark.ink * 0.2 * (1.25 - part)).toFloat()).toArgb()
                paper.save()
                paper.translate(0f, (run * part).toFloat())
                paper.drawPath(stroke.path.asAndroidPath(), paint)
                paper.restore()
            }
        }
    }
}

/** Everything that decides how a line comes out, apart from the width of the page. */
internal data class Recipe(
    val text: String,
    val hand: Hand,
    val xHeight: Double,
    val speed: Double,
    val playful: Boolean,
    val seed: Int,
    val looseness: Double,
    val slant: Double,
    val signatures: List<Glyph>,
    /** A line that was kept: then it is the strokes that are laid out, and the text and the hand are not asked. */
    val kept: Kept? = null,
) {
    fun written(width: Double) =
        if (kept != null) Written(kept, kept.fitted(xHeight, width), speed)
        else Written(text, hand, xHeight, width, speed, playful, seed, looseness, slant, signatures)

    /**
     * Comparing two hands letter by letter on every frame would be slow, and
     * a hand is never changed in place, so "the same hand" here means the
     * very same object (`===`, Java's `==` on references). A kept line has no
     * use for a hand, so there the hand is not compared at all.
     */
    override fun equals(other: Any?): Boolean =
        other is Recipe && text == other.text && (kept != null || hand === other.hand) && xHeight == other.xHeight && speed == other.speed &&
            playful == other.playful && seed == other.seed && looseness == other.looseness && slant == other.slant && signatures === other.signatures &&
            kept === other.kept

    override fun hashCode(): Int = text.hashCode() * 31 + seed
}

/** One stroke ready to draw: its curve, and how long that curve is, for drawing part of it. */
internal class DrawnStroke(val mark: Mark) {
    val path: Path = smooth(mark.points)
    private val measure = PathMeasure().apply { setPath(path, false) }
    private val part = Path()

    /** The stroke from its start to that fraction of its length: what the pen has drawn so far. */
    fun upTo(fraction: Double): Path {
        part.rewind()
        measure.getSegment(0f, (measure.length * fraction).toFloat(), part, true)
        return part
    }
}

/** Remembers the last line worked out, so a frame of animation, or a second measuring, does not redo it. */
internal class LineCache {
    private var recipe: Recipe? = null
    private var width = -1.0
    private var written: Written? = null
    private var strokes: List<DrawnStroke>? = null

    fun written(recipe: Recipe, width: Double): Written {
        written?.let { if (this.recipe == recipe && this.width == width) return it }
        val fresh = recipe.written(width)
        this.recipe = recipe
        this.width = width
        written = fresh
        strokes = null
        return fresh
    }

    /** The line as it was last worked out for a real page (not for one long row), if that was for this recipe. */
    fun laidOut(recipe: Recipe): Written? = written?.takeIf { this.recipe == recipe && width > 0 && width < Double.MAX_VALUE }

    fun strokes(recipe: Recipe, width: Double): List<DrawnStroke> {
        val line = written(recipe, width)
        return strokes ?: line.marks.map { DrawnStroke(it) }.also { strokes = it }
    }
}

/**
 * Sizes the drawing: as wide as it is offered, as tall as the lines need.
 *
 * Compose measures top-down: a parent hands each child `Constraints` (the
 * least and most it may be), and the child answers with a size. Asked with
 * no limit on its width, the line answers with one long row.
 */
private class WritingMeasure(private val recipe: Recipe, private val cache: LineCache) : MeasurePolicy {
    override fun MeasureScope.measure(measurables: List<Measurable>, constraints: Constraints): MeasureResult {
        if (!constraints.hasBoundedWidth) {
            val line = recipe.written(Double.MAX_VALUE).size
            // Rounded up to a whole pixel. Given a hair less than the line needs, the
            // last word would no longer fit and would drop to a second line that nobody made room for.
            val width = ceil(line.width).toInt().coerceAtLeast(constraints.minWidth)
            return layout(width, ceil(line.height).toInt().coerceIn(constraints.minHeight, constraints.maxHeight)) {}
        }
        val width = constraints.maxWidth
        val height = ceil(cache.written(recipe, width.toDouble()).size.height).toInt()
        return layout(width, height.coerceIn(constraints.minHeight, constraints.maxHeight)) {}
    }

    // "Intrinsic" sizes are what a parent asks before it has decided anything: how wide would you like to be?
    override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int): Int =
        ceil(recipe.written(Double.MAX_VALUE).size.width).toInt()

    override fun IntrinsicMeasureScope.minIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int): Int = 0

    override fun IntrinsicMeasureScope.minIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int): Int =
        ceil(recipe.written(if (width == Constraints.Infinity) Double.MAX_VALUE else width.toDouble()).size.height).toInt()

    override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int): Int =
        minIntrinsicHeight(measurables, width)
}

/**
 * How wide and how tall a text would be written on one long line, in pixels.
 * For fitting a line into a space that cannot grow (a label): try a size,
 * and try a smaller one if it does not fit.
 */
fun writtenOnOneLine(text: String, hand: Hand, xHeight: Float, playful: Boolean = true, seed: Int = 0): Extent =
    Written(text, hand, xHeight.toDouble(), Double.MAX_VALUE, 0.0, playful, seed).size

/**
 * A finger leaves a trail of points. Joining them with straight lines shows
 * every corner, so the curve runs through the midpoints with the points
 * themselves as the pull (a quadratic Bezier chain).
 */
fun smooth(points: List<Point>): Path {
    val path = Path()
    val first = points.firstOrNull() ?: return path
    path.moveTo(first.x.toFloat(), first.y.toFloat())
    if (points.size == 1) {
        // A dot: a line of no length still draws its round ends.
        path.lineTo(first.x.toFloat(), first.y.toFloat())
        return path
    }
    for (i in 1 until points.size - 1) {
        val midX = (points[i].x + points[i + 1].x) / 2
        val midY = (points[i].y + points[i + 1].y) / 2
        path.quadraticTo(points[i].x.toFloat(), points[i].y.toFloat(), midX.toFloat(), midY.toFloat())
    }
    val last = points[points.size - 1]
    path.lineTo(last.x.toFloat(), last.y.toFloat())
    return path
}

/**
 * True when the phone's owner has switched animations off (Settings >
 * Accessibility > Remove animations, which sets this scale to zero). Then
 * nothing is written out: it is simply there.
 */
@Composable
internal fun reducesMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}
