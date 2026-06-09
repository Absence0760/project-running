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

plugins {
    id("com.android.application") version "9.2.1" apply false
    // Pinned to 2.3.21 (NOT the 2.4.0 Dependabot offers): CodeQL's Kotlin
    // extractor can't analyse 2.4.0 yet ("kotlin-version-too-new" → the
    // codeql-kotlin Security job fails). Bump only once CodeQL supports it.
    // See apps/watch_wear/CLAUDE.md § Dependency versions.
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.3.21" apply false
}

rootProject.name = "watch_wear"
include(":app")
