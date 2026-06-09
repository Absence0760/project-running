# Local testing — iOS app (Flutter)

The iOS app is a Flutter target at `apps/mobile_ios/`. **Its `lib/` and `test/` are byte-for-byte identical to `apps/mobile_android/`** (see the iOS / android `CLAUDE.md` files and [decisions.md](../../docs/architecture/decisions.md)). Editing happens in either copy and gets mirrored; running on iOS just means picking the iOS target. For shared instructions that aren't iOS-specific (test commands, Melos, etc.), prefer [`../mobile_android/local_testing.md`](../mobile_android/local_testing.md).

---

## Prerequisites

| Tool | Install |
|---|---|
| Flutter 3.19+ | `flutter.dev/docs/get-started/install` |
| Melos 3.x | `dart pub global activate melos` |
| Xcode 15+ | Mac App Store |
| iOS Simulator | Included with Xcode |
| Local backend running | See [../backend/local_testing.md](../backend/local_testing.md) |
| MapTiler API key | Free at maptiler.com/cloud |

---

## Setup

```bash
# From the repo root — bootstrap all Flutter packages
melos bootstrap

# Enable Swift Package Manager globally (one-time)
flutter config --enable-swift-package-manager
```

SPM is the modern path for Flutter plugins on iOS; CocoaPods still handles the plugins that haven't migrated (e.g. `health`), so the project runs in hybrid mode. After the April 2026 unification iOS no longer pulls in `flutter_map_maplibre` — both apps use `flutter_map` with raster tiles for parity.

If `apps/mobile_ios/ios/` doesn't exist (the iOS Runner project can be regenerated at any time), create it:

```bash
cd apps/mobile_ios
flutter create --platforms=ios .
rm test/widget_test.dart          # delete the stock counter-app test
```

Then edit `apps/mobile_ios/ios/Podfile` and set `platform :ios, '15.0'` (the `health` plugin requires 15+). Install pods:

```bash
cd apps/mobile_ios/ios && pod install
```

---

## Running

Put your secrets in `apps/mobile_ios/dart_defines.json` (gitignored):

```json
{
  "SUPABASE_URL": "http://localhost:54321",
  "SUPABASE_ANON_KEY": "<publishable key from `supabase status`>",
  "MAPTILER_KEY": "<your MapTiler key>"
}
```

Inline `--dart-define=` flags don't work on iOS when values are shaped like Supabase's `sb_publishable_…` keys — Flutter's Xcode build script rejects them as "improperly formatted define flag". The JSON file form is the supported path.

`pubspec.yaml` declares `.env.local` as a bundled asset, so the **build** needs the file to exist even though iOS reads its secrets from `dart_defines.json`. Create an empty one once:

```bash
touch apps/mobile_ios/.env.local
```

An empty file is enough — `main.dart` snapshots the `--dart-define` values *before* loading `.env.local`, so the dart-defines survive (you only need real keys in `.env.local` if you prefer the Android-style flow). A missing file fails the build with `No file or variants found for asset: .env.local`.

`open -a Simulator` reopens whichever device was last booted — which may be an **Apple Watch**, not an iPhone. Boot an iPhone explicitly and target it by id:

```bash
xcrun simctl list devices available | grep -i iphone   # find an iPhone + its UDID
xcrun simctl boot "<iphone-udid>"
open -a Simulator
cd apps/mobile_ios
flutter run -d <iphone-udid> --dart-define-from-file=dart_defines.json
```

To target a specific simulator:

```bash
flutter devices                              # list available simulators
flutter run -d <device-id> --dart-define-from-file=dart_defines.json
```

---

## Running tests

```bash
# All Flutter packages
melos run test

# Just the iOS app's dependencies
cd packages/core_models && flutter test
cd packages/run_recorder && flutter test
```

## Lint

```bash
melos run analyze
```

---

## Simulating GPS

The iOS simulator doesn't have real GPS. To test run recording and route navigation:

1. In Simulator: **Features → Location → Custom Location** — set a starting point
2. In Simulator: **Features → Location → Freeway Drive** — simulates movement along a road
3. In Simulator: **Features → Location → City Run** — simulates a running pace through a city

Use **Freeway Drive** or **City Run** to test the live recording screen. Auto-pause is not a feature — moving time is derived from the GPS track at summary time (see [../../docs/architecture/decisions.md § 4](../../docs/architecture/decisions.md)). Off-route detection is implemented in `packages/run_recorder` but has no UI surface on iOS yet.

---

## Troubleshooting

### "Connection refused" when app launches

The local Supabase backend isn't running. Start it first — see [../backend/local_testing.md](../backend/local_testing.md). Verify the URL and publishable key match the output of `supabase status`.

### Map showing blank/grey

Ensure your MapTiler API key is valid and passed correctly via `--dart-define=MAPTILER_KEY=<key>`.

### `melos bootstrap` fails

Make sure Melos is installed and you're running from the repo root:

```bash
dart pub global activate melos
melos bootstrap
```

### HealthKit not available in simulator

HealthKit has limited support in the simulator. You can grant permissions but most workout queries return empty data. Test HealthKit integration on a physical device.

### Build fails with CocoaPods errors

```bash
cd apps/mobile_ios/ios
pod install --repo-update
```

### "Improperly formatted define flag" on build

You're using inline `--dart-define=` flags. Switch to `--dart-define-from-file=dart_defines.json` (see Running above).

### "Failed to find Package.resolved" during build

SPM isn't enabled, or the iOS Runner project predates SPM support. Run `flutter config --enable-swift-package-manager`, then `rm -rf ios && flutter create --platforms=ios .` and redo the Podfile + `pod install` steps.

### `INTERNAL ERROR … count of array (N) differs from count of index set (N-1)` during build

An Xcode 26.x SwiftPM-resolution crash (you'll also see it as `Unable to load workspace 'Runner.xcworkspace'`). It's an Xcode-internal bug in resolving the Flutter-generated SwiftPM package graph, not a problem with the project — almost always a stale SwiftPM / DerivedData index. Fix with Xcode **closed**:

```bash
rm -rf ~/Library/Caches/org.swift.swiftpm ~/Library/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-* ~/Library/Developer/Xcode/DerivedData/Pods-*
cd apps/mobile_ios && flutter clean && flutter pub get && (cd ios && pod install)
```

Then `flutter run` again. These are all regenerable caches; the tracked `Package.resolved` is left alone (it re-resolves on the next build). If it persists, wipe the whole `~/Library/Developer/Xcode/DerivedData`.

### "Target native_assets required define SdkRoot" on first run

Transient glitch after regenerating the iOS project. Fix with `flutter clean && flutter pub get && cd ios && pod install`, then `flutter run` again. If it persists, open `ios/Runner.xcworkspace` in Xcode and build once (Cmd+B) to prime the project.

---

*Last updated: April 2026*
