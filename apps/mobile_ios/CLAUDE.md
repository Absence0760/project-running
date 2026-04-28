# mobile_ios — AI session notes

Flutter iOS app. **The structural catch-up to the Android twin is in progress — the entire `screens/` and `widgets/` trees plus the platform-agnostic `lib/*.dart` libraries are now copied verbatim from `mobile_android`.** Compilation parity is the goal of the catch-up; runtime parity follows as iOS-specific runtime issues (permissions, background modes, native bridges) get exercised on a simulator or device. See `mobile_android_backlog.md` for the canonical execution order — most of it applies to iOS too.

## Scope — read before writing code

**Web is the canonical feature surface. This app mirrors web and adds iOS-only capabilities.** See [../../docs/decisions.md § 24](../../docs/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive) and the live matrix at [../../docs/parity.md](../../docs/parity.md).

**Build here:**

- **iOS-led features** (the physical-exception list in §24, applied to iOS): live GPS recording with `CLLocationManager.allowsBackgroundLocationUpdates`, on-device crash recovery, BLE chest-strap HR, pedometer / cadence, haptic / TTS pace alerts, OS share sheets, **HealthKit** import (replaces Health Connect on Android), **Apple Sign-In** (replaces Google Sign-In on Android), **Watch Connectivity** ingest from `watch_ios` (already live in `WatchIngestBridge.swift`).
- **Mirroring** of an already-shipped web feature, scoped to the gap analysis in `reviews/mobile-ios/gap-analysis.md` and the iOS rows in `parity.md` where web is `✓` and iOS is `✗` / `Partial`. Use `mobile_android` as the **Flutter implementation reference** (idioms, store shape, screen layout) — not as the feature spec.

**Don't build here first:**

- A user-facing feature that doesn't yet exist on web — build it on web first, mirror after. Same rule as Android per §24.
- An Android-only tile that has no iOS equivalent. The deliberately omitted set (already documented in `screens/settings_screen.dart`): BLE pairing UI, Strava ZIP import, backup/restore, advanced-GPS toggle, dark-mode toggle. Don't add these without a fresh decision.
- New abstractions / DI frameworks. Match Android's `StatefulWidget + setState + ChangeNotifier` stack — verbatim. The iOS app is "structurally identical to mobile_android" by design (see "What 'done' means" below).
- Direct `Supabase.instance.client.from(...)` calls in screens. Route through `packages/api_client`.
- Comments, decision docs, READMEs. Conventions in [../../docs/conventions.md](../../docs/conventions.md) apply in full.

## Current state

`lib/` mostly mirrors `apps/mobile_android/lib/` byte-for-byte. The pattern is "copy-then-converge" (the team's chosen alternative to a shared-package extraction — see "What 'done' means" below). When you change a file under `mobile_android/lib/`, the iOS twin needs the same change unless the change is android-specific.

**iOS-owned files (NOT verbatim copies — keep these as-is):**

- `main.dart` — bootstraps the iOS-specific bits: bridges `--dart-define-from-file=dart_defines.json` into `dotenv` (so verbatim libs that read `dotenv.env['X']` don't need an iOS fork), inits the same `Preferences` / `LocalRunStore` / `LocalRouteStore` / `WatchIngestQueue` / `SettingsSyncService` / `AudioCues` / `SocialService` / `RaceController` / `TrainingService` / `BleHeartRate` / `SyncService` chain Android does, and threads them all through `HomeScreen`.
- `screens/sign_in_screen.dart` — email/password + Apple Sign-In button (gated behind `_kAppleSignInEnabled = false` pending Services ID setup). Diverges from Android's Google-Sign-In version intentionally. Pushes `sign_up_screen.dart` from the "Don't have an account?" link.
- `screens/sign_up_screen.dart` — email/password account creation + Apple Sign-In; mirrors Android's `sign_up_screen.dart` shape with Apple substituted for Google.
- `screens/onboarding_screen.dart` — three-page first-launch flow with geolocator-based location permission request.
- `screens/run_screen.dart` — basic `RunRecorder`-driven recording (idle → countdown → recording → paused → finished). The Android twin is much richer (race mode, structured workouts, BLE HR overlay, off-route detection, foreground notification, etc.); iOS lags here on purpose because `run_notification_bridge.dart` is android-only and the rest needs end-to-end testing on a paired iPhone before it's safe to ship.
- `screens/settings_screen.dart` — full iOS settings surface; deliberately omits Android-only tiles (BLE pairing UI, Strava ZIP import, backup/restore, advanced-GPS toggle, dark-mode toggle).
- `watch_ingest_queue.dart` — iOS-specific Apple Watch ingest queue.

**Verbatim copies of `mobile_android/lib/*.dart`** (no edits — re-copy when the twin changes):

- Library: `audio_cues.dart`, `backend_timeout.dart`, `backup.dart`, `ble_heart_rate.dart`, `fitness.dart`, `goals.dart`, `hr_zones.dart`, `local_route_store.dart`, `local_run_store.dart`, `preferences.dart`, `privacy.dart`, `race_controller.dart`, `recurrence.dart`, `route_simplify.dart`, `run_stats.dart`, `segments.dart`, `settings_sync.dart`, `social_service.dart`, `strava_importer.dart`, `sync_service.dart`, `tile_cache.dart`, `training.dart`, `training_load.dart`, `training_service.dart`.
- Every file under `screens/` except the six iOS-owned screens listed above.
- Every file under `widgets/`.

Things deliberately NOT copied across (Android-only mechanisms — iOS uses different counterparts):

- `background_sync.dart` (WorkManager) — iOS will use `BGTaskScheduler` when the bg-fetch path is wired.
- `run_notification_bridge.dart` (foreground-service notification) — iOS uses `CLLocationManager.allowsBackgroundLocationUpdates`.
- `wear_auth_bridge.dart` (Wear OS data layer) — iOS reads watch payloads through `WatchIngestBridge.swift` instead.
- `health_connect_importer.dart` — iOS will use a HealthKit importer (still TBD).

Native iOS files under `ios/Runner/`:

- `AppDelegate.swift` — activates the `WatchIngestBridge` singleton at launch + attaches its method channel when the Flutter engine spins up.
- `WatchIngestBridge.swift` — **live**: `WCSessionDelegate` that receives `WCSessionFile` transfers from the watch, reads the gzipped-JSON track contents, and forwards to Dart via the `run_app/watch_ingest` method channel. Payloads arriving before Flutter is ready are buffered in-process and flushed on attach.

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

## Catch-up status

- **Phase 1 done** — 14 platform-agnostic Dart libraries copied verbatim from android.
- **Phase 2 done** — entire `screens/` and `widgets/` trees copied verbatim from android (29 screens + 20 widgets), with the iOS-owned screens kept intact. `main.dart` updated to construct the Android-twin service set (`AudioCues`, `SocialService`, `RaceController`, `TrainingService`, `BleHeartRate`).
- **Drift catch-up done** — `preferences.dart` + `settings_sync.dart` resynced to the Android twin (recent additions like `default_activity_type`, `keep_screen_on` now present on iOS too). The four remaining portable libs (`backup.dart`, `strava_importer.dart`, `sync_service.dart`, `tile_cache.dart`) ported verbatim. `SyncService` now starts in `main.dart` so background reconciliation runs on iOS the same way it does on Android. `sign_up_screen.dart` shipped on iOS (mirrors android's shape, Apple Sign-In substituted for Google) and wired from `sign_in_screen.dart`.
- **Phase 3+ deferred until a simulator pass** — runtime issues (Info.plist keys for Health / BLE / Background Modes, `permission_handler` configuration, `flutter pub get` on a Mac, `pod install`, native channel wiring for things like `run_notification_bridge` if iOS adopts a watch / phone-side background notification) get exercised the next time someone builds the app on a Mac. The compiled-and-imported state is the deliverable here; a green build in CI is the next gate.

## Recommended approach for a new task here

1. **Feature spec lives on web; Flutter idiom lives on Android.** When deciding *what* a screen does, read the web component (`apps/web/src/lib/components/...` or `apps/web/src/routes/...`) and `parity.md`. When deciding *how* to write a Flutter screen, look at the corresponding `apps/mobile_android/lib/screens/...` for the idiom, store wiring, and api_client usage. Don't invent a new feature on iOS — that violates §24.
2. **If the task is "port the latest Android change to iOS,"** copy the file verbatim (or apply the same diff) — the convergence cost stays low only as long as the twins don't drift.
3. **If the task is "fix iOS-only behaviour,"** keep the change in the four iOS-owned files (`main.dart`, the three iOS-owned screens) or in `ios/Runner/`. Don't fork a verbatim copy unless there is no other way.
4. **Prefer lifting shared code into a package** (`packages/ui_kit`, a new `packages/local_stores`, etc.) over deepening the verbatim duplication when a third client (or shared test surface) will need it. The bar for extracting a package is "more than two clients consume the same file or the file gets meaningfully edited on one twin without the other catching up."

## Dart analyzer

No warning or error level issues. The app carries ~20 info-level lints (mostly `always_use_package_imports` and `unnecessary_library_name`) — treat as noise per repo policy.

## Running it locally

See [local_testing.md](local_testing.md). You need an iOS simulator or a paired device.

The iOS Runner project uses Swift Package Manager + CocoaPods in hybrid mode (most plugins via SPM, `health` still via pods). Podfile pins `platform :ios, '15.0'`. Secrets for `flutter run` pass through `dart_defines.json` (gitignored) because inline `--dart-define=` flags break on the `sb_publishable_…` Supabase anon key format. Rationale: [../../docs/decisions.md § 13](../../docs/decisions.md).

## Before reporting a task done

- Update the iOS checkbox in `roadmap.md` (there are several — "Parse on iOS", etc.).
- If you ported a screen from `mobile_android`, note the source commit in the PR description so future drift fixes can find the twin.
- If the ported screen pulled in a dependency that isn't in Android, add it here so the divergence is visible.
