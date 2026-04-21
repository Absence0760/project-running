# Run recording subsystem

Authoritative reference for how the app records a run — the state machine, the data flow, the hardening that keeps a run from being lost when the real world goes wrong, and the knobs you can tune without redesigning anything.

For a high-level view of where this fits in the repo see [architecture.md](architecture.md). For user-facing feature behaviour see [features.md](features.md). For testing instructions on a real device see [../apps/mobile_android/local_testing.md](../apps/mobile_android/local_testing.md).

---

## Components

| Layer | Code | Role |
|---|---|---|
| Data types | `packages/core_models` | `Run`, `Waypoint`, `Route` |
| Recorder | `packages/run_recorder` | State machine + GPS stream + snapshot emission |
| App screen | `apps/mobile_android/lib/screens/run_screen.dart` | UI, timers, persistence, permission + GPS watchdogs, hold-to-stop |
| Live map | `apps/mobile_android/lib/widgets/live_run_map.dart` | Track polyline + pulsing dot + follow-cam |
| Stats overlay | `apps/mobile_android/lib/widgets/collapsible_panel.dart` | Collapsible bottom panel containing live stats |
| Persistence | `apps/mobile_android/lib/local_run_store.dart` | Completed runs + in-progress save file |

---

## State machine

The recorder has three states. Keeping these separate is load-bearing — see the "Countdown preload" and "Crash-safe persistence" sections below.

```
idle ──prepare()──▶ prepared ──begin()──▶ recording ──stop()──▶ idle
 ▲                                              │
 └──────────────────── dispose ─────────────────┘
```

| State | `_prepared` | `_recording` | GPS stream | `_track` grows? | Elapsed ticks? |
|---|---|---|---|---|---|
| `idle` | false | false | closed | no | no |
| `prepared` | true | false | **open** | no | no |
| `recording` | true | true | open | yes | yes |

`prepare()` is async (permission check + stream subscription + foreground service startup). `begin()` is synchronous — it just flips bits and starts the 1-second elapsed-time timer. `stop()` closes the stream and returns a `Run`.

A `start()` convenience method exists that calls `prepare()` then `begin()` in sequence, for callers that don't need the split.

### Countdown preload

The app splits `prepare` and `begin` so all expensive setup happens during the 3-second countdown. When the countdown timer reaches zero, `begin()` is synchronous and the user sees the run start instantly — no visible delay for GPS warmup, foreground service spin-up, or pedometer subscription.

What runs when (`run_screen.dart`):

- **On tap Start**: `_beginCountdown` → `_maybeRequestPermission` → `_preload` (permission request is non-blocking; denial drops the run into time-only mode rather than aborting)
- **`_preload` (t=0, countdown begins)**:
  - Create `RunRecorder`, subscribe to its `snapshots` stream
  - Subscribe to the pedometer stream (gated — step counts don't accrue until state is `recording`)
  - Enable `WakelockPlus`
  - Call `_recorder.prepare()` — opens GPS, starts foreground service, subscribes to position stream. Store the returned Future in `_prepareFuture`
- **Countdown timer ticks t=1, t=2**: UI only; no background work
- **`_begin` (t=3, countdown ends)**:
  - `await _prepareFuture` — if prepare failed (location services off, permission denied) the error is caught and `_notifyGpsUnavailable` shows a non-blocking snackbar with a Settings shortcut. The recorder is still `prepared` so the run proceeds as an indoor / time-only session: the stopwatch ticks, distance stays 0, `currentPosition` snapshots are null, and the live map falls back to "Waiting for GPS...". If GPS later becomes available via a restart the run populates normally.
  - `_recorder.begin()` — synchronous, flips `_recording = true`, starts elapsed-time timer
  - Generate stable `_runId` (UUID) and `_runStartedAtWall` (wall clock)
  - Reset the pedometer baseline to `_latestPedometerSteps` so any steps taken during the countdown don't count toward the run
  - Start the auto-pause, GPS-lost, incremental-save, and permission watchdog timers
  - Speak the start audio cue
  - Flip state to `_ScreenState.recording`

### Why snapshots are emitted during `prepared`

`_onPosition` in the recorder updates `_currentWaypoint` on every valid GPS fix regardless of whether `_recording` is true. Track append and distance accumulation are separately gated behind `_recording`. That means:

- During `prepared`: the blue dot on the live map can be drawn from the first usable fix, the elapsed time stays at `00:00`, and the track polyline stays empty.
- During `recording`: everything accumulates as normal.

The 1-second elapsed-time timer inside `begin()` emits snapshots unconditionally — it does not gate on `_currentWaypoint`. This keeps the stopwatch advancing for indoor / treadmill runs that never receive a fix. The snapshot simply carries `currentPosition: null` (the field is nullable on `RunSnapshot`), and the live map falls back to its "Waiting for GPS..." placeholder.

---

## Data flow: recording a run

```
1.  User taps Start on the idle screen
2.  _maybeRequestPermission() — requests FINE_LOCATION + POST_NOTIFICATIONS
    (non-blocking; denial drops the run into time-only mode)
3.  _beginCountdown() flips state to countdown and starts the 1s tick timer
4.  _preload() kicks off asynchronously:
    - RunRecorder created
    - snapshots subscription attached (→ _onSnapshot)
    - Pedometer stream subscribed (counts gated on recording state)
    - Wakelock enabled
    - _recorder.prepare() flips _prepared = true, starts the GPS retry
      loop, then tries to open the GPS stream. If services or permission
      are denied it throws a typed error but _prepared stays true — the
      retry loop reopens the stream when conditions come back.
5.  GPS fixes arriving during prepared update _currentWaypoint; snapshots
    drive the blue dot; elapsed stays at 0; track stays empty. With no
    fix the map shows "Waiting for GPS..." — still fine, nothing blocks.
6.  Countdown reaches 0 → _begin() runs:
    - Awaits _prepareFuture (errors caught → _notifyGpsUnavailable snackbar,
      run still starts)
    - _recorder.begin() flips on recording, starts Stopwatch, starts the
      1s elapsed-time timer
    - Stable _runId generated; _runStartedAtWall recorded
    - Pedometer baseline reset so countdown steps don't count
    - Auto-pause, GPS-lost, incremental-save, permission watchdog
      timers start
    - State → recording
7.  While recording:
    - Each valid GPS fix → _onPosition in the recorder:
        * Refresh _currentWaypoint (drives the blue dot)
        * Accuracy filter (>20m rejected)
        * Speed clamp — delta/dt > maxSpeedMps → rejected
        * Movement filter — delta > trackThresholdMetres → track append
          + distance accumulation
    - _emitSnapshot publishes a RunSnapshot (elapsed from Stopwatch, total
      distance, track, current position, pace, off-route, remaining route)
    - _onSnapshot in the screen updates setState, checks movement for
      auto-pause, fires off-route / pace / split TTS
    - Every 10s: _saveInProgress writes current state to runs/in_progress.json
    - Every 2s: _checkGpsHealth flips _gpsLost if _lastSnapshotAt is stale
    - Every 5s: _checkPermission polls Geolocator.checkPermission()
8.  User holds the red stop button for 800ms → _stop():
    - _recorder.stop() closes GPS, cancels the timer, stops the Stopwatch
    - Screen cancels incremental save, GPS-lost, permission, hold timers
    - Wakelock disabled
    - Final Run assembled using the stable _runId (not the recorder's
      stop-time uuid, so incremental saves and the final save share an id)
    - runStore.clearInProgress() deletes the in-progress file
    - runStore.save() writes the completed run
    - api.saveRun() pushes to Supabase if signed in; otherwise marked as
      saved offline
    - State → finished
9.  User taps Done → _discard() resets all state → _ScreenState.idle
```

---

## Persistence and crash recovery

`LocalRunStore` keeps two kinds of files in `runs/`:

- `<run-id>.json` — one per completed run
- `in_progress.json` — at most one, rewritten every 10 seconds during a recording

### Incremental save (`_saveInProgress` in `run_screen.dart`)

Every 10 seconds while the screen state is `recording`, the app serialises the current `Run` state into `in_progress.json`:

- `id` = `_runId` (stable, generated in `_begin`)
- `startedAt` = `_runStartedAtWall` (stable wall-clock start)
- `duration` = `_elapsed` (read from the recorder's Stopwatch via the last snapshot)
- `distanceMetres`, `track`, activity type in metadata

`_loadAll` excludes `in_progress.json` from the normal run list, so the in-progress file never pollutes history.

### Recovery on next launch (`main.dart`)

Immediately after `LocalRunStore.init()` and before `runApp`, the app checks for a leftover `in_progress.json`:

- If the partial run has **≥ 3 waypoints and ≥ 50 m of distance**, it's promoted to a completed run (tagged `metadata.recovered_from_crash = true`) and saved via `store.save()`.
- If it's smaller than that it's dropped silently (filters out "tap Start then background" noise).
- Either way, `store.clearInProgress()` deletes the file so it doesn't get picked up twice.
- If a run was recovered, a snackbar appears on first frame: *"Recovered unfinished run — X.XX km, Y min"*.

### Why a stable run id matters

The id is generated in `_begin` (not at stop time) and reused through the incremental save loop and the final `_stop`. That means:

- Crash recovery produces a `Run` with the same id the app would have written at a clean stop — so cloud sync can eventually deduplicate.
- Multiple incremental saves all overwrite the same file with the same id — no orphan partials.

---

## GPS pipeline

All of this lives in `run_recorder.dart:_onPosition`.

### Stream configuration

```dart
AndroidSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 0,  // receive every fix; filter in software
  foregroundNotificationConfig: ForegroundNotificationConfig(
    notificationTitle: 'Run in progress',
    notificationText: 'Recording your run',
    enableWakeLock: true,
  ),
)
```

The title / text above are only the *initial* state. Once recording begins, `_refreshLockScreenNotification` (run_screen, throttled to ~1 Hz) calls `RunNotificationBridge` which reposts on the same channel + id with live time / distance / pace — so the lock-screen row is live, not the static strings above. See hardening row 12.

**`distanceFilter: 0`** is intentional. The OS-level `distanceFilter` gates position emission by physical distance — a value of 3 means no position until the device has physically moved 3 m. That starves the blue dot at slow walking speeds (the marker doesn't move until 3 m of accumulated motion crosses the threshold).

With `distanceFilter: 0` we receive every fix the sensor produces (~1 Hz on most Android chips) and do all the filtering in software below, which lets the dot refresh at sensor rate while still keeping the track clean.

### Filter chain

Every incoming `Position` goes through:

1. **Paused gate** — if `_paused`, drop (Stopwatch is also paused, so elapsed doesn't advance).
2. **Accuracy filter** — `pos.accuracy > _accuracyGateMetres` (default 20) → drop. 20 m is a compromise between rejecting urban-canyon corruption and keeping sparse fixes alive. Drops log via `debugPrint`, rate-limited to once per 5 s so an always-bad stream doesn't flood. Tightening below 20 m silently rejects realistic outdoor fixes — see [decisions.md § 21](decisions.md).
3. **Always** update `_currentWaypoint` (blue dot).
4. **If not recording**, emit snapshot and return. Track and distance are untouched.
5. **First tracked position** — set `_lastTrackedPosition` + `_lastTrackedPositionAt`, append to track, no distance delta yet.
6. **Subsequent positions** — compute `delta` (haversine distance to last tracked position) and `dt` (seconds since last tracked). Three gates must all pass:
   - `delta > _trackThresholdMetres` — rejects jitter below the minimum-movement threshold
   - `delta < 100` — rejects implausible teleports
   - `delta / dt <= _maxSpeedMps` — rejects implausible speed. A corrupt fix implying 50 m/s on foot would otherwise inflate distance and pace.
7. If all three gates pass: append to track, add `delta` to `_distanceMetres`, update `_lastTrackedPosition` + `_lastTrackedPositionAt`.
8. `_emitSnapshot()` publishes the updated `RunSnapshot`.

### Per-activity tuning

`ActivityType` (`preferences.dart`) declares the per-activity knobs:

| Activity | `gpsDistanceFilter` (m) | `minMovementMetres` (m) | `maxSpeedMps` (m/s) | Split (m) |
|---|---|---|---|---|
| run | 3 | 2 | 10 | 1000 |
| walk | 3 | 2 | 5 | 1000 |
| cycle | 5 | 4 | 25 | 5000 |
| hike | 3 | 2 | 6 | 1000 |

`trackThresholdMetres` in the recorder is `max(distanceFilterMetres, minMovementMetres)` — i.e. the more conservative of the two knobs.

### Advanced GPS override

A user-facing toggle (Settings > Advanced GPS, mobile_android only) overrides the per-activity knobs for higher-fidelity recording on devices with capable chips:

| Knob | Normal | Advanced GPS |
|---|---|---|
| `accuracy` | `LocationAccuracy.high` | `LocationAccuracy.best` |
| `distanceFilterMetres` | per-activity (3 or 5) | 2 |
| `minMovementMetres` | per-activity (2 or 4) | 1 |
| `accuracyGateMetres` | 20 (default) | 20 (default) |

`maxSpeedMps` stays on the per-activity value.

The accuracy gate stays at the 20 m default in both modes — it has to, because the reported `pos.accuracy` is a real-world uncertainty estimate, not a knob the OS scales down when you ask for `best`. A tighter gate silently rejects the 15–30 m fixes that consumer phones routinely produce outdoors. See [decisions.md § 21](decisions.md).

The toggle is per-device (SharedPreferences, not synced) and applies at `RunRecorder.prepare()` time — flipping it mid-run has no effect until the next run. It's only read in `run_screen.dart:_preload`.

### Display smoothing

In `live_run_map.dart`, `_smoothTrack` applies a 1-2-3-2-1 weighted moving average to the rendered polyline. Two passes are run before feeding the `PolylineLayer` stack. This reduces visible zig-zag at walking pace. It's **display-only** — the stored run keeps the raw waypoints, so stored distance/pace and GPX export are unaffected.

Smoothing cannot correct systematic offset from the road (GPS bias, not noise). For that see the [map matching roadmap entry](roadmap.md#future--map-matching-strava--nike-run-club-quality).

### NRC-style polyline

The live track is drawn as four stacked `PolylineLayer`s for a Nike-Run-Club-style glow and pace heatmap:

1. **Outermost halo** — 18 px stroke, indigo at 18% alpha
2. **Mid halo** — 10 px stroke, indigo at 35% alpha
3. **Dark underline** — 8 px stroke, deep indigo (`0xFF1E1B4B`), solid. Replaces the per-polyline border that the old single-gradient line used — a shared underline avoids visible seams at the boundaries between coalesced pace buckets on layer 4.
4. **Pace heatmap** — per-segment polylines coloured by instantaneous speed and faded by age. Built by `buildPaceSegments` in `widgets/pace_segments.dart`, cached in `LiveRunMap` by `(track.length, activity)`. See below. When `LiveRunMap.activity` is null (route preview, manual-entry runs without activity metadata) this falls back to the legacy single 6 px gradient polyline (deep indigo → pale lavender).

Rounded caps and joins are flutter_map's default.

#### Pace heatmap

Each segment (consecutive waypoint pair) is assigned two coordinates:

- **Pace bucket** (0..5, slow → fast) from its instantaneous speed in m/s. Break-points are activity-specific: running ~7:30 → 3:45 per km, walking ~16:40 → 7:35, hiking shifted slower, cycling 12 → 36 km/h. Segments without timestamps (shouldn't happen for recorded runs; guards against manual-entry imports) fall back to the slowest bucket as a safe default.
- **Age band** (0..2, oldest → newest) from its position along the track. Three bands at 1/3 boundaries give the run a "comet trail" fade: oldest segments render at 55 % alpha, mid at 80 %, newest at 100 %.

Consecutive segments sharing both coordinates are coalesced into a single `Polyline` — a 10 km run with steady pacing typically lands at ~20 polylines, a hard-hard-easy interval session at ~50. Adjacent coalesced runs share their boundary vertex so there's no visible gap at bucket transitions.

The six-colour ramp (red → orange → amber → lime → emerald → cyan) is fixed, so a steady 5:00/km pace renders the same colour across every run — you can eyeball a pace comparison between two runs by comparing hue.

Mini-test list in `test/pace_segments_test.dart` covers bucket clamping, activity-specific scaling, uniform-pace coalescing, vertex-sharing continuity, and the no-timestamp fallback.

### Blue dot interpolation

`_PulsingDot` is rendered at an `_animatedLatLng` held in `_LiveRunMapState`, not at the raw `currentPosition`. When a new position arrives via `didUpdateWidget`, a 900 ms `AnimationController` tweens `_animatedLatLng` from the previous interpolated position to the new target. The map camera (in follow mode) rides the interpolated value too, so panning and the dot stay in lockstep and the dot glides between fixes instead of hopping at sensor rate.

The first fix snaps (no animation). Same-target fixes are ignored.

### Follow-cam offset for the bottom panel

`LiveRunMap` takes a `bottomPadding` parameter in logical pixels. All programmatic camera moves go through `_moveCamera`, which passes `offset: Offset(0, -bottomPadding / 2)` to `MapController.move`. flutter_map renders the `center` at `(viewportCenter + offset)`, so a negative `dy` lifts the dot above the geometric centre — leaving it in the middle of the *visible* area above the stats panel rather than hidden behind it.

`run_screen.dart` measures the actual `CollapsiblePanel` height via `GlobalKey` + post-frame callback and passes it through every build, so when the panel collapses the camera offset shrinks and the dot re-centres in the freed space automatically.

---

## Pause: manual only, moving time derived

The app does **not** have live auto-pause. An earlier version did, and it was the single most bug-prone feature in the recorder — false pauses during GPS warmup, slow walking, urban-canyon signal gaps, and edge cases around the track movement threshold. Each round of hardening fixed one class of false-positive and revealed another.

Modern Strava and Nike Run Club handle this differently, and so do we: the clock runs **continuously** during a recording (except when the user explicitly taps the manual pause button), and **moving time** is computed as a *derived metric* on the finished-run screen from the GPS track.

### Manual pause

`_StatsOverlay` still has a pause/resume button. Tapping it calls `RunRecorder.pause()` / `resume()`, which stops and restarts the internal `Stopwatch`. Elapsed time stops advancing while paused. This path is deliberately explicit — the user chose to pause, so the user can unambiguously resume.

### Moving time (derived)

See `apps/mobile_android/lib/run_stats.dart`. The `movingTimeOf(List<Waypoint>)` function walks consecutive waypoint pairs:

- For each pair, compute `speed = distance / time`.
- If `speed >= 0.5 m/s` (~1.8 km/h, slower than a slow walk), count the segment's time toward moving time.
- Otherwise, exclude it (standing still or drifting at GPS-jitter speeds).

This is called once when a run finishes — in `_buildFinished` (freshly-completed run) and in `run_detail_screen` (historical runs). It's O(n) in track length, so cheap enough to run on every render without caching.

The finished-run UI shows **Time** (elapsed clock) alongside **Moving** (derived), and the **Pace** column is computed against moving time so the headline pace excludes stops. Historical runs in `run_detail_screen` get the same treatment, with a fallback to the full duration when the track is missing or too sparse (e.g. imported runs without GPS).

### What's gone

Because auto-pause is removed entirely, all of the following no longer exist: `_autoPauseCheckTimer`, `_lastMovementAt`, `_lastMovementCheckPosition`, `_autoPaused`, `_recordingStartedAt`, `_autoPauseGracePeriod`, `_autoPauseMaxSnapshotGap`, `Preferences.autoPause` (getter + setter + SharedPreferences key), and the auto-pause banner in the recording UI. Around 80 lines of code and its entire edge-case surface.

The GPS-lost banner, permission watchdog, and snapshot freshness tracking (`_lastSnapshotAt`) all remain — they serve a different purpose (observability) and don't touch the clock.

---

## Hardening

Each of these is a self-contained piece with its own purpose. Most can be tuned without touching any other part of the system — the constants live at the top of `run_screen.dart` or in `ActivityType`.

### Layering

The recording stack is organised so a failure at a higher layer cannot break a lower one. "Basics always work" is load-bearing: an indoor treadmill session with no GPS and a crashed tile layer must still show a running clock and a plausible distance.

| Layer | Depends on | Breaks if... |
|---|---|---|
| **L0 — Clock** | `Stopwatch` only | The Dart VM dies. That's it. |
| **L1a — Pedometer distance** | L0 + accelerometer | Phone lacks a step sensor. Used as the indoor-run fallback. |
| **L1b — GPS distance + pace** | L0 + location services + permission + signal | Location off, permission denied, sky blocked. Falls back to L1a. |
| **L2 — Live map tiles + polyline** | L1b + network or tile cache + `flutter_map` | Offline and no cached tiles, or a `flutter_map` crash. Caught by the error boundary (row 15) so L0/L1 stay visible. |
| **L3 — Route overlay** | L2 + a selected `Route` | Usually silent — no route, no overlay. |
| **L4 — Auxiliary effects** | Everything above + TTS + network + pedometer + BLE HR + platform channels | Individually wrapped in try/catch (row 13) so a single failure (e.g. TTS init error) doesn't bring down L0–L2. |

If you add a new feature, place it at the highest layer it actually needs. A new visual (e.g. a cadence chart) is L2 — don't wire it into the `setState` that drives L0/L1. A new alert or side-effect is L4 — wrap it in try/catch.

| # | Concern | Mechanism | Constant(s) |
|---|---|---|---|
| 1 | Crash-safe run data | Serialise partial run to `in_progress.json` every 10 s; recover on launch if ≥ 3 waypoints and ≥ 50 m | `_incrementalSaveInterval` |
| 2 | GPS-lost awareness | Banner when `_lastSnapshotAt` is > 10 s stale | `_gpsLostThreshold` |
| 3 | Speed clamp | Drop GPS fixes implying speed > activity max | `ActivityType.maxSpeedMps` |
| 4 | Hold-to-stop | 800 ms hold with progress ring before `_stop()` fires | `_holdToStopDuration` |
| 5 | Monotonic clock | `Stopwatch`-based elapsed, immune to wall-clock jumps | — |
| 6 | Pedometer resubscribe | Exponential backoff on stream error, up to 5 retries | `_pedometerMaxRetries` |
| 7 | Permission watchdog | Poll `Geolocator.checkPermission()` every 5 s; banner if revoked | — |
| 8 | Activity-type lock | Guard in `onSelected` to reject changes unless state is idle | — |
| 9 | Indoor / no-GPS fallback | `RunRecorder.prepare` flips `_prepared` before opening the position stream and throws typed errors (`LocationServiceDisabledError` / `LocationPermissionDeniedError`) if GPS setup fails. `RunSnapshot.currentPosition` is nullable; the 1-second timer emits snapshots regardless of fix state. `_begin` catches prepare errors, shows a non-blocking snackbar, and the run proceeds as a time-only session. GPS-lost and permission-revoked banners stay dormant until the first real fix arrives, so indoor runs don't nag. | — |
| 10 | LiveRunMap restart reset | `didUpdateWidget` wipes `_animatedLatLng`, tween endpoints, and `_userPanned` when the track clears for a new run, so the next first fix snaps cleanly and the follow-cam re-centres | — |
| 11 | GPS self-heal | `_gpsRetryTimer` inside `RunRecorder` polls every 3 s while `_prepared` is true and `_positionSub` is null. Once `isLocationServiceEnabled()` + `checkPermission()` both pass, it reopens the position stream with the accuracy settings remembered from `prepare()`. The stream subscription uses `onError`/`cancelOnError: true` so an Android-side disconnect (e.g. user toggles Location off mid-run) cleanly clears `_positionSub` and the retry loop takes over. Net effect: tracking resumes automatically when Location is re-enabled, whether the run started without GPS or lost it mid-run. | `_gpsRetryInterval` |
| 12 | Live lock-screen notification (Android) | `RunNotificationBridge` (Kotlin) pre-creates `geolocator_channel_01` with `VISIBILITY_PUBLIC` + `IMPORTANCE_LOW` (winning the race against geolocator's private-visibility default, which is immutable after creation), then reposts on that channel with `BigTextStyle` + `CATEGORY_WORKOUT` so the lock-screen row shows live time / distance / pace instead of the static "Run in progress". Posts are guarded by a runtime POST_NOTIFICATIONS check (Android 13+); if missing the bridge returns an error rather than silently no-opping. The Dart side (`RunNotificationBridge`, called from `_refreshLockScreenNotification` at the end of `_onSnapshot`) throttles to ~1 Hz. Explicitly cleared on stop / discard. Constants in the bridge mirror `GeolocatorLocationService`; if a future geolocator release changes them, the replacement stops applying — fix by updating the constants. | — |
| 13 | Auxiliary-effect isolation | Every L4 effect inside `_onSnapshot` (race ping, off-route cue, pace alert, split snackbar + TTS, lock-screen update) is wrapped in its own try/catch + `debugPrint`. A failure in any one (TTS init error, Supabase realtime drop, corrupt route math) can't break the core `setState` that drives the visible stats — the L0 (clock) / L1 (distance / pace) numbers stay live even when L4 is misbehaving. | — |
| 14 | Pedometer distance fallback | When `_everHadGpsFix` is false and the GPS distance is 0, `_displayDistanceMetres` returns `steps × ActivityType.strideMetres`. UI prefixes a tilde and the indoor chip flags the estimate. On stop, `metadata.indoor_estimated = true` + `metadata.distance_source = "pedometer"` are written so downstream views can render it distinctly. Crash recovery accepts an indoor run with `duration ≥ 60 s` instead of the usual 3-waypoint / 50 m gate, so a treadmill session doesn't evaporate on recovery. | `ActivityType.strideMetres` |
| 15 | Release-build error boundary | `ErrorWidget.builder` is overridden in `main.dart` (release only — debug keeps Flutter's red screen for visibility) with a subtle "This section couldn't load" card. A crash inside `LiveRunMap` or any other subtree replaces only that subtree, leaving the stats panel and recording state intact. `RunRecorder` lives outside the widget tree, so even a full-screen rebuild doesn't stop it. | — |
| + | Reentrancy guard on Start | `_startRequested` flag prevents double-taps from spawning multiple recorders | — |
| + | No live auto-pause | Clock runs continuously; "moving time" computed as a derived metric at summary time instead | — |

---

## Background recording

GPS continues while the app is backgrounded via an Android foreground service spun up by `geolocator_android` when `ForegroundNotificationConfig` is passed to `getPositionStream`. The service runs with these manifest entries:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

`FOREGROUND_SERVICE_LOCATION` is required on Android 14+ for location-type foreground services. `POST_NOTIFICATIONS` is required on Android 13+ to display the service's notification at all.

Practical requirements on the device:

- Location permission must be granted as **"Allow all the time"**, not "While using the app" — the latter stops feeding fixes the moment the app is backgrounded, regardless of the foreground service.
- Battery optimisation must be **Unrestricted** for the app — aggressive OEM battery managers (Samsung, Xiaomi, Huawei) can kill foreground services otherwise.
- A persistent notification showing live time / distance / pace (posted by `RunNotificationBridge` on geolocator's foreground-service channel) must be visible in the shade whenever recording is active. If it's absent, the foreground service (`geolocator_android`) did not start.

When the app returns from background, the Flutter UI resumes and the next snapshot repaints the screen with the latest accumulated state — no data is lost.

---

## Dependencies

From `apps/mobile_android/pubspec.yaml` — major-version baseline after the dep sweep:

| Purpose | Package | Version |
|---|---|---|
| GPS + foreground service | `geolocator` | ^14 |
| Map rendering | `flutter_map` + `latlong2` | ^8 / ^0.9 |
| Map tile HTTP cache | `flutter_map_cache` + `dio_cache_interceptor` | ^2 / ^4 |
| Step + cadence sensor | `pedometer` | ^4 |
| Audio cues | `flutter_tts` | ^4 |
| Screen on during run | `wakelock_plus` | ^1.2 |
| Location/motion permissions | `permission_handler` | ^12 |
| Connectivity triggers | `connectivity_plus` | ^7 |
| Env config | `flutter_dotenv` | ^6 |
| Stable run ids | `uuid` | ^4.5 |
| Local persistence | `path_provider` (+ JSON via `dart:convert`) | ^2.1 |

See [../apps/mobile_android/local_testing.md](../apps/mobile_android/local_testing.md#android-tech-stack) for the full stack.

---

## Tunable constants

All in `apps/mobile_android/lib/screens/run_screen.dart` unless noted.

| Constant | Default | Meaning |
|---|---|---|
| `_incrementalSaveInterval` | 10 s | Cadence of crash-safe persistence writes |
| `_gpsLostThreshold` | 10 s | Snapshot staleness that triggers the GPS-lost banner |
| `_gpsRetryInterval` (in `run_recorder.dart`) | 3 s | Cadence of the in-recorder retry loop that reopens the position stream after a service/permission outage |
| `_holdToStopDuration` | 800 ms | Hold time before the stop button fires |
| `_pedometerMaxRetries` | 5 | Exponential-backoff cap before giving up on pedometer |
| `_offRouteThresholdMetres` | 40 m | Distance from selected route that triggers off-route warning |
| `_positionTweenDuration` (in `live_run_map.dart`) | 900 ms | Dot interpolation tween length |
| `movingTimeOf`'s `minSpeedMps` (in `run_stats.dart`) | 0.5 m/s | Minimum speed to count toward derived moving time |
| `ActivityType.maxSpeedMps` (per-activity, in `preferences.dart`) | run 10 / walk 5 / cycle 25 / hike 6 | Speed clamp for dropping bad GPS fixes |
| `ActivityType.gpsDistanceFilter` (m) | run 3 / cycle 5 | Software track-append threshold |
| `ActivityType.minMovementMetres` (m) | run 2 / cycle 4 | Minimum delta to count as real motion |

---

## Known limitations

- **Line drift onto sidewalks/verges.** Consumer phone GPS is 3–8 m accurate under open sky, worse elsewhere. Smoothing reduces jitter but cannot correct bias. The real fix is backend map matching — tracked in the [roadmap](roadmap.md#future--map-matching-strava--nike-run-club-quality) as a self-hosted Valhalla / OSRM / GraphHopper deployment, post-run only.
- **Resume recording after a crash.** The current recovery path saves the partial as a completed run. It does not re-enter recording mode on the recovered data — that would require preserving the full recorder state machine across process death, which is out of scope for the current persistence shape.
- **Widget / integration test coverage.** Unit tests cover the `RunRecorder` state machine + filter chain + indoor-mode timer (17 tests in `packages/run_recorder/test/run_recorder_test.dart`), the `movingTimeOf` helper (8 tests in `apps/mobile_android/test/run_stats_test.dart`), and `LocalRunStore` persistence (14 tests in `apps/mobile_android/test/local_run_store_test.dart`) — see [testing.md](testing.md) for the full list. The recording UI (`run_screen.dart`, `live_run_map.dart`, `collapsible_panel.dart`) and the sync pipeline have no widget or integration tests yet. The GPS self-heal retry loop + typed errors thrown from `prepare()` are not unit-tested either — both would require injecting a mock `GeolocatorPlatform.instance`.
