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

**Primary path — phone handoff.** Auth comes from the paired Android phone
over the Wearable Data Layer. `mobile_android` pushes `{access_token,
refresh_token, user_id, base_url, anon_key, expires_at_ms}` to
`/supabase_session` whenever Supabase's `onAuthStateChange` fires;
`SessionBridge` on the watch receives it and `SessionStore` caches it to
DataStore so a cold launch while offline still has credentials.
`RunViewModel.refreshIfExpired` exchanges the refresh token for a new
access token automatically, and `drainQueue` retries once on HTTP 401 by
refreshing then re-pushing.

**Fallback — direct sign-in on the watch.** For standalone Wear OS
users (LTE watch, no paired Android phone), the pre-run screen has a
"Sign in" button that opens a Compose email/password form
(`Stage.SignIn` in the ViewModel). Calls the same `SupabaseClient.signIn`
path that the seed-creds fallback used to use, and stores the resulting
session in `SessionStore` so it's indistinguishable from a
phone-handed-over session for the rest of the lifecycle. Typing an email
on a 46mm screen is awful; the docs say so explicitly. Use it only when
you don't have a paired Android phone.

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

## Dev-only env flags (`.env.local`)

Gitignored file at `apps/watch_wear/android/.env.local` — copy from
`.env.example` and flip what you need. Values are read at Gradle-configure
time and emitted as `BuildConfig` constants; changes require a rebuild
(`./gradlew installDebug`).

| Flag | Default | Effect |
|---|---|---|
| `BYPASS_LOGIN` | `false` | On app start, if no cached session and no phone handoff, auto-sign-in as `runner@test.com` / `testtest`. Skips the sign-in screen. Use only against local/dev Supabase. **Not a sign-out switch**: flipping to `false` won't sign out a user whose session is already cached — tap the "Sign out" chip on PreRun or `./gradlew uninstallDebug && ./gradlew installDebug` to get a clean slate. |
| `ENABLE_HR` | `false` | Start the Health Services `MeasureClient` during a run and write `avg_bpm` into run metadata. Default off because the Wear OS emulator produces synthetic HR samples that look like real readings — leaving it off by default keeps fake data out of the runs table. Turn on when building for a real device with a real sensor. |

The UI tracks the flags: with `ENABLE_HR` off, the BPM row on the Running
screen and the "N bpm avg" line on PostRun both disappear rather than
showing placeholder text that would train you to trust an emptyish reading.

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

## Production reliability (Phase 4)

The recording loop lives in **`RunRecordingService`** — a foreground
service with `foregroundServiceType="location"`, a sticky notification,
and a partial wake-lock — not in the ViewModel's coroutine scope. This
is what lets a run survive the activity being destroyed (ambient mode,
backgrounding, low-memory kills).

- `recording/RecordingRepository.kt` — process-singleton `StateFlow`
  that the service writes and the ViewModel reads. The decoupling is
  the whole point.
- `recording/RunRecordingService.kt` — owns the GPS + HR streams, ticks
  the elapsed clock every 500ms, posts notification updates, holds the
  wake lock.
- `recording/CheckpointStore.kt` — DataStore snapshot of an in-progress
  run, written every 15s during recording. On next launch, if a
  checkpoint exists, the pre-run screen shows a **"Recover unsaved
  run?"** prompt — accepting saves it as a finished run (queued for
  upload), discarding clears it. This is what saves a run when the
  process is killed mid-recording.
- `system/BatteryOptimization.kt` — checks
  `PowerManager.isIgnoringBatteryOptimizations` at launch and on each
  `onResume`. If we're not whitelisted, the pre-run screen surfaces a
  **"Fix battery saver"** chip that opens the system whitelist prompt.
  Without this, Android throttles the foreground service after ~10
  minutes — fatal for long runs.
- `system/NetworkWatcher.kt` — `ConnectivityManager.NetworkCallback`
  flow. The ViewModel collects it; offline → online transitions fire
  `drainQueue` automatically so a run recorded out of range uploads as
  soon as connectivity returns.
- `awaitAuth()` in `RunViewModel.drainQueue` — waits up to 3s for the
  cached-session restore to land before bailing with "not
  authenticated". Kills the cold-start race that previously surfaced a
  spurious sync error after a quick start/stop.

### Ultra-length runs (10+ hours)

The recording loop was engineered for marathon scale (4–6 h); these
pieces extend that to all-day efforts without drifting into O(n) memory
or hammering the NotificationManager:

- `recording/TrackWriter.kt` streams GPS points to a JSON array on disk
  (cache dir, `tracks/{runId}.json`) with a flush every 32 points. The
  in-memory point list is gone — `RecordingRepository.Metrics` carries
  only `trackPointCount` + `latestPoint` + `trackFilePath`.
- Rolling HR. `RunRecordingService` tracks `bpmSum: Long` + `bpmCount:
  Long` instead of a list; avg is O(1) regardless of sample count.
  `Checkpoint` carries the same rolling pair, so recovery works without
  replaying 36,000 samples.
- Notification refresh is throttled to every 10 tickerJob iterations (~5s).
  The UI still gets its 500ms elapsed tick, but NotificationManager only
  sees a fraction of the churn.
- `SupabaseClient.saveRun` takes a `File` and gzips disk-to-disk into a
  sibling temp file before uploading — peak memory is one 8 KiB buffer.
- `system/BatteryStatus.kt` reads `BATTERY_PROPERTY_CAPACITY` and the
  pre-run screen surfaces a warning below 40%. A 10-hour run on a half-
  charged watch is the single most common way to lose an ultra attempt.

Permissions added in the manifest: `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.

## What's still deferred

- **Ambient-mode rendering.** The recording continues in the foreground
  service when the watch dims — it will not be killed — but the Compose
  UI doesn't yet have a low-color "ambient" branch. Wire
  `AmbientLifecycleObserver` + a dimmed Compose render path. (Glanceable
  watch face complication is a separate, larger item.)
- **Live map during recording / live position marker on a route.** The
  RunningScreen is still pure stats. The off-route banner + "X to go"
  badge ship without a map (the math runs per GPS sample); the
  *visual* position marker on the planned route is blocked on adding
  a tile renderer, which is a multi-day platform project in its own
  right. Not started.
- **Live HTTP tile cache.** Blocked on the live map above;
  pre-downloaded tiles are still the only path.
- **Google Sign-In on the watch** (today only email/password direct
  sign-in works; for Google use the phone app + Data Layer handoff, or
  build out `RemoteActivityHelper`).
- **Watch face tile / complication.**
- **End-to-end soak test on a real device.** All of the above ships in
  this session as compiles-cleanly code; verifying it actually
  records 60+ minutes without dropping samples requires putting it on a
  watch and going for a real run.

## Recording UX — what's shipped on the Running screen

What the UI exposes during a recording, for quick reference when reading
`ui/RunWatchApp.kt`:

- **Pre-run activity picker.** `CompactChip` on `PreRunScreen` cycles
  `run → walk → hike → cycle`; the choice flows through to
  `metadata.activity_type` on save.
- **3-second start countdown.** Between permission grant and
  `vm.start()`, a full-screen `CountdownOverlay` shows `3 → 2 → 1`
  (tap anywhere to cancel). UI-only — the recording service isn't live
  during the countdown.
- **Pause / resume.** `||` button toggles to `Go`; stage flips
  `Running ↔ Paused`. The foreground service owns the actual pause state
  via `RunRecordingService.pause / resume`.
- **Lap button.** `vm.markLap()` → service appends to the laps list;
  `FinishedSummary.laps` powers the splits table on `PostRunScreen`
  and writes `metadata.laps` on sync.
- **Hold-to-stop.** `HoldToStopButton` requires an 800 ms press before
  `vm.stop()` fires; a circular progress ring fills during the hold,
  releasing early cancels. Stops a single accidental tap from ending a
  long run.
- **Haptic confirmations.** Pause / Resume / Lap buttons fire
  `LocalHapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)`
  on tap — the runner feels a confirmation pulse on every control
  action, not just the countdown-less Start.
- **GPS self-heal retry.** `RunRecordingService.gpsRetryJob` mirrors
  the `_startGpsRetryLoop` shape from
  `packages/run_recorder/lib/src/run_recorder.dart`: a 10 s poll that
  re-subscribes whenever the subscription is dead. Primary trigger is
  `gpsJob?.isActive != true` (same as Android's `_positionSub == null`);
  secondary Wear-only trigger is "stream silent for >30 s mid-run",
  added because `FusedLocationProviderClient` can keep a callback
  registered while silently emitting nothing — a failure mode
  Geolocator surfaces as a stream error. Initial no-fix
  (`lastPointAtMs == 0L`) is explicitly not a stall; that's indoor mode.
- **Indoor / no-GPS mode.** The elapsed clock ticks regardless of GPS;
  distance stays 0 until the first fix lands. `TrackWriter.close()`
  produces a valid empty `[]` track, so the upload and downstream run
  detail render without special-casing. The RunningScreen banner reads
  "No GPS — time only" when no fix has landed yet, and "GPS lost"
  after a mid-run drop, so the runner can tell the two apart.
- **Route overlay (no map).** Pre-run Route chip → `Stage.RoutePicker`
  (backed by `LocalRouteStore` + `SupabaseClient.fetchRoutes`).
  Selected waypoints flow via `ACTION_START` extras into
  `RunRecordingService.parseRouteWaypoints`, which calls
  `RouteMath.offRouteDistanceM` + `routeRemainingM` per GPS sample.
  `RunningScreen` renders the "Off route · N m" banner (with hysteresis
  at 40 m / 20 m and a double-haptic on entry) and a "X.XX km to go"
  badge under the distance readout. The *visual* position marker on a
  rendered route is still deferred — no live map yet.
- **TTS audio cues.** `recording/TtsAnnouncer.kt` wraps
  `android.speech.tts.TextToSpeech` with an async init + flush-queued
  speak. `RunRecordingService` announces "Run started" on begin,
  a split on each completed kilometre ("1 kilometre. Pace 5 minutes
  30 seconds per kilometre" — same phrasing as Android's
  `audio_cues.dart`), pace-drift nudges from `firePaceAlert`, and a
  finish summary in `stopRecording`. Gated on `BuildConfig.ENABLE_TTS`
  (defaults on; set `DISABLE_TTS=true` in `.env.local` to silence).
- **Target-pace picker + haptic pace alerts.** Pre-run **Pace** chip
  cycles `off / 4:00 / 4:30 / 5:00 / 5:30 / 6:00 / 6:30 / 7:00 /km` via
  `RunViewModel.cycleTargetPace`. `start()` passes the value through
  `EXTRA_TARGET_PACE_SEC_PER_KM`; the service compares live pace every
  GPS sample (after the 50 m stabilisation gate used for pace) and
  calls `firePaceAlert(tooSlow)` when drift > 30 s/km, rate-limited to
  one alert per 30 s. Haptic fires via `VibratorManager` — a
  `createWaveform(longArrayOf(0, 180, 180, 180), ...)` double pulse
  for "speed up", a `createOneShot(220, DEFAULT_AMPLITUDE)` single
  pulse for "slow down", paired with a TTS nudge. Matches the
  two-pulse vs single-pulse pattern on Android.
- **Pedometer.** `Pedometer.kt` wraps `Sensor.TYPE_STEP_COUNTER` with a
  per-run baseline subtraction so the flow yields cumulative steps
  since recording started. `RunRecordingService` collects into
  `RecordingRepository.Metrics.steps`; `QueuedRun.steps` persists the
  final count; `pushRun` writes `run.metadata.steps` when non-zero.
  Requires `ACTIVITY_RECOGNITION` at runtime — requested alongside
  `ACCESS_FINE_LOCATION` + `BODY_SENSORS` by `permissionLauncher`.
  `RunningScreen` surfaces the live count as a `"N steps"` caption
  beneath `bpm`.

## Before reporting a task done

- `./gradlew compileDebugKotlin` passes.
- If you touched the `runs` schema or added a table to `_kotlinTables`, re-ran `dart run scripts/gen_dart_models.dart` and committed the regenerated Kotlin file.
- Updated [../../docs/metadata.md](../../docs/metadata.md) if a new `metadata` key is written from this app.
- Ticked the corresponding Wear OS box in [../../docs/roadmap.md](../../docs/roadmap.md).
