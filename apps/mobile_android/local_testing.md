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
| Local backend running | See [../backend/local_testing.md](../backend/local_testing.md) |
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

**Nothing to copy or edit for local dev.** `apps/mobile_android/.env.development` is
**committed** with working local-stack defaults (the standard public Supabase
demo anon key, `127.0.0.1` URLs for Supabase / the web Coach / Protomaps tiles,
and the seed-user auto-login). It's loaded only by DEBUG builds, so it never
ships in a release APK. `npm run dev:up` runs the `adb reverse` that makes
`127.0.0.1` reach the host from a device or emulator.

To use a **real** external key (MapTiler, Strava), edit the values locally —
but **don't commit your change**. `.env.example` is the full annotated
reference for every supported variable.

> **`127.0.0.1` vs `10.0.2.2`:** the committed default is `127.0.0.1`, which
> works on a physical device **and** the emulator as long as `adb reverse` is
> set (it is, after `npm run dev:up`). `10.0.2.2` is the emulator-only alias
> for the host loopback and needs no `adb reverse`, but fails on a real device
> — see the physical-device section below.

### Running on a physical device (not the emulator)

`10.0.2.2` is an **emulator-only** alias — on a real phone it routes to nothing, so the app silently can't reach the local stack. The symptom is subtle: locally-cached data (e.g. previously-synced runs in History) still renders, but anything that needs a fresh server fetch never loads — the History **Lifts / Meals chips stay hidden** because `LocalGymStore` / `LocalFoodStore` were never hydrated, daily nutrition shows nothing, the feed is empty, etc. The fetch failures are swallowed by each surface's best-effort try/catch (layered resilience), so there's no error — just missing data.

Two ways to point a physical device at the local stack:

- **`adb reverse` (recommended).** Forwards the device's own loopback to your host, so `127.0.0.1` works on the phone exactly as on the host:

  ```bash
  adb reverse tcp:54321 tcp:54321   # Supabase REST/Auth/Storage/Functions
  adb reverse tcp:54322 tcp:54322   # Postgres, only if you hit the DB directly
  adb reverse tcp:7777  tcp:7777    # web dev server — AI Coach (WEB_BASE_URL → /api/coach)
  adb reverse tcp:8080  tcp:8080    # local Protomaps tile server (TILE_URL_TEMPLATE)
  ```

  Then point every URL in `.env.local` at `127.0.0.1` (not `10.0.2.2`):

  ```
  SUPABASE_URL=http://127.0.0.1:54321
  WEB_BASE_URL=http://127.0.0.1:7777
  TILE_URL_TEMPLATE=http://127.0.0.1:8080/styles/basic/{z}/{x}/{y}.png
  ```

  `127.0.0.1` also works on the emulator (via the same `adb reverse`), so it's the one set of values correct for both. `adb reverse` even bridges to a host listener bound only to IPv6 `[::1]` (Vite's default), so the web dev server needs no `--host`. Re-run the `adb reverse` lines after any reconnect/reboot (the forwards don't persist). `.env.development` is a bundled Flutter asset (`pubspec.yaml`), so **hot-restart (`R`) or relaunch after editing it** — a hot reload won't re-read it.

- **Host LAN IP.** Set each URL to `http://<your-workstation-LAN-IP>:...` (find it with `ip route get 1.1.1.1`) and make sure each service binds beyond loopback (Supabase + the Protomaps Docker already publish on `0.0.0.0`; the Vite web dev server needs `--host`) and your firewall allows the ports. No `adb` needed, but more setup, and it breaks when your DHCP lease changes.

**Local AI Coach (Ollama).** The mobile Coach POSTs to `WEB_BASE_URL/api/coach`, so the **web dev server must be running** (`npm run dev:run:web`) and configured for Ollama in `apps/web/.env.local`: `COACH_PROVIDER=openai`, `OPENAI_BASE_URL=http://localhost:11434/v1`, and `OPENAI_MODEL=<a model you've actually pulled>` (check with `ollama list` — a model name that isn't installed makes the coach 404). The web server reaches Ollama on the host directly, so no `adb reverse` is needed for port 11434.

## Google Sign-In (optional)

Email/password sign-in works out of the box against any Supabase instance with no extra setup. Google Sign-In requires a one-time Google Cloud Console + Supabase dashboard configuration because Supabase validates the Google ID token against a specific OAuth client.

Skip this section if you're only using email/password.

### 1. Create Google Cloud OAuth credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/apis/credentials) → your project (create one if needed) → **Credentials** → **Create credentials** → **OAuth client ID**.
2. Create a **Web application** client. Name it "Run app — Supabase". No redirect URI is required for the native-ID-token flow, but Supabase needs this client's ID for token validation. Copy the **Client ID** — this is your `GOOGLE_WEB_CLIENT_ID`.
3. Create a second OAuth client, this time **Android**. You need:
   - **Package name**: `com.example.mobile_android` (see `apps/mobile_android/android/app/build.gradle.kts`)
   - **SHA-1 certificate fingerprint**: for debug builds, run:
     ```bash
     keytool -keystore ~/.android/debug.keystore -list -v \
       -alias androiddebugkey -storepass android -keypass android
     ```
     and copy the SHA1 line. For release builds, use your release keystore.
   No Client ID is stored for this one — it's matched by package + SHA alone.

### 2. Configure Supabase

1. Supabase dashboard → **Authentication → Providers → Google** → **Enable**.
2. Paste the **Web** Client ID from step 1.2 into the **Authorized Client IDs** field.
3. Save.

### 3. Add the client ID to `.env.local`

```
GOOGLE_WEB_CLIENT_ID=<your-web-client-id>.apps.googleusercontent.com
```

### 4. Test

Run the app, open the Sign In screen, tap **Sign in with Google**. The system Google chooser appears; pick an account, and the sign-in dialog closes and returns you to the app as an authenticated user.

If the sign-in fails with "Google sign-in did not return an ID token" or similar, the most common causes are:

- The Web Client ID in `.env.local` doesn't match what's configured in Supabase → triple-check both values.
- The Android OAuth client's package name or SHA-1 doesn't match the APK that's installed → rerun `keytool` and compare to what's in Google Cloud Console.
- You're testing on an emulator without Google Play services → use a Google Play system image, not the stock AOSP one.

## Running

```bash
cd apps/mobile_android
flutter run -d emulator-5554
```

To find your emulator device ID:

```bash
flutter devices
```

### Sign in automatically as the seed runner

To skip the sign-in screen and land in the app already authenticated as the
seed user (`runner@test.com` / `testtest`), run from the repo root:

```bash
pnpm dev:run:android:seed
```

This passes `DEV_USER_EMAIL` / `DEV_USER_PASSWORD` via `--dart-define`; the app
signs in after the first frame. Alternatively, set those two keys in
`apps/mobile_android/.env.local` and any plain `flutter run` will auto-login.

The auto-login only fires when `SUPABASE_URL` is a loopback address (the
gate lives in `lib/dev_auto_login.dart`), so seed credentials can never sign
you into a production backend. Make sure the local backend is up first
(`pnpm dev:db:up`, then `pnpm dev:db:reset` if the runner account is missing).

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
# All Flutter packages in the workspace
melos run test

# Single package
cd apps/mobile_android && flutter test
cd packages/run_recorder && flutter test

# Single file / test name
flutter test test/run_stats_test.dart
flutter test --plain-name "speed clamp"
```

See [testing.md](../../docs/testing/testing.md) for the complete testing reference — what's covered, how to add a new test, the `@visibleForTesting` / override-directory / synthetic-`Position` patterns, and what's still uncovered.

## Lint

```bash
melos run analyze
```

---

## Features

The Android app supports the following. For a side-by-side view against Strava, Nike Run Club, Garmin Connect, and Komoot, see [competitors.md](../../docs/product/competitors.md#whats-shipped-today-android).

### First launch

- **Onboarding flow** — 3-page welcome tour with location permission request
- **Offline ready** — no sign-in required to record and store runs locally

### Dashboard

- **Weekly, monthly, all-time stats** — total distance, run count, time
- **Training goals** — one or more weekly/monthly goals, each with any combination of distance, time, avg-pace, and run-count targets. Progress is tracked per-target with an aggregate bar.
- **Personal bests** — longest run, fastest pace, fastest 5k. All three are **running-only** (walks, hikes, and cycles don't starve the run PBs). **Fastest 5k** is the fastest rolling 5 km window inside any recorded GPS track, not `total_time × 5 / total_distance` — so a 10 km at even pace does *not* show up as a half-time 5k. Manual runs and summary-only imports don't have a track and are excluded from this card.

### Activity types

The activity type you pick on the idle screen genuinely changes how the run is recorded and displayed:

| Type | Primary metric | Calorie × | Split interval | GPS filter | Min move | Max speed | Pace alerts |
|---|---|---|---|---|---|---|---|
| Run | Pace (min/km) | 1.0× | 1 km/mi | 3 m | 2 m | 10 m/s | Yes |
| Walk | Pace (min/km) | 0.5× | 1 km/mi | 3 m | 2 m | 5 m/s | Yes |
| Cycle | **Speed (km/h)** | 0.4× | **5 km** | 5 m | 4 m | 25 m/s | No |
| Hike | Pace (min/km) | 0.7× | 1 km/mi | 3 m | 2 m | 6 m/s | Yes |

- **GPS filter + Min move**: software movement thresholds — a new GPS fix is appended to the track only when it's more than `max(GPS filter, Min move)` metres from the last tracked point. Filters out jitter.
- **Max speed**: corrupted GPS fixes implying faster than this are dropped (a single teleport can't inflate total distance). See [run_recording.md](../../docs/features/run_recording.md#per-activity-tuning) for the full filter chain.

When you pick **Cycle**, the live stats overlay swaps Pace/Avg Pace for Speed/Avg Speed, the audio cue announces speed instead of pace, and split notifications fire every 5 km instead of every km. The history list and run detail screen also adapt — cycling rides show speed in their trailing column. All three Personal Bests cards (including "Longest run") are running-only — see the Dashboard section above.

Activity type is locked once you tap Start — it can't change mid-run.

### Recording a run

- **Activity types** — run, walk, cycle, hike (see table above)
- **Countdown with preload** — 3-2-1 before recording starts. All expensive setup (GPS stream, foreground service, pedometer, wakelock) runs *during* the countdown so recording begins instantly when the timer hits zero. Steps and GPS track captured during the countdown are discarded on begin.
- **Live map — Nike Run Club-style glowing line** — dark MapTiler tiles, three stacked polyline layers for a gradient halo effect, and a pulsing blue dot. The track is smoothed at render time (1-2-3-2-1 weighted moving average) to tame walking-pace GPS jitter. The smoothing is display-only; the stored track keeps the raw waypoints.
- **Buttery dot** — the blue dot is tweened between GPS fixes at 60 fps over 900 ms, so it glides rather than hops on each new fix. The map camera (in follow mode) rides the interpolated value too, so everything stays in lockstep.
- **Collapsible stats panel** — tap or flick down the drag handle to shrink the bottom stats panel to a minimal bar showing time + a stop button. The map's follow-cam automatically recentres the blue dot in the freed visible area. Tap or flick up to expand.
- **Live stats** (expanded) — time, distance, current pace / speed, average pace / speed, calories, elevation gain, steps, cadence, lap count
- **Audio cues** — text-to-speech split announcements at each km/mi (toggle in Settings)
- **Manual pause only — no live auto-pause** — the elapsed clock runs continuously during a run and only stops when the user explicitly taps the pause button on the expanded stats panel. Live auto-pause was removed because it was the single most bug-prone feature (false pauses during GPS warmup, slow walking, urban-canyon signal gaps). Instead, the finished-run screen computes **moving time** as a derived metric from the GPS track — the sum of segments where speed was ≥ 0.5 m/s — and shows it alongside elapsed time.
- **Moving time + pace on summary screens** — both the finished-run screen and the historical run detail screen display four primary stats: Distance, Time (elapsed), Moving (derived), and Pace (computed against moving time so it excludes stops at traffic lights). Imported runs without GPS fall back to the full duration.
- **Hold-to-stop** — the big red stop button requires an **800 ms hold** before the run ends. A circular progress ring animates around the button during the hold; releasing early cancels. Prevents accidental one-tap stops. Works from both the expanded and collapsed stats panel.
- **Manual pause/resume** — pause button on the expanded stats panel. Uses the recorder's Stopwatch so resumed elapsed time is exact.
- **Lap markers** — flag button records a lap split mid-run
- **Pace alerts** — set a target pace in Settings; TTS warns when you're 30s+ off
- **Wake lock** — screen stays on during the entire run
- **Background recording** — GPS tracking continues when the screen is off or the app is backgrounded, via a foreground service notification ("Run in progress"). Requires location permission granted as **"Allow all the time"** and battery optimisation disabled for the app.
- **Km/mi splits** — snackbar notification at each distance tick (every 1 km / 1 mi for run/walk/hike, every 5 km for cycle)
- **Route following** — pick a saved route before starting; the planned route shows underneath your live track
- **Off-route alerts** — banner + TTS announcement when you drift more than 40m from the selected route
- **Distance remaining** — when following a route, a "X to go" badge in the top right shows distance to the end of the route, measured along the remaining segments
- **GPS-lost banner** — if no GPS fix arrives for 10 seconds, a red banner appears at the top: *"GPS signal lost — move to open sky"*. Dismisses when fixes resume.
- **Permission-revoked banner** — if location permission is toggled off in Android settings during a run, a red banner warns you immediately.
- **Crash-safe persistence** — the current run state is serialised to disk every 10 seconds. If the app is killed mid-run, the next launch promotes the partial data to a completed run tagged `recovered_from_crash` and shows a snackbar. Tiny runs (< 3 waypoints or < 50 m) are dropped silently.
- **Monotonic clock** — elapsed time uses `Stopwatch`, so wall-clock jumps (NTP sync, DST, timezone change, manual time change) can't corrupt the duration.
- **Speed clamp** — a single corrupt GPS fix implying a speed faster than the activity's maximum (see table) is discarded so it can't inflate total distance.

See [run_recording.md](../../docs/features/run_recording.md) for the architecture behind all of the above — state machine, filter chain, hardening gates, and tunable constants.

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
- **Edit run** — add a custom title and notes. For manual-entry runs (no GPS track), the edit dialog also lets you correct distance and duration; recorded runs keep those derived from the track to avoid desyncing splits / map / PBs from the headline stats.
- **Add run manually** — the FAB on the History tab opens a form to log a run you did without the recorder. Date/time, activity type, duration, distance, optional saved route (searchable picker that pre-fills the distance), and optional title/notes. The run is saved with `metadata.manual_entry = true` and an empty GPS track.
- **Share run** — exports as GPX and opens the system share sheet
- **Delete runs** from the detail screen
- **Multi-select & bulk delete** — long-press to enter selection mode, tap to add more, delete from the app bar
- **Unified timeline (multi-modal)** — once you've logged a lift (Log → Log lift) or a meal (Log → Log food), the History tab grows `All / Runs / Lifts / Meals` chips at the top and a day-grouped cross-modality timeline. **All / Lifts / Meals** show the timeline (run rows → run detail, lift rows → gym detail, meals read-only); the **Runs** chip restores the full run list with all its filters / sort / bulk-delete. A pure runner (no lifts or meals) never sees the chips. Pull-to-refresh updates both the runs and the activities feed.
- **Sync button** — bulk-upload all unsynced runs (when signed in)
- **Offline indicator** — runs saved offline show a cloud-off icon

The run detail screen adapts to runs without a track: the map shows the linked route's planned path if one is attached (or is hidden entirely if not), the "Moving" stat column is dropped (it would equal Time), and the Splits section is hidden.

### Settings

- **Sign in / Sign out** — email/password against the same backend as the web app
- **Use miles / km** — switches all distance and pace displays
- **Audio cues toggle** — silence TTS announcements
- **Target pace** — m:ss per km/mi; voice alerts when off by 30s+
- **Dark mode** — light/dark theme override
- **Import from another app** — pull runs from Strava (data export ZIP) or Health Connect (Google Fit, Samsung Health, Garmin, Fitbit) — see "Migrating from another app" below
- **Backup runs** — export every locally stored run as a single JSON file via the system share sheet

### Migrating from another app

The Settings → "Import from another app" screen offers two paths:

**Strava ZIP import.** Strava lets every user request a full data export from Settings → My Account → Download or Delete Your Account. You get an email with a ZIP containing `activities.csv` and per-activity track files (`.gpx`, `.tcx`, or `.gpx.gz`). Pick the ZIP in the file picker and the app parses every track file, converts them to runs, saves them locally, and pushes them to the cloud if you're signed in. FIT files are skipped — Strava lets you re-export as GPX/TCX from the activity edit page.

**Health Connect import.** On Android 14+, Google Fit, Samsung Health, Garmin Connect, Fitbit, and most other fitness apps sync into Health Connect. The importer reads workout summaries (date, distance, duration, type) for the last year and creates runs from them. The catch: Health Connect doesn't expose GPS routes for workouts written by other apps, so imported runs from this path won't have a map trace. They still count toward distance and weekly goals.

Both importers save locally first and push to the cloud asynchronously, so they work offline (with the cloud push happening on next sync).

### Sync behaviour

- **Auto-sync** — runs sync to the backend automatically when connectivity comes back (wifi or mobile) and when the app comes to the foreground. Powered by `connectivity_plus` and the app lifecycle observer.
- **Conflict resolution** — every save stamps a `last_modified_at` timestamp into the run metadata. When the cloud sends a remote run that conflicts with a local one, the newer copy wins. Editing a run locally also re-marks it as unsynced so the change gets pushed.
- **Manual sync** — the History screen still has a sync button for unsynced runs and a refresh button to pull from the cloud.

### Offline mode

If `.env.local` is missing, empty, or the backend is unreachable, the app starts in **offline mode**. All features work locally — you can record runs, view history, and import routes without ever signing in. Runs stay on the device until you sign in and the auto-sync picks them up.

### Not yet implemented

A few items remain out of scope for now:

- **Strava live OAuth** — the ZIP import path is shipped; the OAuth flow that auto-syncs new activities still routes through the web app per [decisions.md § 41](../../docs/architecture/decisions.md#41-oauth-tokens-are-stored-in-supabase-vault-not-as-plaintext-columns).
- **Garmin live OAuth** — same shape as Strava: ZIP import works, live OAuth still web-only.
- **Live race spectator** — see roadmap, the recording side ships but the active spectator screen on mobile is web-only today.

---

## Simulating GPS

In Android Studio's emulator controls (the `...` button on the emulator toolbar):

1. **Location → Single points** — set a fixed GPS position
2. **Location → Routes** — draw a path and play it back to simulate movement
3. **Location → Import GPX/KML** — replay a recorded route file

Use route playback to test live run recording, auto-pause, and km splits. The step counter and cadence don't work on the emulator (no physical accelerometer); test those on a real device.

---

## Android tech stack

What's actually wired up in [apps/mobile_android/](.):

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
| Strava ZIP import | `archive` + `csv` + `gpx_parser` | Unzip, parse CSV index, parse GPX/TCX track files |
| Health Connect import | `health` | Read workouts from Google Fit, Samsung Health, Garmin Connect, Fitbit |
| Wake lock during run | `wakelock_plus` | Keep screen on |
| Auto-sync triggers | `connectivity_plus` + `WidgetsBindingObserver` | Push runs on wifi/foreground |
| Run sharing | `share_plus` | System share sheet for GPX export |
| UUIDs for run IDs | `uuid` | Avoid sync collisions |
| Env config | `flutter_dotenv` | Loads `.env.local` |
| Local persistence | JSON files via `path_provider` | One file per run / per route — no sqlite or hive. Plus a single `in_progress.json` rewritten every 10s during a recording for crash-safe recovery. |
| Backend client | `supabase_flutter` (via shared `api_client` package) | Same backend as the web app |

The two local stores ([`LocalRunStore`](lib/local_run_store.dart) and [`LocalRouteStore`](lib/local_route_store.dart)) are intentionally simple — JSON files in the app's documents directory. No sqlite, no Hive. The whole point is that `cat ~/runs/*.json` is debuggable and the offline-first behaviour falls out for free.

---

## Troubleshooting

### "Connection refused" or network errors

- Make sure the backend is running (`supabase start`)
- Make sure you're using `http://10.0.2.2:54321`, not `http://localhost:54321`
- Check that the emulator has internet access (try opening a URL in the emulator's browser)

### Map showing blank/grey

Ensure your MapTiler API key is valid and passed correctly via `--dart-define=MAPTILER_KEY=<key>`.

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

*Last updated: April 2026 — hardening sweep (crash-safe persistence, hold-to-stop, speed clamp, monotonic clock, GPS + permission watchdogs); auto-pause removed in favour of derived moving time on summary screens.*
