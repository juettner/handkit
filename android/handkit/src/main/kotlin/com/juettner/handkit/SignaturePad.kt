//
//  SignaturePad.kt
//
//  "Your signature": where you sign.
//
//  This page is for one thing: sign on the line, tap "keep". Sign a few
//  times and the pen has a few to pick between, so two notes are not signed
//  with exactly the same strokes, as a stamp would.
//
//  A signature is a `Glyph`, the same data as a letter: pen strokes measured
//  in x-heights from a baseline (see Hand.kt). So everything that shows a
//  drawing shows a signature:
//
//      Handwriting(text = note, hand = hand, signatures = signatures)   the pen signs under the note
//      Handwriting(text = "", hand = Hand(), signatures = signatures)   the signature alone
//      GlyphView(signatures[0])                                         a still picture of one
//
//  Where the signatures are kept is the app's business, not this page's. The
//  page is handed the list and a function to call with the new list when it
//  adds one or removes one. (SwiftUI passes a `Binding` for this; in Compose
//  the same idea is spelled as two parameters, the value and `onChange`, and
//  is called "state hoisting": the state lives with the caller.)
//
//      var signatures by remember { mutableStateOf(listOf<Glyph>()) }
//      SignaturePad(signatures = signatures, onChange = { signatures = it }, onClose = { ... })
//
//  The size it is signed at matters. The line on the page stands for a line
//  of writing, and one x-height is a fifth of the page's height, so a
//  signature that fills the page comes out about three lines of a note tall.
//  Sign smaller and it is written smaller.
//
//  The three short lines beside "clear" choose the pen: fine, medium or bold.
//  Each stroke keeps the line it was signed with, and the pen signs with it.
//
//  Nothing is smoothed or corrected. If a signature has more points than an
//  app would want to send over a network, every other point is dropped until
//  it does not; at this density the eye cannot tell.
//
//  The Kotlin twin of Sources/HandKit/SignaturePad.swift, and what it keeps
//  is the same data: a signature made on either phone signs on both.
//

package com.juettner.handkit

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.hypot
import kotlin.math.max

/** The page to sign on, in fractions of its height. */
private object Signing {
    /** Twice as wide as it is tall. */
    const val aspect = 2.0
    /** The line the signature sits on. */
    const val baseline = 0.7
    /** One x-height. */
    const val unit = 0.2
    /** The most points and strokes one signature is kept with. */
    const val points = 1200
    const val strokes = 60
}

/** The three lines the pen can draw with. `weight` is a multiple of the usual line; `sample` how thick its picture is drawn. */
enum class LineWeight(val weight: Double, val sample: Double, val word: String) {
    FINE(0.55, 2.0, "fine"),
    MEDIUM(1.0, 4.5, "medium"),
    BOLD(1.8, 9.0, "bold"),
}

/** How many signatures a person keeps unless the app says otherwise. */
const val MOST_SIGNATURES = 5

/**
 * @param signatures the list this page shows.
 * @param onChange called with the whole new list when one is added or removed.
 * @param limit the most that may be kept.
 * @param style the page's colours and typeface.
 * @param onClose what "back" does.
 */
@Composable
fun SignaturePad(
    signatures: List<Glyph>,
    onChange: (List<Glyph>) -> Unit,
    modifier: Modifier = Modifier,
    limit: Int = MOST_SIGNATURES,
    style: HandStyle = HandStyle.journal,
    onClose: () -> Unit,
) {
    val view = LocalView.current
    // Finished strokes of the signature being made, in fractions of the page's height.
    var strokes by remember { mutableStateOf(listOf<List<Point>>()) }
    // How thick each finished stroke is, as a multiple of the usual line.
    var weights by remember { mutableStateOf(listOf<Double>()) }
    // The line the pen is signing with.
    var weight by remember { mutableStateOf(LineWeight.MEDIUM) }
    // The stroke under the finger.
    var current by remember { mutableStateOf(listOf<Point>()) }
    // Which of the signatures already kept is picked, in the row above the page.
    var picked by remember { mutableStateOf<Int?>(null) }

    val blank = strokes.isEmpty() && current.isEmpty()
    val full = signatures.size >= limit

    fun clear() {
        strokes = emptyList()
        weights = emptyList()
        current = emptyList()
    }

    // Adds what is on the page to the list, as one more signature.
    fun keep() {
        if (full) return
        val thin = thinned(strokes, Signing.points)
        val points = thin.flatten()
        if (points.isEmpty()) return
        val left = points.minOf { it.x }
        val right = points.maxOf { it.x }
        fun rounded(value: Double) = Math.round(value * 1000) / 1000.0
        // From fractions of the page into x-heights: x from the left edge of the ink, y from the line.
        val flat = thin.map { stroke ->
            stroke.flatMap { listOf(rounded((it.x - left) / Signing.unit), rounded((it.y - Signing.baseline) / Signing.unit)) }
        }
        onChange(
            signatures + Glyph(
                strokes = flat,
                advance = max(0.12, rounded((right - left) / Signing.unit)),
                widths = if (weights.any { it != 1.0 }) weights else null,
            ),
        )
        Haptic.success(view)
        clear()
        picked = null
    }

    // Column stacks its children top to bottom (SwiftUI's VStack); Row puts them side by side (HStack).
    Column(
        modifier
            .fillMaxSize()
            .background(style.paper)
            // Keeps clear of the status bar, the camera cut-out and the gesture bar.
            .safeDrawingPadding()
            .padding(horizontal = 36.dp)
            .padding(top = 24.dp),
    ) {
        Row(Modifier.fillMaxWidth().heightIn(min = 24.dp), verticalAlignment = Alignment.CenterVertically) {
            PadWord("back", style, tone = style.muted, size = 13, onClick = onClose)
            Spacer(Modifier.weight(1f))
            PadSmall(if (signatures.isEmpty()) "not signed yet" else "${signatures.size} of $limit kept", style)
        }

        BasicText("your signature", style = TextStyle(color = style.ink, fontSize = 30.sp, fontFamily = style.font))
        PadSmall("Sign on the line, the way you would sign a card. Keep a few, and each note is signed a little differently.", style, Modifier.padding(top = 4.dp))

        // Every signature kept, small, in the order they were made. Tap one to
        // pick it. The row keeps its height when it is empty, so the page below
        // never moves under the pen.
        Row(
            Modifier.padding(top = 12.dp).height(THUMB.dp).fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            signatures.forEachIndexed { number, glyph ->
                val chosen = picked == number
                Box(
                    Modifier
                        .size(width = (THUMB * Signing.aspect).dp, height = THUMB.dp)
                        .border(1.dp, if (chosen) style.ink else style.edge)
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button) {
                            picked = if (chosen) null else number
                        }
                        .semantics {
                            contentDescription = "Signature ${number + 1} of ${signatures.size}"
                            selected = chosen
                        }
                        .padding(6.dp),
                ) {
                    GlyphView(glyph, Modifier.fillMaxSize(), ink = style.ink)
                }
            }
        }

        // Forgetting the picked signature. Always there, dimmed until one is picked, so nothing below moves.
        val chosen = picked?.takeIf { it in signatures.indices }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            PadSmall(
                when {
                    signatures.isEmpty() -> "the ones you keep show here"
                    chosen == null -> "tap one to forget it"
                    else -> "this one"
                },
                style,
            )
            Spacer(Modifier.weight(1f))
            PadWord("forget", style, tone = style.muted, size = 13, enabled = chosen != null, description = "Forget this signature") {
                if (chosen != null) onChange(signatures.filterIndexed { index, _ -> index != chosen })
                picked = null
            }
        }

        // The page you sign on: the line, what has been drawn, and the gesture that draws.
        Canvas(
            Modifier
                .padding(top = 8.dp)
                // On a tablet there is room to spare; a page wider than this would be signed with the whole arm.
                .widthIn(max = 520.dp)
                .fillMaxWidth()
                .aspectRatio(Signing.aspect.toFloat())
                .border(1.dp, style.edge)
                .semantics { contentDescription = "The page to sign on" }
                // `pointerInput` is the raw touch stream. A drag detector would
                // wait for the finger to move a little before it starts; reading the
                // touches directly starts at the touch, so a dot is a stroke too.
                .pointerInput(Unit) {
                    awaitEachGesture {
                        val height = size.height.toDouble()
                        var trail = listOf<Point>()
                        fun add(at: Offset) {
                            // Kept inside the page, in fractions of its height.
                            val point = Point((at.x / height).coerceIn(0.0, Signing.aspect), (at.y / height).coerceIn(0.0, 1.0))
                            // Skip points that have barely moved: they add noise, not shape. (2 dp, as on the iPhone.)
                            val last = trail.lastOrNull()
                            if (last != null && hypot(point.x - last.x, point.y - last.y) * height < 2.dp.toPx()) return
                            trail = trail + point
                            current = trail
                        }
                        val down = awaitFirstDown(requireUnconsumed = false)
                        down.consume()
                        add(down.position)
                        while (true) {
                            val event = awaitPointerEvent()
                            val finger = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!finger.pressed) break
                            add(finger.position)
                            finger.consume()
                        }
                        if (trail.isNotEmpty() && strokes.size < Signing.strokes) {
                            strokes = strokes + listOf(trail)
                            weights = weights + weight.weight
                        }
                        current = emptyList()
                    }
                },
        ) {
            val h = size.height.toDouble()
            val y = (Signing.baseline * h).toFloat()

            // The line to sign on, and the small cross a form prints where it starts.
            drawLine(style.grey, Offset((0.12 * h).toFloat(), y), Offset(size.width - (0.12 * h).toFloat(), y), strokeWidth = 1.dp.toPx())
            val centre = Offset((0.17 * h).toFloat(), y - (0.1 * h).toFloat())
            val arm = (0.035 * h).toFloat()
            drawLine(style.faint, Offset(centre.x - arm, centre.y - arm), Offset(centre.x + arm, centre.y + arm), strokeWidth = 1.dp.toPx())
            drawLine(style.faint, Offset(centre.x + arm, centre.y - arm), Offset(centre.x - arm, centre.y + arm), strokeWidth = 1.dp.toPx())

            // The pen is as thick here, against the line, as it will be on a note.
            // That is the usual line; a stroke signed fine or bold is a multiple of it.
            val nib = Pen.nib * Signing.unit * h
            for ((number, stroke) in (strokes + listOf(current)).withIndex()) {
                if (stroke.isEmpty()) continue
                // Finished strokes keep their line; the one under the finger shows the pen as it is now.
                val thick = weights.getOrNull(number) ?: weight.weight
                drawPath(
                    path = smooth(stroke.map { Point(it.x * h, it.y * h) }),
                    color = style.ink,
                    style = Stroke(width = (nib * thick).toFloat(), cap = StrokeCap.Round, join = StrokeJoin.Round),
                )
            }
        }

        Row(Modifier.padding(top = 8.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) {
            PadWord("keep", style, enabled = !blank && !full, description = "Keep this signature") { keep() }
            PadWord("clear", style, tone = style.muted, enabled = !blank) { clear() }
            Spacer(Modifier.weight(1f))
            LineChoice(weight, style) { weight = it }
        }

        // Below everything, so the page above never moves when it appears.
        if (full) {
            PadSmall("$limit is the most. Forget one to sign another.", style)
        }
    }
}

/** How tall the row of kept signatures is. */
private const val THUMB = 56

/**
 * Drops every other point of each stroke, keeping its two ends, until there
 * are no more than `limit` points in all.
 */
internal fun thinned(strokes: List<List<Point>>, limit: Int): List<List<Point>> {
    var out = strokes
    var count = out.sumOf { it.size }
    while (count > limit) {
        out = out.map { stroke ->
            if (stroke.size <= 2) stroke
            else (0 until stroke.size - 1 step 2).map { stroke[it] } + stroke[stroke.size - 1]
        }
        val now = out.sumOf { it.size }
        // Nothing left to drop (very many very short strokes): keep what there is.
        if (now == count) break
        count = now
    }
    return out
}

/** The pen's line: three short lines, fine, medium and bold. The one in ink is the one in use. */
@Composable
private fun LineChoice(weight: LineWeight, style: HandStyle, onPick: (LineWeight) -> Unit) {
    val view = LocalView.current
    Row {
        for (choice in LineWeight.entries) {
            Box(
                // The line is small; the place to tap is not.
                Modifier
                    .size(width = 36.dp, height = 44.dp)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.RadioButton) {
                        Haptic.tick(view)
                        onPick(choice)
                    }
                    .semantics {
                        contentDescription = "Draw the next strokes with a ${choice.word} line"
                        selected = weight == choice
                    },
                contentAlignment = Alignment.Center,
            ) {
                // A line with round ends, like the pen's.
                Box(Modifier.width(22.dp).height(choice.sample.dp).background(if (weight == choice) style.ink else style.faint, CircleShape))
            }
        }
    }
}

/** A word you can tap. The page has no buttons: actions are words. */
@Composable
private fun PadWord(
    title: String,
    style: HandStyle,
    tone: Color = style.ink,
    size: Int = 15,
    enabled: Boolean = true,
    description: String? = null,
    onClick: () -> Unit,
) {
    val view = LocalView.current
    Box(
        Modifier
            // 44 dp is about the smallest thing a finger hits reliably.
            .heightIn(min = 44.dp)
            .alpha(if (enabled) 1f else 0.45f)
            .clickable(enabled = enabled, interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button) {
                Haptic.tick(view)
                onClick()
            }
            .then(if (description != null) Modifier.semantics { contentDescription = description } else Modifier),
        contentAlignment = Alignment.CenterStart,
    ) {
        BasicText(title, style = TextStyle(color = tone, fontSize = size.sp, fontFamily = style.font))
    }
}

/** Small grey text: a count, a hint. */
@Composable
private fun PadSmall(text: String, style: HandStyle, modifier: Modifier = Modifier) {
    BasicText(text, modifier, style = TextStyle(color = style.grey, fontSize = 13.sp, lineHeight = 18.sp, fontFamily = style.font))
}
