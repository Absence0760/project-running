# watch_wear — AI session notes

**Pure Kotlin Wear OS app** using Jetpack Compose-for-Wear. **Not Flutter.**
The Flutter build was removed when the team committed to Compose-for-Wear
native UI (see [../../docs/decisions.md § 15](../../docs/decisions.md)).

## Layout

```
apps/watch_wear/
├── CLAUDE.md                       # this file
└── android/                        # Android project root
    ├── build.gradle.kts
    ├── settings.gradle.kts
    ├── gradle.properties           # pins Gradle JDK to Android Studio's JBR 21
    ├── gradle/wrapper/
    └── app/
        ├── build.gradle.kts
        └── src/main/
            ├── AndroidManifest.xml
            ├── kotlin/com/runapp/watchwear/
            │   ├── MainActivity.kt
            │   ├── RunViewModel.kt        # single source of UI state
            │   ├── SupabaseClient.kt      # OkHttp REST + Storage client
            │   ├── GpsRecorder.kt         # FusedLocationProviderClient wrapper
            │   ├── HeartRateMonitor.kt    # Health Services MeasureClient
            │   ├── LocalRunStore.kt       # DataStore-backed retry queue
            │   ├── ui/RunWatchApp.kt      # Compose-for-Wear screens
            │   └── generated/DbRows.kt    # GENERATED — do not edit
            └── res/mipmap-*/ic_launcher.png
```

## Schema drift protection

`RunRow` in `generated/DbRows.kt` is emitted by `scripts/gen_dart_models.dart`
from the Supabase migrations alongside the Dart `db_rows.dart`. Same
generator, same parse, two emitters — schema changes regenerate both. Renaming
`runs.distance_m` to, say, `runs.distance_metres` in a migration regenerates
the Kotlin file and breaks `SupabaseClient.saveRun` at compile time, exactly
like it breaks Dart callers of `RunRow`.

**If you change the `runs` schema**: run `dart run scripts/gen_dart_models.dart`.
Both outputs are committed. CI's `parity-types` job checks the TypeScript
file; the Dart and Kotlin emitters currently lean on `dart analyze` (Dart)
and `./gradlew compileDebugKotlin` (Kotlin) catching drift locally. A CI
hook that re-runs the generator and fails on uncommitted diff is a TODO.

If you add a new table that Wear OS writes to, add it to `_kotlinTables`
in `gen_dart_models.dart`.

## Sync architecture

Wear OS watches are standalone-capable (WiFi + optional cellular), so the
watch talks to Supabase directly — no paired-phone handoff, no Wearable
Data Layer proxy. `SupabaseClient` is a thin OkHttp wrapper:

1. `signIn(email, password)` → POST `/auth/v1/token?grant_type=password`, stashes access token + user id in memory.
2. `saveRun(...)` → gzips the track JSON, POSTs to `/storage/v1/object/runs/{user_id}/{run_id}.json.gz`, then POSTs the row to `/rest/v1/runs` with `Prefer: return=minimal`. Matches the Dart `ApiClient.saveRun` contract byte-for-byte so the web/Android apps read Wear-produced runs without special cases.

Auth comes from the paired Android phone over the Wearable Data Layer.
`mobile_android` pushes `{access_token, refresh_token, user_id, base_url,
anon_key, expires_at_ms}` to `/supabase_session` whenever Supabase's
`onAuthStateChange` fires; `SessionBridge` on the watch receives it and
`SessionStore` caches it to DataStore so a cold launch while offline
still has credentials. `RunViewModel.refreshIfExpired` exchanges the
refresh token for a new access token automatically, and `drainQueue`
retries once on HTTP 401 by refreshing then re-pushing. If no session has
ever been received (fresh install, phone app never signed in), the
pre-run screen shows an auth error — open the phone app and sign in
there; the watch picks up the session within a second.

Offline runs persist in `LocalRunStore` (DataStore, `watch_wear` prefs,
key `queued_runs_v1`). `RunViewModel.drainQueue()` fires on app start after
auth succeeds and after every run stops. A connectivity-change auto-retry is
a TODO — today the queue drains opportunistically.

## Heart rate

`HeartRateMonitor` registers a `MeasureCallback` on
`HealthServices.getClient(context).measureClient` for
`DataType.HEART_RATE_BPM` and exposes a `Flow<Int>` of live samples.
`RunViewModel` collects into a list during recording, averages on stop,
writes `avg_bpm` into `run.metadata` before upload. Behaviour matches
`watch_ios`'s HealthKit integration — [docs/metadata.md](../../docs/metadata.md)
registers the key.

## Running it locally

See [local_testing.md](local_testing.md).

Build and install on a Wear OS emulator:

```bash
cd apps/watch_wear/android
./gradlew installDebug
```

Override the Supabase backend:

```bash
./gradlew installDebug -PSUPABASE_URL=https://staging.example.co -PSUPABASE_ANON_KEY=...
```

The default `SUPABASE_URL` points at `http://10.0.2.2:54321` — the Android
emulator's loopback alias for the host machine, matching the local Supabase
stack that `mobile_android` also uses.

## Dependency versions

All versions are pinned to latest stable as of April 2026. Key points:

- **AGP 9.1.0** + **Gradle 9.4.1**. AGP 9 removed the `org.jetbrains.kotlin.android` plugin — it's now built-in — and removed the `kotlinOptions {}` DSL block in favour of `kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }`. Both changes are reflected in the root plugin list + `app/build.gradle.kts`.
- **Kotlin 2.3.20** (compose + serialization plugins). Kotlin 2.0+ means the Compose Compiler is a Kotlin plugin (`org.jetbrains.kotlin.plugin.compose`), versioned with Kotlin itself.
- **Compose BOM 2026.03.01** pins core Compose artifacts; **Wear Compose 1.6.1** (material / foundation / navigation) is declared separately because it's not under the core BOM.
- **Health Services 1.1.0-rc01**. Last stable is 1.0.0 but lacks some of the APIs we rely on; bump to 1.1.0 stable when it ships.
- **OkHttp 5.3.2**. OkHttp 5 made `ResponseBody` non-nullable (`response.body.string()` instead of `response.body?.string()`) — one ergonomic break to watch for when adding network code.
- **compileSdk 36** / **targetSdk 35** / **minSdk 30**. AGP 9.1 requires compileSdk 36; Health Services requires minSdk 30; Wear OS 3 is the realistic deployment floor regardless.

When bumping, regenerate the codegen afterwards (`dart run scripts/gen_dart_models.dart`) and build both `./gradlew assembleDebug` and `./gradlew assembleRelease`.

## Gradle JDK quirk

Homebrew's default JDK on this machine is 25; Gradle 8.14's embedded Kotlin
compiler can't parse that version string and fails the whole build with a
cryptic `IllegalArgumentException: 25.0.2`. `gradle.properties` pins
`org.gradle.java.home` to the JDK bundled inside Android Studio (JBR 21).
If Android Studio lives somewhere other than `/Applications/Android Studio.app`
on your machine, override that line locally.

## What's deferred

- Connectivity-change auto-retry (today `drainQueue` only fires on app start + after stop).
- Foreground service for background-safe GPS across wrist-down / ambient.
- Standalone sign-in for users without a paired Android phone (QR pairing / Google Sign-In via `RemoteActivityHelper`).
- Watch face tile / complication.

## Before reporting a task done

- `./gradlew compileDebugKotlin` passes.
- If you touched the `runs` schema or added a table to `_kotlinTables`, re-ran `dart run scripts/gen_dart_models.dart` and committed the regenerated Kotlin file.
- Updated [../../docs/metadata.md](../../docs/metadata.md) if a new `metadata` key is written from this app.
- Ticked the corresponding Wear OS box in [../../docs/roadmap.md](../../docs/roadmap.md).
