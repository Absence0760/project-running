# watch_ios — AI session notes

> **Deferred.** The public landing page lists Apple Watch as "Coming soon" and the team is not actively pushing it forward right now. Keep the project building and don't break the existing Swift code, but **don't start net-new watch work** (HealthKit workout sessions, complications, App Store submission prep, etc.) until the deferral is lifted. See [../../docs/product/parity.md](../../docs/product/parity.md) for the current per-feature state and [decisions.md § 1](../../docs/architecture/decisions.md) for why this is a native target.

**Native Swift / SwiftUI watchOS app.** Separate Xcode project (`WatchApp.xcodeproj`) — **not** a Flutter target. None of Melos, `flutter analyze`, or `dart pub` apply here. You edit `.swift` files and build through Xcode or `xcodebuild`.

## Why native Swift instead of Flutter

See [decisions.md § 1](../../docs/architecture/decisions.md). Flutter's watchOS story isn't production-ready, and a running watch app needs direct access to `HKWorkoutSession`, `CLLocationManager` background modes, and `WKExtendedRuntimeSession` — all of which are cleaner through native APIs than through a Flutter channel.

## Scope — read before writing code

**Web is the canonical feature surface; the watch is a wrist-only complement,
not a parallel client.** See [../../docs/architecture/decisions.md § 24](../../docs/architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)
and the live matrix at [../../docs/product/parity.md](../../docs/product/parity.md). Watch
columns in `parity.md` are `N/A` for almost everything by design — the watch
is **not** trying to mirror web's feature surface.

**Build here:**

- **Wrist-only capabilities**: `HKWorkoutSession` standalone workouts,
  `CLLocationManager` background GPS, `WKExtendedRuntimeSession` for long
  recordings, `HKLiveWorkoutBuilder` HR streams, haptic pace alerts via
  `WKInterfaceDevice`, on-watch crash recovery, watch faces / complications,
  Always-On (ambient) rendering.
- **Watch Connectivity** push to the paired iPhone (`WCSession.transferFile`)
  + DEBUG-only direct Supabase REST as a fallback (`SupabaseService.swift`).
  The phone is the durable sync target.

**Don't build here:**

- Anything that belongs in a pocket app: history browse, settings, social
  feed, club detail, plan editing, OAuth setup. The watch is a recording
  surface and a status surface — not a phone in a smaller form factor. If a
  feature can wait for the runner to be near their phone, it doesn't go on
  the watch.
- A feature that doesn't exist on web yet. Same web-first rule as the rest
  of the monorepo per §24.
- A Flutter or React-Native UI layer (see [§ 1](../../docs/architecture/decisions.md)).
  Don't reintroduce Flutter even for "shared code" reasons.
- A new direct-to-Supabase code path in `SupabaseService.swift` for any
  feature beyond completing a workout. The watch is not the place to grow
  the Supabase surface — that lives in `packages/api_client` (Dart) and
  `apps/web/src/lib/data.ts` (TS).
- New layout abstractions or DI frameworks. `@StateObject` / `@ObservedObject`
  / `@Published` is the whole UI stack.

## Source files

All under `WatchApp/` inside `WatchApp.xcodeproj`:

- `RunApp.swift` — SwiftUI app entry (`@main`)
- `ContentView.swift` — root view, run state routing (idle / recovering / recording / paused / finished)
- `WorkoutManager.swift` — `HKWorkoutSession` wrapper, workout lifecycle (start / pause / resume / stop / recovery)
- `CheckpointStore.swift` — 15s crash checkpoint to `UserDefaults` + incremental track NDJSON to `Caches/run_checkpoint/<id>.ndjson`. The track file is written through one long-lived `FileHandle` (opened once per run, not re-opened per GPS batch), one self-contained JSON object per line, `synchronize()`d every 32 points and on each 15s metadata checkpoint — so a crash can only truncate the final partial line (which the loader skips) and loses at most ~15s of GPS. The checkpoint carries `averageBPM` so a recovered run keeps its heart-rate summary
- `WatchConnectivityManager.swift` — Watch Connectivity framework, two-way messaging with the iOS phone app
- `RouteNavigator.swift` — off-route detection engine: `RouteGeometry` (Swift port of web `route_geometry.ts` `distanceAlongRoute` / `route_snap.ts` — nearest perpendicular foot per segment in a local planar frame, haversine along-distance, remaining = total − along), `OffRouteLatch` (the cross-platform 40 m trigger / 20 m re-arm hysteresis shared with the mobile run screen, Wear's banner, and the custom watch's `OffCourseAlert`), and the `RouteNavigator` ObservableObject that publishes `isOffRoute` / `deviationMetres?` / `remainingMetres?` and fires the `WKInterfaceDevice` haptic once per off-route transition (injectable auxiliary seam). Degenerate routes / non-finite fixes publish nil, never bogus zeros. **Engine only — no UI consumes it yet and no phone-side route push exists**, so the roadmap route-preview / off-route checkboxes stay unticked
- `HealthKitManager.swift` — `HKWorkoutSession` + `HKLiveWorkoutBuilder` wrapper that publishes live heart rate from the watch's sensor
- `SupabaseService.swift` — DEBUG-only direct Supabase REST calls from the watch (no shared Dart/JS code)
- `ActiveRunBridge.swift` — App-Group-backed `UserDefaults` write/read shared with the active-run complication target. `WorkoutManager.publishComplicationSnapshot()` writes here on every workout state transition. See `apps/watch_ios/Complications/README.md` for the one-time Xcode wiring
- `AppTheme.swift` — `Color` palette + reusable text styles for the watch UI (single source of truth so the SwiftUI subviews — `PreRunView`, `RunningView`, `PausedView`, `RecoveryView`, `PostRunView` — share dimensions and colours rather than each redefining their own)

## Localization

The watch UI is localised to the same six locales as web / Flutter / Wear OS:
**en, de, fr, es, ja, pt-BR**. There is **no in-app language picker** — the watch
follows the device / paired-iPhone locale (`Locale.current`), as Apple intends.

- **String Catalog**: `WatchApp/Localizable.xcstrings` (modern `.xcstrings`, source
  string is the key). SwiftUI `Text("Ready to Run")` is a `LocalizedStringKey` and
  localises automatically against the catalog with no code change. Non-`Text` surfaces
  (the sync-status strings in `ContentView.syncedStatusText`) are wrapped in
  `String(localized:)` so they pull from the catalog too. Translations match the
  dialect / wording already used in `apps/mobile_android/lib/l10n/app_*.arb` and
  `apps/watch_wear/.../res/values-*/strings.xml`. "Threkir" stays untranslated.
- **Number / unit formatting**: `WatchApp/RunFormat.swift` is the single source of
  truth — `RunFormat.distance(...)` and `RunFormat.pace(...)`. Distance uses
  `NumberFormatter` (locale decimal separator: `5,12 km` on a German watch) +
  `MeasurementFormatter` (localised unit word) and honours the km/mi preference
  (`UserDefaults preferred_unit`, same key the pre-run pace presets read). Pace is
  `m:ss` + a `/km`|`/mi` suffix (the m:ss part is a stopwatch reading, not a decimal,
  so it isn't locale-separated — matching Wear OS / Flutter). `formattedElapsed`
  stays `%d:%02d:%02d` for the same reason. The complication
  (`Complications/ActiveRunComplication.swift`) carries its own copy of the same
  formatting logic because it builds in a **separate** Widget Extension target that
  can't link `RunFormat.swift`; keep the two in lockstep.
- **`CFBundleLocalizations`** lists all six locales in `WatchApp/Info.plist`; the six
  locales are also in the project's `knownRegions` (`WatchApp.xcodeproj/project.pbxproj`).
  `SWIFT_EMIT_LOC_STRINGS = YES` is already set so Xcode keeps the catalog populated
  from source on build.
- **Parity check (no Xcode needed)**: `scripts/check_xcstrings_parity.sh` parses the
  catalog and fails if any string lacks a non-empty translation for all six locales
  (ja is exempt from the plural `one` category by design). Pure `python3` — runs on
  Linux / CI without a Mac. Run it after editing the catalog.
- **Complication caveat**: the complication's `.xcstrings` localisation only takes
  effect once `Localizable.xcstrings` is added to the Widget Extension target's bundle
  — see step 5 in `Complications/README.md`. Until that target exists in Xcode the
  complication source isn't built at all.
- **Remaining verification**: this work was done on a Linux workstation with no Xcode,
  so it is **correct-by-construction but not compiled**. A Mac/Xcode build
  (`xcodebuild -project apps/watch_ios/WatchApp.xcodeproj -scheme WatchApp …`) plus a
  spot-check of each locale in the simulator is the outstanding verification step.

## What's real vs stubbed

More than a stub — there's a multi-file architecture with `@StateObject` / `@ObservedObject` / `@Published` state flow, a working Supabase client, and cross-device sync via Watch Connectivity. Specific "real" features: workout session start/stop, GPS tracking with background location updates, pause/resume, crash checkpoint recovery, haptic pace alerts, the off-route detection engine (unit-tested, no UI consuming it yet), phone-to-watch message passing.

Per [`roadmap.md` § Phase 2](../../docs/product/roadmap.md), the current checkbox status is:

- [x] Standalone workout session (no phone required) — background GPS via `allowsBackgroundLocationUpdates = true`; crash checkpoint recovery in `CheckpointStore.swift` writes a 15s snapshot to UserDefaults + streams the track to NDJSON in Caches; on next launch the user is offered "Recover unsaved run?" (recovery restores the avg HR from the checkpoint). The run keeps **one UUID end-to-end** — the id minted at `start()` is the one the checkpoint, the on-disk track file, and the finished run row all share (a finished run no longer mints a second UUID). `WorkoutManager.track` is a **bounded rolling window** (`maxInMemoryTrackPoints`); the full track lives on disk and is read back at stop, so an all-day ultra holds flat memory instead of a 360k-point array. `trackPointCount` carries the authoritative count
- [x] Heart rate via HealthKit sensor
- [x] Haptic pace alerts — target pace set via preset list in `PreRunView`; `WKInterfaceDevice.current().play(.notification)` fires when pace leaves the ±15 s/km band, debounced to once per 30s per direction
- [ ] Syncs run data via Watch Connectivity framework — watch side wired (`WCSession.transferFile`); phone-side receiver + sign-in UI live; checkbox remains unticked pending end-to-end verification on paired physical devices
- [ ] Route preview on watch face before starting
- [ ] Live position on mini-map during run
- [ ] Off-route haptic + "recalculating" indicator — the detection engine (geometry + 40/20 hysteresis + transition haptic) is implemented and unit-tested in `RouteNavigator.swift`; the checkbox stays unticked until a route source (phone push) + an on-watch surface consume it
- [ ] watchOS complication: pace + distance — Swift source (provider + four `widgetFamily` views) ships in `apps/watch_ios/Complications/`. `WorkoutManager.publishComplicationSnapshot` writes the active-run state to an App-Group `UserDefaults` on every transition (start / pause / resume / stop / reset) and nudges `WidgetCenter.shared.reloadTimelines`. Checkbox stays `[ ]` until the Widget Extension target is added in Xcode — see `apps/watch_ios/Complications/README.md`

`WorkoutManager.State` now has five cases: `idle`, `recovering`, `recording`, `paused`, `finished`.

`LocationManager.swift` has been deleted — it was dead code; `WorkoutManager` owns the embedded `CLLocationManager`.

## Sync architecture: phone-as-proxy

In Release builds the watch does **not** talk to Supabase directly. On run finish, `WorkoutManager.writeTrackJSON()` serialises the track to a file in the Caches directory and `WatchConnectivityManager.transferRun(fileURL:metadata:)` hands it off via `WCSession.transferFile(_:metadata:)`. The paired iPhone is responsible for gzipping, uploading to the `runs` Storage bucket, and inserting the row via the shared `packages/api_client`. WCSession picks the transport (Bluetooth / Wi-Fi P2P / iCloud relay), queues across app launches, and retries on its own — so the watch needs no Supabase credentials, no anon key, and no internet connectivity.

**Fail-closed hand-off (issue #372):** `transferRun` **returns `Bool`** — `true` only once the file is actually in WCSession's outbox, `false` when the session isn't `.activated` yet (the activation guard, decided by the pure `WatchConnectivityManager.canTransfer(activationState:)`) and nothing was queued. `WCSession.activate()` is async at launch, so a short run right after a cold launch can reach the sync tap before the session is ready. `ContentView.syncRun()` sets `thisRunSynced = true` **only** when `transferRun` returns `true`; a `false` leaves the run in the `finished` state showing a retry-able error (`Phone unavailable — tap Sync Run to retry`, localised in `Localizable.xcstrings`) so `PostRunView` keeps `finishedRun` and re-offers **Sync Run**. Never mark a run synced when it wasn't queued.

The phone-side receiver is **built**: `WatchIngestBridge.swift` in `apps/mobile_ios/ios/Runner/` implements `session(_:didReceive file:)` and calls the `run_app/watch_ingest` Flutter method channel; `main.dart` `WatchIngest.attach(api)` saves the run via `api_client`. `mobile_ios` now has email/password sign-in (Apple Sign-In scaffolded behind a compile flag). Payloads received before the user signs in are persisted by `WatchIngestQueue` (`apps/mobile_ios/lib/watch_ingest_queue.dart`) and replayed on the next `AuthChangeEvent.signedIn` — see [`docs/architecture/decisions.md § 22`](../../docs/architecture/decisions.md).

`SupabaseService.swift` still exists but is wrapped in `#if DEBUG` — it gives watch-sim-alone developers a direct upload path via the "DEBUG: Sync Direct" button, signing in with seed creds against `http://127.0.0.1:54321`. Release builds compile that file out entirely: the watch binary ships without any Supabase client, anon key, or credential-handling code. Rationale: [decisions.md § 14](../../docs/architecture/decisions.md).

Metadata dict sent with each run file: `{id, started_at, duration_s, distance_m, source, activity_type, last_modified_at, avg_bpm?}` — the phone supplies `user_id` from its own authenticated session when inserting the row. `activity_type` is hardcoded to `"run"` (the watch only records runs) so the row passes the `runs_metadata_activity_type_check` CHECK constraint without depending on the phone's defaulting. `last_modified_at` is a UTC ISO-8601 stamp (set at sync time) that mobile's delta-fetch (`runs_screen._fetchRemote`) filters on — without it an Apple-Watch run never resurfaces on another device after the first full pull, matching Wear's `WatchRunMetadata.buildRunMetadata`. **Caveat:** for the WCSession phone-proxy path the key only reaches the row once the phone-side ingest (`apps/mobile_ios/ios/Runner/WatchIngestBridge.swift` forwarding + `WatchIngest._runFromArgs` in `main.dart`) also carries it through — those files are outside this app. The DEBUG-only direct path in `SupabaseService.swift` writes `last_modified_at` straight to the row, so it's effective there immediately. `steps` and `laps` (present in the Wear payload) stay omitted — this watch captures neither, and Wear likewise omits them when absent. The file contents are a raw JSON array of `{lat, lng, ele, ts}` points; the phone compresses before upload.

## Building and testing

See [local_testing.md](local_testing.md). You need:

- Xcode with watchOS simulators installed
- A paired iOS simulator + Apple Watch simulator, or a physical paired pair

From CI, the build is driven by `xcodebuild`:

```bash
xcodebuild -project apps/watch_ios/WatchApp.xcodeproj \
  -scheme WatchApp \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 9' \
  build
```

This is exactly what `.github/workflows/ci.yml`'s `build-watch-swift` job runs on a macOS runner.

**Unit tests: `WatchAppTests` XCTest target.** `apps/watch_ios/WatchAppTests/`
holds the first automated coverage for the watch app — a host-bundle unit-test
target wired into `WatchApp.xcodeproj` (product type
`com.apple.product-type.bundle.unit-test`, `TEST_HOST` = the WatchApp binary,
depends on the WatchApp target). The app's Debug config already sets
`ENABLE_TESTABILITY = YES`, so `@testable import WatchApp` works. The test files
exercise the pure / serialisation surfaces (the Android-bound pieces —
`HKWorkoutSession`, `CLLocationManager`, timers, WidgetKit — are not driven):

- `RunFormatTests.swift` — `RunFormat.distance` / `.pace` km↔mi conversion, m:ss decomposition, `--:--` placeholder, fraction-digit handling.
- `ComplicationFormatterTests.swift` — the complication's own copy of the formatters (`formatElapsed` / `formatDistanceKm` / `formatPaceSecPerKm`), kept in lockstep with `RunFormat`; mirrors Wear's `ActiveRunTileFormattersTest.kt`.
- `ActiveRunBridgeTests.swift` — `ActiveRunSnapshot` Codable round-trip, App-Group write/read fallback to `.empty`, and the 24 h staleness ceiling the complication provider applies to a crash-orphaned snapshot.
- `RunCheckpointCodableTests.swift` — the hand-written `RunCheckpoint.init(from:)` back/forward-compat decode (absent `version`→1, absent `averageBPM`→nil, `{}`→safe defaults, unknown future keys ignored); mirrors Wear's `CheckpointSerializationTest.kt`.
- `CheckpointStoreTrackTests.swift` — NDJSON append/load round-trip, the crash-truncated-final-line skip, garbage-line tolerance, `clear()`, and metadata-checkpoint UserDefaults round-trip; mirrors Wear's `TrackWriterTest.kt`.
- `WatchRunPayloadFixtureTests.swift` — the cross-platform `fixtures/watch_run_payload.json` contract (the Swift slice that closes the loop alongside the Dart / Kotlin / TS fixture tests), plus that the watch's `TrackPoint` encodes the canonical `lat/lng/ele/ts` field names with no stray keys.
- `WorkoutManagerTrackJSONTests.swift` — `writeTrackJSON()` file naming + round-trip + empty-track validity + the no-finished-run guard, and `TrackPoint` codec edge cases (nil ts/ele, negative coords).
- `WorkoutManagerRecoveryTests.swift` — `recoverRun()` rebuilds a `FinishedRun` keeping the same id end-to-end + restoring avg HR, and `formattedElapsed` mm:ss↔h:mm:ss crossover (the elapsed analogue of Wear's `ElapsedMathTest.kt`).
- `TransferStateTests.swift` — `WatchConnectivityManager.TransferState` Equatable (two `.failed` with different messages must differ) + associated-value extraction, plus the pure `canTransfer(activationState:)` activation guard that fixes issue #372 (true only when `.activated`; false when `.notActivated` / `.inactive`, so `transferRun` returns false and `syncRun` never marks an un-queued run synced).
- `RouteNavigatorTests.swift` — the off-route detection engine: `RouteGeometry.project` mirrors the web `distanceAlongRoute` cases (nil on <2 points / non-finite input, vertex + mid-segment along-distance, perpendicular offset maps to the right along-distance, start/end clamps, nearest-of-two-segments, duplicate-vertex tolerance), the `OffRouteLatch` 40 m / 20 m hysteresis cases (fires once, stays latched, strict boundaries, no flap — mirrors `course.rs`'s `OffCourseAlert` tests), and the `RouteNavigator` wiring (haptic exactly once per transition via the injected seam, nil-neutral degenerate route, a non-finite fix keeps the latch).
- `WorkoutManagerDistanceTests.swift` — the per-fix distance accumulation: the pure `WorkoutManager.distanceDelta(from:to:)` `2..<100 m` filter band (in-band adds, jitter below 2 m and reacquisition jumps over 100 m contribute zero), normal consecutive-fix accumulation, and the pause -> wander -> resume regression (#371) — `resume()` clears `lastLocationForDistance` so the first post-resume fix establishes a fresh reference and an aid-station wander while paused is not banked as post-resume distance. Drives `didUpdateLocations` directly (safe: it touches no live `CLLocationManager` / HealthKit / timers).

Run from a Mac: `xcodebuild test -project apps/watch_ios/WatchApp.xcodeproj -scheme WatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 9'`. **These tests were authored on a Linux workstation with no Xcode — correct-by-construction against the source APIs but NOT yet compiled or run.** A Mac/Xcode `xcodebuild test` pass is the outstanding verification step (same situation as the localisation work above).

Still uncovered (Android-bound, not unit-testable without a simulator/host harness): `WorkoutManager` live state transitions driven by `start/pause/resume/stop` (they spin timers + `CLLocationManager` + `HKWorkoutSession`), `HealthKitManager` HR averaging (driven by `HKLiveWorkoutBuilder` delegate callbacks), `WatchConnectivityManager`'s real `WCSession.transferFile`, and `SupabaseService.swift`'s network path. Follow Wear's extract-then-test pattern if those grow non-trivial branches.

## Conventions for Swift code

- SwiftUI-first. Don't mix in UIKit-on-watchOS / WatchKit ObjC unless a framework genuinely requires it.
- State flow: `@StateObject` in the view that owns the lifecycle, `@ObservedObject` in views that consume it, `@Published` on the manager properties. No Combine `Subject`s in the public API if a `@Published` will do.
- File-per-concern, not file-per-view. `WorkoutManager`, `HealthKitManager`, `CheckpointStore`, etc. are each their own file; views can group.
- Swift conventions follow [Apple's API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) — same case style, same parameter labelling.

## Before reporting a task done

- Build the Xcode project (`xcodebuild` command above) and confirm zero errors — warnings are acceptable if they match the baseline.
- Tick the matching Phase 2 checkbox in `roadmap.md`.
- If you touched `SupabaseService.swift`, re-check every other Supabase call site — the watch doesn't have a compiler-enforced link between the generated row types and its own models.
- If you added a new native capability (HealthKit, haptics, background runtime), confirm the entitlements and `Info.plist` keys are set on the watch target, not just the phone.
