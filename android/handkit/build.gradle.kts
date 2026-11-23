// The HandKit library for Android.
//
// For a Java person: this is the module's pom.xml. `plugins` are the Maven
// plugins, `android { }` configures the Android one, `dependencies` are the
// dependencies. `api` is Maven's "compile" scope (whoever uses HandKit sees
// it too); `implementation` is hidden from them.
//
// No versions are given for the plugins here. They come from whichever
// build includes this folder: the build.gradle.kts next to it when HandKit is
// built by itself, or the app's own when an app points at this folder.
plugins {
    id("com.android.library")
    // Jetpack Compose is a compiler plugin: it rewrites @Composable functions.
    id("org.jetbrains.kotlin.plugin.compose")
    // Writes the JSON mapping for classes marked @Serializable, at compile
    // time (Swift's Codable; Jackson without the reflection).
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.juettner.handkit"
    // The Android version the code is compiled against: 17, second minor release. (Not the oldest phone it runs on; that is minSdk.)
    compileSdk {
        version = release(37) { minorApiLevel = 2 }
    }

    defaultConfig {
        // Android 9. Everything below it is a rounding error by now.
        minSdk = 28
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

// One test reads the pen's numbers out of the Swift source, to hold the Kotlin ones to them. Gradle skips
// a test run when nothing it knows about has changed, so it has to be told that this file is something
// the tests depend on. Otherwise a change to Written.swift would not run them again.
tasks.withType<Test>().configureEach {
    inputs.file(layout.projectDirectory.file("../../Sources/HandKit/Written.swift"))
}

dependencies {
    // A BOM pins the versions of all the Compose libraries to ones that go together.
    val composeBom = platform("androidx.compose:compose-bom:2026.11.01")
    implementation(composeBom)
    api("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")

    // The one real dependency: Kotlin's own JSON library. A hand is a JSON file.
    api("org.jetbrains.kotlinx:kotlinx-serialization-json:1.13.0")

    testImplementation("junit:junit:4.13.2")
}
