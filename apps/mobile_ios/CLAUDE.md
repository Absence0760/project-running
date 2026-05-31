# mobile_ios — AI session notes

> **Deferred.** The public landing page lists the iOS app as "Coming soon" and the team is not actively pushing it forward right now. The code stays in lockstep with `mobile_android` via the byte-identical-twin convention so this doesn't bit-rot, but **don't start net-new iOS-led work** (HealthKit, Apple Sign-In hardening, App Store submission prep, etc.) until the deferral is lifted. Twin-parity edits made on Android still need to be mirrored here in the same commit — that's mechanical and stays cheap. See [../../docs/product/parity.md](../../docs/product/parity.md) for the current per-feature state.

Flutter iOS app. **`lib/` and `test/` are now byte-for-byte identical to `apps/mobile_android/`.** Every screen, widget, library, and test is the same file. Platform-specific behaviour (Apple Sign-In vs Google, dotenv vs `--dart-define-from-file`, Apple Watch ingest vs Wear OS bridge, etc.) is dispatched at runtime via `Platform.isIOS` / `Platform.isAndroid` inside the unified files. The pubspec deltas are the package `name` / `description` and nothing else.

## Scope — read before writing code

**Web is the canonical feature surface. This app mirrors web and adds iOS-only capabilities.** See [../../docs/architecture/decisions.md § 24](../../docs/architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive) and the live matrix at [../../docs/product/parity.md](../../docs/product/parity.md).

**Build here:**

- **iOS-led features** (the physical-exception list in §24, applied to iOS): live GPS recording with `CLLocationManager.allowsBackgroundLocationUpdates`, on-device crash recovery, BLE chest-strap HR, pedometer / cadence, haptic / TTS pace alerts, OS share sheets, **HealthKit** import (replaces Health Connect on Android), **Apple Sign-In** (replaces Google Sign-In on Android), **Watch Connectivity** ingest from `watch_ios` (already live in `WatchIngestBridge.swift`).
- **Mirroring** of an already-shipped web feature, scoped to the gap analysis in `reviews/mobile-ios/gap-analysis.md` and the iOS rows in `parity.md` where web is `✓` and iOS is `✗` / `Partial`. Use `mobile_android` as the **Flutter implementation reference** (idioms, store shape, screen layout) — not as the feature spec.

**Don't build here first:**

- A user-facing feature that doesn't yet exist on web — build it on web first, mirror after. Same rule as Android per §24.
- An Android-only tile that has no iOS equivalent. The deliberately omitted set (already documented in `screens/settings_screen.dart`): BLE pairing UI, Strava ZIP import, backup/restore, advanced-GPS toggle, dark-mode toggle. Don't add these without a fresh decision.
- New abstractions / DI frameworks. Match Android's `StatefulWidget + setState + ChangeNotifier` stack — verbatim. The iOS app is "structurally identical to mobile_android" by design (see "What 'done' means" below).
- Direct `Supabase.instance.client.from(...)` calls in screens. Route through `packages/api_client`.
- Comments, decision docs, READMEs. Conventions in [../../docs/architecture/conventions.md](../../docs/architecture/conventions.md) apply in full.

## Current state

**Single-source-of-truth Dart codebase.** `lib/` and `test/` are kept identical to `apps/mobile_android/` via `diff -rq`. There are no iOS-owned screens, libraries, or widgets — every file lives in both apps in the same form, with `Platform.isIOS` / `Platform.isAndroid` branches inside where the runtime actually differs.

**Editing rule:** apply every change to both apps in the same commit. The architecture guard tests run on the android target; iOS will pick up the same code when the Mac build runs.

**Where the platforms diverge inside the unified code:**

| Concern | Android path | iOS path |
|---|---|---|
| Auth (third-party) | Google Sign-In (`google_sign_in`) | Sign in with Apple (`sign_in_with_apple`) — gated by `_kAppleSignInEnabled` |
| Secrets | `.env.local` asset (read by `flutter_dotenv`) | `--dart-define-from-file=dart_defines.json`, mirrored into `dotenv.env` at startup |
| Apple Watch ingest | `WatchIngest.attach` is a no-op (channel never registered) | `Runner/WatchIngestBridge.swift` posts payloads through `run_app/watch_ingest` |
| Wear OS auth bridge | `WearAuthBridge.attach` posts via `run_app/wear_auth` | No-op (`MissingPluginException` caught) |
| Foreground service notification | `RunNotificationBridge` overrides geolocator's notification | No-op (channel not registered) |
| Background sync | `Workmanager().registerPeriodicTask` | iOS uses `BGTaskScheduler` via the same package |
| Background GPS | Geolocator foreground service | `CLLocationManager.allowsBackgroundLocationUpdates` (Info.plist `UIBackgroundModes:location`) |
| Health Connect / HealthKit | `health` package on Android Health Connect | Same package, HealthKit backend |
| Onboarding permission | `Geolocator.requestPermission` (location-when-in-use) | Same `Geolocator.requestPermission` call — no platform divergence |

**Pubspec divergence:** only `name` and `description`. Every dependency, every version, the asset list, and `dev_dependencies` all match. Run `diff apps/mobile_android/pubspec.yaml apps/mobile_ios/pubspec.yaml` — should be exactly two lines.

**Native iOS files under `ios/Runner/`:**

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

- **Code parity done.** `diff -rq apps/mobile_android/lib apps/mobile_ios/lib` and `diff -rq apps/mobile_android/test apps/mobile_ios/test` both return empty. The iOS-owned screens were merged with the Android twins via `Platform.isIOS` / `Platform.isAndroid` branches inside the unified files. Six previously-iOS-owned files (`main.dart`, `home_screen.dart`, `onboarding_screen.dart`, `run_screen.dart`, `settings_screen.dart`, `sign_in_screen.dart`, `sign_up_screen.dart`) now live as a single source-of-truth file used by both apps.
- **Info.plist** — every Apple usage-description key the Flutter plugins require is now in `ios/Runner/Info.plist`: `NSLocationWhenInUseUsageDescription` + `NSLocationAlwaysAndWhenInUseUsageDescription` (geolocator), `NSHealthShareUsageDescription` (health → HealthKit), `NSBluetoothAlwaysUsageDescription` (flutter_reactive_ble), `NSMotionUsageDescription` (pedometer), `NSPhotoLibraryUsageDescription` (image_picker for run photos). `UIBackgroundModes` carries `location` + `processing` (NOT `fetch` — background sync runs via `BGTaskScheduler`/`processing`, not background app refresh; reconciled with the plist per audit-findings 2026-05-30 Medium) and `BGTaskSchedulerPermittedIdentifiers` includes `com.threkir.backgroundSync` so the Workmanager periodic task can register on iOS 13+. Without these the corresponding features fail silently — adding them removes a runtime-only failure mode that wouldn't have surfaced until a user denied an invisible permission prompt.
- **Runtime parity** is the next gate. `ios/Runner/Runner.entitlements` now exists and declares `com.apple.developer.healthkit` (wired into all three Runner build configs via `CODE_SIGN_ENTITLEMENTS`; pinned by the `iOS Info.plist` group in `architecture_guards_test.dart`) — added per audit/app-store-privacy (2026-05-30) Critical, which flagged that the missing capability is an App Store reject + a runtime crash on the first HealthKit call. Sign-in-with-Apple still needs its own entitlement entry + Apple Developer-portal Services ID. Remaining Mac-only validation: archiving the IPA to confirm the entitlement signs cleanly, `pod install` for the native plugins, `permission_handler` configuration. `parity.md` cells flip when each row is verified on a simulator or device.

## Recommended approach for a new task here

1. **Feature spec lives on web; Flutter idiom lives on Android.** When deciding *what* a screen does, read the web component (`apps/web/src/lib/components/...` or `apps/web/src/routes/...`) and `parity.md`. When deciding *how* to write a Flutter screen, look at the corresponding `apps/mobile_android/lib/screens/...` for the idiom, store wiring, and api_client usage. Don't invent a new feature on iOS — that violates §24.
2. **If the task is "port the latest Android change to iOS,"** copy the file verbatim (or apply the same diff) — the convergence cost stays low only as long as the twins don't drift.
3. **If the task is "fix iOS-only behaviour,"** keep the change in the four iOS-owned files (`main.dart`, the three iOS-owned screens) or in `ios/Runner/`. Don't fork a verbatim copy unless there is no other way.
4. **Prefer lifting shared code into a package** (`packages/ui_kit`, a new `packages/local_stores`, etc.) over deepening the verbatim duplication when a third client (or shared test surface) will need it. The bar for extracting a package is "more than two clients consume the same file or the file gets meaningfully edited on one twin without the other catching up."

## Dart analyzer

No warning or error level issues. The app carries ~20 info-level lints (mostly `always_use_package_imports` and `unnecessary_library_name`) — treat as noise per repo policy.

## Running it locally

See [local_testing.md](local_testing.md). You need an iOS simulator or a paired device.

## Deploying to production

See [deployment.md](deployment.md) — App Store Connect setup, distribution cert + provisioning profile, ASC API key, Apple Watch bundling, observability, rollback, DR. The Apple Watch app at `apps/watch_ios/` ships inside this app's IPA — no separate listing.

The iOS Runner project uses Swift Package Manager + CocoaPods in hybrid mode (most plugins via SPM, `health` still via pods). Podfile pins `platform :ios, '15.0'`. Secrets for `flutter run` pass through `dart_defines.json` (gitignored) because inline `--dart-define=` flags break on the `sb_publishable_…` Supabase anon key format. Rationale: [../../docs/architecture/decisions.md § 13](../../docs/architecture/decisions.md).

## Before reporting a task done

- Update the iOS checkbox in `roadmap.md` (there are several — "Parse on iOS", etc.).
- If you ported a screen from `mobile_android`, note the source commit in the PR description so future drift fixes can find the twin.
- If the ported screen pulled in a dependency that isn't in Android, add it here so the divergence is visible.
