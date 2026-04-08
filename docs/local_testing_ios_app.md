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
| Local backend running | See `local_testing_backend.md` |
| MapTiler API key | Free at maptiler.com/cloud |

---

## Setup

```bash
# From the repo root — bootstrap all Flutter packages
melos bootstrap
```

This links local packages (`core_models`, `gpx_parser`, `run_recorder`, `api_client`, `ui_kit`) and fetches dependencies.

---

## Running

```bash
# Open the iOS simulator
open -a Simulator

cd apps/mobile_ios
flutter run -d iPhone \
  --dart-define=SUPABASE_URL=http://localhost:54321 \
  --dart-define=SUPABASE_ANON_KEY=<publishable-key-from-supabase-status> \
  --dart-define=MAPTILER_KEY=<your-maptiler-key>
```

To target a specific simulator:

```bash
flutter devices                 # list available simulators
flutter run -d <device-id>     # run on a specific one
```

---

## VS Code launch configuration

To avoid typing `--dart-define` flags every time, create `.vscode/launch.json`:

```json
{
  "configurations": [
    {
      "name": "iOS (dev)",
      "type": "dart",
      "program": "apps/mobile_ios/lib/main.dart",
      "args": [
        "--dart-define=SUPABASE_URL=${env:SUPABASE_URL}",
        "--dart-define=SUPABASE_ANON_KEY=${env:SUPABASE_ANON_KEY}",
        "--dart-define=MAPTILER_KEY=${env:MAPTILER_KEY}"
      ]
    }
  ]
}
```

Set the environment variables in your shell profile or a `.env` file.

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

Use **Freeway Drive** or **City Run** to test the live recording screen, auto-pause, and off-route detection.

---

## Troubleshooting

### "Connection refused" when app launches

The local Supabase backend isn't running. Start it first — see `local_testing_backend.md`. Verify the URL and publishable key match the output of `supabase status`.

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

---

*Last updated: April 2026*
