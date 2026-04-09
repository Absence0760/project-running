# Local testing — Android app (Flutter)

The Android app is a Flutter target at `apps/mobile_android/`.

---

## Prerequisites

| Tool | Install |
|---|---|
| Flutter 3.19+ | `flutter.dev/docs/get-started/install` |
| Melos 7.x | `dart pub global activate melos` |
| Android Studio Hedgehog+ | `developer.android.com/studio` |
| Android emulator | Created via Android Studio Device Manager |
| Local backend running | See `local_testing_backend.md` |
| MapTiler API key | Free at maptiler.com/cloud |

---

## Setup

### 1. Install Melos

```bash
dart pub global activate melos
```

Make sure `~/.pub-cache/bin` is on your PATH. Add this to `~/.zshrc` (or `~/.bashrc`):

```bash
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

Then reload your shell: `source ~/.zshrc`

### 2. Fix Android toolchain

Run `flutter doctor` and resolve any issues:

- **Missing cmdline-tools:** In Android Studio → **Settings → Languages & Frameworks → Android SDK → SDK Tools** → check **Android SDK Command-line Tools** → **Apply**.
- **Licenses not accepted:** Run `flutter doctor --android-licenses` and accept all with `y`.

### 3. Create an emulator

In Android Studio: **Device Manager → Create Device → Phone → Pixel 8 → API 34** (or newer).

Start the emulator before running the app.

### 4. Bootstrap packages

```bash
# From the repo root
dart pub get
melos bootstrap
```

---

## Environment

Copy the example env file and fill in your values:

```bash
cp apps/mobile_android/.env.example apps/mobile_android/.env.local
```

Then edit `apps/mobile_android/.env.local` with your values:

```
SUPABASE_URL=http://10.0.2.2:54321
SUPABASE_ANON_KEY=<publishable-key-from-supabase-status>
MAPTILER_KEY=<your-maptiler-key>
```

Get your Supabase anon key from `supabase status`. Get a free MapTiler key at [maptiler.com/cloud](https://www.maptiler.com/cloud/).

> **Important:** Use `10.0.2.2` instead of `localhost`. The Android emulator's `localhost` refers to the emulator itself, not your host machine. `10.0.2.2` is a special alias that routes to the host's loopback address.

## Running

```bash
cd apps/mobile_android
flutter run -d emulator-5554
```

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

### Map showing blank/grey

Ensure your MapTiler API key is valid and passed correctly via `--dart-define=MAPTILER_KEY=<key>`.
```

### Health Connect not available

Health Connect comes pre-installed on API 34+. On older API levels, you'll need to install it manually on the emulator from the Play Store. The emulator must use a **Google Play** system image (not a plain Google APIs image).

### `melos bootstrap` fails

```bash
dart pub global activate melos
```

Run from the repo root where `melos.yaml` lives. Melos 7.x requires:
- A root `pubspec.yaml` with `melos` as a dev dependency
- An SDK constraint of `^3.11.4` in the root and all child `pubspec.yaml` files
- `resolution: workspace` in each child `pubspec.yaml`

These are already configured in the repo. If you see "not within a Melos workspace", make sure you are in the repo root and run `dart pub get` before `melos bootstrap`.

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
