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

Start the emulator before running the app. You can launch it from the command line as well:

```bash
# List available emulators
flutter emulators

# Launch one by name
flutter emulators --launch Pixel_10_Pro
```

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

## Installing on a physical phone (APK)

The app works fully offline, so you can install a release APK on your phone without any backend setup.

### 1. Build the release APK

```bash
cd apps/mobile_android
flutter build apk
```

The APK is output to `build/app/outputs/flutter-apk/app-release.apk`.

### 2. Enable USB debugging on the phone

**Samsung (S24 and similar):**

1. **Settings → About Phone → Software Information** → tap **Build Number** 7 times until you see "Developer mode enabled"
2. Go back to **Settings → Developer Options** → enable **USB Debugging**

**Stock Android / Pixel:**

1. **Settings → About Phone** → tap **Build Number** 7 times
2. **Settings → System → Developer Options** → enable **USB Debugging**

### 3. Connect via USB and install

1. Plug the phone into your Mac with a **data-capable** USB cable (not a charge-only cable)
2. Swipe down on the phone's notification shade and change USB mode from **Charging** to **File Transfer (MTP)**
3. Tap **Allow** on the "Allow USB debugging?" prompt on the phone
4. Verify the phone is detected:

```bash
adb devices
```

You should see your device ID listed. If the list is empty, try a different USB cable or port.

5. Install the APK:

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

If `adb` isn't on your PATH, add it to `~/.zshrc`:

```bash
echo 'export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"' >> ~/.zshrc
source ~/.zshrc
```

The app will appear in your app drawer. When prompted on the phone, allow **Install from unknown sources** for adb.

### Offline mode

Without `.env.local` credentials (or if the backend is unreachable), the app runs in **offline mode**: runs are recorded and stored locally on the phone. To sync runs across devices, fill in `DEV_USER_EMAIL` and `DEV_USER_PASSWORD` in `.env.local` before building the APK.

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

## Features

The Android app supports the following. For a side-by-side view against Strava, Nike Run Club, Garmin Connect, and Komoot, see [competitors.md](competitors.md#whats-shipped-today-android).

### First launch

- **Onboarding flow** — 3-page welcome tour with location permission request
- **Offline ready** — no sign-in required to record and store runs locally

### Dashboard

- **Weekly, monthly, all-time stats** — total distance, run count, time
- **Weekly goal** — set a kilometre target, track progress with a progress bar
- **Personal bests** — longest run, fastest pace, fastest 5k

### Activity types

The activity type you pick on the idle screen genuinely changes how the run is recorded and displayed:

| Type | Primary metric | Calorie multiplier | Split interval | GPS filter | Pace alerts |
|---|---|---|---|---|---|
| Run | Pace (min/km) | 1.0× | 1 km/mi | 3 m | Yes |
| Walk | Pace (min/km) | 0.5× | 1 km/mi | 3 m | Yes |
| Cycle | **Speed (km/h)** | 0.4× | **5 km** | 5 m | No |
| Hike | Pace (min/km) | 0.7× | 1 km/mi | 3 m | Yes |

When you pick **Cycle**, the live stats overlay swaps Pace/Avg Pace for Speed/Avg Speed, the audio cue announces speed instead of pace, and split notifications fire every 5 km instead of every km. The history list and run detail screen also adapt — cycling rides show speed in their trailing column. Personal bests for "Fastest pace" and "Fastest 5k" only consider running-style activities.

### Recording a run

- **Activity types** — run, walk, cycle, hike (see table above)
- **Countdown** — 3-2-1 before recording starts so you can put your phone away
- **Live map** — full-screen dark map with your route as an indigo polyline, a pulsing blue dot, and HTTP tile caching so previously loaded tiles work offline
- **Live stats** — time, distance, current pace, average pace, calories, elevation gain, steps, cadence
- **Audio cues** — text-to-speech split announcements at each km/mi (toggle in Settings)
- **Auto-pause** — timer pauses automatically when you stop moving for 10+ seconds (toggle in Settings)
- **Manual pause/resume** — pause button on the recording overlay
- **Lap markers** — flag button records a lap split mid-run
- **Pace alerts** — set a target pace in Settings; TTS warns when you're 30s+ off
- **Wake lock** — screen stays on during the entire run
- **Background recording** — GPS tracking continues when screen is off or app is backgrounded, via a foreground service notification
- **Km/mi splits** — snackbar notification at each distance tick
- **Route following** — pick a saved route before starting; the planned route shows underneath your live track
- **Off-route alerts** — banner + TTS announcement when you drift more than 40m from the selected route
- **Distance remaining** — when following a route, a "X to go" badge in the top right shows distance to the end of the route, measured along the remaining segments

### Routes

- **Import GPX/KML** files via the Import button on the Routes tab
- **Sync from cloud** — pulls routes you created in the web app (when signed in)
- **Local storage** — routes saved on the phone, available offline
- **Route detail** — tap a route to see its map preview and stats
- **Use during a run** — select a route on the run screen before pressing start

### History

- **Tap a run** to see the route map, elevation chart, lap splits, distance splits, and full stats
- **Pull from cloud** — pulls runs created on other devices when signed in (also pull-to-refresh)
- **Sort** — newest, oldest, longest distance, fastest pace
- **Activity icons** — list items show the activity type icon
- **Edit run** — add a custom title and notes
- **Share run** — exports as GPX and opens the system share sheet
- **Delete runs** from the detail screen
- **Sync button** — bulk-upload all unsynced runs (when signed in)
- **Offline indicator** — runs saved offline show a cloud-off icon

### Settings

- **Sign in / Sign out** — email/password against the same backend as the web app
- **Use miles / km** — switches all distance and pace displays
- **Audio cues toggle** — silence TTS announcements
- **Auto-pause toggle** — disable if running on a treadmill
- **Target pace** — m:ss per km/mi; voice alerts when off by 30s+
- **Dark mode** — light/dark theme override
- **Backup runs** — export every locally stored run as a single JSON file via the system share sheet

### Sync behaviour

- **Auto-sync** — runs sync to the backend automatically when connectivity comes back (wifi or mobile) and when the app comes to the foreground. Powered by `connectivity_plus` and the app lifecycle observer.
- **Conflict resolution** — every save stamps a `last_modified_at` timestamp into the run metadata. When the cloud sends a remote run that conflicts with a local one, the newer copy wins. Editing a run locally also re-marks it as unsynced so the change gets pushed.
- **Manual sync** — the History screen still has a sync button for unsynced runs and a refresh button to pull from the cloud.

### Offline mode

If `.env.local` is missing, empty, or the backend is unreachable, the app starts in **offline mode**. All features work locally — you can record runs, view history, and import routes without ever signing in. Runs stay on the device until you sign in and the auto-sync picks them up.

### Not yet implemented

A few items are deliberately out of scope for now:

- **OAuth sign-in (Google/Apple)** — only email/password is supported on Android; the web app has OAuth
- **Strava and parkrun sync** — see roadmap; need API credentials and OAuth/scraping work
- **Heart rate from Bluetooth devices** — no Bluetooth LE support yet
- **Persistent offline map tile cache** — currently in-memory only; tiles re-download on app restart

---

## Simulating GPS

In Android Studio's emulator controls (the `...` button on the emulator toolbar):

1. **Location → Single points** — set a fixed GPS position
2. **Location → Routes** — draw a path and play it back to simulate movement
3. **Location → Import GPX/KML** — replay a recorded route file

Use route playback to test live run recording, auto-pause, and km splits. The step counter and cadence don't work on the emulator (no physical accelerometer); test those on a real device.

---

## Android tech stack

What's actually wired up in [apps/mobile_android](../apps/mobile_android):

| Concern | Package | Why |
|---|---|---|
| GPS recording with foreground service | `geolocator` | Continues tracking when screen is off |
| Map rendering | `flutter_map` + `latlong2` | Open-source MapLibre stack |
| Map tile cache (in-memory) | `flutter_map_cache` + `dio_cache_interceptor` | Reuse loaded tiles within a session |
| Step count and cadence | `pedometer` | Reads the Android step sensor |
| Audio cues | `flutter_tts` | TTS for splits and pace alerts |
| File picker for GPX/KML import | `file_picker` | System file picker |
| GPX/KML/GeoJSON parsing | `gpx_parser` (workspace package) | Implemented from scratch with `xml` |
| User preferences | `shared_preferences` | Units, audio, auto-pause, target pace, weekly goal |
| Permissions | `permission_handler` | Location + activity recognition |
| Wake lock during run | `wakelock_plus` | Keep screen on |
| Auto-sync triggers | `connectivity_plus` + `WidgetsBindingObserver` | Push runs on wifi/foreground |
| Run sharing | `share_plus` | System share sheet for GPX export |
| UUIDs for run IDs | `uuid` | Avoid sync collisions |
| Env config | `flutter_dotenv` | Loads `.env.local` |
| Local persistence | JSON files via `path_provider` | One file per run / per route — no sqlite or hive |
| Backend client | `supabase_flutter` (via shared `api_client` package) | Same backend as the web app |

The two local stores ([`LocalRunStore`](../apps/mobile_android/lib/local_run_store.dart) and [`LocalRouteStore`](../apps/mobile_android/lib/local_route_store.dart)) are intentionally simple — JSON files in the app's documents directory. No sqlite, no Hive. The whole point is that `cat ~/runs/*.json` is debuggable and the offline-first behaviour falls out for free.

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
