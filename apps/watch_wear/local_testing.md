# Local testing — Wear OS app (native Kotlin + Compose-for-Wear)

The Wear OS app is a **native Kotlin Android project**, not Flutter. See [CLAUDE.md](CLAUDE.md) and [decisions.md § 15](../../docs/architecture/decisions.md) for why.

---

## Prerequisites

| Tool | Install |
|---|---|
| Android Studio (Ladybug+ recommended) | `developer.android.com/studio` — ships the JBR 21 that this build pins Gradle to |
| Wear OS emulator | Created via Android Studio Device Manager |
| Local backend running | See [../backend/local_testing.md](../backend/local_testing.md) |

You do **not** need Flutter, Dart, or Melos for this app.

---

## Setup

### Create a Wear OS emulator

In Android Studio: **Device Manager → Create Virtual Device → Wear OS → Wear OS Large Round → API 30+**. `minSdk = 30` because `androidx.health:health-services-client` requires it; older images won't install the app.

Start the emulator before running.

### Gradle JDK

`gradle.properties` pins `org.gradle.java.home` to `/Applications/Android Studio.app/Contents/jbr/Contents/Home` (the JBR 21 bundled inside Android Studio). If Studio isn't at that path on your machine, override locally:

```bash
echo "org.gradle.java.home=/path/to/your/jdk21" >> android/gradle.properties
```

Do not commit that override. The default works on a standard macOS install.

---

## Running

```bash
cd apps/watch_wear/android
./gradlew installDebug
```

Then launch the **Run** app from the Wear OS emulator's app launcher.

A fresh clone needs no `-P` flags: the committed `apps/watch_wear/android/.env.development`
(overlaid by a gitignored `.env.local` if you add one) points the **debug** build at the local stack (`SUPABASE_URL=http://127.0.0.1:54321`,
seed-user auto-login, local Protomaps tiles). Run `npm run dev:core` from the repo
root first — it starts the local stack and runs `adb reverse` so `127.0.0.1`
reaches the host from the emulator/watch.

Point a **release** build at staging / prod (release ignores `.env.local`):

```bash
./gradlew assembleRelease \
  -PSUPABASE_URL=https://your-project.supabase.co \
  -PSUPABASE_ANON_KEY=<publishable-key>
```

---

## Testing features

### Standalone run recording

1. Tap **Start** on the watch.
2. The app requests `ACCESS_FINE_LOCATION`, `BODY_SENSORS`, `ACTIVITY_RECOGNITION` and (API 33+) `POST_NOTIFICATIONS` on the first GO tap. Only the location one blocks the run; decline any of the others and the pre-run notice names what you gave up before it lets you start (`decisions.md § 1018`). Decline location and the same notice says so instead of the tap doing nothing.
3. GPS recording begins using the emulator's simulated location.
4. Tap **Stop** to end the workout.
5. The app saves the run to its local DataStore queue and immediately tries to push to Supabase. Check the **Runs** screen in the web app (`:7777/runs`) or the Android phone app to confirm it landed.

### GPS simulation

In Android Studio's emulator controls (`...` button on the emulator toolbar):

- **Location → Single points** — set a fixed GPS position.
- **Location → Routes** — draw a path and replay it at configurable speed. Useful for getting a realistic distance/pace on the watch UI.

### Heart rate simulation

The Wear OS emulator does **not** synthesise heart-rate samples — `HealthServices.getClient(...).measureClient` produces nothing in the emulator. Test HR end-to-end on a physical Wear OS 3+ watch.

In the emulator the running screen's HR slot now reads **`HR…`** and stays there: the registration succeeds, so the sensor state is `Acquiring` and no sample ever follows. The rest of the run records normally. What this paragraph used to claim — that the field "stays at `— bpm`" — was never true: before `decisions.md § 1052` the slot rendered *nothing at all* when `bpm` was null, which is exactly the defect that entry closed. The four states you can now tell apart on the wrist are `HR…` (registered, no sample yet), a reading such as `146 bpm · Z3`, `HR off wrist` (Health Services reports `UNAVAILABLE_DEVICE_OFF_BODY` — take the watch off a real wrist mid-run to see it), and `No HR` (registration refused, the stream threw, or the sensor reports `UNAVAILABLE`; declining `BODY_SENSORS` is the easy way to reproduce this one). A build with `DISABLE_HR` set renders no HR text at all, deliberately — a build with no heart rate should not caption every run with its absence.

### Distance-unit preference (km / mi)

The watch reads `user_settings.prefs.preferred_unit` (`km` | `mi`) on every
session restore and renders distance + pace in that unit on the running
screen, the route "to go" badge, the route picker, the PostRun summary, and
the active-run tile. The pure parse/format paths are covered by
`UnitFormatTest`, `ActiveRunTileFormattersTest`, and `UniversalSettingsTest`
(`./gradlew testDebugUnitTest`). The **on-face visual flip** still needs a
device check:

1. On the paired phone (or web), set Preferences → distance unit to **mi**.
2. Record a short run on the watch with a starred route loaded.
3. Confirm the running-screen distance reads "… mi", pace reads "…/mi", the
   "to go" badge reads "… mi to go", PostRun shows "… mi", and the active-run
   tile shows miles. Flip the pref back to **km** and re-check.
4. With **mi** set, run past 1.61 km with the volume up: the first spoken cue
   must land at one *mile*, not at one kilometre, and read "1 mile. Pace
   m minutes s seconds per mile". The finish summary must read miles too.
   `completedSplits` / `paceMinSecFor` pin the arithmetic in
   `UnitFormatTest` / `TtsPhrasesTest`; the wiring is pinned by
   `TtsSplitUnitWiringTest`, but the audible read-out needs an ear.

(Editing the unit on the wrist is intentionally not supported — settings stay
on phone / web. The unit is sampled once at run start, so flipping it on the
phone mid-run does not change the cue until the next run — same stamping the
active-run tile uses.)

### Offline queue behaviour

1. Stop the local Supabase stack (`supabase stop` in `apps/backend`).
2. Record a run on the watch. The sync fails and the run stays in the DataStore queue.
3. Restart Supabase.
4. Open the app again — the `init` block's `drainQueue()` fires after auth, and the queued run uploads. The queued-count badge on the pre-run screen disappears.

Auto-retry on connectivity change is wired: `RunViewModel.observeConnectivity` collects from `system/NetworkWatcher.kt`'s `ConnectivityManager.NetworkCallback` flow and runs `drainQueue()` on every offline → online edge, in addition to the app-open and post-stop drains.

---

## Build verification (no device)

```bash
cd apps/watch_wear/android
./gradlew compileDebugKotlin   # catches schema drift + type errors
./gradlew assembleDebug        # produces app/build/outputs/apk/debug/app-debug.apk
./gradlew assembleRelease      # release-signed with debug keys; same verify path
```

JVM unit tests live under `apps/watch_wear/android/app/src/test/` (~86 `@Test` methods across 8 files — `SupabaseErrorClassificationTest`, `WatchRunPayloadFixtureTest`, `MercatorTilesTest`, `RouteMiniMapWiringTest`, `ActiveRunTileFormattersTest`, recording-side helpers, etc. — see [docs/testing/testing.md](../../docs/testing/testing.md) for what each pins). Run them with `./gradlew testDebugUnitTest`. There are no instrumented (`androidTest`) tests yet; for end-to-end coverage we still rely on `compileDebugKotlin` plus a real-device soak.

---

## Schema codegen

If you change the `runs` table in `apps/backend/supabase/migrations/`, regenerate the Kotlin row class:

```bash
cd /path/to/repo
dart run scripts/gen_dart_models.dart
```

That writes both `packages/core_models/lib/src/generated/db_rows.dart` (Dart) and `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/generated/DbRows.kt` (Kotlin). Compile the Kotlin app afterwards — drift surfaces as a compile error at `SupabaseClient.kt`.

---

## Troubleshooting

### `IllegalArgumentException: 25.0.2` on `./gradlew` commands

Gradle 8.14's embedded Kotlin compiler can't parse Java 25's version string. Your system JDK is probably Homebrew `openjdk@25`. Pin Gradle to JDK 21 via `gradle.properties` (the default already points at Android Studio's JBR 21 — check it exists at the configured path).

### Emulator shows round black screen

Wear OS emulators take 1–2 minutes to boot on first launch. Wait for the watch face.

### "Connection refused" from the watch

The committed default is `http://127.0.0.1:54321`, which reaches the host only
once `adb reverse tcp:54321 tcp:54321` is set — `npm run dev:core` does this for
every attached device/emulator. If you skipped `dev:core`, either run those
`adb reverse` lines (also 8080 for tiles) or, on the emulator only, change
`SUPABASE_URL` to `http://10.0.2.2:54321` in `.env.local` (the emulator's host
alias; don't commit that edit). Plain `localhost`/`127.0.0.1` without
`adb reverse` resolves to the emulator itself, not the host.

### `./gradlew installDebug` hangs on "Connecting to devices"

Check `adb devices` — the emulator should appear as `online`. If it's `offline`, restart it from Device Manager.

### App crashes on first launch with `SecurityException: BODY_SENSORS`

**Fixed — if you see this on a current build, it is a new defect.** The old explanation here was wrong: the permission launcher gates the countdown on `ACCESS_FINE_LOCATION` alone, never on all of them, so granting location and declining body sensors did start a run — whose `registerMeasureCallback` then threw out of an unhandled `launch` and killed the process. Heart rate now fails closed and the run records without it (`decisions.md § 1017`), and the pre-run notice tells you that is what happened.

### APK install fails with `INSTALL_FAILED_OLDER_SDK`

The target device / emulator is below API 30. Recreate the emulator at API 30+ (Wear OS 3).

---

*Last updated: April 2026*
