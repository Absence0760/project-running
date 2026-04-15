plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.runapp.watchwear"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
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
    val composeBom = platform("androidx.compose:compose-bom:2024.10.00")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")

    // Compose-for-Wear
    implementation("androidx.wear.compose:compose-material:1.4.0")
    implementation("androidx.wear.compose:compose-foundation:1.4.0")
    implementation("androidx.wear.compose:compose-navigation:1.4.0")
    implementation("androidx.wear:wear-ongoing:1.0.0")

    // Health Services (live HR)
    implementation("androidx.health:health-services-client:1.1.0-alpha05")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.2.0")
    implementation("com.google.guava:guava:33.3.1-android")

    // Location
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // Networking
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Local persistence
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    // Serialization + coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")
}
