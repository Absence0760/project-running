# watch_wear — AI session notes

Flutter app targeting Wear OS. **Phase 2 usable** — real GPS recording,
live heart rate via Health Services, local persistence of finished runs,
auto-sync to Supabase on connectivity change. Phase 3 rewrites the UI in
Compose-for-Wear.

## Current state

Four Dart files under `lib/`:

- `main.dart` — app entry, `Supabase.initialize`, wires `ApiClient` + `LocalRunStore` into the screen
- `run_watch_screen.dart` — pre-run / running / post-run state machine, driven by `packages/run_recorder`; listens to `Connectivity.onConnectivityChanged` and drains the local queue when the watch comes online
- `local_run_store.dart` — `SharedPreferences`-backed list of unsynced runs, keyed by id
- `heart_rate_service.dart` — thin Dart wrapper around the `watch_wear/hr` method channel + `watch_wear/hr/stream` event channel

Native Kotlin (`android/app/src/main/kotlin/com/runapp/watchwear/watch_wear/`):

- `MainActivity.kt` — installs the HR plugin on `configureFlutterEngine`
- `HeartRatePlugin.kt` — registers a `MeasureCallback` on `HealthServices.getClient(context).measureClient` for `DataType.HEART_RATE_BPM`; pipes samples to the event channel. `start` / `stop` methods drive the lifecycle.

Native Android project is scaffolded (previous sessions had none) with a
Wear OS-shaped manifest: `<uses-feature android:name="android.hardware.type.watch" />`,
`<uses-library name="com.google.android.wearable" required="false" />`,
`com.google.android.wearable.standalone = true`, plus location + wake-lock
permissions.

## Sync architecture

The watch talks to Supabase **directly** over WiFi/cellular, same `ApiClient`
that `mobile_android` uses — no phone handoff, no duplicate REST client like
`watch_ios`. Because it reuses `packages/api_client` and the generated row
types under `packages/core_models`, schema drift is caught at compile time
instead of silently breaking sync.

Flow:
1. User taps Start → `RunRecorder.prepare()` requests location permission, opens the position stream.
2. User taps Stop → `RunRecorder.stop()` returns a `Run`. We immediately persist it to `LocalRunStore`.
3. User taps Sync → `ApiClient.saveRun(run)` uploads the gzipped track to Storage and inserts the row. On success, remove from `LocalRunStore`. On failure (offline, auth), the run stays in the store and the user retries later.
4. Pre-run screen shows the unsynced-count badge so runs that failed to sync are visible across app restarts.

Auth in Phase 1 is a hardcoded seed sign-in (`runner@test.com` /
`testtest`) on app start — sufficient for dogfooding on a dev Supabase.
Real auth lands with Phase 2 or 3.

## What's deferred

- **Wearable Data Layer paired-phone handoff** — optional alternative to direct-to-Supabase; WiFi-direct works for now.
- **Route preview / live navigation / off-route haptics** — `run_recorder` already supports it, but the watch UI doesn't surface it.
- **Glanceable tile / watch face complication** — native Kotlin work.
- **Compose-for-Wear UI** — Flutter widgets on a round Wear OS face are functional but not idiomatic. Rotary-bezel input and curved text need Compose.

## Running it locally

See [../../docs/local_testing_wear_os.md](../../docs/local_testing_wear_os.md).
`flutter run -d <wear-device>` from `apps/watch_wear/` with a local Supabase
stack running. Override the backend with
`--dart-define SUPABASE_URL=... --dart-define SUPABASE_ANON_KEY=...`.

## Before reporting a task done

- `dart analyze` passes with only `info`-level lints (imports, pubspec sort).
- If you added a new native capability, update the manifest permissions and add a pointer to this file.
- Tick the corresponding Wear OS box in `roadmap.md` § Phase 2.
- If you touched `run_recorder` behaviour, test on both `mobile_android` and here — same package, two consumers.
