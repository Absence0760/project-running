# Local testing — Wear OS app (native Kotlin + Compose-for-Wear)

The Wear OS app is a **native Kotlin Android project**, not Flutter. See [CLAUDE.md](CLAUDE.md) and [decisions.md § 15](../../docs/decisions.md) for why.

---

## Prerequisites

| Tool | Install |
|---|---|
| Android Studio (Ladybug+ recommended) | `developer.android.com/studio` — ships the JBR 21 that this build pins Gradle to |
| Wear OS emulator | Created via Android Studio Device Manager |
| Local backend running | See [../backend/local_testing.md](../backend/local_testing.md) |

You do **not** need Flutter, Dart, or Melos for this app.

---

## Setup

### Create a Wear OS emulator

In Android Studio: **Device Manager → Create Virtual Device → Wear OS → Wear OS Large Round → API 30+**. `minSdk = 30` because `androidx.health:health-services-client` requires it; older images won't install the app.

Start the emulator before running.

### Gradle JDK

`gradle.properties` pins `org.gradle.java.home` to `/Applications/Android Studio.app/Contents/jbr/Contents/Home` (the JBR 21 bundled inside Android Studio). If Studio isn't at that path on your machine, override locally:

```bash
echo "org.gradle.java.home=/path/to/your/jdk21" >> android/gradle.properties
```

Do not commit that override. The default works on a standard macOS install.

---

## Running

```bash
cd apps/watch_wear/android
./gradlew installDebug
```

Then launch the **Run** app from the Wear OS emulator's app launcher.

Override the Supabase backend for staging / prod:

```bash
./gradlew installDebug \
  -PSUPABASE_URL=https://your-project.supabase.co \
  -PSUPABASE_ANON_KEY=<publishable-key>
```

The default `SUPABASE_URL` is `http://10.0.2.2:54321` — the emulator's loopback alias for the host machine, same pattern as `mobile_android`.

---

## Testing features

### Standalone run recording

1. Tap **Start** on the watch.
2. The app requests `ACCESS_FINE_LOCATION` + `BODY_SENSORS` on first launch — grant both.
3. GPS recording begins using the emulator's simulated location.
4. Tap **Stop** to end the workout.
5. The app saves the run to its local DataStore queue and immediately tries to push to Supabase. Check the **Runs** screen in the web app (`:7777/runs`) or the Android phone app to confirm it landed.

### GPS simulation

In Android Studio's emulator controls (`...` button on the emulator toolbar):

- **Location → Single points** — set a fixed GPS position.
- **Location → Routes** — draw a path and replay it at configurable speed. Useful for getting a realistic distance/pace on the watch UI.

### Heart rate simulation

The Wear OS emulator does **not** synthesise heart-rate samples — `HealthServices.getClient(...).measureClient` produces nothing in the emulator. Test HR end-to-end on a physical Wear OS 3+ watch. In the emulator, the "HR" field stays at `— bpm`; the rest of the run records normally.

### Offline queue behaviour

1. Stop the local Supabase stack (`supabase stop` in `apps/backend`).
2. Record a run on the watch. The sync fails and the run stays in the DataStore queue.
3. Restart Supabase.
4. Open the app again — the `init` block's `drainQueue()` fires after auth, and the queued run uploads. The queued-count badge on the pre-run screen disappears.

(Auto-retry on connectivity-change isn't wired up yet — it fires on app open + after every stop. TODO in `CLAUDE.md`.)

---

## Build verification (no device)

```bash
cd apps/watch_wear/android
./gradlew compileDebugKotlin   # catches schema drift + type errors
./gradlew assembleDebug        # produces app/build/outputs/apk/debug/app-debug.apk
./gradlew assembleRelease      # release-signed with debug keys; same verify path
```

There's no test suite yet. `compileDebugKotlin` is the bar.

---

## Schema codegen

If you change the `runs` table in `apps/backend/supabase/migrations/`, regenerate the Kotlin row class:

```bash
cd /path/to/repo
dart run scripts/gen_dart_models.dart
```

That writes both `packages/core_models/lib/src/generated/db_rows.dart` (Dart) and `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/generated/DbRows.kt` (Kotlin). Compile the Kotlin app afterwards — drift surfaces as a compile error at `SupabaseClient.kt`.

---

## Troubleshooting

### `IllegalArgumentException: 25.0.2` on `./gradlew` commands

Gradle 8.14's embedded Kotlin compiler can't parse Java 25's version string. Your system JDK is probably Homebrew `openjdk@25`. Pin Gradle to JDK 21 via `gradle.properties` (the default already points at Android Studio's JBR 21 — check it exists at the configured path).

### Emulator shows round black screen

Wear OS emulators take 1–2 minutes to boot on first launch. Wait for the watch face.

### "Connection refused" from the watch

Use `http://10.0.2.2:54321` for the Supabase URL (the default). `localhost` and `127.0.0.1` resolve to the emulator itself, not the host.

### `./gradlew installDebug` hangs on "Connecting to devices"

Check `adb devices` — the emulator should appear as `online`. If it's `offline`, restart it from Device Manager.

### App crashes on first launch with `SecurityException: BODY_SENSORS`

You granted `ACCESS_FINE_LOCATION` but not `BODY_SENSORS`. The permission launcher in `RunWatchApp.kt` only `start()`s the run after *all* requested permissions are granted; if `start` never fires, re-tap Start and approve both.

### APK install fails with `INSTALL_FAILED_OLDER_SDK`

The target device / emulator is below API 30. Recreate the emulator at API 30+ (Wear OS 3).

---

*Last updated: April 2026*
