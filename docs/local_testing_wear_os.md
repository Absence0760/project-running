# Local testing — Wear OS app (Flutter)

The Wear OS app is a Flutter target at `apps/watch_wear/`.

---

## Prerequisites

| Tool | Install |
|---|---|
| Flutter 3.19+ | `flutter.dev/docs/get-started/install` |
| Melos 3.x | `dart pub global activate melos` |
| Android Studio Hedgehog+ | `developer.android.com/studio` |
| Wear OS emulator | Created via Android Studio Device Manager |
| Local backend running | See `local_testing_backend.md` |

---

## Setup

```bash
# From the repo root — bootstrap all Flutter packages
melos bootstrap
```

### Create a Wear OS emulator

In Android Studio: **Device Manager → Create Device → Wear OS → Wear OS Large Round → API 34** (or newer).

Start the emulator before running the app.

---

## Running

```bash
cd apps/watch_wear
flutter run -d <wear-emulator-id> \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_ANON_KEY=<publishable-key-from-supabase-status>
```

To find the emulator device ID:

```bash
flutter devices
```

The Wear OS emulator typically shows as something like `emulator-5556`.

> **Note:** Use `10.0.2.2` instead of `localhost` — same as the Android phone emulator.

---

## Testing features

### Standalone run recording

1. Tap **Start** on the watch
2. GPS recording begins using the emulator's simulated location
3. Tap **Stop** to end the workout
4. The run saves locally and queues for sync to the phone

### GPS simulation

In Android Studio's emulator controls (`...` button on the emulator toolbar):

- **Location → Single points** — set a fixed GPS position
- **Location → Routes** — draw a path and replay it

### Phone sync via Data Layer

The Wear OS app syncs with the Android phone app via the Wear Data Layer API. To test this:

1. Run both the phone emulator and Wear OS emulator
2. Pair them in Android Studio: **Device Manager → Pair Wearable**
3. Record a run on the watch, then check that it appears in the phone app

---

## Running tests

```bash
# All Flutter packages
melos run test

# Single package
cd packages/run_recorder && flutter test
```

## Lint

```bash
melos run analyze
```

---

## Troubleshooting

### Emulator shows round black screen

The Wear OS emulator can take a while to boot. Wait for the watch face to appear — it can take 1-2 minutes on first boot.

### "Connection refused" from the watch

Use `http://10.0.2.2:54321` for the Supabase URL. Verify the backend is running.

### Flutter can't find the Wear OS emulator

Make sure the emulator is fully booted and appears in:

```bash
flutter devices
```

If it doesn't appear, try:

```bash
adb devices
```

If the emulator shows as `offline`, restart it from Android Studio Device Manager.

### UI doesn't fit the round screen

The app uses the `wear` Flutter plugin for round-screen-optimised layouts. If content is clipped, check that `compose_for_wear` widgets are being used instead of standard Material widgets.

### Data Layer sync not working

Both emulators (phone + watch) must be paired. In Android Studio: **Device Manager → Pair Wearable**. After pairing, restart both emulators.

### `melos bootstrap` fails

```bash
dart pub global activate melos
melos bootstrap
```

Run from the repo root where `melos.yaml` lives.

---

*Last updated: April 2026*
