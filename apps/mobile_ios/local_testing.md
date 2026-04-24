# Local testing — iOS app (Flutter)

The iOS app is a Flutter target at `apps/mobile_ios/`.

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

SPM is required because `maplibre_ios` (pulled in by `flutter_map_maplibre`) uses Flutter's native-assets build hook. CocoaPods still handles the plugins that haven't migrated (e.g. `health`), so the project runs in hybrid mode.

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

```bash
open -a Simulator
cd apps/mobile_ios
flutter run --dart-define-from-file=dart_defines.json
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

Use **Freeway Drive** or **City Run** to test the live recording screen. Auto-pause is not a feature — moving time is derived from the GPS track at summary time (see [../../docs/decisions.md § 4](../../docs/decisions.md)). Off-route detection is implemented in `packages/run_recorder` but has no UI surface on iOS yet.

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

### "Target native_assets required define SdkRoot" on first run

Transient glitch after regenerating the iOS project. Fix with `flutter clean && flutter pub get && cd ios && pod install`, then `flutter run` again. If it persists, open `ios/Runner.xcworkspace` in Xcode and build once (Cmd+B) to prime the project.

---

*Last updated: April 2026*
