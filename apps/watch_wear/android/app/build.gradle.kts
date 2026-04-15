import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // `org.jetbrains.kotlin.android` is built-in from AGP 9.0.
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

android {
    namespace = "com.runapp.watchwear"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.runapp.watchwear"
        // API 30 = Wear OS 3. `androidx.health:health-services-client` requires 30+
        // regardless, so we set it here rather than as a library override.
        minSdk = 30
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        // Defaults match the local Supabase stack so `./gradlew installDebug`
        // Just Works on a dev machine. Override via
        //   `-PSUPABASE_URL=... -PSUPABASE_ANON_KEY=...`
        // to point at staging / prod.
        val supabaseUrl: String = (project.findProperty("SUPABASE_URL") as String?)
            ?: "http://10.0.2.2:54321"
        val supabaseAnonKey: String = (project.findProperty("SUPABASE_ANON_KEY") as String?)
            ?: "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
        buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrl\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKey\"")
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Compose
    val composeBom = platform("androidx.compose:compose-bom:2026.03.01")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")

    // Compose-for-Wear
    implementation("androidx.wear.compose:compose-material:1.6.1")
    implementation("androidx.wear.compose:compose-foundation:1.6.1")
    implementation("androidx.wear.compose:compose-navigation:1.6.1")
    implementation("androidx.wear:wear-ongoing:1.1.0")

    // Health Services (live HR). 1.1.0-rc01 is the latest pre-stable; 1.0.0
    // is the last stable tag but lacks the flow helpers we want. Move to
    // 1.1.0 stable when it ships.
    implementation("androidx.health:health-services-client:1.1.0-rc01")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.3.0")
    implementation("com.google.guava:guava:33.6.0-android")

    // Location
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // Wearable Data Layer — receives Supabase session handoff from the paired phone.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")

    // Networking
    implementation("com.squareup.okhttp3:okhttp:5.3.2")

    // Local persistence
    implementation("androidx.datastore:datastore-preferences:1.2.1")

    // Serialization + coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
}
