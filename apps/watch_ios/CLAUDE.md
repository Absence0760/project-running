# watch_ios — AI session notes

**Native Swift / SwiftUI watchOS app.** Separate Xcode project (`WatchApp.xcodeproj`) — **not** a Flutter target. None of Melos, `flutter analyze`, or `dart pub` apply here. You edit `.swift` files and build through Xcode or `xcodebuild`.

## Why native Swift instead of Flutter

See [decisions.md § 1](../../docs/decisions.md). Flutter's watchOS story isn't production-ready, and a running watch app needs direct access to `HKWorkoutSession`, `CLLocationManager` background modes, and `WKExtendedRuntimeSession` — all of which are cleaner through native APIs than through a Flutter channel.

## Source files

All under `WatchApp/` inside `WatchApp.xcodeproj`:

- `RunApp.swift` — SwiftUI app entry (`@main`)
- `ContentView.swift` — root view, run state routing (idle / recovering / recording / paused / finished)
- `WorkoutManager.swift` — `HKWorkoutSession` wrapper, workout lifecycle (start / pause / resume / stop / recovery)
- `CheckpointStore.swift` — 15s crash checkpoint to `UserDefaults` + incremental track JSON to `Caches/run_checkpoint/<id>.ndjson`
- `WatchConnectivityManager.swift` — Watch Connectivity framework, two-way messaging with the iOS phone app
- `RouteNavigator.swift` — route preview and off-route detection on the watch (stub — no logic yet)
- `HealthKitManager.swift` — `HKWorkoutSession` + `HKLiveWorkoutBuilder` wrapper that publishes live heart rate from the watch's sensor
- `SupabaseService.swift` — DEBUG-only direct Supabase REST calls from the watch (no shared Dart/JS code)

## What's real vs stubbed

More than a stub — there's a multi-file architecture with `@StateObject` / `@ObservedObject` / `@Published` state flow, a working Supabase client, and cross-device sync via Watch Connectivity. Specific "real" features: workout session start/stop, GPS tracking with background location updates, pause/resume, crash checkpoint recovery, haptic pace alerts, route navigation scaffolding, phone-to-watch message passing.

Per [`roadmap.md` § Phase 2](../../docs/roadmap.md), the current checkbox status is:

- [x] Standalone workout session (no phone required) — background GPS via `allowsBackgroundLocationUpdates = true`; crash checkpoint recovery in `CheckpointStore.swift` writes a 15s snapshot to UserDefaults + incremental track JSON to Caches; on next launch the user is offered "Recover unsaved run?"
- [x] Heart rate via HealthKit sensor
- [x] Haptic pace alerts — target pace set via preset list in `PreRunView`; `WKInterfaceDevice.current().play(.notification)` fires when pace leaves the ±15 s/km band, debounced to once per 30s per direction
- [ ] Syncs run data via Watch Connectivity framework — watch side wired (`WCSession.transferFile`); phone-side receiver + sign-in UI live; checkbox remains unticked pending end-to-end verification on paired physical devices
- [ ] Route preview on watch face before starting
- [ ] Live position on mini-map during run
- [ ] Off-route haptic + "recalculating" indicator
- [ ] watchOS complication: pace + distance

`WorkoutManager.State` now has five cases: `idle`, `recovering`, `recording`, `paused`, `finished`.

`LocationManager.swift` has been deleted — it was dead code; `WorkoutManager` owns the embedded `CLLocationManager`.

## Sync architecture: phone-as-proxy

In Release builds the watch does **not** talk to Supabase directly. On run finish, `WorkoutManager.writeTrackJSON()` serialises the track to a file in the Caches directory and `WatchConnectivityManager.transferRun(fileURL:metadata:)` hands it off via `WCSession.transferFile(_:metadata:)`. The paired iPhone is responsible for gzipping, uploading to the `runs` Storage bucket, and inserting the row via the shared `packages/api_client`. WCSession picks the transport (Bluetooth / Wi-Fi P2P / iCloud relay), queues across app launches, and retries on its own — so the watch needs no Supabase credentials, no anon key, and no internet connectivity.

The phone-side receiver is **built**: `WatchIngestBridge.swift` in `apps/mobile_ios/ios/Runner/` implements `session(_:didReceive file:)` and calls the `run_app/watch_ingest` Flutter method channel; `main.dart` `WatchIngest.attach(api)` saves the run via `api_client`. `mobile_ios` now has email/password sign-in (Apple Sign-In scaffolded behind a compile flag). Payloads received before the user signs in are persisted by `WatchIngestQueue` (`apps/mobile_ios/lib/watch_ingest_queue.dart`) and replayed on the next `AuthChangeEvent.signedIn` — see [`docs/decisions.md § 22`](../../docs/decisions.md).

`SupabaseService.swift` still exists but is wrapped in `#if DEBUG` — it gives watch-sim-alone developers a direct upload path via the "DEBUG: Sync Direct" button, signing in with seed creds against `http://127.0.0.1:54321`. Release builds compile that file out entirely: the watch binary ships without any Supabase client, anon key, or credential-handling code. Rationale: [decisions.md § 14](../../docs/decisions.md).

Metadata dict sent with each run file: `{id, started_at, duration_s, distance_m, source, avg_bpm?}` — the phone supplies `user_id` from its own authenticated session when inserting the row. `activity_type` is read on the phone side if present but is not currently sent by the watch (see `reviews/data-sync-audit/watches.md` — low priority). The file contents are a raw JSON array of `{lat, lng, ele, ts}` points; the phone compresses before upload.

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
