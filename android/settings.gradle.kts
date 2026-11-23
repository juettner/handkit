// The Android side of HandKit: one library module, `:handkit`.
//
// For a Java person: this file is the parent pom's <modules> list, and
// `pluginManagement` / `dependencyResolutionManagement` are its
// <pluginRepositories> and <repositories>.
//
// An app does not have to build HandKit through this file. P.S. points its
// own settings.gradle.kts straight at the `handkit` folder next to this one,
// so the library is compiled as part of the app (see ps/android).

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "HandKit"
include(":handkit")
