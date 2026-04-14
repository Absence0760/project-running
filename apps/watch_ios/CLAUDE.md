# watch_ios — AI session notes

**Native Swift / SwiftUI watchOS app.** Separate Xcode project (`WatchApp.xcodeproj`) — **not** a Flutter target. None of Melos, `flutter analyze`, or `dart pub` apply here. You edit `.swift` files and build through Xcode or `xcodebuild`.

## Why native Swift instead of Flutter

See [decisions.md § 1](../../docs/decisions.md). Flutter's watchOS story isn't production-ready, and a running watch app needs direct access to `HKWorkoutSession`, `CLLocationManager` background modes, and `WKExtendedRuntimeSession` — all of which are cleaner through native APIs than through a Flutter channel.

## Source files

All under `WatchApp/` inside `WatchApp.xcodeproj`:

- `RunApp.swift` — SwiftUI app entry (`@main`)
- `ContentView.swift` — root view, run state routing
- `WorkoutManager.swift` — `HKWorkoutSession` wrapper, workout lifecycle (start / pause / end)
- `LocationManager.swift` — `CLLocationManager` wrapper, background location updates
- `WatchConnectivityManager.swift` — Watch Connectivity framework, two-way messaging with the iOS phone app
- `RouteNavigator.swift` — route preview and off-route detection on the watch
- `SupabaseService.swift` — direct Supabase REST calls from the watch (no shared Dart/JS code)

## What's real vs stubbed

More than a stub — there's a multi-file architecture with `@StateObject` / `@ObservedObject` / `@Published` state flow, a working Supabase client, and cross-device sync via Watch Connectivity. Specific "real" features: workout session start/stop, GPS tracking, route navigation scaffolding, phone-to-watch message passing.

Per [`roadmap.md` § Phase 2](../../docs/roadmap.md), the boxes still unchecked are:

- [ ] Standalone workout session (no phone required)
- [ ] Heart rate via HealthKit sensor
- [ ] Haptic pace alerts
- [ ] Syncs run data via Watch Connectivity framework
- [ ] Route preview on watch face before starting
- [ ] Live position on mini-map during run
- [ ] Off-route haptic + "recalculating" indicator
- [ ] watchOS complication: pace + distance

Several of these have "code exists, not yet wired up" as their true state — verify against the source before assuming any are done.

## The watch has its own Supabase client

`SupabaseService.swift` talks directly to the Supabase REST API from the watch. This **does not share code with `packages/api_client`** — no common library, no shared row types, no shared auth. Changes to the schema have to be ported here by hand; the Phase 1 parity-enforcement work (see [schema_codegen.md](../../docs/schema_codegen.md)) does not cover Swift.

If you change a column name or a table shape, grep `WatchApp/` for the old column string and update the Swift client manually. A future parity-enforcement phase may add Swift codegen — not today.

## Auth on the watch

The watch defers auth to the phone app via Watch Connectivity. It receives the Supabase access token from the iPhone over `WCSession` and uses it directly. **Don't** try to bring up a sign-in UI on the watch — the device is too small for credential entry, and the account is already active on the paired phone.

## Building and testing

See [../../docs/local_testing_apple_watch.md](../../docs/local_testing_apple_watch.md). You need:

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
- File-per-concern, not file-per-view. `WorkoutManager`, `LocationManager`, etc. are each their own file; views can group.
- Swift conventions follow [Apple's API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) — same case style, same parameter labelling.

## Before reporting a task done

- Build the Xcode project (`xcodebuild` command above) and confirm zero errors — warnings are acceptable if they match the baseline.
- Tick the matching Phase 2 checkbox in `roadmap.md`.
- If you touched `SupabaseService.swift`, re-check every other Supabase call site — the watch doesn't have a compiler-enforced link between the generated row types and its own models.
- If you added a new native capability (HealthKit, haptics, background runtime), confirm the entitlements and `Info.plist` keys are set on the watch target, not just the phone.
