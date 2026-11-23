//
//  HandStyle.kt
//
//  The few colours and the one typeface the signing page (SignaturePad)
//  uses, so it can look like the app it is in. The pen itself needs only an
//  ink colour, which `Handwriting` takes directly.
//
//  `journal` is the look these came from: white paper, near-black ink, warm
//  greys. Pass your own to change any of it:
//
//      SignaturePad(..., style = HandStyle.journal.copy(ink = Color(0xFF23263A)))
//

package com.juettner.handkit

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily

data class HandStyle(
    /** The page. */
    val paper: Color = Color(0xFFFFFFFF),
    /** Ink: the letter being drawn, the word you can tap. */
    val ink: Color = Color(0xFF1E1A17),
    /** Quiet text: a count, a hint. Also the line to sign on. */
    val grey: Color = Color(0xFF9A9088),
    /** A quiet word you can tap. */
    val muted: Color = Color(0xFF6B625A),
    /** The option you did not pick. */
    val faint: Color = Color(0xFFC4BCB2),
    /** The lightest ruled lines. */
    val rule: Color = Color(0xFFF1EEE9),
    /** The border of the page you sign on. */
    val edge: Color = Color(0xFFE6E1DA),
    /** A heart's red. */
    val heart: Color = Color(0xFFC8322B),
    /** The typeface for the page's own words. */
    val font: FontFamily = FontFamily.Serif,
) {
    companion object {
        /** White paper, near-black ink, the system serif. */
        val journal = HandStyle()
    }
}

/** A colour from 0xRRGGBB, the way a stroke's colour is kept in a hand. (Compose wants the alpha too: 0xAARRGGBB.) */
internal fun inkColor(rgb: Int): Color = Color(0xFF000000 or (rgb.toLong() and 0xFFFFFF))
