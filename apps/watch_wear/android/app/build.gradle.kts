import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // `org.jetbrains.kotlin.android` is built-in from AGP 9.0.
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Gradle-time env reader (repo-wide convention, decisions §137): load the
// committed, non-secret `.env.development` defaults, then overlay a gitignored
// `.env.local` if present so a per-machine override wins. Missing files → every
// flag defaults to the safe production value. DEV-only; the release build type
// reads nothing from these (see the defaultConfig note below).
val envProps = Properties().apply {
    rootProject.file(".env.development").takeIf { it.exists() }
        ?.inputStream()?.use { load(it) }
    rootProject.file(".env.local").takeIf { it.exists() }
        ?.inputStream()?.use { load(it) }
}
fun envFlag(key: String, default: Boolean = false): Boolean {
    val raw = envProps.getProperty(key) ?: project.findProperty(key) as? String
    return raw?.trim()?.lowercase() == "true"
}
fun envString(key: String, default: String = ""): String {
    val raw = envProps.getProperty(key) ?: project.findProperty(key) as? String
    return raw?.trim() ?: default
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

android {
    namespace = "com.runapp.watchwear"
    // androidx.lifecycle:*-compose 2.11.0 requires compileSdk 37 (AGP 9.2.1
    // + Gradle 9.6 support it). targetSdk stays 35.
    compileSdk = 37

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

        // RELEASE-SAFE BASELINE. `defaultConfig` reads NOTHING from the
        // committed `apps/watch_wear/android/.env.development` (envProps) —
        // every value here comes from a `-P` gradle flag or is a hardcoded
        // safe-for-release default — so a release artifact can never inherit a
        // local-dev value. The committed `.env.development` is applied ONLY by
        // the `debug { }` build type below, which re-reads these via envString
        // / envFlag and overrides the baseline for local dev.
        //
        // SUPABASE_URL / SUPABASE_ANON_KEY come from `-PSUPABASE_URL=...
        // -PSUPABASE_ANON_KEY=...` (the release workflow injects production
        // values from `secrets.SUPABASE_*`). No default URL or key is
        // hardcoded — a misconfigured release fails the OkHttp request loudly
        // rather than silently baking a dev default into the artifact (audit).
        val supabaseUrl: String = (project.findProperty("SUPABASE_URL") as String?)
            ?: ""
        val supabaseAnonKey: String = (project.findProperty("SUPABASE_ANON_KEY") as String?)
            ?: ""
        buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrl\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKey\"")

        // Dev toggles — pinned to their safe-for-release defaults here (NOT
        // read from `.env.local`, or the committed file would leak into
        // release). BYPASS_LOGIN off (no seed-creds in a shipping build); HR +
        // TTS on (real watches record optical HR / speak cues); no tile
        // override (release uses the MapTiler `-P` key). The `debug { }` block
        // re-reads all of these from `.env.local`.
        buildConfigField("boolean", "BYPASS_LOGIN", "false")
        buildConfigField("boolean", "ENABLE_HR", "true")
        buildConfigField("boolean", "ENABLE_TTS", "true")
        // MapTiler key + Sentry come from `-P` flags in release (empty ⇒ the
        // feature is a no-op); the tile-URL override is debug-only so it is
        // pinned empty here.
        buildConfigField(
            "String", "PUBLIC_MAPTILER_KEY",
            "\"${(project.findProperty("PUBLIC_MAPTILER_KEY") as String?) ?: ""}\"",
        )
        buildConfigField("String", "PUBLIC_TILE_URL_TEMPLATE", "\"\"")
        buildConfigField(
            "String", "SENTRY_DSN",
            "\"${(project.findProperty("SENTRY_DSN") as String?) ?: ""}\"",
        )
        buildConfigField(
            "String", "APP_RELEASE",
            "\"${(project.findProperty("APP_RELEASE") as String?) ?: "dev"}\"",
        )
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // Release signing config. Matches the pattern used by
    // `apps/mobile_android`: if `key.properties` exists at the Android
    // project root, use it; otherwise fall back to the debug key so
    // local `./gradlew assembleRelease` on a clean checkout still
    // produces an installable (though untrusted) APK. CI supplies the
    // real keystore via secrets.
    val keystoreFile = rootProject.file("key.properties")
    val keystoreProps = Properties().apply {
        if (keystoreFile.exists()) keystoreFile.inputStream().use { load(it) }
    }

    signingConfigs {
        if (keystoreFile.exists()) {
            create("release") {
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
                storeFile = file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // Local-stack dev defaults from the committed
            // `apps/watch_wear/android/.env.local`. These OVERRIDE the
            // safe-for-release `defaultConfig` baseline above and are confined
            // to the debug build type, so they can never reach a release
            // artifact. A fresh clone gets a working local-stack build with no
            // `-P` flags: SUPABASE_URL/ANON point at the loopback stack,
            // BYPASS_LOGIN auto-signs-in the seed user, and the tile override
            // uses the local Protomaps server.
            buildConfigField("String", "SUPABASE_URL", "\"${envString("SUPABASE_URL")}\"")
            buildConfigField("String", "SUPABASE_ANON_KEY", "\"${envString("SUPABASE_ANON_KEY")}\"")
            buildConfigField("boolean", "BYPASS_LOGIN", envFlag("BYPASS_LOGIN").toString())
            buildConfigField("boolean", "ENABLE_HR", (!envFlag("DISABLE_HR")).toString())
            buildConfigField("boolean", "ENABLE_TTS", (!envFlag("DISABLE_TTS")).toString())
            buildConfigField(
                "String", "PUBLIC_MAPTILER_KEY",
                "\"${envString("PUBLIC_MAPTILER_KEY")}\"",
            )
            buildConfigField(
                "String", "PUBLIC_TILE_URL_TEMPLATE",
                "\"${envString("PUBLIC_TILE_URL_TEMPLATE")}\"",
            )
            buildConfigField("String", "SENTRY_DSN", "\"${envString("SENTRY_DSN")}\"")
            buildConfigField(
                "String", "APP_RELEASE",
                "\"${envString("APP_RELEASE", "dev")}\"",
            )
        }
        release {
            isMinifyEnabled = false
            signingConfig = if (keystoreFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")

    // Compose
    val composeBom = platform("androidx.compose:compose-bom:2026.06.01")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.compose.material:material-icons-core")

    // Compose-for-Wear
    implementation("androidx.wear.compose:compose-material:1.6.2")
    implementation("androidx.wear.compose:compose-foundation:1.6.2")
    implementation("androidx.wear.compose:compose-navigation:1.6.2")
    implementation("androidx.wear:wear-ongoing:1.1.0")
    // AmbientLifecycleObserver + AmbientAware lives here.
    implementation("androidx.wear:wear:1.4.0")

    // Tiles + ProtoLayout for the active-run tile. ProtoLayout is the
    // modern layout dialect (replaces the older `wear-tiles-material`
    // builders); the `tooling-preview` artefact is the side-loadable
    // tile preview Studio uses, kept off the release classpath via
    // `debugImplementation`.
    implementation("androidx.wear.tiles:tiles:1.6.1")
    implementation("androidx.wear.protolayout:protolayout:1.4.1")
    implementation("androidx.wear.protolayout:protolayout-material:1.4.1")
    implementation("androidx.wear.protolayout:protolayout-expression:1.4.1")
    debugImplementation("androidx.wear.tiles:tiles-renderer:1.6.1")

    // Health Services (live HR). 1.1.0-rc01 is the latest pre-stable; 1.0.0
    // is the last stable tag but lacks the flow helpers we want. Move to
    // 1.1.0 stable when it ships.
    implementation("androidx.health:health-services-client:1.1.0-rc02")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.3.0")
    implementation("com.google.guava:guava:33.6.0-android")

    // Location
    implementation("com.google.android.gms:play-services-location:21.4.0")

    // Wearable Data Layer — receives Supabase session handoff from the paired phone.
    implementation("com.google.android.gms:play-services-wearable:20.0.1")

    // Networking
    implementation("com.squareup.okhttp3:okhttp:5.4.0")

    // Local persistence
    implementation("androidx.datastore:datastore-preferences:1.2.1")

    // Encrypted storage for the auth session (access + refresh tokens are
    // bearer credentials — they live in EncryptedSharedPreferences, not
    // plaintext DataStore). 1.1.0-alpha06 is the build the MasterKey.Builder
    // API ships in; security-crypto has no newer stable than 1.0.0.
    implementation("androidx.security:security-crypto:1.1.0")

    // Serialization + coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.11.0")

    // Sentry crash reporting. Init in MainActivity.onCreate; gated on a
    // non-empty BuildConfig.SENTRY_DSN so dev / debug builds are
    // no-ops. The Android SDK auto-captures unhandled JVM exceptions;
    // we additionally wire breadcrumbs in long-running paths via
    // Sentry.captureException calls from coroutine catch blocks.
    implementation("io.sentry:sentry-android:8.47.0")
}
