plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreProperties.load(FileInputStream(keystoreFile))
}

android {
    namespace = "com.threkir.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Kotlin 2.3+ removed the `kotlinOptions { jvmTarget = ... }` DSL.
    // Migrate to the `compilerOptions` block on the kotlin extension.
    // https://kotl.in/u1r8ln
    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        applicationId = "com.threkir.app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Wearable Data Layer — pushes the Supabase session to the paired watch_wear app.
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    // NotificationCompat / NotificationManagerCompat used by
    // RunNotificationBridge live under androidx.core:core, which geolocator
    // already pulls in transitively at 1.16.0 — no explicit dep needed.

    // JUnit for pure-JVM unit tests on the native Kotlin bridges
    // (WearRoutesBridge / WearAuthBridge / RunNotificationBridge).
    // The bridges' platform-channel + Wearable Data Layer surfaces
    // can't run on a host JVM, but the arg-parsing + DataMap-field
    // construction logic is extracted into pure helpers that we
    // test here. Mirrors the watch_wear test surface convention.
    testImplementation("junit:junit:4.13.2")
}
