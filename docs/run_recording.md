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

- **On tap Start**: `_beginCountdown` → `_ensurePermission` → `_preload`
- **`_preload` (t=0, countdown begins)**:
  - Create `RunRecorder`, subscribe to its `snapshots` stream
  - Subscribe to the pedometer stream (gated — step counts don't accrue until state is `recording`)
  - Enable `WakelockPlus`
  - Call `_recorder.prepare()` — opens GPS, starts foreground service, subscribes to position stream. Store the returned Future in `_prepareFuture`
- **Countdown timer ticks t=1, t=2**: UI only; no background work
- **`_begin` (t=3, countdown ends)**:
  - `await _prepareFuture` as a safety net (no-op in the common case — prepare is done by now)
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

---

## Data flow: recording a run

```
1.  User taps Start on the idle screen
2.  _ensurePermission() — request location + notifications if needed
3.  _beginCountdown() flips state to countdown and starts the 1s tick timer
4.  _preload() kicks off asynchronously:
    - RunRecorder created
    - snapshots subscription attached (→ _onSnapshot)
    - Pedometer stream subscribed (counts gated on recording state)
    - Wakelock enabled
    - _recorder.prepare() opens the GPS stream with a foreground service
      notification ("Run in progress") and begins receiving positions
5.  GPS fixes arriving during prepared update _currentWaypoint; snapshots
    drive the blue dot; elapsed stays at 0; track stays empty
6.  Countdown reaches 1 → _begin() runs:
    - Awaits _prepareFuture (no-op in the common case)
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

**`distanceFilter: 0`** is intentional. The OS-level `distanceFilter` gates position emission by physical distance — a value of 3 means no position until the device has physically moved 3 m. That starves the blue dot at slow walking speeds (the marker doesn't move until 3 m of accumulated motion crosses the threshold).

With `distanceFilter: 0` we receive every fix the sensor produces (~1 Hz on most Android chips) and do all the filtering in software below, which lets the dot refresh at sensor rate while still keeping the track clean.

### Filter chain

Every incoming `Position` goes through:

1. **Paused gate** — if `_paused`, drop (Stopwatch is also paused, so elapsed doesn't advance).
2. **Accuracy filter** — `pos.accuracy > 20` → drop. 20 m is a compromise between rejecting urban-canyon corruption and keeping sparse fixes alive.
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

### Display smoothing

In `live_run_map.dart`, `_smoothTrack` applies a 1-2-3-2-1 weighted moving average to the rendered polyline. Two passes are run before feeding the `PolylineLayer` stack. This reduces visible zig-zag at walking pace. It's **display-only** — the stored run keeps the raw waypoints, so stored distance/pace and GPX export are unaffected.

Smoothing cannot correct systematic offset from the road (GPS bias, not noise). For that see the [map matching roadmap entry](roadmap.md#future--map-matching-strava--nike-run-club-quality).

### NRC-style polyline

The live track is drawn as three stacked `PolylineLayer`s for a Nike-Run-Club-style glow:

1. **Outermost halo** — 18 px stroke, indigo at 18% alpha
2. **Mid halo** — 10 px stroke, indigo at 35% alpha
3. **Main line** — 6 px stroke, gradient from deep indigo (oldest) → pale lavender (newest), 2 px dark indigo border for contrast against dark map tiles

Rounded caps and joins are flutter_map's default. The gradient direction makes the line look like it's trailing behind a comet, brightening toward the blue dot.

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
- The **Run in progress** notification must be visible in the shade whenever recording is active. If it's not, the foreground service didn't start.

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
- **Widget / integration test coverage.** Unit tests cover the `RunRecorder` state machine + filter chain (14 tests in `packages/run_recorder/test/run_recorder_test.dart`), the `movingTimeOf` helper (8 tests in `apps/mobile_android/test/run_stats_test.dart`), and `LocalRunStore` persistence (14 tests in `apps/mobile_android/test/local_run_store_test.dart`) — see [testing.md](testing.md) for the full list. The recording UI (`run_screen.dart`, `live_run_map.dart`, `collapsible_panel.dart`) and the sync pipeline have no widget or integration tests yet. Adding widget tests for state transitions would be a good next move.
