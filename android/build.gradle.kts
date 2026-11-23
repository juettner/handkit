// Versions of the build plugins, in one place. `apply false` means "make
// this plugin available to the modules, but do not apply it here": the
// module's own build file applies it.
//
// Since Android Gradle Plugin 9, Kotlin is compiled by the Android plugin
// itself, so there is no separate kotlin-android plugin.
plugins {
    id("com.android.library") version "9.5.2" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.21" apply false
}
