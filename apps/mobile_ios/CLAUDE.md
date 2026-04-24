# mobile_ios — AI session notes

Flutter iOS app. **Phone-side WCSession sink for Apple Watch runs is live; sign-in, onboarding, local stores, preferences, and GPS recording are now wired.** The hard work of Phase 1 has been done on Android first. See Phase 1 in [../../docs/roadmap.md](../../docs/roadmap.md) for the remaining iOS-specific boxes.

## Current state

Dart files under `lib/`:

- `main.dart` — **wired**: initialises Supabase from `--dart-define-from-file=dart_defines.json`; inits `Preferences`, `LocalRunStore` (with crash recovery), `LocalRouteStore`, and `WatchIngestQueue`; routes unauthenticated users to `SignInScreen`, first-launch users to `OnboardingScreen`, and signed-in/onboarded users to `HomeScreen`; wires `WatchIngest.attach` on sign-in and drains the persistent queue via `onAuthStateChange`.
- `preferences.dart` — `SharedPreferences` wrapper; ported verbatim from `mobile_android`. `Preferences.init()` called at startup. `SettingsScreen` unit toggle persists across restarts.
- `goals.dart` — `RunGoal` model + `evaluateGoal`; ported verbatim from `mobile_android`.
- `local_run_store.dart` — on-disk run persistence with sidecar sync state, crash recovery (`in_progress.json`), and parallel load; ported verbatim from `mobile_android`.
- `local_route_store.dart` — on-disk route persistence; ported verbatim from `mobile_android`.
- `watch_ingest_queue.dart` — persists watch-run payloads received before sign-in to `<documents>/watch_ingest_queue/` and replays them on the next sign-in. Fixes the previous behaviour where unauthenticated watch runs were silently dropped on app restart.
- `mock_data.dart` — fallback UI data (still used by RunsScreen/RoutesScreen until M1/M2 land)
- `screens/home_screen.dart`, `runs_screen.dart`, `routes_screen.dart` — minimal shells (runs/routes still show mock data)
- `screens/sign_in_screen.dart` — email/password + Apple Sign-In button (gated behind `_kAppleSignInEnabled = false` pending Services ID setup)
- `screens/onboarding_screen.dart` — three-page first-launch flow with geolocator-based location permission request
- `screens/run_screen.dart` — **wired**: `RunRecorder` from `packages/run_recorder`; state machine idle → countdown → recording → paused → finished; saves to `LocalRunStore` on stop with incremental crash-safe persistence every 10s
- `screens/settings_screen.dart` — full settings surface: account (change password + delete account via `delete-account` Edge Function), preferences (units, audio cues, split interval, default activity, map style, pace format, auto-pause), profile & training (DOB, HR zones, resting/max HR, weekly goal, week start, privacy default, Strava auto-share, coach personality). All bag-backed keys round-trip through `SettingsSyncService`; Android-only tiles (BLE pairing, Strava ZIP import, backup/restore, advanced-GPS, dark mode) are deliberately omitted.
- `settings_sync.dart` — **verbatim port** of `mobile_android/lib/settings_sync.dart`. Keep in sync; when a key is added to the Android twin, mirror it here. Long-term this wants to live in a shared package; copy-then-converge for now.

Native iOS files under `ios/Runner/`:

- `AppDelegate.swift` — activates the `WatchIngestBridge` singleton at launch + attaches its method channel when the Flutter engine spins up.
- `WatchIngestBridge.swift` — **live**: `WCSessionDelegate` that receives `WCSessionFile` transfers from the watch, reads the gzipped-JSON track contents, and forwards to Dart via the `run_app/watch_ingest` method channel. Payloads arriving before Flutter is ready are buffered in-process and flushed on attach.

## What "done" means

Structurally identical to `mobile_android` (same stack, same `StatefulWidget + setState` pattern, same dependence on `packages/run_recorder` and `packages/api_client`). Every module in `mobile_android/lib/` that isn't Android-specific is a candidate to hoist into a shared package before the iOS port — ask before doing that; the team may prefer copy-then-converge.

## What this app will look like when it's done

Android-specific concerns that don't port:
- Foreground service for background GPS → iOS uses `CLLocationManager.allowsBackgroundLocationUpdates` (already done via run_recorder + Info.plist UIBackgroundModes:location).
- Health Connect importer → replaced by HealthKit importer.
- Google Sign-In flow → replaced by Apple Sign-In.
- Disk-backed tile cache → the same `flutter_map_cache` + `dio_cache_interceptor` combo works.

iOS-only concerns with no Android analogue:
- **Watch run ingest.** `WatchIngestBridge.swift` is live. The `WatchIngestQueue` now persists unauthenticated payloads to disk and replays them on sign-in — no runs are lost across restarts. Previously the in-process `pending` buffer was lost on app restart.

## Remaining HIGH gaps (from reviews/mobile-ios/gap-analysis.md)

- **H4 — GPX/KML import**: `import_screen.dart` not yet wired. `gpx_parser` is in pubspec; this is the next highest-value easy win.

## Recommended approach for a new task here

1. **Don't mirror Android file-by-file.** Port only what the task needs. The gap is large enough that a greenfield port of every screen is more churn than the task is worth.
2. **Prefer lifting shared code into a package** (`packages/ui_kit`, a new `packages/local_stores`, etc.) over copying Dart files between the two app directories. Two divergent copies of the same screen is the drift problem the parity-enforcement initiative is trying to prevent.
3. **Check Android first** for the pattern being asked for. If it exists there, port; if not, design on Android first and port second — Android is where the fast iteration happens.

## Dart analyzer

No warning or error level issues. The app carries ~20 info-level lints (mostly `always_use_package_imports` and `unnecessary_library_name`) — treat as noise per repo policy.

## Running it locally

See [local_testing.md](local_testing.md). You need an iOS simulator or a paired device.

The iOS Runner project uses Swift Package Manager + CocoaPods in hybrid mode (most plugins via SPM, `health` still via pods). Podfile pins `platform :ios, '15.0'`. Secrets for `flutter run` pass through `dart_defines.json` (gitignored) because inline `--dart-define=` flags break on the `sb_publishable_…` Supabase anon key format. Rationale: [../../docs/decisions.md § 13](../../docs/decisions.md).

## Before reporting a task done

- Update the iOS checkbox in `roadmap.md` (there are several — "Parse on iOS", etc.).
- If you ported a screen from `mobile_android`, note the source commit in the PR description so future drift fixes can find the twin.
- If the ported screen pulled in a dependency that isn't in Android, add it here so the divergence is visible.
