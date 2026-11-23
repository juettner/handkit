//
//  HandStore.kt
//
//  Where a hand lives on the phone.
//
//  Two places, looked in this order:
//
//    1. hand.json in the app's private files folder: a hand brought onto
//       this phone with `use` (one sent over from the iPad, say). If there is
//       one, it wins.
//    2. hand.json shipped inside the app (in its `assets` folder): the hand
//       everybody gets.
//
//  If neither exists the hand is empty and `active` is null: the app should
//  show its text some other way.
//
//  The drawing page (HandEditor) exists on iOS only, where an iPad and a
//  Pencil are. A hand drawn there is the same JSON here.
//
//  An app that fetches hands from somewhere else (a server, say) does not
//  need this class at all: decode a `Hand` and give it to `Handwriting`.
//
//  For a Spring person: a small singleton repository over one JSON file,
//  whose properties are observable. `mutableStateOf` is what makes them so:
//  any @Composable that read `hand` or `enabled` is called again when it
//  changes. (On iOS this is an ObservableObject with @Published properties.)
//
//  Android has no global "the app": most things need a `Context`, the handle
//  to the app's files, settings and resources. So the store has to be told
//  about it once, at launch: `HandStore.start(context)`.
//

package com.juettner.handkit

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File

class HandStore private constructor(context: Context, name: String) {
    private val file = File(context.filesDir, "$name.json")
    private val settings = context.getSharedPreferences("handkit", Context.MODE_PRIVATE)
    private val offKey = "${name}Off"

    /** The hand as it is now. `private set`: anyone may read it, only this class changes it. */
    var hand: Hand by mutableStateOf(Hand())
        private set

    private var on: Boolean by mutableStateOf(!settings.getBoolean(offKey, false))

    /** "By hand" or "typed". Off means `active` is null, whatever has been drawn. Setting it is remembered. */
    var enabled: Boolean
        get() = on
        set(value) {
            on = value
            settings.edit().putBoolean(offKey, !value).apply()
        }

    /** The hand to write with right now, or null to show text another way. */
    val active: Hand? get() = if (enabled && !hand.isEmpty) hand else null

    init {
        val brought = runCatching { Hand.from(file.readBytes()) }.getOrNull()?.takeIf { !it.isEmpty }
        // `assets` are files packed into the app as they are. A missing one throws, which here just means "no hand shipped".
        val shipped = runCatching { context.assets.open("$name.json").use { Hand.from(it.readBytes()) } }.getOrNull()
        hand = brought ?: shipped ?: Hand()
    }

    /** Replaces the hand with one from the bytes of a hand.json. False if they are not a hand. */
    fun use(bytes: ByteArray): Boolean {
        val picked = Hand.from(bytes)?.takeIf { !it.isEmpty } ?: return false
        hand = picked
        runCatching { file.writeText(picked.json()) }
        return true
    }

    companion object {
        @Volatile
        private var store: HandStore? = null

        /** Reads the hand. Call once when the app starts (in Application.onCreate); calling it again does nothing. */
        fun start(context: Context, name: String = "hand"): HandStore =
            store ?: synchronized(this) {
                store ?: HandStore(context.applicationContext, name).also { store = it }
            }

        /** The store most apps want. `start` must have been called first. */
        val shared: HandStore
            get() = store ?: error("HandStore.start(context) has not been called. Call it in Application.onCreate.")
    }
}
