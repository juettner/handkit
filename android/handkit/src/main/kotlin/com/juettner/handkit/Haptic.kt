//
//  Haptic.kt
//
//  The tactile side of the pen: a soft tick as each word starts, and a
//  firmer one when a signature is kept.
//
//  On Android a haptic is asked of a View (any view will do: the system only
//  uses it to check that haptics are allowed), which is why these take one.
//  Compose hands out the view it lives in as `LocalView.current`. A phone
//  with touch feedback switched off in its settings stays quiet.
//

package com.juettner.handkit

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View

internal object Haptic {
    /** The lightest there is: a clock's tick. */
    fun tick(view: View) {
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }

    /** "That worked." Android 11 has a constant for exactly this; older phones get an ordinary tap. */
    fun success(view: View) {
        val kind = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
        view.performHapticFeedback(kind)
    }
}
