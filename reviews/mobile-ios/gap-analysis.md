# iOS Gap Analysis: `apps/mobile_ios/` vs `apps/mobile_android/`

## 1. Executive summary

`apps/mobile_ios/` is a functional scaffold with 7 Dart files and 3 Swift files. The only production-grade feature it ships today is the Apple Watch run ingest pipeline (WatchIngestBridge → method channel → `ApiClient.saveRun`). Every other surface — recording, local store, sync, routes, history, auth — is either a timer-based simulation or a mock-data ListView. The gap to Android parity is large (~20 real features, dozens of screens), but the iOS `pubspec.yaml` already declares all five shared packages as dependencies, so the easy wins are substantial: `run_recorder`, `gpx_parser`, `api_client`, `core_models`, and `ui_kit` are all wired and available.

Recommended sequencing: (1) auth flow + local store — without these nothing persists and sync is impossible; (2) background GPS recording wired through `run_recorder` — the highest-visibility Phase 1 gap; (3) file importer for GPX/KML via `gpx_parser`; (4) real run history backed by the local store and sync service; (5) remainder (maps, settings sync, paywall, clubs, training) as follow-on work. Do not attempt a simultaneous full-screen port — the CLAUDE.md explicitly prohibits that approach.

---

## 2. Inventory: what exists on iOS today

### `apps/mobile_ios/lib/`

| File | Status | Notes |
|------|--------|-------|
| `main.dart` | Real | Initialises Supabase, auto-signs in via `DEV_USER_EMAIL`, wires `WatchIngest.attach(api)`. No `LocalRunStore`, `Preferences`, or `SyncService`. |
| `mock_data.dart` | Stub | `MockRun`/`MockRoute` display classes; hardcoded date `DateTime(2026, 4, 8)`. Same pattern as the dead `mock_data.dart` in Android (flagged in `social-training.md` P2-2). |
| `screens/home_screen.dart` | Stub | 4-tab `NavigationBar` (Run, Runs, Routes, Settings). No Dashboard tab, no Clubs tab, no Plans tab. |
| `screens/run_screen.dart` | Stub | Timer + `_distanceMetres += 3.3` simulation. No GPS, no `RunRecorder`, no local save, no audio cues. |
| `screens/runs_screen.dart` | Stub | Shows `mockRuns` from `mock_data.dart`. No `LocalRunStore`, no sort/filter, no detail. |
| `screens/routes_screen.dart` | Stub | Shows `mockRoutes`. FAB snackbar: "Import GPX/KML coming soon". |
| `screens/settings_screen.dart` | Stub | Hardcoded username/email, in-memory `_useKilometres` toggle (not persisted), Strava/parkrun "coming soon" stubs. |

### `apps/mobile_ios/ios/Runner/`

| File | Status | Notes |
|------|--------|-------|
| `AppDelegate.swift` | Real | Activates `WatchIngestBridge.shared` at launch; attaches the method channel when the Flutter engine initialises. |
| `WatchIngestBridge.swift` | Real | Full `WCSessionDelegate` implementation. Receives `WCSessionFile` transfers, reads the gzipped-JSON track, builds the payload, dispatches via `run_app/watch_ingest` method channel. Buffers runs arriving before the channel is attached and re-queues on Dart-side `false` return. This code is production-ready. |
| `SceneDelegate.swift` | Present | Empty boilerplate — no custom scene lifecycle. |

**WatchIngestBridge completeness:** The Swift side is complete. The Dart side (`WatchIngest` class in `main.dart`) is also complete — it deserialises the payload, constructs a `cm.Run`, and calls `api.saveRun(run)`. The one missing layer is that `WatchIngest.attach()` is called only when `api != null`. If the user is not signed in, watch runs are silently dropped. This is documented in the iOS CLAUDE.md ("blocked on Supabase auth landing here first") but means the entire WatchIngest pipeline is gated on auth, which is not yet implemented on this app.

---

## 3. Gap matrix: Android features missing on iOS

### Recording pipeline

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/screens/run_screen.dart` (1800+ lines), `apps/mobile_android/lib/audio_cues.dart`, `apps/mobile_android/lib/run_notification_bridge.dart` |
| **Reusable shared packages** | `packages/run_recorder` (full GPS state machine, filter chain, auto-pause, off-route detection) — already a dependency in iOS `pubspec.yaml`; `packages/core_models` |
| **iOS-specific work required** | (a) `CLLocationManager.allowsBackgroundLocationUpdates = true` + `Info.plist` `NSLocationAlwaysAndWhenInUseUsageDescription` + `UIBackgroundModes: location` instead of Android's foreground service; (b) `BGProcessingTask` registration for the incremental-save heartbeat (or rely on `CLLocationManager` background delivery, which keeps the process alive during a run); (c) `WakelockPlus` may need the iOS entitlement — verify; (d) No `RunNotificationBridge.kt` equivalent needed: on iOS, a `UNMutableNotificationContent` live activity (or a plain local notification update) achieves the lock-screen stat. Live Activities (ActivityKit) would be the right iOS-native approach but is out of scope for MVP — a simple periodic `UNUserNotificationCenter` update at 10s intervals is sufficient. |
| **Rough size** | L (1–2 wks) |

### Local run store + crash recovery

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/local_run_store.dart`, `apps/mobile_android/lib/local_route_store.dart` |
| **Reusable shared packages** | `packages/core_models` (domain types), `packages/api_client` (for sync path). The store itself is Android-app-level code. |
| **iOS-specific work required** | None — `path_provider` + `dart:io` + `dart:convert` work identically on iOS. The Android store can be lifted verbatim (or, better, extracted to a new `packages/local_stores` package per the CLAUDE.md "prefer lifting" rule). |
| **Rough size** | S (1–2 days) to copy; M (3–5 days) if lifted into a shared package |

### Sync service (cloud push/pull + conflict resolution)

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/sync_service.dart`, `apps/mobile_android/lib/background_sync.dart` |
| **Reusable shared packages** | `packages/api_client` (already wired) |
| **iOS-specific work required** | `workmanager` (used on Android for hourly background sync) works on iOS via `BGAppRefreshTask`/`BGProcessingTask`. The pub package supports iOS. Alternatively, use `connectivity_plus` + lifecycle observers (same as Android) for foreground sync without a separate background task. |
| **Rough size** | S (1–2 days) |

### Auth flow + onboarding

| | |
|---|---|
| **Status on iOS** | Partial — `ApiClient.initialize` + `signIn` wired in `main.dart`; no sign-in screen, no onboarding screen, no Apple Sign-In |
| **Source of truth on Android** | `apps/mobile_android/lib/screens/sign_in_screen.dart`, `apps/mobile_android/lib/screens/onboarding_screen.dart` |
| **Reusable shared packages** | `packages/api_client` (email/password, Google ID token path already implemented) |
| **iOS-specific work required** | (a) Apple Sign-In via `sign_in_with_apple` pub package + Supabase `signInWithIdToken(provider: OAuthProvider.apple, idToken: ...)` — this is iOS's primary OAuth path, not Google; (b) `NSLocationWhenInUseUsageDescription` + `NSLocationAlwaysAndWhenInUseUsageDescription` permission strings in `Info.plist` for the onboarding permission request (different from Android's `permission_handler` approach); (c) `AuthorizationStatus` checks use `geolocator` which works on both platforms. |
| **Rough size** | M (3–5 days) including Apple Sign-In wiring |

### GPX/KML/GeoJSON/TCX import

| | |
|---|---|
| **Status on iOS** | Missing (roadmap: "Parse on iOS" — unchecked) |
| **Source of truth on Android** | `apps/mobile_android/lib/screens/import_screen.dart`, `apps/mobile_android/lib/strava_importer.dart` |
| **Reusable shared packages** | `packages/gpx_parser` (already a dependency — `RouteParser.fromGpx`, `fromKml`, `fromGeoJson`, plus `FitParser` for FIT files) — this is an easy win |
| **iOS-specific work required** | `file_picker` (already in iOS `pubspec.yaml`) works on iOS. The import screen itself is largely portable — just wire `gpx_parser` the same way Android does. |
| **Rough size** | S (1–2 days) |

### HealthKit import

| | |
|---|---|
| **Status on iOS** | Missing (roadmap Phase 3 "External platform sync / Apple HealthKit") |
| **Source of truth on Android** | `apps/mobile_android/lib/health_connect_importer.dart` |
| **Reusable shared packages** | `health` pub package (already in iOS `pubspec.yaml` — the same package abstracts HealthKit on iOS and Health Connect on Android) |
| **iOS-specific work required** | (a) `NSHealthShareUsageDescription` in `Info.plist`; (b) HealthKit entitlement in `Runner.entitlements`; (c) The `health` package API is identical — same `getHealthDataFromTypes([HealthDataType.WORKOUT])` call, same filter on `activityType`. The `externalId` prefix should be `healthkit:` not `healthconnect:` |
| **Rough size** | S (1–2 days) |

### Maps and tile cache

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/tile_cache.dart`, `apps/mobile_android/lib/widgets/live_run_map.dart`, `apps/mobile_android/lib/widgets/pace_segments.dart` |
| **Reusable shared packages** | `packages/ui_kit` (`RunMap` widget — already a dependency). `flutter_map` and `flutter_map_maplibre` are in the iOS `pubspec.yaml`. |
| **iOS-specific work required** | `flutter_map_cache` + `dio_cache_interceptor` + `http_cache_file_store` are NOT in the iOS `pubspec.yaml` — they need to be added to enable the disk tile cache. Otherwise `flutter_map` itself and `RunMap` from `ui_kit` run without changes. |
| **Rough size** | XS (tile cache pubspec additions only) for basic map; M (3–5 days) to wire the full live run map with pace heatmap and off-route banner |

### Run history screen (real data)

| | |
|---|---|
| **Status on iOS** | Stub (shows `mockRuns`) |
| **Source of truth on Android** | `apps/mobile_android/lib/screens/runs_screen.dart`, `apps/mobile_android/lib/screens/run_detail_screen.dart`, `apps/mobile_android/lib/screens/add_run_screen.dart` |
| **Reusable shared packages** | `packages/ui_kit` (`RunListTile`, `ElevationChart`, `StatCard`), `packages/core_models` |
| **iOS-specific work required** | None — pure Dart. Requires the local store to be in place first. |
| **Rough size** | M (3–5 days) for runs list + run detail; L for full feature parity including elevation chart, lap splits, share card, bulk-delete |

### Settings persistence

| | |
|---|---|
| **Status on iOS** | Stub — in-memory bool only, no persistence |
| **Source of truth on Android** | `apps/mobile_android/lib/preferences.dart`, `apps/mobile_android/lib/settings_sync.dart` |
| **Reusable shared packages** | None (Preferences wraps `shared_preferences` which works on iOS) |
| **iOS-specific work required** | `shared_preferences` is not in the iOS `pubspec.yaml` — add it. `Preferences` class itself is portable verbatim. |
| **Rough size** | XS |

### Dashboard screen

| | |
|---|---|
| **Status on iOS** | Missing (there is no dashboard tab in `home_screen.dart`) |
| **Source of truth on Android** | `apps/mobile_android/lib/screens/dashboard_screen.dart` |
| **Reusable shared packages** | `packages/api_client` (weekly_mileage + personal_records RPCs), `packages/core_models` |
| **iOS-specific work required** | None. Requires local store and sync in place first. |
| **Rough size** | M (3–5 days) |

### Preferences sync (settings roaming)

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/settings_sync.dart`, `packages/api_client/lib/src/settings_service.dart` |
| **Reusable shared packages** | `packages/api_client` exposes `SettingsService` — already a dependency |
| **iOS-specific work required** | None — `SettingsSyncService` is portable once `Preferences` exists. |
| **Rough size** | XS (assuming Preferences is already ported) |

### Audio cues (TTS splits and pace alerts)

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/audio_cues.dart` |
| **Reusable shared packages** | None (wraps `flutter_tts`) |
| **iOS-specific work required** | `flutter_tts` is not in the iOS `pubspec.yaml` — add it. The `flutter_tts` package supports iOS natively. The `AudioCues` class itself is portable. |
| **Rough size** | XS (pubspec + copy) |

### BLE heart-rate monitor

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/ble_heart_rate.dart` |
| **Reusable shared packages** | None (wraps `flutter_blue_plus`) |
| **iOS-specific work required** | `NSBluetoothAlwaysUsageDescription` in `Info.plist`; `flutter_blue_plus` is not in iOS `pubspec.yaml`. The class itself is portable. |
| **Rough size** | S (1–2 days including the Info.plist setup and testing on a real device) |

### Pedometer (step count + cadence)

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | Wired in `apps/mobile_android/lib/screens/run_screen.dart` via `pedometer` package |
| **Reusable shared packages** | None |
| **iOS-specific work required** | `pedometer` package supports iOS via `CMPedometer`. `NSMotionUsageDescription` needed in `Info.plist`. |
| **Rough size** | XS |

### Social layer (clubs, events)

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/social_service.dart`, `apps/mobile_android/lib/screens/clubs_screen.dart`, `club_detail_screen.dart`, `event_detail_screen.dart` |
| **Reusable shared packages** | `packages/api_client` |
| **iOS-specific work required** | None — pure Dart. APNs push notifications for club events (Phase 4b) would require iOS-specific setup, but that's deferred. |
| **Rough size** | L (1–2 wks) |

### Training plans

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/training_service.dart`, `apps/mobile_android/lib/training.dart`, screens: `plans_screen.dart`, `plan_detail_screen.dart`, `plan_new_screen.dart`, `workout_detail_screen.dart` |
| **Reusable shared packages** | `packages/api_client` |
| **iOS-specific work required** | None — pure Dart. |
| **Rough size** | L (1–2 wks) |

### Explore routes (public route discovery)

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/screens/explore_routes_screen.dart` |
| **Reusable shared packages** | `packages/api_client`, `packages/ui_kit` |
| **iOS-specific work required** | None. `geolocator` (already in iOS pubspec) handles the "near me" geolocation. |
| **Rough size** | M (3–5 days) |

### Backup / restore

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/backup.dart` |
| **Reusable shared packages** | `packages/core_models`, `packages/api_client` |
| **iOS-specific work required** | `share_plus` is not in iOS `pubspec.yaml` — add it. `archive` package (for zip) is not listed either — add it. Logic is fully portable. |
| **Rough size** | S (1–2 days) |

### Period summary screen

| | |
|---|---|
| **Status on iOS** | Missing |
| **Source of truth on Android** | `apps/mobile_android/lib/screens/period_summary_screen.dart` |
| **Reusable shared packages** | `packages/core_models` |
| **iOS-specific work required** | None. `share_plus` needed (see Backup entry). |
| **Rough size** | M (3–5 days) |

---

## 4. Prioritised backlog

### HIGH

**H1. Local run store + crash recovery**
- **Why**: Every other iOS feature depends on runs persisting. Without it, the recording screen cannot save a run, the history screen cannot show real data, and sync has nothing to push.
- **Acceptance criteria**: `lib/local_run_store.dart` and `lib/local_route_store.dart` copied from Android (or extracted to `packages/local_stores` — see non-goals) and wired into `main.dart`. Startup reads from disk; `_inProgress.json` crash recovery runs on launch. `flutter test` passes on a `local_run_store_test.dart` port. No `LocalRunStore` call in `main.dart` is left uninitialised.
- **Roadmap**: no single checkbox, but gates all recording + history checkboxes.
- **Reference**: `apps/mobile_android/lib/local_run_store.dart`, `apps/mobile_android/test/local_run_store_test.dart`

---

**H2. Auth flow + onboarding screen (with Apple Sign-In)**
- **Why**: Currently watch runs are silently dropped when the user is not signed in (the `WatchIngest.attach(api)` call in `main.dart` is guarded by `api != null`, and `api` is only constructed after a successful Supabase init + auth). Auth is also a prerequisite for sync.
- **Acceptance criteria**: `lib/screens/sign_in_screen.dart` and `lib/screens/onboarding_screen.dart` exist and are wired through `main.dart`. Email/password sign-in works against the local Supabase (seed user `runner@test.com`/`testtest`). Apple Sign-In button present (can be hidden behind a compile flag if credentials aren't available). Location permission request runs during onboarding. `Preferences.onboarded` persists across restarts. `roadmap.md` Phase 1 "Google and Apple OAuth scaffolded" iOS checkbox ticked (Apple path only — Google is explicitly deferred per Android CLAUDE.md).
- **Reference**: `apps/mobile_android/lib/screens/sign_in_screen.dart:1–100`, `apps/mobile_android/lib/screens/onboarding_screen.dart`

---

**H3. Background GPS recording wired through `run_recorder`**
- **Why**: The single most visible Phase 1 iOS gap. The run screen is currently a timer simulation with no GPS.
- **Acceptance criteria**: `lib/screens/run_screen.dart` wires `RunRecorder` from `packages/run_recorder`. The screen mirrors the Android state machine (idle → countdown → recording → paused → finished). GPS positions are accumulated into the track. The run is saved locally via `LocalRunStore` on stop. Background location continues while the screen is backgrounded (iOS foreground delivery via `CLLocationManager` background mode — no separate `BGProcessingTask` needed for the recording path itself). `Info.plist` contains `NSLocationAlwaysAndWhenInUseUsageDescription` and `UIBackgroundModes: [location]`. `roadmap.md` "Background location tracking (iOS)" checkbox ticked.
- **Reference**: `apps/mobile_android/lib/screens/run_screen.dart:1–200` (state machine skeleton), `packages/run_recorder/lib/src/run_recorder.dart`

---

**H4. GPX/KML/GeoJSON/TCX import via `gpx_parser`**
- **Why**: The roadmap has an explicit unchecked "Parse on iOS" checkbox. `gpx_parser` is already in the iOS `pubspec.yaml` — this is the highest-value easy win.
- **Acceptance criteria**: `lib/screens/import_screen.dart` exists, wires `file_picker` to `RouteParser.fromGpx`/`fromKml`/`fromGeoJson` and `FitParser` (for Strava ZIP TCX/FIT), saves parsed routes to `LocalRouteStore`, shows the route on `RunMap` from `ui_kit` before the user confirms. `roadmap.md` "Parse on iOS" checkbox ticked.
- **Reference**: `apps/mobile_android/lib/screens/import_screen.dart`, `packages/gpx_parser/lib/src/route_parser.dart`

---

**H5. Preferences persistence (`shared_preferences` wrapper)**
- **Why**: The settings screen currently silently discards changes on restart. Every downstream feature (units, audio cues, split interval, advanced GPS) reads from `Preferences`. The `WatchIngest` auth guard also reads `Preferences.onboarded`.
- **Acceptance criteria**: `lib/preferences.dart` ported from Android (or a minimal subset covering `onboarded`, `preferredUnit`, `audioCues`). `shared_preferences` added to `pubspec.yaml`. `SettingsScreen` unit toggle persists across cold restarts.
- **Roadmap**: none explicitly, but it unblocks H2, H3.
- **Reference**: `apps/mobile_android/lib/preferences.dart:1–80`

---

### MEDIUM

**M1. Real run history + sync service**
- **Why**: Meaningful to the user only after H1 (local store) and H2 (auth) are done. Ports two Android features in one pass.
- **Acceptance criteria**: `lib/sync_service.dart` ported (pull from Supabase + merge via `last_modified_at`). `RunsScreen` reads from `LocalRunStore` instead of `mockRuns`. Auto-sync fires on `connectivity_plus` connectivity change and app foreground via `WidgetsBindingObserver`. Unsynced count badge shows on the Runs tab. `roadmap.md` Phase 1 iOS sync checkboxes ticked.
- **Reference**: `apps/mobile_android/lib/sync_service.dart`, `apps/mobile_android/lib/screens/runs_screen.dart`

---

**M2. Run detail screen**
- **Why**: High user value; backed by `ui_kit` widgets (`ElevationChart`, `StatCard`, `RunMap`) that eliminate most of the implementation work.
- **Acceptance criteria**: `lib/screens/run_detail_screen.dart` exists. Shows the GPS trace on `RunMap`, key stats, elevation chart from `ui_kit`, pace splits. Share run as GPX via `share_plus`. Delete run. Edit title/notes.
- **Reference**: `apps/mobile_android/lib/screens/run_detail_screen.dart:1–200` (map + stats scaffold), `packages/ui_kit/lib/src/widgets/`

---

**M3. Dashboard screen**
- **Why**: The Android home screen's first tab is the dashboard (weekly mileage, personal bests, goal cards) — iOS has no equivalent tab. It's the "is this app worth using" first impression.
- **Acceptance criteria**: Dashboard tab added to `home_screen.dart` (making it a 5-tab nav: Run / Runs / Routes / Dashboard / Settings). Shows weekly distance and run count from `api_client.weeklyMileage()`. Shows personal bests from `api_client.personalRecords()`. Goal card visible if `Preferences.goals` is non-empty.
- **Reference**: `apps/mobile_android/lib/screens/dashboard_screen.dart`

---

**M4. Audio cues (TTS)**
- **Why**: Listed in "Live and working" on Android; entirely absent on iOS. `flutter_tts` is cross-platform with minimal setup.
- **Acceptance criteria**: `lib/audio_cues.dart` ported. `flutter_tts` added to `pubspec.yaml`. Audio cues fire on split completion and pace alerts during a run, wrapped in try/catch per the layered-resilience contract. The P0 bug from the Android recording audit (`announceFinish` and `announceStart` must be in try/catch so a TTS failure cannot abort `LocalRunStore.save`) must NOT be replicated — wire the iOS version correctly from the start.
- **Reference**: `apps/mobile_android/lib/audio_cues.dart` — but see also `reviews/mobile-android/recording.md` P0 findings before copy-pasting the Android implementation.

---

**M5. HealthKit import**
- **Why**: iOS's equivalent of Android's Health Connect import. The `health` pub package is already in the iOS `pubspec.yaml` and abstracts both platforms behind the same Dart API. This is a low-effort, high-value parity item.
- **Acceptance criteria**: `lib/health_kit_importer.dart` (renamed from `health_connect_importer.dart`) uses `health.getHealthDataFromTypes([HealthDataType.WORKOUT])`. `externalId` is prefixed with `healthkit:` (not `healthconnect:`). `NSHealthShareUsageDescription` in `Info.plist`. Import screen's "Import from HealthKit" option visible on iOS. Deduplication tested: re-running the import does not create duplicate rows.
- **Reference**: `apps/mobile_android/lib/health_connect_importer.dart` — but change the `externalId` prefix (the Android version has the prefix bug flagged in `data-sync.md` P0.1; fix it correctly on iOS).

---

**M6. Live run map with route overlay**
- **Why**: Without a map, the run screen is just numbers. `flutter_map` + `RunMap` from `ui_kit` are already declared dependencies.
- **Acceptance criteria**: The live run map renders the GPS track as it's recorded. Route overlay appears when a saved route is selected before starting. Off-route banner shows when the runner is >40m from the route line (same threshold as Android). `flutter_map_cache` + `dio_cache_interceptor` + `http_cache_file_store` added to `pubspec.yaml` for disk tile cache.
- **Reference**: `apps/mobile_android/lib/widgets/live_run_map.dart`, `apps/mobile_android/lib/tile_cache.dart`

---

### LOW

**L1. Strava ZIP import**
- **Why**: Android has this, iOS has the `gpx_parser` package which already handles GPX, TCX, and FIT. The main effort is the ZIP-reading logic.
- **Acceptance criteria**: Import screen's "Import from Strava" option wires `archive` package to extract the ZIP, then `RouteParser`/`FitParser` on each contained file. `externalId` prefixed with `strava:`. `archive` added to `pubspec.yaml`.
- **Reference**: `apps/mobile_android/lib/strava_importer.dart`

---

**L2. Social layer (clubs + events)**
- **Why**: This is Phase 3 on Android; low priority for iOS MVP. It's pure Dart code — no iOS-specific platform work — but it's a large surface (5 screens + `social_service.dart` + `recurrence.dart`).
- **Acceptance criteria**: When landed: `social_service.dart`, `recurrence.dart`, and the 5 social screens ported. Clubs added as a 6th bottom-nav tab. The UTC-hour bug in `recurrence.dart` (flagged in `social-training.md` P0-1) must NOT be replicated — use `e.startsAt.toLocal().hour` when building stamped instance dates.
- **Reference**: `apps/mobile_android/lib/social_service.dart`, `apps/mobile_android/lib/recurrence.dart` (read the `social-training.md` P0-1 finding before porting)

---

**L3. Training plans**
- **Why**: Phase 3 feature; not required for iOS MVP. No iOS-specific work.
- **Acceptance criteria**: `training_service.dart`, `training.dart`, and the 4 plan screens ported. `preferred_unit` is respected in all pace/distance displays (the unit-ignorance bug in `social-training.md` P1-4 must not be replicated). Inject `Preferences` at construction time.
- **Reference**: `apps/mobile_android/lib/training_service.dart`, `apps/mobile_android/lib/training.dart`

---

**L4. BLE heart-rate monitor**
- **Why**: Non-critical for recording; requires a physical device to test; needs Bluetooth entitlement review.
- **Acceptance criteria**: `lib/ble_heart_rate.dart` ported. `flutter_blue_plus` added to `pubspec.yaml`. `NSBluetoothAlwaysUsageDescription` in `Info.plist`. The Android bugs from `reviews/mobile-android/recording.md` P1 (`_discard()` missing `_hrSub?.cancel()`, no `onError` handler on the GATT stream) must be fixed in the iOS port, not reproduced.
- **Reference**: `apps/mobile_android/lib/ble_heart_rate.dart`

---

**L5. Explore routes (public route discovery)**
- **Why**: Phase 3 feature; requires PostGIS in the backend (Phase 3 backend work).
- **Acceptance criteria**: `lib/screens/explore_routes_screen.dart` ported. `geolocator` (already in `pubspec.yaml`) handles the "near me" geolocation query.
- **Reference**: `apps/mobile_android/lib/screens/explore_routes_screen.dart`

---

## 5. Explicit non-goals / "do not attempt" list

1. **Do not mirror Android file-by-file in one pass.** The iOS CLAUDE.md states this explicitly. Porting 30+ files in a single PR produces a diff too large to review and merges undiscovered Android bugs into iOS. Work in the sequence defined by this backlog.

2. **Do not duplicate code that belongs in a shared package.** Before copying `local_run_store.dart` and `local_route_store.dart` into `apps/mobile_ios/lib/`, evaluate extracting them to `packages/local_stores`. Two divergent copies of store logic is the drift problem the parity-enforcement initiative exists to prevent. Ask the user before deciding which path to take — the CLAUDE.md says "the team may prefer copy-then-converge."

3. **Do not use `WearAuthBridge`.** That is Android-only (it writes to the Wearable Data Layer via a native Kotlin bridge). The iOS equivalent for sharing auth state with the Apple Watch is out of scope — the Watch app records independently and syncs runs via `WatchIngestBridge`, which is already implemented.

4. **Do not add a Google Sign-In button on iOS.** The iOS CLAUDE.md specifies: "Google Sign-In flow → replaced by Apple Sign-In." `google_sign_in` is not in the iOS `pubspec.yaml` and should not be added. Apple Sign-In is required by App Store guidelines for any app that offers third-party login.

5. **Do not implement WorkManager for background sync.** Android uses `workmanager` with a Kotlin WorkManager backend. On iOS, use `BGAppRefreshTask` (via the `workmanager` pub package's iOS implementation, or via `connectivity_plus` + `WidgetsBindingObserver` for foreground-only sync as an acceptable MVP shortcut). Do not add `WorkManager`-specific platform code.

6. **Do not add a `RunNotificationBridge` native Swift file mirroring `RunNotificationBridge.kt`.** The Android bridge reposts on the same geolocator foreground-service notification channel. iOS has no foreground service. For MVP, a periodic `UNUserNotificationCenter` update is sufficient. Live Activities (ActivityKit, iOS 16.2+) is the correct long-term path but is not a Phase 1 requirement.

7. **Do not port `wear_auth_bridge.dart`.** iOS has no Wear Data Layer equivalent. The `WatchIngestBridge` (already implemented) is the complete iOS watch integration.

8. **Do not replicate Android bugs.** The four Android audit docs identify concrete bugs. When porting a file that contains a known bug, fix it on arrival: the UTC-hour recurrence bug (social-training P0-1), the `external_id` prefix bug (data-sync P0.1), the TTS try/catch gaps (recording P0), and the `_discard()` BLE subscription leak (recording P1).

---

## 6. Open questions for the user

**Q1: Extract `LocalRunStore`/`LocalRouteStore` to a shared package or copy-then-converge?**
The iOS CLAUDE.md says "the team may prefer copy-then-converge" but strongly recommends lifting shared code into packages. Lifting into `packages/local_stores` is 1–2 extra days but prevents two divergent store implementations. Decision needed before H1 is picked up.

**Q2: Apple Sign-In credentials availability.**
H2 (auth flow) includes Apple Sign-In. Apple requires an Apple Developer account and a Services ID configured in the Apple Developer portal. Are credentials already set up, or should Apple Sign-In be scaffolded but gated behind a flag for now?

**Q3: Background location scope for MVP.**
iOS background location keeps the process alive during an active `CLLocationManager` session. For a run that is minimised but not stopped, this works without `BGProcessingTask`. However, the App Store review team scrutinises background location usage. Should the MVP ship with `NSLocationAlwaysAndWhenInUseUsageDescription` (required for background) or start with `whenInUse` only (which stops GPS when the app is backgrounded)? The latter reduces App Store review friction but breaks recording if the user receives a call.

**Q4: WatchIngest drop-on-no-auth hardening.**
Currently watch runs arriving when the user is not signed in are silently dropped after `WatchIngest.attach` is skipped. Should unauthed watch runs be queued locally (to `LocalRunStore`) and synced when the user signs in, or is the current behaviour (drop) acceptable for MVP?

**Q5: Should the iOS paywall use StoreKit directly or RevenueCat?**
Android uses RevenueCat (configured per `docs/paywall.md`). RevenueCat supports iOS. However, since the paywall is currently disabled (`isLocked()` returns `false`), this is not a blocking question for Phase 1 — but the answer affects whether `purchases_flutter` (RevenueCat's pub package) needs to be added to the iOS `pubspec.yaml`.
