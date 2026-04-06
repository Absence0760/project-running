# Local testing — Android app (Flutter)

The Android app is a Flutter target at `apps/mobile_android/`.

---

## Prerequisites

| Tool | Install |
|---|---|
| Flutter 3.19+ | `flutter.dev/docs/get-started/install` |
| Melos 3.x | `dart pub global activate melos` |
| Android Studio Hedgehog+ | `developer.android.com/studio` |
| Android emulator | Created via Android Studio Device Manager |
| Local backend running | See `local_testing_backend.md` |
| Google Maps API key | Google Cloud Console (enable Maps SDK for Android) |

---

## Setup

```bash
# From the repo root — bootstrap all Flutter packages
melos bootstrap
```

### Create an emulator

In Android Studio: **Device Manager → Create Device → Phone → Pixel 8 → API 34** (or newer).

Start the emulator before running the app.

---

## Running

```bash
cd apps/mobile_android
flutter run -d emulator-5554 \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon-key-from-supabase-start> \
  --dart-define=MAPS_API_KEY=<your-google-maps-key>
```

> **Important:** Use `10.0.2.2` instead of `localhost`. The Android emulator's `localhost` refers to the emulator itself, not your host machine. `10.0.2.2` is a special alias that routes to the host's loopback address.

To find your emulator device ID:

```bash
flutter devices
```

---

## Running tests

```bash
# All Flutter packages
melos run test

# Single package
cd packages/core_models && flutter test
```

## Lint

```bash
melos run analyze
```

---

## Simulating GPS

In Android Studio's emulator controls (the `...` button on the emulator toolbar):

1. **Location → Single points** — set a fixed GPS position
2. **Location → Routes** — draw a path and play it back to simulate movement
3. **Location → Import GPX/KML** — replay a recorded route file

Use route playback to test live run recording, auto-pause, and off-route detection.

---

## Troubleshooting

### "Connection refused" or network errors

- Make sure the backend is running (`supabase start`)
- Make sure you're using `http://10.0.2.2:54321`, not `http://localhost:54321`
- Check that the emulator has internet access (try opening a URL in the emulator's browser)

### Google Maps showing blank/grey

Ensure the **Maps SDK for Android** is enabled in the Google Cloud Console for your API key. The key must also be added to `AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="${MAPS_API_KEY}" />
```

### Health Connect not available

Health Connect comes pre-installed on API 34+. On older API levels, you'll need to install it manually on the emulator from the Play Store. The emulator must use a **Google Play** system image (not a plain Google APIs image).

### `melos bootstrap` fails

```bash
dart pub global activate melos
melos bootstrap
```

Run from the repo root where `melos.yaml` lives.

### Gradle build fails

```bash
cd apps/mobile_android
flutter clean
flutter pub get
flutter run -d <device-id>
```

If it persists, try invalidating caches in Android Studio: **File → Invalidate Caches → Restart**.

---

*Last updated: April 2026*
