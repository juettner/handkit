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

// The hand HandKit carries is ONE file, kept with the Swift package:
// Sources/HandKit/hand.json. Rather than keep a second copy here that could
// fall behind, the build copies it into the library's assets each time, as
// handkit/hand.json (HandStore.PACKAGED), and it travels inside the library
// into whichever app uses it.
//
// A Gradle task is a small class with declared inputs and outputs; Gradle
// runs it only when an input has changed. Handing the task to the Android
// plugin as a "generated source directory" is what makes every step that
// reads the assets (packaging, lint, the tests) wait for it.
abstract class CopyHand : DefaultTask() {
    @get:InputFile
    abstract val from: RegularFileProperty

    @get:OutputDirectory
    abstract val into: DirectoryProperty

    @TaskAction
    fun copy() {
        from.get().asFile.copyTo(into.get().asFile.resolve("handkit/hand.json"), overwrite = true)
    }
}

val packagedHand = layout.projectDirectory.file("../../Sources/HandKit/hand.json")

val copyPackagedHand = tasks.register<CopyHand>("copyPackagedHand") {
    from.set(packagedHand)
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(copyPackagedHand, CopyHand::into)
    }
}

// Two tests read files of the Swift package: the pen's numbers out of Written.swift, to hold the Kotlin
// ones to them, and the hand HandKit carries, to see that Kotlin reads it. Gradle skips a test run when
// nothing it knows about has changed, so it has to be told that these files are something the tests
// depend on. Otherwise a change to either would not run them again.
tasks.withType<Test>().configureEach {
    inputs.file(layout.projectDirectory.file("../../Sources/HandKit/Written.swift"))
    inputs.file(packagedHand)
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
