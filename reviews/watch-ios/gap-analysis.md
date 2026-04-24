# Review: apps/watch_ios/WatchApp/ — Phase 2 gap analysis

## Scope
- Files reviewed: 8 Swift source files (`RunApp.swift`, `ContentView.swift`, `WorkoutManager.swift`, `LocationManager.swift`, `WatchConnectivityManager.swift`, `HealthKitManager.swift`, `RouteNavigator.swift`, `SupabaseService.swift`), plus `Info.plist`, `WatchApp.entitlements`; `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift`; `apps/mobile_ios/lib/main.dart`; `docs/roadmap.md` Phase 2 section; `apps/watch_wear/CLAUDE.md`; `reviews/data-sync-audit/watches.md`; `packages/core_models/lib/src/run_source.dart` + `run.g.dart`
- Focus: feature parity with Phase 2 roadmap checkboxes and `apps/watch_wear/`, plus phone-watch integration correctness
- Reviewer confidence: high — every file in scope read in full; cross-referenced against Dart core_models, api_client, and the prior data-sync-audit

---

## 1. Executive summary

`watch_ios` has a functional skeleton: GPS recording starts and stops, heart rate comes from `HKWorkoutSession`, and `WCSession.transferFile` is wired on the watch side. Of the eight Phase 2 watchOS checkboxes, one is genuinely done (`[x] Heart rate via HealthKit sensor`), one was already noted fixed in the data-sync-audit (`source = 'watch'` — confirmed in the current code), and six remain unimplemented. The phone-side receiver (`WatchIngestBridge.swift` + `WatchIngest` in `main.dart`) is structurally complete but has two blockers that prevent any run from reaching Supabase in production: the iOS app has no sign-in UI, and `RunSource.watch` is missing from the generated Dart enum map, causing a guaranteed runtime crash when `api.saveRun` serialises a watch-originated `Run` via `Run.toJson()`.

Compared to `watch_wear`, the watchOS app lacks: a foreground service / `WKExtendedRuntimeSession` for background recording resilience, pause/resume, crash checkpoint recovery, a standalone auth path, network-triggered queue drain, battery warning, and all three route-navigation features. Live race mode is out of scope for watchOS Phase 2. The recommended sequence is: fix the two crash-level blockers first (they gate everything else), then standalone workout / background resilience, then haptic pace alerts, then route preview and mini-map.

---

## 2. Inventory: what exists on watchOS today

| File | What it does | Wired into app flow | Real vs stubbed |
|---|---|---|---|
| `RunApp.swift` | `@main` entry, renders `ContentView` | Yes | Real — 10 lines |
| `ContentView.swift` | State-routing root (`idle / recording / finished`), `PreRunView`, `RunningView`, `PostRunView`, `syncRun()` calling `WatchConnectivityManager.transferRun` | Yes | Real — WCSession transfer path wired; DEBUG direct-sync path also wired |
| `WorkoutManager.swift` | Owns `CLLocationManager`, 1s `Timer`, GPS filter (2–100 m gate, 30 m accuracy), distance accumulation, pace rolling window (~200 m lookback), `HKWorkoutSession` start/stop delegation, `writeTrackJSON()` | Yes | Real and functional; background recording relies on `HKWorkoutSession` contract but does NOT call `allowsBackgroundLocationUpdates = true` (see H1) |
| `LocationManager.swift` | Second `CLLocationManager` wrapper with its own `startTracking` / `stopTracking` | **Not wired** — never instantiated anywhere in the app | Dead code — `WorkoutManager` has its own embedded CLLocationManager |
| `WatchConnectivityManager.swift` | `WCSession.default.transferFile`, `didFinish` callback, queued count tracking | Yes — called from `ContentView.syncRun()` | Real and correct. `queuedCount` tracks outbox accurately |
| `HealthKitManager.swift` | `HKWorkoutSession` + `HKLiveWorkoutBuilder`, `currentBPM`, `averageBPM` with 30–230 clamp | Yes — wired in `WorkoutManager.start()` and displayed in `RunningView` | Real; clamp is present at line 101 (data-sync-audit finding HR_NO_CLAMP has been fixed in current code) |
| `RouteNavigator.swift` | Shell class with `isOffRoute`, `deviationMetres`, `remainingMetres` properties; `update(currentLocation:)` method body is four `// TODO` comments | **Not wired** — never instantiated anywhere | Stub — zero logic implemented |
| `SupabaseService.swift` | Full REST client for DEBUG path: sign-in, gzip, Storage upload, row insert | Yes, wrapped in `#if DEBUG`; accessible via "DEBUG: Sync Direct" button | Real and functional for dev/simulator use only; correctly excluded from Release |
| `AppTheme.swift` | Color palette constants | Yes | Real |

---

## 3. Phase 2 checkbox status — ground truth

| Checkbox | Roadmap state | Actual state | Gap to close |
|---|---|---|---|
| Standalone workout session (no phone required) | Unchecked | **Missing.** The app requires a phone for sync (by design), but "standalone" here means the recording itself must survive without the phone present — specifically, background GPS during a run must not depend on the phone being reachable. Current code does NOT set `allowsBackgroundLocationUpdates = true` on the CLLocationManager, and uses a main-thread `Timer` for elapsed time. When the watch face sleeps, the Timer fires are suppressed, and if the `HKWorkoutSession` is not in `.running` state CLLocation updates also pause. No `WKExtendedRuntimeSession` fallback. There is no checkpoint recovery if the process is killed mid-run. | H1 + M1 |
| Heart rate via HealthKit sensor | **Checked** in roadmap | Confirmed real: `HealthKitManager.swift` wires `HKLiveWorkoutBuilder`, live BPM displayed in `RunningView`, `avg_bpm` forwarded in metadata dict. 30–230 BPM clamp present at line 101. | None |
| Haptic pace alerts (above / below target) | Unchecked | **Missing.** No pace-target concept exists anywhere in the codebase. `WKInterfaceDevice.current().play(_:)` is not called anywhere. `RouteNavigator.update` has a `// TODO: Trigger haptic if off-route` comment but no implementation. | M2 |
| Syncs run data via Watch Connectivity framework | Unchecked | **Partially built — blocked on Dart enum codegen bug.** The watch side is wired: `WatchConnectivityManager.transferRun` calls `WCSession.default.transferFile`. The phone side (`WatchIngestBridge.swift` + `WatchIngest` in `main.dart`) is structurally complete. But two bugs block production use: (a) `RunSource.watch` is missing from the generated `_$RunSourceEnumMap` in `run.g.dart`, causing a nil-force-unwrap crash when `api.saveRun` serialises the run; (b) `mobile_ios` has no sign-in UI, so `api` is unauthenticated in production and `saveRun` throws "Not authenticated". | H2 + H3 |
| Route preview on watch face before starting | Unchecked | **Missing.** `RouteNavigator` exists but has no data and is never instantiated. `WatchConnectivityManager.didReceiveMessage` is an empty stub. No route-loading flow exists. | M3 |
| Live position on mini-map during run | Unchecked | **Missing.** `RunningView` shows distance, pace, HR, GPS point count — no map. watchOS has `WKInterfaceMap` (WatchKit, deprecated since watchOS 7) and SwiftUI has no native map widget on watchOS; the canonical approach is a rendered `UIImage` / `CGImage` of the route overlay. | M4 |
| Off-route haptic + "recalculating" indicator | Unchecked | **Missing.** `RouteNavigator.update` has the right properties (`isOffRoute`, `deviationMetres`) but zero logic and no haptic call. | L1 (depends on M3) |
| watchOS complication: pace + distance | Unchecked | **Missing.** No `WidgetKit` extension, no `CLKComplication` entry point, no `WKApplication.requestLocation` flow. Requires a separate Xcode target. | L2 |

---

## 4. Gap matrix: Wear OS features missing on watchOS

| Capability | watchOS status | Wear OS source | watchOS-equivalent API | Rough size |
|---|---|---|---|---|
| Background recording resilience (foreground service / wake lock) | **Partial** — `HKWorkoutSession` holds background location while active, but no `WKExtendedRuntimeSession` fallback, no crash checkpoint, elapsed timer stops when background | `recording/RunRecordingService.kt` + `recording/CheckpointStore.kt` | `WKExtendedRuntimeSession` (for non-workout background time), `HKWorkoutSession` contract (already used), DataStore checkpoint → UserDefaults snapshot | M |
| Pause / resume | **Missing** | `RunViewModel.pause()` / `resume()`, `Stage.Paused` | `HKWorkoutSession.pause()` / `resume()`, matching `CLLocationManager` stop/start | S |
| Crash checkpoint recovery | **Missing** | `recording/CheckpointStore.kt` — DataStore snapshot every 15s; next launch shows "Recover unsaved run?" prompt | `UserDefaults` or on-disk checkpoint every N points in `WorkoutManager`; `ContentView` checks on `.task` | M |
| Standalone auth (no phone required) | **Missing** — DEBUG uses seed creds; Release has no auth path at all on watch | `Stage.SignIn`, `SupabaseClient.signIn`, `SessionStore` | N/A by design (decisions §14 — watch never holds credentials in Release). Standalone is defined as "runs without phone present" not "syncs without phone". No gap to close here except ensuring WCSession queuing works correctly. | None |
| Network-triggered queue drain | **Missing** — WCSession handles its own retry, but queued-run display (`queuedCount`) doesn't reflect post-phone-arrival drain | `system/NetworkWatcher.kt` → `drainQueue()` on connectivity change | `NWPathMonitor` → re-trigger `WCSession.transferFile` if activationState != activated, or surface WCSession's own outbox count more accurately | S |
| Battery warning before run | **Missing** | `system/BatteryStatus.kt` — warns below 40% | `WKInterfaceDevice.current().batteryLevel`, enable monitoring with `WKInterfaceDevice.current().isBatteryMonitoringEnabled = true` | XS |
| Route preview (pre-run map) | **Missing** | Wear OS also missing per roadmap; no `RouteNavigator` logic in either | Phone pushes route points via `WCSession.updateApplicationContext`; watch renders via SwiftUI canvas or pre-rendered image | M |
| Live mini-map during run | **Missing** | Wear OS also missing per roadmap | SwiftUI `Canvas` drawing the route polyline + current-position dot as a `CGPoint` overlay; update on each CLLocation callback | M |
| Off-route haptic | **Missing** | `RouteNavigator.swift` has TODO | `WKInterfaceDevice.current().play(.failure)` when deviation > threshold | XS (once route data exists) |
| Live race mode (server-authoritative ARM/GO/END) | **Missing** | `RaceSessionClient.kt`, `ActiveRaceState`, WebSocket to Go service | WebSocket via `URLSessionWebSocketTask`; Go service dependency | L (blocked on Go service — out of Phase 2 scope) |
| Ultra-length streaming track writer | **Not needed yet** — GPS track held in memory as `[CLLocation]` in `WorkoutManager.track` | `recording/TrackWriter.kt` — streams to disk every 32 points | Write `TrackPoint` structs to a JSON file incrementally; seal on `stop()` | M (at marathon+ scale) |
| Wear OS tile / complication | **Missing** (both platforms) | Not started on either | WidgetKit `AppIntentTimelineProvider` for watchOS | L |

---

## 5. Phone-watch integration check

### Watch side — `WCSession.transferFile`

**Does the watch call `WCSession.transferFile` on run finish?**

Yes. `ContentView.syncRun()` calls `workoutManager.writeTrackJSON()` which writes `{run.id}.json` to the Caches directory, then calls `connectivity.transferRun(fileURL:metadata:)` which calls `WCSession.default.transferFile(_:metadata:)`. This is manually triggered by the "Sync Run" button — there is no automatic trigger on run finish. The user must tap the button before navigating away. `startNextRun()` (called by "Discard" and "Start next run") calls `workoutManager.reset()` which clears `finishedRun` — if the user taps "Discard" without syncing first, the run data is gone.

**Metadata dict sent:**

```
{ "id": String, "started_at": ISO8601 String, "duration_s": Int, "distance_m": Double,
  "source": "watch", "avg_bpm": Double? }
```

`activity_type` is NOT sent (confirmed by inspecting `ContentView.syncRun()` lines 47–53). The data-sync-audit LOW finding `WATCHIOS_NO_ACTIVITY_TYPE` remains open.

### Phone side — `WatchIngestBridge.swift` + `WatchIngest` in `main.dart`

**Is the receiver complete?**

Structurally yes. `WatchIngestBridge.swift` implements `session(_:didReceive file:)`, reads the file contents, assembles a payload dict, and calls the `run_app/watch_ingest` method channel. `main.dart` `WatchIngest.attach(api)` subscribes and calls `api.saveRun(run)`.

**CLAUDE.md in `mobile_ios` is stale**: it says "the phone-side receiver is a TODO, blocked on Supabase auth landing here first." The receiver is built and wired. The auth gap is real but is now an implicit pre-condition, not a missing file.

**Two blockers prevent production use:**

1. `mobile_ios` has no sign-in UI (`home_screen.dart` is a nav shell with no auth flow). `main.dart` attaches `WatchIngest` only when `api != null` (i.e. Supabase URL/key configured), but production users cannot sign in. When `api.saveRun` throws "Not authenticated", `WatchIngest` returns `false` to the method channel, `WatchIngestBridge` re-queues the payload in `pending`, but `pending` is an in-process array — it is lost on app restart. Watch-originated runs that arrive at an unauthenticated phone are silently dropped on app restart.

2. **`RunSource.watch` is absent from the generated `_$RunSourceEnumMap` in `packages/core_models/lib/src/run.g.dart`.** The source enum in `run_source.dart` includes `watch` (line 3), but `run.g.dart` (generated, not manually edited) omits it from `_$RunSourceEnumMap`. `api_client.saveRun` at line 99 uses `run.source.name` directly (bypassing the map), so the Supabase row insert itself works. However, if `Run.toJson()` is ever called on a `RunSource.watch` run — e.g. in the backup export flow or JSON debug output — Swift's force-unwrap at `_$RunSourceEnumMap[instance.source]!` will crash at runtime because the map returns `nil`. The fix is `dart run build_runner build` in `packages/core_models`, which regenerates `run.g.dart` with the `watch` entry.

**Metadata contract match:**

| Field | Watch sends | Bridge extracts | Dart handles |
|---|---|---|---|
| `id` | Yes | Yes (line 55) | Yes |
| `started_at` | Yes | Yes (line 55) | Yes — `DateTime.parse` |
| `duration_s` | Yes | Yes (line 58) | Yes |
| `distance_m` | Yes | Yes (line 59) | Yes |
| `source` | `"watch"` | Yes (line 55) | `_parseSource` finds `RunSource.watch` via `.values` iteration — works |
| `avg_bpm` | Yes (optional) | Yes (line 60) | Yes |
| `activity_type` | **Not sent** | Extracted if present (line 55) | Handled conditionally — no crash, just absent from metadata |
| `track` (file) | Raw JSON file | File contents read as UTF-8 string (line 67) | Decoded via `jsonDecode(trackRaw)` — correct |

The contract is coherent. The missing `activity_type` is a LOW issue already documented.

---

## 6. Prioritised backlog

### HIGH

**H1. Background GPS recording drops when watch face sleeps**

- **Why HIGH:** A user who turns their wrist down mid-run will silently stop accumulating distance and GPS track points. This is a data-loss bug on any run longer than ~2 minutes.
- **Root cause:** `WorkoutManager` does not call `locationManager.allowsBackgroundLocationUpdates = true`. On watchOS, `CLLocationManager.startUpdatingLocation()` continues during an active `HKWorkoutSession` — but only if the location manager is configured for background delivery. Without it, iOS throttles location updates when the face is off. The 1-second `Timer` is also not background-safe, but elapsed time is computed from `startDate` so that's cosmetic only.
- **Files to touch:** `apps/watch_ios/WatchApp/WorkoutManager.swift` — add `locationManager.allowsBackgroundLocationUpdates = true` in `init()` (after setting delegate and accuracy). `Info.plist` already declares `WKBackgroundModes: [location, workout-processing]` — no plist change needed. `WatchApp.entitlements` already has `com.apple.developer.healthkit`.
- **Acceptance criteria:**
  - `locationManager.allowsBackgroundLocationUpdates = true` set in `WorkoutManager.init()`.
  - Simulator test: start a run, lock the watch face (click Digital Crown), wait 60 seconds, unlock — GPS track must have continued accumulating points.
  - `xcodebuild -project apps/watch_ios/WatchApp.xcodeproj -scheme WatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 9' build` passes zero errors.
  - Tick `[ ] Standalone workout session` in `docs/roadmap.md` Phase 2 once verified on device (this is a prerequisite, not the full checkbox — see H4 for checkpoint).
- **Wear OS reference:** `GpsRecorder.kt` — `FusedLocationProviderClient` with `RunRecordingService` foreground service holds the Android equivalent.
- **Size:** XS (one line + verification)
- **Risk if applied:** None. This is a missing required call, not a behavior change to existing logic.

---

**H2. `RunSource.watch` missing from generated Dart enum map — runtime crash on backup/export**

- **Why HIGH:** `packages/core_models/lib/src/run.g.dart` `_$RunSourceEnumMap` omits `RunSource.watch`. The force-unwrap `_$RunSourceEnumMap[instance.source]!` at line 35 of `run.g.dart` crashes at runtime on any call to `Run.toJson()` for a watch-source run. `api.saveRun` uses `run.source.name` directly and is not immediately affected, but the backup export flow (`saveRunsBatch`, any JSON serialisation of a `Run` object) will crash.
- **Files to touch:** Run `dart run build_runner build --delete-conflicting-outputs` in `packages/core_models/`. Do not manually edit `run.g.dart`. Commit the regenerated file.
- **Acceptance criteria:**
  - `run.g.dart` contains `RunSource.watch: 'watch'` in `_$RunSourceEnumMap`.
  - `dart analyze packages/core_models` exits clean (no errors or warnings).
  - `dart test packages/core_models` passes (if tests exist; create one if not: construct a `Run` with `source: RunSource.watch`, call `.toJson()`, assert `json['source'] == 'watch'`).
- **Wear OS reference:** N/A — Kotlin-side uses `RunRow.COL_SOURCE to "watch"` directly.
- **Size:** XS
- **Risk if applied:** None — additive enum map entry.

---

**H3. `mobile_ios` has no sign-in UI — watch-run queue silently lost on app restart**

- **Why HIGH:** In production, `api` in `main.dart` is non-null (Supabase URL/key configured) but the user is unauthenticated. `api.saveRun` throws "Not authenticated". `WatchIngest` returns `false` to the method channel, `WatchIngestBridge` appends to `pending`, but `pending` is discarded on process exit. The run is permanently lost.
- **Files to touch:** `apps/mobile_ios/lib/screens/settings_screen.dart` or a new `auth_screen.dart` — add email/password sign-in (same pattern as `mobile_android/lib/screens/settings_screen.dart`). Alternatively, gate `WatchIngest.attach(api)` in `main.dart` on `api.isSignedIn` and also wire it to `onAuthStateChange`. A minimal acceptable fix: surface a sign-in form in `SettingsScreen` and call `api.signIn(email:password:)`.
- **Acceptance criteria:**
  - A user can sign in via the iOS app's Settings screen before pairing with the watch.
  - After sign-in, a watch-triggered file transfer results in `api.saveRun` succeeding (verify via Supabase Studio local: run appears in `runs` table with `source = 'watch'`).
  - `WatchIngest` is re-attached (or always attached) when auth state changes to signed-in.
- **Wear OS reference:** `Stage.SignIn` in `RunViewModel.kt`, email/password form in `ui/RunWatchApp.kt` — but watchOS uses phone-as-proxy so the phone's sign-in is the equivalent.
- **Size:** S (1–2 days — reuse `packages/api_client` and the Android auth pattern)
- **Risk if applied:** Low. Adding sign-in does not break the existing flow.

---

**H4. No crash checkpoint — mid-run process kill loses the entire track**

- **Why HIGH:** `WorkoutManager.track` is an in-memory `[CLLocation]` array. If the watch process is killed (low memory, watchOS background eviction), all track data is lost. `Wear OS` `CheckpointStore` writes a DataStore snapshot every 15 seconds; on next launch the user is offered "Recover unsaved run?". Without this, runs longer than ~30 minutes carry material risk of total data loss.
- **Files to touch:** Create `apps/watch_ios/WatchApp/CheckpointStore.swift`. In `WorkoutManager`, add a `Timer` (separate from the elapsed timer) that fires every 15 seconds during recording and writes a lightweight checkpoint to `UserDefaults`: `{ id, startedAt, distanceMetres, elapsedSeconds, trackPointCount, cacheFileURL }`. Write track points incrementally to a JSON file in Caches (same approach as `TrackWriter.kt`) rather than accumulating them in `self.track`. On `RunApp` launch, check `UserDefaults` for a checkpoint — if found and no active run, surface a "Recover" prompt in `ContentView` (new `.recovering` state case).
- **Acceptance criteria:**
  - Checkpoint written every 15s during recording (verifiable via breakpoint in simulator).
  - Killing the app mid-run in the simulator and re-launching shows the recovery prompt.
  - Accepting recovery produces a `FinishedRun` with the recovered track that can be synced normally.
  - Discarding clears the checkpoint.
  - `xcodebuild` build passes.
  - Tick `[ ] Standalone workout session` in `docs/roadmap.md` Phase 2 (this is the completing item for that checkbox once H1 is also done).
- **Wear OS reference:** `recording/CheckpointStore.kt`, `recording/TrackWriter.kt`.
- **Size:** M (3–5 days)
- **Risk if applied:** Moderate. UserDefaults writes on a background timer during recording — must use `weak self` capture and not block the main thread.

---

### MEDIUM

**M1. Pause / resume is missing**

- **Why MEDIUM:** User-visible Phase 2 parity gap with both Wear OS and the Android phone app. A runner who needs to stop at a traffic light has no option other than ending the run.
- **Files to touch:** `apps/watch_ios/WatchApp/WorkoutManager.swift` — add `pause()` and `resume()` methods: `locationManager.stopUpdatingLocation()` / `startUpdatingLocation()`, `healthKit.session?.pause()` / `resume()`, record a `pausedAt: Date?` to subtract from elapsed time. Add `.paused` case to `WorkoutManager.State`. `ContentView.swift` — add `PausedView` with "Resume" and "Stop" buttons; route `case .paused` in the state switch.
- **Acceptance criteria:**
  - Tap "Pause" during a run — location updates stop, elapsed time freezes.
  - Tap "Resume" — location updates resume, elapsed time continues from where it paused.
  - `HKWorkoutSession` pause/resume reflected (so HealthKit logs the gap).
  - Finishing from paused state produces a correct `FinishedRun` with total active duration.
  - `xcodebuild` build passes.
- **Wear OS reference:** `Stage.Paused`, `RunViewModel.pause()` / `resume()`, `RunRecordingService` pause handling.
- **Size:** S (1–2 days)

---

**M2. Haptic pace alerts (above / below target)**

- **Why MEDIUM:** Named Phase 2 checkbox; comparable to Wear OS which also lacks this (no equivalent found in `RunWatchApp.kt`). However the Android phone app has audio cues for pace (`TTS` in `run_recorder`). On a watch, haptics are the natural equivalent and explicitly called out in the roadmap.
- **Files to touch:** Add a target pace concept to `WorkoutManager` — a `targetPaceSecondsPerKm: Double?` property settable from `ContentView`. In `updatePace()`, after computing `currentPace`, compare to `targetPaceSecondsPerKm ± toleranceSeconds` (reasonable default: ±15 s/km). Call `WKInterfaceDevice.current().play(.notification)` when pace goes outside band (debounced to at most once per 30 seconds to avoid haptic spam). Add a target-pace entry field to `PreRunView` (optional — runs fine without it).
- **Acceptance criteria:**
  - When `currentPace` is set and a `targetPaceSecondsPerKm` is configured, `WKInterfaceDevice.current().play(.notification)` is called when pace exceeds the band.
  - Haptic fires at most once per 30 seconds per violation direction.
  - `xcodebuild` build passes.
  - Tick `[ ] Haptic pace alerts` in `docs/roadmap.md` Phase 2.
- **Wear OS reference:** Neither `RunWatchApp.kt` nor `RunViewModel.kt` implement haptic pace alerts — no direct port available; implement independently.
- **Size:** S (1–2 days)

---

**M3. Route preview before starting (requires phone-to-watch route push)**

- **Why MEDIUM:** Named Phase 2 checkbox. Requires end-to-end work: phone pushes a selected route's waypoints over `WCSession.updateApplicationContext` or `transferUserInfo`; watch receives them in `WatchConnectivityManager.session(_:didReceiveMessage:)` (currently a stub) and passes to `RouteNavigator`.
- **Files to touch:** 
  - `WatchConnectivityManager.swift` — implement `session(_:didReceiveMessage:)` and/or `session(_:didReceive userInfo:)` to decode a `{ routePoints: [{lat,lng}] }` payload and publish via `@Published var receivedRoute: [CLLocation]?`.
  - `RouteNavigator.swift` — implement `update(currentLocation:)`: nearest-point-on-segment projection (standard cross-product formula), `deviationMetres` calculation, `remainingMetres` projection.
  - `ContentView.swift` — in `PreRunView`, if `connectivity.receivedRoute != nil`, show a "Route loaded" indicator and pass `routePoints` to `WorkoutManager` on start.
  - Phone side (`apps/mobile_ios/lib/`) — add a `sendRouteToWatch(route:)` call when the user selects a route before running.
- **Acceptance criteria:**
  - Phone sends a route; `PreRunView` shows "Route loaded (N km)".
  - `RouteNavigator.update` correctly computes `deviationMetres` for a sample location off-route.
  - `xcodebuild` build passes.
  - Tick `[ ] Route preview on watch face before starting` in `docs/roadmap.md`.
- **Wear OS reference:** Neither `watch_wear` nor `watch_ios` has this implemented — both are at zero.
- **Size:** M (3–5 days — most complexity is in nearest-point-on-segment math and the phone-side push UI)

---

**M4. Live position mini-map during run**

- **Why MEDIUM:** Named Phase 2 checkbox. Requires rendering a route polyline + current-position dot as a SwiftUI `Canvas` or pre-rendered `UIImage`. The route data comes from M3.
- **Files to touch:** Add a `MapCanvas` SwiftUI view in `ContentView.swift` or a dedicated `MiniMapView.swift`. In `RunningView`, render `MiniMapView(routePoints:, currentLocation:, track:)`. The map is a normalized coordinate space: compute bounding box of all route points, scale to the available canvas size (typically 48×48 pts on Series 9 in the stats row), draw route in grey, completed track in coral, current position as a filled dot.
- **Acceptance criteria:**
  - During an active run with a loaded route (M3), `RunningView` shows a small route map with current position.
  - On runs without a loaded route, the map is absent (guard on `routePoints.isEmpty`).
  - Canvas render is on main thread only; coordinate transforms are precomputed off main thread.
  - `xcodebuild` build passes.
  - Tick `[ ] Live position on mini-map during run` in `docs/roadmap.md`.
- **Wear OS reference:** Not implemented on either platform.
- **Size:** M (3–5 days)

---

### LOW

**L1. Off-route haptic + "recalculating" indicator (depends on M3)**

- **Why LOW:** Depends on M3 (route data on watch) and M4 has no dependency. The `RouteNavigator` skeleton is already present; once `update(currentLocation:)` is implemented in M3, this is just wiring `isOffRoute` to `WKInterfaceDevice.current().play(.failure)` and showing a "Recalculating..." label in `RunningView`.
- **Files to touch:** `RouteNavigator.swift` — call `WKInterfaceDevice.current().play(.failure)` when transitioning from on-route to off-route (debounce to once per 30 seconds). `ContentView.swift RunningView` — add `if routeNavigator.isOffRoute { Text("Off route — recalculating") }`.
- **Acceptance criteria:** `WKInterfaceDevice.current().play(.failure)` called on first off-route event after a 30-second cooldown. `xcodebuild` build passes. Tick `[ ] Off-route haptic + "recalculating" indicator` in `docs/roadmap.md`.
- **Size:** XS (< 1 day — once M3 is done)

---

**L2. watchOS complication: pace + distance**

- **Why LOW:** Phase 2 checkbox, but WidgetKit complications require a separate Xcode target (`WatchApp Extension` or `Widget Extension`), entitlements (`com.apple.developer.widgetkit-extension`), and a `TimelineProvider` implementation. This is non-trivial plumbing with no runtime dependency on the core recording path.
- **Files to touch:** Add a new `Complication` target to `WatchApp.xcodeproj`. Create `ComplicationProvider.swift` implementing `AppIntentTimelineProvider`. Share `WorkoutManager` state via App Groups (`group.com.runapp.watchapp`) with `UserDefaults(suiteName:)`. The complication reads pace + distance from the shared defaults, refreshed every 30 seconds during active recording.
- **Acceptance criteria:** Complication appears in the watchOS complication picker; during an active run, pace and distance update within 30 seconds of actual values. `xcodebuild -scheme Complication` passes. Tick `[ ] watchOS complication: pace + distance` in `docs/roadmap.md`.
- **Wear OS reference:** Not implemented on Wear OS either (also unchecked in roadmap).
- **Size:** M–L (3–10 days depending on WidgetKit familiarity)

---

**L3. `LocationManager.swift` is dead code**

- **Why LOW:** `LocationManager.swift` defines a `CLLocationManager` wrapper that is never instantiated anywhere. `WorkoutManager` has its own embedded `CLLocationManager`. The file adds confusion for implementers (two CLLocationManager wrappers, one unused).
- **Fix:** Delete `apps/watch_ios/WatchApp/LocationManager.swift`. Remove from the Xcode project's file list (in `WatchApp.xcodeproj/project.pbxproj`). `xcodebuild` build passes after deletion.
- **Risk if applied:** None — the class is not referenced anywhere.

---

**L4. `mobile_ios/CLAUDE.md` is stale — says phone receiver is "a TODO"**

- **Why LOW:** `WatchIngestBridge.swift` and `WatchIngest` in `main.dart` are built and wired. The CLAUDE.md at `apps/mobile_ios/CLAUDE.md` still reads "the phone-side receiver is a TODO, blocked on Supabase auth landing here first." A future implementer reading this will waste time hunting for something that already exists.
- **Fix:** Update the relevant paragraph in `apps/mobile_ios/CLAUDE.md` to note that `WatchIngestBridge.swift` is live, and the remaining blocker is the sign-in UI (addressed by H3).

---

## 7. Non-goals / "do not attempt"

- **Rewrite in Flutter.** See `docs/decisions.md` §1. Direct access to `HKWorkoutSession`, `CLLocationManager`, and `WCSession` is the reason this is native Swift. Do not propose Flutter.
- **Add Supabase anon key or auth credentials to the Release watch binary.** See `docs/decisions.md` §14. `SupabaseService.swift` is `#if DEBUG` only. Do not move it out of the debug guard.
- **Add UIKit-on-watchOS.** The CLAUDE.md convention is SwiftUI-first; `WKInterfaceController` and the WatchKit ObjC layer are deprecated since watchOS 7. `WKInterfaceDevice.current().play(_:)` is an exception — it is not UIKit.
- **Live race mode on watchOS.** This requires the Go service WebSocket endpoint (Phase 2 backend, not started). `RaceSessionClient.kt` on Wear OS is the reference. Do not start this until the Go service is deployed.
- **Port `packages/run_recorder` to Swift.** The Dart package has lap markers, GPS filter chains, and off-route detection that the watchOS app would benefit from, but the port would be a multi-week effort and is explicitly out of scope per the watch-is-lean philosophy in the CLAUDE.md.
- **Ultra-length streaming track writer.** Address once H4 (checkpoint) is done and 10h+ runs are an actual use case. Priority is basic reliability first.
- **WidgetKit complication before H1–H3 are resolved.** A complication that reads data from a recording loop that drops GPS when backgrounded is counterproductive. Sequence: H1 → H2 → H3 → H4 → M1 → M2 → L2.

---

## 8. Open questions for the user

1. **Sync trigger: manual vs automatic.** Currently the user must tap "Sync Run" on the post-run screen; if they tap "Discard" first, the run is gone. Should syncing be triggered automatically when the run stops (i.e. `syncRun()` called in `stop()` directly)? This is a UX decision — automatic is more user-friendly but removes the inspection step before committing.

2. **Standalone workout definition.** The roadmap checkbox says "no phone required". H1 and H4 address recording resilience, but the run will never reach Supabase without a paired iPhone (by design, decisions §14). Should the complication / post-run screen surface a "waiting for phone" indicator that explains why sync is pending, rather than showing "queued" (which implies imminent delivery)?

3. **Target pace entry on the watch.** M2 (haptic pace alerts) needs a target pace input. Options: (a) enter on the watch before starting (awful on a 44mm touchscreen), (b) phone app sends it over `WCSession.updateApplicationContext` alongside the route, (c) derive from the loaded route's expected pace. Which approach is in scope for Phase 2?

4. **Route push mechanism.** M3 requires the phone to push route waypoints to the watch. `WCSession.updateApplicationContext` silently drops data > 65 KB; a 10 km route with 1m spacing is ~200 KB uncompressed. `transferUserInfo` queues correctly but may be delayed. `transferFile` is for runs only. Which mechanism and what waypoint density limit should the implementer use?

5. **Mini-map rendering approach (M4).** watchOS has no `MapKit` map view in SwiftUI (only deprecated `WKInterfaceMap` via WatchKit). The implementer will use a SwiftUI `Canvas`. Should it show only the planned route + current position, or also the recorded track to date (i.e., the portion already covered)? The latter is richer but requires passing `WorkoutManager.track` into the view.

6. **Complication data sharing via App Groups.** L2 (complication) requires `UserDefaults(suiteName: "group.com.runapp.watchapp")` to share state between the app and the widget extension. The App Group entitlement (`com.apple.security.application-groups`) must be added to both targets' entitlements. Does the user have an App Group already provisioned in the Apple Developer portal for this bundle ID?
