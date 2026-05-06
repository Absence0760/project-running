# Testing

Authoritative reference for the test suite — where tests live, how to run them, patterns we use, and when to run what.

For the behaviour being tested, see [run_recording.md](run_recording.md). For how to run the app itself, see [../apps/mobile_android/local_testing.md](../apps/mobile_android/local_testing.md).

---

## TL;DR

```bash
# Run every Flutter test in the workspace (Melos 7 — see CLAUDE.md gotcha:
# the `melos run` script lookup is broken; use `melos exec` instead).
melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test
# (CI runs the same scopes — broader globs cost time without coverage.)

# Run one package's tests
cd apps/mobile_android && flutter test
cd packages/run_recorder && flutter test

# Run one file
flutter test test/run_stats_test.dart

# Run one group / test by name (substring match)
flutter test --plain-name "movingTimeOf"
flutter test --plain-name "speed clamp drops teleport-style jumps"

# Or regex match
flutter test --name "^position filter chain"

# Web (TypeScript) tests — from apps/web
npx tsx --test src/lib/training.test.ts

# Web e2e (Playwright) — from apps/web. Requires local Supabase
# running with seed.sql applied: cd apps/backend && supabase db reset.
pnpm test:e2e          # headless run
pnpm test:e2e:ui       # interactive picker
```

`flutter test` has no built-in `--watch` flag. For a tight edit-save-test loop, either rerun the single file manually (sub-second) or wire up an editor integration — the Flutter plugin for VS Code and Android Studio both support running individual tests from gutter icons and auto-re-running on save.

**When to run:**

- **While editing the file you're testing** — run that one test file (`flutter test test/foo_test.dart`). Sub-second feedback loop.
- **Before committing** — `melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test` across the workspace. Catches cross-package breakage.
- **Before pushing a PR** — `melos exec -- dart analyze && melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test`. Both must pass.
- **In CI** — both commands run automatically (see [architecture.md — CI/CD](architecture.md#cicd-pipeline)).

---

## What's covered today

Total: **~687 unique Dart mobile tests across 85 test files, executed by both mobile targets** (mobile_android and mobile_ios share a byte-for-byte identical Dart codebase — see the iOS / android `CLAUDE.md` files), plus 78 tests in run_recorder (across 5 files), 28 in api_client, 2 in core_models, **253 TypeScript unit tests across 20 files** in the web app, and **111 Playwright e2e tests across 51 files** that drive the real web app against a local Supabase. Both mobile apps run the same 85 test files; `flutter test` compiles them once per target, so end-to-end CI exercises ~1,374 mobile test runs. `recording_integration_test.dart` covers the data-pipeline golden path (GPS → recorder → LocalRunStore → SyncService → API) and `run_screen_recording_flow_test.dart` drives the corresponding UI flow (tap START → countdown → recording state with LiveRunMap mounted). No `integration_test`-package tests (device-instrumented) yet, no golden tests. Counts here are point-in-time — they drift fast. Run `grep -cE '^\s*(test|testWidgets)\(' apps/mobile_android/test/*.dart` for the live per-target count and `diff -rq apps/mobile_android/test apps/mobile_ios/test` to confirm the trees stay in lockstep.

Test files use **relative imports** (`import '../lib/widgets/run_photos.dart'`) instead of `package:mobile_android/...` so the same file resolves on both targets — both apps' pubspecs differ only in `name`, and the Dart analyzer would reject `package:mobile_android/...` when building the iOS target.

### `apps/mobile_android/test/run_stats_test.dart` — 13 tests

Pure-function tests for two helpers in `lib/run_stats.dart`:

**`movingTimeOf(track, {minSpeedMps})`** — the replacement for live auto-pause, so it's the most behaviourally important helper in the app. Covers:

- Empty / single-point tracks → `Duration.zero`
- Fast segments (≥ threshold) counted
- Slow segments (< threshold) excluded
- Mixed "running → long stop → running" — only the running segments counted
- Custom `minSpeedMps` override
- Waypoints without timestamps skipped
- Same-timestamp pairs (`dt == 0`) skipped
- Multi-segment summation

**`fastestWindowOf(track, windowMetres)`** — rolling-window scan behind the dashboard "Fastest 5k" PB. Regression-tests the scaled-average-pace bug it replaced (see `decisions.md`). Covers:

- Empty / short tracks → `null`
- Track shorter than window → `null`
- Even-paced 10 km → exact half-time (with 1 s interpolation slack)
- Slow → fast → slow run → picks the fast middle 5 km
- Regression: a 10 km in 1:14:34 does **not** surface as a 37:17 fastest 5k

### `packages/run_recorder/test/run_recorder_test.dart` — 18 tests

The recorder's state machine and GPS filter chain. Uses `@visibleForTesting` hooks (see below) to bypass the real geolocator stream and inject synthetic `Position` objects directly into `_onPosition`.

**State machine (4 tests):**
- Initial state is idle (`prepared == false`, `recording == false`)
- `debugPrepareWithoutStream` flips to prepared
- `begin()` before `prepare()` throws `StateError`
- `begin()` after prepare flips to recording

**Position filter chain (6 tests):**
- Positions during `prepared` update the dot but not the track
- First post-`begin` fix becomes the track anchor
- Accuracy filter (> 20 m) drops bad fixes
- Movement threshold (default 3 m) rejects sub-jitter deltas
- Real movement above threshold accumulates distance correctly
- Speed clamp drops implausible-speed fixes (≥ `maxSpeedMps`)
- Single-hop jump > 100 m rejected even when speed is plausible

**Pause / resume (3 tests):**
- Pause drops incoming positions entirely (track doesn't grow, distance doesn't accumulate)
- Resume clears `_lastTrackedPosition` so the pause-duration gap isn't counted
- `Stopwatch` stops during pause — asserted with `Future.delayed(50ms)` on both sides

**Indoor / no-GPS mode (3 tests):**
- `RunSnapshot.currentPosition` is nullable (construct with `null` and read back)
- The 1-second timer emits snapshots with `currentPosition: null` when `begin()` runs without any injected fix — the stopwatch ticks even for a treadmill run
- An injected fix after begin populates `currentWaypoint` normally (indoor → outdoor transition)

**Not covered (require mocking `GeolocatorPlatform.instance`):** typed errors thrown from `prepare()`, the `_gpsRetryTimer` retry loop, position-stream `onError` cleanup, `stop`/`dispose` cancelling the retry timer.

### `packages/run_recorder/test/calculate_pace_test.dart` — 8 tests

Tests for the rolling-pace helper exposed via `RunRecorder.debugPaceSecondsPerKm`. Pins the null returns (empty track, fewer than 5 points, total tracked distance below 50 m, paused state), pins the GPS-derived pace value (5 fixes 50 m apart at 10 s intervals → 200 s/km regardless of wall-clock), demonstrates the trailing-window slide (8 fixes with two slow opening segments + six fast trailing segments still yields a fast pace because the early slow part falls outside the ~200 m window), and asserts the snapshot stream's `currentPaceSecondsPerKm` matches `debugPaceSecondsPerKm`.

When the test was first written, `_currentWaypoint.timestamp` was set from `DateTime.now()`; a tight inject loop collapsed all five waypoint timestamps to the same millisecond, and `_calculatePace` returned null because `segmentTime <= 0`. The recorder was changed to `pos.timestamp` for the waypoint timestamp (matching the speed-clamp's GPS-time policy) so the function works correctly under fix-batching / CPU contention. See § Troubleshooting.

### `packages/run_recorder/test/route_helpers_test.dart` — 17 tests

Tests for `_routeRemaining` and `_offRouteDistance` exposed via `debugRouteRemaining` / `debugOffRouteDistance`. Routes are constructed at the equator so equirectangular projection (used for the perpendicular-distance and segment-projection math) and haversine (used to total segment lengths) align to within ~0.5 m for the 0.001°-spaced fixtures. `_routeRemaining` block (9 tests): null returns (no route, single-waypoint route), at start = full length, at segment midpoint = unwalked tail, on the boundary between segments = total minus the first leg, at end ≈ 0, past end clamps to 0, perpendicular offset projects onto the nearest segment, multi-segment route sums correctly. `_offRouteDistance` block (8 tests): null returns, on a waypoint ≈ 0, inline along the route ≈ 0, perpendicular offset returns the perpendicular distance, past the end returns distance to the last waypoint, multi-segment route picks the closest segment, degenerate zero-length waypoint pair is tolerated.

### `packages/run_recorder/test/laps_serialiser_test.dart` — 6 tests

Round-trips the canonical `metadata.laps` shape through `lapsToCanonicalJson` and `parseLapsFromJson`. Pins the per-lap-delta fields (1-based `index`, `start_offset_s` cumulative-BEFORE, `distance_m` + `duration_s` per-lap deltas) so a refactor of the serialiser can't quietly regress the cross-platform contract. Ties into the watch-payload fixture test on every platform — see [§ Cross-platform fixture contract](manual_testing.md#cross-platform-fixture-contract) in the manual testing guide.

### `packages/run_recorder/test/architecture_guards_test.dart` — 7 tests

Static source-level guards on the recorder package itself: no banned imports, no `print` in production, the public-API surface stays minimal, etc. Same shape as `apps/mobile_android/test/architecture_guards_test.dart` — read the `reason:` strings before rubber-stamping a fix; failures usually mean a recent change reversed an optimisation we deliberately codified.

### `packages/run_recorder/test/workout_runner_test.dart` — 13 tests

The structured-workout step engine — step expansion (warmup → reps → recovery → cooldown), auto-advance, halfway / last-50 m progress signals, skip / abandon, and pace-adherence "wayBehind" classification. See [workout_execution.md](workout_execution.md) for the runner state machine + UI contract.

### `packages/run_recorder/test/geolocator_platform_fake_test.dart` — 8 tests

Closes the documented "typed errors thrown from `prepare()`" gap. Replaces `GeolocatorPlatform.instance` with a fake that extends `GeolocatorPlatform` (so `PlatformInterface.verify` passes) and exposes setters for `serviceEnabled` / `permissionState` / `requestPermissionResult` plus an `emit(Position)` and `emitError(Object)` method that pushes through the live position stream. The error-path tests cover `LocationServiceDisabledError` when services are off, `LocationPermissionDeniedError(forever: false)` when the request returns denied, and `LocationPermissionDeniedError(forever: true)` when permission is denied-forever — plus the "already granted" path that skips the request. The happy-path tests cover `prepare()` opening the position stream, positions flowing through the filter chain (pre-begin updates the dot but not the track; post-begin first fix becomes the track anchor; subsequent fixes accumulate distance), stream `onError` not crashing the recorder, and `dispose()` cancelling the subscription so subsequent emits don't extend the track.

### `apps/mobile_android/test/local_run_store_test.dart` — 23 tests

Persistence round-trips against a real temporary filesystem directory. Tests inject a tempDir via `LocalRunStore.init(overrideDirectory: ...)` so they never touch `path_provider` or the platform channel.

**Completed runs (5 tests):**
- Empty-directory init
- Save → load round-trip across fresh store instances (crash-simulation)
- `save` stamps `last_modified_at` and marks unsynced
- `markSynced` flips state
- `delete` removes from memory and disk

**In-progress save (7 tests):**
- `saveInProgress` creates the file
- `loadInProgress` round-trip preserves all fields
- `loadInProgress` returns null when no file
- `clearInProgress` removes the file
- **`_loadAll` ignores `in_progress.json`** — the key invariant that keeps partials out of the run list
- Corrupt in-progress file deleted instead of crashing
- Repeat saves overwrite previous content

**Edge cases (2 tests):**
- Corrupt `.json` file in the directory is tolerated during init (skipped)
- Multi-run init sorts newest-first by `startedAt`

### `apps/mobile_android/test/strava_importer_zip_test.dart` — 21 tests

Comprehensive coverage for `StravaImporter.importFromZip`. Complements the smaller `importer_external_id_test.dart` (which only pinned the `external_id` prefix). Each test builds an in-memory zip with the `activities.csv` + a track file, then asserts on the resulting `Run`.

**Activity-type derivation (6 tests):** `Run`/`Walk`/`Hike` map directly, `Trail Running` still maps to `run`, case-insensitive (`WALKING` → `walk`), unknown activity type falls back to `run`.

**CSV column handling (6 tests):** missing `activities.csv` throws, missing `Filename` column throws, missing `Activity Date` column throws, header-only CSV → empty result with no errors, row with empty filename silently skipped, the `Distance (km)` header variant is recognised.

**Multi-row imports (3 tests):** multiple activities import as separate runs, one missing track file errors per-file but the rest still import, an unknown track extension is reported as a per-file error.

**Distance + duration fallback (3 tests):** distance falls back to CSV when GPX has no waypoints, duration falls back to CSV elapsed when track has fewer than 2 waypoints, duration uses GPX timestamps when CSV elapsed is 0 (regression for the "GPX `<time>` was never parsed" bug).

**Metadata + compression (3 tests):** `imported_from`/`strava_activity_type`/`title`/`activity_type`/`imported_at` populate, blank activity name falls back to "Strava import", `.gpx.gz` is decompressed before parsing.

### `apps/mobile_android/test/settings_sync_test.dart` — 18 tests

Covers the universal-bag and device-bag overlay logic on `SettingsSyncService` via two new `@visibleForTesting` delegates (`debugApplyUniversal`, `debugApplyDevice`). The applied-bag flow is the substantive logic — `pushX` / `updateX` are passthroughs to `SettingsService` which needs Supabase to test. Uses a real `Preferences` instance backed by `SharedPreferences.setMockInitialValues({})`.

**Universal bag (9 tests):** `preferred_unit` ("mi" → `useMiles=true`, "km" → false, integer-typed value ignored), `default_activity_type` (string updates local default, empty string rejected), `weekly_mileage_goal_m` (seeds a weekly distance goal when none exists, does NOT replace an existing one — the dashboard editor wins on edit, zero / negative values ignored), empty bag is a no-op, unknown keys ignored.

**Device bag (6 tests):** `voice_feedback_enabled` flips `audioCues`, `voice_feedback_interval_km` maps to `splitIntervalMetres` for both double and integer-typed values, non-bool `voice_feedback_enabled` is ignored, `keep_screen_on` round-trips, empty device bag is a no-op.

**Initial state (2 tests):** `synced` is false and `service` is null before `onSignedIn`, every `pushX` / `updateX` is a no-op while settings is null (so a UI handler can safely call them before sign-in).

### `apps/mobile_android/test/backup_test.dart` — 20 tests

Covers `BackupService.restore` on the offline path (no Supabase session — runs hydrate into `LocalRunStore` and `LocalRouteStore`, ready for `SyncService` to push once the user signs in). Builds synthetic backup zips in-memory using `package:archive` so the tests don't need a real backup file on disk. Initialises Supabase with the same fake-URL pattern the screen tests use (`http://127.0.0.1:54321`) so `BackupService(api: _OfflineApi())` can construct without hitting the network.

**Manifest validation (4 tests):** missing manifest throws, mismatched `format` throws, version-too-new throws (forward-compat guard), current version is accepted.

**Offline restore — runs (9 tests):** empty `runs.json` is a no-op, single run preserves id, missing `activity_type` defaults to `'run'` (matches the DB CHECK), explicit `activity_type` is preserved, gzipped track decodes onto `Run.track` with elevation + UTC timestamps intact, unknown `source` falls back to `RunSource.app`, `generateNewIds` actually replaces ids, non-Map entries are silently skipped, malformed rows surface in `result.warnings` without poisoning the rest.

**Offline restore — routes (4 tests):** waypoints preserved with elevation, null `name` falls back to `'Route'`, `generateNewIds` replaces route ids, non-Map waypoint entries inside a route are silently skipped.

**Guards + progress (3 tests):** offline restore with neither store supplied throws; supplying only `routeStore` leaves a warning that the run branch was skipped; the `onProgress` callback emits `reading → … → done` stages.

The online path (`api.fetchRunRowsRaw` + Storage uploads) still needs a fake `SupabaseClient` to test, same constraint as the rest of `ApiClient`'s wire-level methods.

### `apps/mobile_android/test/run_screen_recording_flow_test.dart` — 5 tests

Drives the full RunScreen UI flow on top of the existing data-pipeline integration test. Adds a mock-everything setUp that closes every platform-channel surface RunScreen touches when transitioning out of idle:

- `GeolocatorPlatform.instance` — fake (extends the platform interface).
- `WakelockPlusPlatformInterface.instance` — no-op subclass.
- MethodChannel `flutter.baseflow.com/permissions/methods` — returns "granted".
- MethodChannel `flutter_tts` — returns success.
- MethodChannel `run_app/run_notification` — returns null (lock-screen update channel).
- EventChannels `step_count` and `step_detection` (pedometer) — silent streams via the underlying MethodChannel `listen` / `cancel`.
- `dotenv.loadFromString(isOptional: true)` so LiveRunMap's MAPTILER_KEY lookup doesn't throw `NotInitializedError` when the recording state mounts the map.

Tests: tapping START transitions the screen into countdown state (text "3" appears, START button gone); the countdown ticks 3 → 2 → 1 across three seconds (Timer.periodic at 1 Hz); after the countdown elapses the screen leaves countdown state (the large "3" is no longer the focal text); LiveRunMap mounts once recording begins (the invariant from `run_screen_test.dart` flips after `_begin()`); positions emitted by the geolocator fake during recording flow into the recorder without throwing.

The test stops short of tapping Finish + asserting save — that flow does an animated transition + a Storage upload that needs a real Supabase client. The data-pipeline equivalent is covered by `recording_integration_test.dart`.

### `apps/mobile_android/test/recording_integration_test.dart` — 3 tests

Integration test for the GPS → record → save → sync golden path. Reuses the `_FakeGeolocatorPlatform` pattern from `packages/run_recorder/test/geolocator_platform_fake_test.dart` (extends `GeolocatorPlatform` and feeds synthetic positions). Drives the full pipeline:

1. `RunRecorder` consumes the synthetic feed through the real `prepare()` → `begin()` → filter chain.
2. The recorded track is persisted to a `LocalRunStore` rooted at a fresh tempDir.
3. `SyncService.debugTrySync` drains the unsynced run through a capturing `_CapturingApiClient` that records the batch.

Three scenarios: the happy-path full pipeline (GPS feed → recorder → store → sync → API), a stream error mid-recording (recorder cancels its subscription on error; the partial track is still saveable), and the offline path (api null → run stays unsynced for a later attempt).

Stops short of driving the full `RunScreen` UI, which would need additional mocks for Pedometer / WakelockPlus / flutter_tts / flutter_local_notifications. The data pipeline is the regression target — UI mocking is documented as a follow-up below.

### `apps/mobile_android/test/sync_service_test.dart` — 19 tests

Covers the `_trySync` loop on `SyncService` via the new `@visibleForTesting debugTrySync` hook. A `_FakeApiClient` subclasses `ApiClient` and overrides `userId`, `saveRunsBatch`, and `deleteRunById`; `LocalRunStore` runs against a real `tempDir` (same pattern as `local_run_store_test.dart`).

**Guard clauses (3 tests):** no-op when `apiClient` is null, no-op when not signed in (`userId == null`), no-op when there is nothing to do.

**Push path (2 tests):** every unsynced run goes through one `saveRunsBatch` call and is marked synced afterwards, and a `saveRunsBatch` failure is swallowed without flipping the unsynced flag.

**Pending-delete drain (3 tests):** a successful delete removes the row from cloud / local / pending set, one failing delete does not poison the rest of the queue (others still drain), and `deleteRunById` is called once per pending id.

**Combined paths (2 tests):** a single tick handles both an unsynced push and a pending-delete drain in one cycle, and a reentrant call landing while a sync is in flight short-circuits on the `_syncing` guard so the batch isn't pushed twice.

**Lifecycle wiring (2 tests):** `didChangeAppLifecycleState(resumed)` triggers a sync; `paused` / `inactive` / `detached` do not.

**Connectivity wiring (5 tests):** drives the connectivity branch directly via `@visibleForTesting debugOnConnectivity`. `[wifi]` triggers a sync; `[mobile]` and `[ethernet]` also trigger; `[none]` and `[bluetooth]` alone do not; multi-result lists with at least one online entry fire (the common Android shape). Pins the guard policy: bluetooth-tethering is intentionally excluded from the "online" set since it isn't routable for upload.

**start / stop (2 tests):** `start()` registers as a binding observer, fires the startup `_trySync`, and routes subsequent lifecycle events through the observer. `stop()` removes the observer so further binding-level resume events don't fire syncs.

### `apps/mobile_android/test/local_route_store_test.dart` — 16 tests

Persistence tests for `LocalRouteStore` mirroring the `local_run_store_test.dart` pattern — `init(overrideDirectory: ...)` with a tempDir, real file I/O, no mocks. Covers init (directory creation, non-`.json` file filtering, corrupt-file tolerance), save (file write, round-trip across fresh instances, replace-on-same-id, newest-first ordering, single-listener-call invariant), `saveBatch` (parallel write + single notify, empty-iterable no-op, overlapping-id replace), `delete` (disk + memory + unknown-id), and the unmodifiable `routes` view.

### `apps/mobile_android/test/track_smoother_test.dart` — 9 tests

Pure-function tests for the top-level `smoothTrack(List<LatLng>)` helper extracted from `widgets/live_run_map.dart` (1-2-3-2-1 weighted polyline smoother used to reduce GPS jitter on the live map). Pins: short-track passthrough (length < 5), first-two-and-last-two preservation, the explicit `(a + 2b + 3c + 2d + e) / 9` weighted-mean formula, co-linear evenly-spaced points are unchanged, the no-mutation contract (returns a new list), length-0/1 inputs handled, length-5 input smooths exactly index 2, and constant-coordinate input (weights sum to 9) returns its input.

### `apps/mobile_android/test/period_summary_test.dart` — 23 tests

Pure-function tests for the period summary screen's extracted helpers in `lib/screens/period_summary_screen.dart`:

**`periodStart` / `periodEnd` (5 tests):**
- Week: Monday 00:00 for any day in the week
- Month: 1st of the month; end is 1st of next month
- December → January year rollover

**`periodTitle` / `periodLabel` (4 tests):**
- Week: "Week of 13 Apr" format
- Month: "November 2026" format
- Label date ranges

**`computePeriodStats` (4 tests):**
- Empty list → zeroes and null pace
- Single run → correct totals and pace
- Multiple runs → aggregated correctly
- Very short distance → null pace (below 10 m threshold)

**`buildPeriodShareText` (4 tests):**
- Includes title, count, distance, pace, per-run lines
- Singular "run" for count of 1
- Empty runs omits per-run section and pace
- Respects miles unit preference

**Formatting helpers (6 tests):**
- `formatDurationCoarse`: minutes+seconds, hours+minutes, exact hours, zero
- `shortDate`: day + abbreviated month
- `monthName`: full month name for all positions

### `apps/mobile_android/test/goals_test.dart` — 20 tests

Pure-function tests for `evaluateGoal` and `RunGoal` JSON serialisation in `lib/goals.dart`:

- Period bounds (week start = Monday 00:00, month end wraps to next year)
- Distance target: empty list, runs outside period, sum, goal reached, ahead/behind pace
- Avg pace target: cycling-only runs excluded, meeting/exceeding/missing target, distance-weighted
- Run count and time targets
- Multi-target goal: each target evaluated independently, overall complete only when all met
- `RunGoal.toJson` / `fromJson` round-trip, legacy single-target migration

### `apps/mobile_android/test/fit_export_test.dart` — 3 tests

Round-trips the `lib/fit_export.dart` writer that produces FIT files for sharing recorded runs to Garmin Connect / TrainingPeaks. Pins the binary header layout (`.FIT` magic, protocol version, profile version, data record schema) and a small synthetic-track encode → decode → equality assertion.

### `apps/mobile_android/test/route_simplify_test.dart` — 8 tests

Tests for Ramer-Douglas-Peucker track simplification in `lib/route_simplify.dart`:

- Fewer than 3 points returned unchanged
- Collinear points dropped
- `computeElevationGain` accumulates only positive deltas

### `apps/mobile_android/test/ble_heart_rate_test.dart` — 9 tests

Pure-function tests for `parseBleHeartRateMeasurement` in `lib/ble_heart_rate.dart`, the BLE Heart Rate Service characteristic 0x2A37 parser:

- 8-bit BPM decoding (flags byte with various sensor-contact + EE bits)
- 16-bit BPM little-endian decoding
- 16-bit at low value (some straps always report 16-bit)
- Empty payload returns null
- Truncated payload returns null
- Single-byte payload returns null

### `apps/mobile_android/test/training_test.dart` — 18 tests

Dart mirror of `apps/web/src/lib/training.test.ts`. The Dart engine (`lib/training.dart`) must produce the same paces and phase assignments as the TypeScript engine for the same inputs. Covers the same functions:

- `vdotFromRace`: 3 tests (VDOT 50, VDOT 54, faster = higher)
- `riegelPredict`: 2 tests (identity, projection)
- `pacesFromGoalPace`: 2 tests (zone ordering, 4:00/km band)
- `resolveTrainingPaces`: 2 tests (recent 5k anchor, fallback)
- `phaseFor`: 2 tests (phase splits, final week)
- `generatePlan`: 7 tests (week count, day distribution, taper volume, race week, intervals, no-input fallback, stepback)

### `apps/mobile_android/test/training_load_test.dart` — 10 tests

Dart mirror of `apps/web/src/lib/training_load.test.ts`. The Dart engine (`lib/training_load.dart`) must produce the same Fitness / Fatigue / Form curves as the TypeScript engine for the same inputs. Covers `computeStress` (distance fallback ~50 for an easy 5k, TRIMP path lights up with `avg_bpm` + resting + max, zero-input → 0), `aggregateDailyStress` (sums same-day runs), `computeTrainingLoadSeries` (emits exactly `windowDays` entries, TSB rises during a 14-day taper, all-zero with no runs), and `hasTrimpSignal` (no `avg_bpm` / has `avg_bpm` + prefs / prefs missing).

### `apps/mobile_android/test/segments_test.dart` — 8 tests

Dart mirror of `apps/web/src/lib/segments.test.ts`. Pure tests for the segment-effort walker in `lib/segments.dart#computeEffortFromTrack`. Same `straightTrack` synthetic helper (meridian-aligned, constant pace) so haversine cumulative distance is predictable. Covers a clean segment, run shorter than segment end, sub-2-point tracks, zero / negative segment windows, sparse-sampling guard (median step > segLen / 5), missing timestamps in the interpolation bracket, mid-segment interpolation, and sample-aligned endpoints.

### `apps/mobile_android/test/privacy_test.dart` — 8 tests

Dart mirror of `apps/web/src/lib/privacy.test.ts`. Pure tests for `lib/privacy.dart`. Covers `isInAnyZone` (empty zones, centre, far point) and `clipPointsToZones` (empty zones returns input, drops leading + trailing in-zone, keeps interior, every-point-in-zone returns empty, multi-zone union).

### `apps/mobile_android/test/run_photos_helpers_test.dart` — 9 tests

Pure-function tests for two top-level helpers in `lib/widgets/run_photos.dart` extracted so the Storage-extension and content-type logic could be exercised without a `WidgetTester`. `extensionForFilename` covers the normal lowercase return, the `jpeg → jpg` and `heif → heic` collapses, the no-extension default, the leading-dot dotfile case, and the multi-dot trailing-extension case. `contentTypeForExtension` covers the explicit `image/png|webp|heic` branches and the `image/jpeg` fallback (jpg + unknown).

### `apps/mobile_android/test/coach_screen_helpers_test.dart` — 19 tests

Pure-function tests for the three top-level helpers in `lib/screens/coach_screen.dart`: `coachTitleFromMessage` (verbatim under 48 chars, whitespace collapse, leading/trailing trim, ellipsis past the cap, exact-48 vs 49 boundary), `coachArchiveLabel` ("Today" same day, "Yesterday" 1 day, "N days ago" 2..6, `YYYY-MM-DD` past a week, zero-padded month and day), and `parseCoachSseEvent` (event + data block parsing for `meta` / `token` / `done`, null when the block has no data line, null on invalid JSON, null on non-Map JSON, default `event: 'message'` when no event line, multi-line `data:` concatenation, `done` block with `cache` usage stats).

### Screen + widget smoke tests — ~48 files, ~178 testWidgets calls

After the April 2026 mobile-codebase unification, every screen and most user-facing widgets gained a smoke test (including `RunScreen` and `LiveRunMap`, which were previously the documented gaps). Each one verifies the *initial render* surface — app-bar title, primary action visibility, loading-spinner-vs-error fork — without exercising the post-fetch state, since none of these tests have a mockable Supabase backend. Tests that need a real `ApiClient` use a `setUpAll` helper that calls `Supabase.initialize(url: 'http://127.0.0.1:54321', anonKey: 'eyJ.local.test')` plus `SharedPreferences.setMockInitialValues({})` — the fake URL is never reached because each screen catches the connection failure into an ErrorState.

The widget-test files outgrew the original "(4 files)" headline as we mirrored web features back into mobile. The current canonical list — easier to keep accurate than to maintain by hand — is `for f in apps/mobile_android/test/*_test.dart; do c=$(grep -cE '^\s*testWidgets\(' "$f"); [ "$c" -gt 0 ] && printf "%4d  %s\n" "$c" "$(basename $f)"; done | sort -rn`. As of this edit there are ~19 screen-test files and ~19 widget-test files. Notable widget tests added since the original group: `error_state_test.dart` (5), `live_run_map_test.dart` (3), `plan_calendar_test.dart`, `route_share_card_test.dart`, `run_screen_test.dart`, `goal_editor_sheet_test.dart`, `workout_execution_band_test.dart`, `workout_review_section_test.dart`, `fitness_card_test.dart`, `todays_workout_card_test.dart`, `upcoming_event_card_test.dart`, `run_share_card_test.dart`, `import_screen_test.dart`, `home_screen_test.dart`.

- **Form sheets (2 files):** `showClubFormSheet` + `showEventFormSheet` — open the sheet from a launcher widget at `600x1200` test viewport (default `600x800` clips the bottom of the modal column).

### Pure-helper extractions — 4 files, ~55 tests

Several private formatters were extracted from stateful classes into top-level pure functions so they can be tested without booting their host (TTS, queue IO, importer ZIP path). The original private static methods are kept as one-line delegates so the runtime call paths are unchanged.

- **`preferences_helpers_test.dart` (21 tests):** `UnitFormat.distance` / `distanceValue` / `distanceLabel`, `pace` / `paceLabel`, `distanceTicks`, `activityTicks`, `speed` / `speedLabel`; `ActivityType.label` / `usesSpeed` / `kcalPerKgPerKm` / `splitIntervalMetres` / `gpsDistanceFilter`.
- **`audio_cues_helpers_test.dart` (15 tests):** `formatSpeedUtterance`, `formatPaceUtterance`, `formatSpokenDistance`, `formatWorkoutStepUtterance` — covers the km / mi forks, the empty-string fallback for null pace, integer-vs-fractional km wording, and the rep / warmup / recovery / steady / cooldown intros.
- **`strava_importer_helpers_test.dart` (9 tests):** `parseStravaDate` — ISO 8601 fast path, `"Apr 9, 2026, 7:30:00 AM"` canonical Strava format, AM/PM noon and midnight edges, case-insensitive month, long month names, null fallback for unparseable input.
- **`watch_ingest_queue_helpers_test.dart` (10 tests):** `runFromWatchPayload` + `parseRunSource` — required-fields happy path, missing id / source defaults, optional track waypoints with elevation + timestamp, non-Map track entries skipped, avg_bpm + activity_type promoted into Run.metadata, metadata stays null when neither is set, non-numeric avg_bpm ignored, unknown source falls back to RunSource.watch.
- **`watch_payload_fixture_test.dart` (5 tests):** Cross-platform contract test against `fixtures/watch_run_payload.json`. Decodes the same canonical fixture the Wear OS Kotlin test (`apps/watch_wear/.../WatchRunPayloadFixtureTest.kt`) and the web test (`apps/web/src/lib/watch_payload_fixture.test.ts`) read; asserts row fields match `expectedRow`, `metadata.activity_type` / `avg_bpm` / `laps` round-trip, per-point `bpm` survives the decoder, and the canonical lap shape is preserved. Editing the fixture without updating all three platform tests is a deliberate hard-fail.

### `apps/mobile_ios/test/` — same 83 files, byte-for-byte

After the April 2026 mobile-codebase unification, `apps/mobile_ios/test/` is kept identical to `apps/mobile_android/test/` via `diff -rq`. Every test file documented above runs on the iOS target too. Per-target counts: `flutter test` compiles separately, so each test file is executed twice when you run both apps. Don't add iOS-specific test files — every test belongs in both apps. The architecture-guard tests under `apps/mobile_android/test/architecture_guards_test.dart` read `lib/screens/run_screen.dart` from the working directory, so they pin the same invariants on both targets.

### `packages/api_client/test/api_client_di_test.dart` — 4 tests

Smoke tests for the `@visibleForTesting ApiClient.withClient(SupabaseClient)` named constructor — the DI seam that lets tests inject a fake `SupabaseClient` without booting `Supabase.initialize`. Pins: `userId` reads from the injected client (null when not signed in), `userEmail` reads from the injected client, two `withClient` instances stay independent (the override is an instance field, not static), and the default `ApiClient()` constructor still falls back to the global (which throws when `Supabase.initialize` hasn't run — the throw is the test value, confirming the seam only fires for `withClient`).

### `packages/api_client/test/api_client_codecs_test.dart` — 24 tests

Covers the four pure helpers on `ApiClient` exposed via `@visibleForTesting` static accessors (`debugWaypointToJson`, `debugWaypointFromJson`, `debugRunFromRow`, `debugRouteFromRow`). The methods drive the wire format for the gzipped track blob in the `runs` Storage bucket and the row-to-domain conversion that powers every list / detail screen — code that previously had no direct coverage because it hides behind `Supabase.instance.client`.

**Waypoint codec (7 tests):** round-trip with all optional fields, timestamp encodes UTC ISO 8601, local-time timestamps are normalised to UTC on encode, omits `bpm` key when `null`, decodes integer-typed `lat`/`lng` into `double`, treats `null`-vs-absent `ele` the same, malformed timestamp falls back to `null` (via `DateTime.tryParse`).

**`debugRunFromRow` (8 tests):** basic field mapping, `track_url` stashed onto `metadata` for lazy-fetch by callers, null metadata + null `track_url` leaves `Run.metadata` null, existing metadata keys survive alongside the stashed `track_url`, every `RunSource` value parses correctly, unknown `source` falls back to `RunSource.app` (matches the [`apps/web/src/lib/types.test.ts`](../apps/web/src/lib/types.test.ts) defensive contract), `externalId` and `createdAt` pass through.

**`debugRouteFromRow` (9 tests):** basic field mapping, null `elevation_m` collapses to `0` (not null), explicit `elevation_m` is preserved, null `is_public` is treated as `false`, explicit `is_public=true` round-trips, `tags` pass through verbatim, `featured` + `run_count` + `is_starred` populate as expected, waypoint elevation passes through (or is null when absent).

The tests run under `flutter test` because `api_client` transitively depends on `supabase_flutter` (which pins Flutter); the test bodies themselves use only `package:test/test.dart`.

### `packages/gpx_parser/test/route_parser_test.dart` — 25 tests

Pure-parser coverage for `RouteParser` (GPX/KML/TCX/GeoJSON) and `FitParser`. GPX block (9 tests): `<trkpt>` happy path with elevation gain summed correctly, `<rtept>` and `<wpt>` fallbacks when no track points, malformed `lat="bad"` skipped, `name` defaults to "Imported route", elevation gain ignores descents, `<time>` parsed onto `Waypoint.timestamp`, missing `<time>` leaves it null, empty document returns an empty waypoint list. KML block (4 tests): LineString with elevation, missing `<coordinates>` element, non-numeric triples dropped, 2D coordinates leave elevation null. TCX block (3 tests): `<Trackpoint><Position>` with altitude + timestamps, missing `<Position>` skipped, `<Notes>` fallback when `<Name>` is absent. GeoJSON block (5 tests): `[lng, lat, ele]` order, 2D coordinates, missing geometry, missing `properties.name`, malformed coordinate entries skipped. FIT block (4 tests): too-short bytes throw, `.FIT` signature mismatch throws, header size other than 12/14 throws, valid empty header parses to an empty route.

### `packages/core_models/test/run_source_test.dart` — 2 tests

Regression for the `RunSource.watch` enum-map regen. Constructs a `Run` with `source: RunSource.watch`, asserts `toJson()['source'] == 'watch'` and `fromJson({'source': 'watch'}).source == RunSource.watch`. Existed to catch the crash that would otherwise hit `_$RunSourceEnumMap[instance.source]!` on any serialisation of a watch-originated run.

### `apps/web/src/lib/training.test.ts` — 29 tests

TypeScript unit tests for the training plan engine, written against Node's `node:test` API (no test runner dependency). Run with `npx tsx --test src/lib/training.test.ts` from `apps/web`.

**`vdotFromRace` (3 tests):**
- 20-min 5k yields ~VDOT 50
- 3:00 marathon yields ~VDOT 54
- Slower runners get lower VDOT

**`riegelPredict` (3 tests):**
- 20-min 5k projects to ~41-42 min 10k
- Identity for same distance
- Longer target means longer predicted time

**`pacesFromGoalPace` (2 tests):**
- Zones ordered slow to fast
- 4:00/km goal yields easy pace in the 4:30-5:15 band

**`resolveTrainingPaces` (3 tests):**
- Recent 5k beats goal time as pace anchor
- Fall-back without race data produces valid paces
- Marathon-only goal time yields a valid pace set

**`phaseFor` (2 tests):**
- 16-week plan splits ~30/40/20/10 base/build/peak/taper
- Final week is always race

**`generatePlan` (8 tests):**
- Correct number of weeks produced
- 4-day plan has 3 runs + 1 long per week in base
- Taper weeks have lower volume than peak
- Race week ends with a race-kind workout
- Build-phase intervals have structured interval data
- No recent 5k + no goal still produces a plan
- Weekly volume steps back every 4th week
- Regression: every workout has a `kind` (null-kind race-week bug)

**`GOAL_DISTANCES_M` (1 test):**
- Half marathon constant is within 1m of 21.0975km

**`formatISO` (3 tests):**
- Returns local-tz components, not UTC
- Zero-pads single-digit month and day
- `shiftPeriod` by 7 days lands on the same weekday

**`isWorkoutCompleted` (4 tests):**
- False when neither flag set
- True when a run is linked
- True when manually marked
- True when both set

### `apps/web/src/lib/segments.test.ts` — 8 tests

TypeScript unit tests for the pure segment-effort compute (`lib/segments.ts`, decisions §37). Run with `npx tsx --test src/lib/segments.test.ts` from `apps/web`. Covers `computeEffortFromTrack`:

- Computes elapsed time over a clean segment (5 m/s straight-line track, 500m segment ≈ 100s).
- Returns null when the run is shorter than the segment end.
- Returns null on tracks shorter than two points.
- Returns null on zero or negative-length segment windows.
- Rejects sparse sampling (median step > segment / 5 — the §37 trade-off-2 guard).
- Returns null when adjacent track points lack timestamps in the bracket.
- Interpolates start and end timestamps mid-segment.
- Handles tracks where segment endpoints align with sample crossings.

The synthetic `straightTrack` helper builds a meridian-aligned sequence of `(lat, lng, ts)` so haversine cumulative distance matches `(i * stepM)` to within ~0.5m.

### `apps/web/src/lib/privacy.test.ts` — 8 tests

TypeScript unit tests for the pure privacy-zone clipper (`lib/privacy.ts`, decisions §33). Run with `npx tsx --test src/lib/privacy.test.ts` from `apps/web`.

**`isInAnyZone` (3 tests):**
- Empty zones returns false
- A point at a zone's centre is inside
- A far-away point is not

**`clipPointsToZones` (5 tests):**
- Empty zones returns input unchanged
- Drops a leading prefix and a trailing suffix that are entirely inside zones
- Keeps interior in-zone segments (v1 only clips the ends — see source comment)
- Every point in a zone returns empty
- Multiple zones — clips against the union

The pure-JS clipper drives owner-side previews; non-owner viewers go through the `clip_track_for_user` SECURITY DEFINER RPC so zones never leave the database.

### `apps/web/src/lib/training_load.test.ts` — 10 tests

TypeScript unit tests for the training-load curves (`lib/training_load.ts`, decisions §34). Run with `npx tsx --test src/lib/training_load.test.ts` from `apps/web`.

**`computeStress` (3 tests):**
- Distance-fallback path gives ~50 for an easy 5K
- TRIMP path lights up when avg_bpm + resting + max are all set
- Zero distance + zero duration gives 0

**`aggregateDailyStress` (1 test):**
- Sums same-day runs into one daily bucket

**`computeTrainingLoadSeries` (3 tests):**
- Emits exactly `windowDays` entries
- TSB rises during a taper (no runs after a heavy build)
- Series is all-zero when there are no runs

**`hasTrimpSignal` (3 tests):**
- False when no run has avg_bpm
- True when at least one run has avg_bpm and prefs are set
- False when prefs are missing

The TrainingLoadChart component on `/dashboard` renders the three series; `hasTrimpSignal` flips the chart's "TRIMP / distance proxy" subtitle.

**Test-runner constraint:** `tsx --test` runs raw TypeScript through the Node loader and does not understand Svelte runes. That means `*.svelte.ts` modules (`units.svelte.ts`, `stores/auth.svelte.ts`, `stores/toast.svelte.ts`) cannot be imported — the `$state(...)` call at module load fails with `ReferenceError: $state is not defined`. Keep test-targeted modules (`training.ts`, `fitness.ts`, etc.) free of imports from `.svelte.ts` files. The unit-aware formatters `fmtKm` / `fmtPace` live in `units.svelte.ts` for that reason; UI code imports them from `$lib/units.svelte` directly. Adding vitest with the Svelte plugin would lift this restriction — not done yet.

### `apps/web/src/lib/types.test.ts` — 6 tests

`parseRunSource` defensive-fallback contract — every valid `RunSource` value passes through; null, undefined, empty string, unknown string, and case-mismatched input all fall back to `'app'`.

### `apps/web/src/lib/route_simplify.test.ts` — 10 tests

Mirror of `apps/mobile_android/test/route_simplify_test.dart`. Pure tests for the Ramer-Douglas-Peucker simplifier in `lib/route_simplify.ts`. Covers the short-track passthrough (< 3 points), the clean straight-line collapse to two endpoints, sharp-corner preservation above epsilon, sub-epsilon jitter collapse on a straight line, the first/last retention contract, the no-mutation guarantee, and `computeElevationGain` (positive-delta-only sum, descending-only profile = 0, null-elevation skip with chain-breaking, empty / single-point input).

### `apps/web/src/lib/elevation.test.ts` — 9 tests

Pure tests for the Open-Meteo elevation helpers (`lib/elevation.ts`). `calculateElevationGain` covers positive-delta accumulation, flat profile = 0, descending profile = 0, empty / single-point input, and the rounding contract (sum of three +0.4 deltas → 1). `sampleCoordinates` covers passthrough below `maxPoints`, equal-count passthrough, exact-`maxPoints` cap when input is larger (with first + last endpoints retained), and the `indices ↔ sampled` alignment invariant.

### `apps/web/src/lib/gpx.test.ts` — 13 tests

Pure tests for the GPX / KML / run-GPX writers in `lib/gpx.ts`. `toGpx` covers the GPX 1.1 namespace + creator, one trkpt per coordinate, the lat/lon attribute mapping (input `[lng, lat]` → `lat="..." lon="..."`), missing-elevation falls back to 0, XML escaping in the name (`& < >`), and an empty-coordinates input emits a well-formed empty trkseg. `toRunGpx` covers per-point `<time>` emission when present, omission of `<ele>` when null and `<time>` when missing, the metadata `<time>` carrying `startedAtIso` (not the local clock), and name escaping. `toKml` covers the KML 2.2 namespace + the `lng,lat,ele` coordinate-string ordering, missing-elevation = 0, and name escaping in both Document and Placemark scopes.

### `apps/web/src/lib/run_stats.test.ts` — 17 tests

Pure tests for `lib/run_stats.ts` (web-only — Android computes splits inline in `run_detail_screen.dart`). `movingTimeSeconds` covers empty / single-point input = 0, threshold-passing segments counted, sub-threshold (stopped) segments dropped, mixed running + 60 s stop counts only running, the custom `minSpeedMps` override, same-timestamp pairs (`dt == 0`) skipped, and points without `ts` skipped. `elevationGainMetres` covers positive-only sum, null elevation chain break, and empty / single-point input. `computeRealSplits` covers short-track + no-timestamp early returns, the even-paced 3 km run producing three full splits at the right pace and distance (with one-sample overshoot tolerance — see source comment), the final partial split being emitted when remainder > 50 m, the final partial < 50 m being dropped, per-split elevation gain carrying through, and tracks without elevation leaving every split's `elevation_m` null.

### `apps/web/src/lib/recurrence.test.ts` — 14 tests

Mirror of `apps/mobile_android/test/recurrence_test.dart`. Pure tests for `lib/recurrence.ts`. `expandInstances` covers the non-recurring single-instance fork (in / out of window), weekly events producing 4-5 instances in a month, biweekly producing fewer than weekly, `recurrence_count` cap, `recurrence_until` cap, monthly producing one per month in window, instances never preceding `starts_at`, and monthly with `recurrence_count`. `nextInstanceAfter` covers the next-instance lookup and the null past-`recurrence_until` case. `describeRecurrence` covers the null-freq "One-off event" string, the monthly "Repeats monthly" string, weekly + byday output in ISO order regardless of input order, and biweekly without byday.

### `apps/web/src/lib/goals.test.ts` — 28 tests

Mirror of `apps/mobile_android/test/goals_test.dart`. Pure tests for `lib/goals.ts`. `periodStart` / `periodEnd` cover Monday-default + Sunday-override week anchoring, month start = 1st, week end = start + 7 days, December → January wrap. `formatPaceSecPerKm` covers em-dash for non-positive / non-finite, m:ss/km formatting with zero-padded seconds, half-up rounding. `evaluateGoal` covers empty list = 0%, runs outside the period excluded, distance target accumulation + complete-on-hit, pace target excluding cycling rides from the distance-weighted average, pace target with no qualifying runs reporting 0% + em-dash currentLabel, lower-is-better partial progress, time + runCount targets, multi-target complete-only-when-every-hit, `overallPercent` as the mean of target percents, and zero / negative targets being filtered out of the targets list. `newGoalId` covers uniqueness across 100 calls. `loadGoals` / `saveGoals` cover empty when no data, save / load round-trip preservation, per-user keying isolating two users on the same browser, null userId returns empty, the legacy unscoped-key migration on first load (with the legacy key removed afterwards), accepting both legacy camelCase and canonical snake_case wire shapes, and corrupt-JSON returning empty.

### `apps/web/src/lib/fitness.test.ts` — 26 tests

Mirror of `apps/mobile_android/test/fitness_test.dart`. Pure tests for `lib/fitness.ts`. `qualifyingRuns` covers sub-3km / sub-5min drop, every recognised `source` accepted plus a non-recognised value rejected. `vdotFromRun` covers sub-1km / sub-2min returning null, ~50 for a 20-min 5k, ~54 for a 3-hour marathon, faster pace → higher VDOT. `currentVdot` covers picking the best in-window qualifying run and ignoring runs older than 90 days. `vo2MaxFromVdot` is identity passthrough. `thresholdPaceSecPerKmFromVdot` covers null in / null out, VDOT 50 in the 240-260 s/km band, and higher VDOT yielding a faster threshold (catches the formula bug fixed during this pass — see [decisions.md § 54](decisions.md#54-fix-thresholdpacesecperkmfromvdot-formula)). `runTss` covers the sub-100m / sub-30s / zero-threshold returning 0, threshold pace = 100 TSS at 1 hour (Coggan reference), and faster-than-threshold raising TSS faster than linearly. `trainingLoad` covers null inputs / no qualifying runs all-null, non-null curves with at least one qualifying run, TSB rises during a 14-day taper. `computeSnapshot` covers the rollup contract + empty input. `recoveryAdvice` covers null inputs, sub-10 CTL → consistency-building advice, and the five-band TSB ladder producing five distinct strings.

### `apps/web/src/lib/coach/types.test.ts` — 4 tests

Smoke tests for the coach config / tier shape. `emptyUsage` returns a fresh zeroed object every call (no shared reference; mutation doesn't leak across calls). `TIER_LIMITS.free` keeps a finite daily cap so anonymous abuse can't drain quota. `TIER_LIMITS.pro` is uncapped (`Infinity`) on daily limit, larger on token + runs windows than free. Anchors the paywall contract — flipping any of these silently would change rate-limit behaviour without code review.

### `apps/web/src/lib/coach/limits.test.ts` — 21 tests

Pure tests for the validation / clamping helpers extracted from `coach/handler.ts` so they can run under `tsx --test` without booting `createClient`. `parseAuthHeader` covers `Bearer ` prefix stripping (case-insensitive on the prefix), null / undefined / empty input, bare `Bearer ` returning null, and tokens-without-prefix being passed through verbatim. `clampRunsLimit` covers undefined / null returning the default, non-finite (NaN, Infinity, non-numeric strings) returning the default rather than the tier cap, the tier max ceilings (free=30, pro=200), the floor at 1 (zero-runs context is never useful), fractional input being truncated, string-typed integer coercion, and pro tier honouring larger requests up to its cap. `jsonError` covers the canonical pre-stream response shape, extra fields landing alongside `error`, and the spread-order behaviour where `extra.error` wins over the literal. `rateLimitHeaders` covers the free-tier finite limit / remaining, remaining clamping to 0 when usage exceeds the cap, and the pro-tier "unlimited" sentinel. `personalityAddendum` covers the `drill_sergeant` and `analytical` tone overrides + the empty-string default for null / undefined / unknown styles.

### `apps/web/src/lib/settings_overlay.test.ts` — 9 tests

Pure tests for the universal + per-device prefs overlay helper extracted from `settings.ts` so it can run under `tsx --test` without dragging in the SvelteKit `$env/static/public` virtual import. `effective<T>` covers the fallback path when neither bag has the key, universal-wins-over-fallback, device-overrides-universal, device-null fall-through to universal (null is treated as "missing", not "unset to nothing"), device-undefined fall-through, universal-null-with-no-device fallback, falsy-but-concrete values (0, '', false) winning over fallback, object / array values round-tripping, and the type-parameter being a viewer-side hint with no runtime cast.

### `apps/web/src/lib/watch_payload_fixture.test.ts` — 6 tests

Cross-platform contract test against `fixtures/watch_run_payload.json`. The same fixture is decoded by `apps/mobile_android/test/watch_payload_fixture_test.dart`, its `mobile_ios` mirror, and the Wear OS Kotlin test (`apps/watch_wear/.../WatchRunPayloadFixtureTest.kt`). Editing the fixture without updating all three platform tests is a deliberate hard-fail. Web's slice asserts: source parses to a valid `RunSource`, `metadata.activity_type` is a registered value, `avg_bpm` is positive, laps use the canonical 1-based `index` + cumulative-BEFORE `start_offset_s` shape with deltas accumulating correctly, and the row + payload sources agree.

### `apps/watch_wear/.../WatchRunPayloadFixtureTest.kt` — 3 tests

Kotlin/JUnit slice of the same cross-platform fixture contract. Exercises `buildRunMetadata` (the pure helper extracted from `RunViewModel.pushRun`) by feeding it cumulative-form `QueuedLap` inputs derived from the fixture's expected per-lap-delta shape and asserting it produces matching JSON. Also asserts the payload source and per-point bpm round-trip.

### `apps/watch_wear/.../SupabaseErrorClassificationTest.kt` — 16 tests

Regression guard for the post-stop "unauthorized" sync error. `SupabaseClient.execute` throws a typed `HttpException(code, message)` whose message is the body's `msg` / `error_description` / `error` / `message` field (in priority order), falling back to `"HTTP $code"` only when the body has none of them. The first half of the suite pins that field-precedence so a future refactor can't quietly regress it; the second half asserts `classifyDrainError` branches on `HttpException.code`, not the (often-prose) message. Includes the exact PostgREST shape that originally defeated the pre-existing `msg.contains("HTTP 401")` substring match in `drainQueue` — `{"message":"JWT expired","code":"PGRST301"}` now correctly routes to `RetryAfterRefresh`.

### `apps/job_worker/internal/*_test.go` — Go unit tests

Run with `go test ./...` from `apps/job_worker`. No network or Postgres dependency — the worker tests use a fake `Backend`, the matcher tests use `httptest.Server` to stand in for OSRM. Files:

- **`worker_test.go`** — table-driven coverage of the claim → handle → finish loop. Pins the transient/permanent classifier (`isTransient` branches on `HTTPError.StatusCode`, falls back to message sniffing for dial errors), the re-upload race (`TestWorker_ReuploadDuringMatchDiscardsResult` for the pre-write recheck path; `TestWorker_StaleSourceTrackURLDiscardsResult` for the `source_track_url` CAS path), and the auto-link scoring policy (`TestWorker_AutoLinksWhenConfident` — must satisfy both endpoint-offset < 200 m AND |distance ratio| < 0.20 against `runs.distance_m`).
- **`matcher_test.go`** — pins `PassthroughMatcher` contract: input not aliased into output, empty in → nil out, stable algorithm/version strings.
- **`matcher_osrm_test.go`** — 10 tests covering `OSRMMatcher`: chunking (250 points → 3 calls, stitched), tail-of-1 passthrough, NoMatch translation (`code != "Ok"` → nil, downstream `'skipped'`), HTTP error surfacing (`*HTTPError` for 5xx), malformed-JSON wrapping, trailing-slash normalisation. The real engine isn't reachable from a unit test (multi-GB pre-extracted graph), so the tests stand up an `httptest.Server` that returns canned `/match` JSON.

### `apps/mobile_android/test/social_service_test.dart` — 13 tests

Pure-unit coverage for the value classes and helpers exposed by `lib/social_service.dart`. Covers `ClubView.isAdmin` / `isEventOrganiser` / `isRaceDirector` / `isMember` (the booleans that drive admin-only buttons + race-director Arm/Fire on `club_detail_screen` + `event_detail_screen`) — pinning that owner / admin both grant the full ladder, that `event_organiser` and `race_director` are siloed, that `member` carries no special affordances, and that an unrecognised viewerRole string is treated as not-admin so a future role we haven't taught the client about doesn't accidentally inherit admin powers. Plus 6 tests for `parseBydayCodes` (the byday-jsonb parser used by `_enrichEvents` + `fetchNextRsvpedEvent`): valid 'MO','WE','FR' shape, order + duplicate preservation, non-array fallback, empty + all-unknown → null (caller treats as "no override"), mixed known/unknown filters to known.

The Supabase-touching surface of `SocialService` (`browseClubs`, `fetchMyClubs`, the enrichment pipelines, RSVP writes, post creation) is NOT covered here — the class resolves `Supabase.instance.client` inline, so meaningful unit coverage of those branches needs a DI seam refactor (constructor-injected `SupabaseClient`, mirroring the `ApiClient.withClient` pattern). Tracked in [What's not covered](#whats-not-covered-honest).

### `apps/backend/supabase/tests/rls_*.sql` — pgtap RLS suite (181 tests across 23 files)

pgTAP tests against the highest-blast-radius RLS policies, run by `cd apps/backend && supabase test db --local`. Each file is wrapped in `begin; ... rollback;` so it's idempotent against the running local DB; tests filter to fixture user_ids so they don't trip on `seed.sql` rows. Pattern: insert two test users into `auth.users`, then `set local role authenticated; set local "request.jwt.claims" = '{"sub":"<uuid>"}';` to switch identity. Anon paths use `set local role anon`.

- **`rls_runs_test.sql`** — 16 tests. Owner CRUD; non-owner direct `SELECT` on `runs` returns zero (the wire-leak SELECT policy was deliberately dropped in 20260701_001 — public visibility now flows through the `public_runs` view, see [decisions.md § 33](decisions.md)); `public_runs` view exposes redacted public rows + strips audit / training-plan-linkage keys (`strava_id`, `plan_workout_id`); anon SELECT on `runs` is empty but on `public_runs` returns the public row; `is_run_visible_to(run_id, caller)` SECURITY DEFINER helper used by 5 sibling policies returns true for any caller on a public run.
- **`rls_routes_test.sql`** — 8 tests. Same shape as runs: non-owner direct SELECT on `routes` is empty even for `is_public=true` (the policy was dropped in 20260703_001); `public_routes` view is the public read path.
- **`rls_user_settings_test.sql`** — 8 tests. Owner-only across `user_settings` + `user_device_settings`; tests forbid forged-`user_id` INSERT and pin that privacy_zones in `prefs` are owner-only (a leak here is a doxxing vector).
- **`rls_coach_messages_test.sql`** — 7 tests. Owner-only across SELECT / INSERT / UPDATE / DELETE; pins reaction-update gate; non-owner reads of another user's coach conversation return zero.
- **`rls_integrations_test.sql`** — 6 tests. Owner-only — actual OAuth tokens live in `vault.secrets` (referenced by `*_secret_id`), but provider link + sync state are sensitive enough on their own to gate.
- **`rls_device_tokens_test.sql`** — 6 tests. Owner-only — APNs / FCM push tokens. Cross-user access would let an attacker route push notifications to arbitrary devices.
- **`rls_notifications_test.sql`** — 6 tests. No INSERT policy (notifications come from triggers running as SECURITY DEFINER); pins owner read / mark-read / delete and asserts authenticated-user direct INSERT is rejected.
- **`rls_live_run_pings_test.sql`** — 8 tests. Real-time location broadcasts. Non-owner cannot read pings of a private run; non-owner CAN read pings of a public run via `is_run_visible_to`; INSERT requires both `auth.uid() = user_id` AND ownership of `run_id`.
- **`rls_live_run_pings_trigger_test.sql`** — 7 tests pinning the `live_run_pings_drop_in_zone` BEFORE-INSERT trigger from migration `20260618_001`. Trigger exists with the right name + table, fires BEFORE INSERT (AFTER would be too late — Realtime would already have seen the row), function is SECURITY DEFINER (required to read the broadcaster's owner-only `user_settings.prefs.privacy_zones`), and behaviourally drops in-zone pings while keeping out-of-zone + no-zones-configured + empty-zones-array fast-paths. The spectator clients (`apps/web/src/routes/live/[id]/+page.svelte` + `apps/mobile_*/lib/screens/live_spectator_screen.dart`) render pings verbatim, so this trigger is the single line of defence between a runner's home/work coordinates and any anonymous spectator on a public live run.
- **`rls_fitness_snapshots_test.sql`** — 6 tests. Owner-only across SELECT + INSERT + DELETE (no UPDATE — append-only); the `source = 'client'` INSERT-CHECK ensures users can't forge snapshots that look like server / job output.
- **`rls_engagement_chain_test.sql`** — 21 tests. The four engagement tables that gate visibility through `is_run_visible_to(run_id, caller)`: `run_kudos`, `run_comments`, `run_photos`, `segment_efforts`. Pins that non-owner reads succeed on a public run + return zero on a private run for all three (kudos / comments / photos), that non-owner INSERT is allowed on the public run + rejected on the private run, that forged user_id / author_id / owner_id INSERTs are rejected even on a public run, that comment authors / photo owners can self-edit and self-delete, that the run owner can delete any comment on their run, that kudos givers can rescind their own kudos, and the same six-pattern matrix from anon (no kudos/comments/photos visible on private runs; visible on public via the helper). Plus the helper-contract sanity test — `is_run_visible_to(private, owner) = true`.
- **`rls_privacy_clipping_test.sql`** — 17 tests for the `clip_track_for_user` SECURITY DEFINER RPC + its `privacy_in_any_zone` + `privacy_distance_m` helpers. Pins the actual privacy invariant: leading + trailing in-zone points dropped, mid-track in-zone points (loop-home pattern) preserved, all-in-zone collapses to empty, never-touches-zone returned unchanged, no-zones-configured returns input unchanged, defensive shape (null / non-array / empty input → []), 50000-point input cap enforced, and the most important test — that the clip output never leaks zone metadata (`radius_m` / `privacy_zones` strings can never appear in the function's output, even though the SECURITY DEFINER context reads them). The wrapping `clip-public-track` Edge Function is untested in isolation — it's thin orchestration over this tested RPC + RLS-gated row lookup + Storage download.
- **`rls_paywall_test.sql`** — 17 tests for the revenue-critical paywall surface: `is_pro()` (true for pro / lifetime, false for free / unauthenticated); `check_rate_limit_tiered()` (free user denied at the free ceiling; pro user allowed past it on the same args; lifetime user treated as pro; cross-user calls rejected with `not authorized`; positive-args validation; `retry_after_seconds` is non-zero on denial; tier reported in the result row); and the `lock_subscription_columns` trigger pin — a `set local "request.jwt.claim.role" = 'authenticated'` UPDATE on `user_profiles.subscription_tier` raises `42501` and the row stays at `free`. This last one is the single test that stops a malicious user from self-upgrading to pro by editing their own row.
- **`rls_events_meet_point_test.sql`** — 4 tests for the `events.meet_lat` / `meet_lng` anon revoke from migration `20260723_001`. Pins that anon SELECT on the precise coords raises `42501`, that authenticated callers still see them, and that anon can still read `meet_label` (the canonical text display field). The original migration shape was `revoke select (cols) from anon` — a no-op when anon still has table-level SELECT — so this test fired during the regression-test pass and forced the migration to be rewritten as `revoke select on events from anon` + a column-level grant on the safe columns.
- **`rls_user_coach_usage_test.sql`** — 3 tests for the explicit DELETE deny policy from migration `20260722_001`. Pins that the owner can read their own row (SELECT policy works), DELETE attempts return zero affected rows (RLS deny), and the row survives the DELETE attempt — ensures a free user cannot reset the daily-cap counter by wiping their own `user_coach_usage` row.
- **`rls_plan_templates_test.sql`** — 5 tests for the `clone_plan_template` strip from migration `20260721_001`. A service-role insert seeds a template with non-null `vdot` + `current_5k_seconds` (simulating a future writer that bypasses the publish-side strip), then a club member clones it via the RPC and the test asserts the clone's `vdot` and `current_5k_seconds` are both null and that non-fitness fields (`name`, `days_per_week`) are preserved.
- **`rls_user_profiles_column_lockdown_test.sql`** — 5 tests for the `user_profiles` column lockdown from migration `20260707_001`. Pins that authenticated SELECT on each of `subscription_tier`, `parkrun_number`, `subscription_at` raises `42501`; that `display_name` (the cross-user join column) still works; and that `get_my_profile()` SECURITY DEFINER RPC returns the full self row including the locked-down columns. Same pattern-fix story as `rls_events_meet_point_test.sql` — the test exposed that the original migration's column-level revoke was a no-op and forced a rewrite to revoke-table + grant-safe-columns.
- **`rls_plan_workouts_writes_test.sql`** — 6 tests for the `plan_weeks` / `plan_workouts` write split from migration `20260613_001_rls_hardening.sql`. Pins that a non-admin club member CAN SELECT a club template's workouts (read flow preserved) but CANNOT INSERT / UPDATE / DELETE them (the regression — pre-fix `for all using (...)` let any club member with read access write to the parent's children even when they had no write authority on the parent training_plan). Plus positive controls: owner can write their own personal plan; club admin can write into their own template.
- **`rls_event_results_test.sql`** — 4 tests for the `event_results` INSERT visibility check from migration `20260613_001_rls_hardening.sql`. Pre-fix, the policy only checked `auth.uid() = user_id` with no event-visibility predicate — a user with a guessed event_id could plant a self-attributed result on a private-club event they couldn't even read. The test pins that an attacker (random authed user) cannot write to a private-club event's leaderboard, but CAN write to a public-club event (positive control), and that a private-club member can write to their own private event (positive control). Forged user_id is rejected even on a public event.
- **`rls_admin_user_id_forge_test.sql`** — 5 tests for the club admin `user_id` forge guards on `routes` + `training_plans` from migration `20260614_001_rls_hardening_pt2.sql`. Pre-fix, the `for all` admin write policies on both tables had no explicit WITH CHECK constraining `user_id`, so an admin could attribute a row to any user — the documented "uploader" audit trail was forgeable. Test pins that admins can self-author on both tables (positive controls), cannot forge another user's id on either, and crucially that admin UPDATE on a member-owned route still works (the relaxed UPDATE rule must be preserved — admins legitimately need write authority on routes / templates owned by other club members; the forge guard is INSERT-side only).
- **`rls_public_runs_view_denylist_test.sql`** — 2 tests but a 24-key sweep. Inserts a public run carrying every metadata key the strip list claims to remove, then SELECTs through `public_runs` as anon and asserts none survive. Catches drift in either direction — a removed strip OR a new sensitive key written without a matching update. Adding a key to the strip list = add it to the array in the test. Companion to `rls_runs_test.sql` which pins the row-level visibility chain (this file is denylist-coverage only).
- **`rls_function_hygiene_test.sql`** — 7 tests pinning the function-grant + search_path closures from migrations `20260710_001` (search_path on `weekly_mileage` + `personal_records`), `20260711_001_definer_grant_hygiene.sql` (revoke EXECUTE on `is_route_visible_to` + `recompute_event_ranks` from anon and PUBLIC), and `20260713_001_is_run_visible_to_anon_grant.sql` (restore the anon EXECUTE that pass-1 dropped, breaking every social-affordance read on `/share/run/<id>`). Reading the test exposed that the original `20260711_001` only revoked from `public` (the catch-all role group) — anon held its own explicit grant and the existence-oracle was still open. The migration was rewritten to also revoke from anon. Pinned with `has_function_privilege('anon', '<fn>', 'execute')` so a future Supabase auto-grant or a `grant ... to anon, authenticated` mistake fails CI.

These twenty-three files cover the tables + RPCs + triggers where a single-row leak / single-trigger bypass would be a privacy, impersonation, or revenue incident. They do NOT exhaustively cover every table (37 in total) — `clubs`, `club_members`, `club_posts`, `events` (full), `event_attendees`, `route_reviews`, `segments`, and others are still uncovered. Add a file when you touch a sensitive policy, or when an audit lands.

### `apps/backend/supabase/functions/_shared/webhook_security.test.ts` + `revenuecat-webhook/lib.test.ts` — 27 deno tests

Pure-helper tests for the webhook security primitives that gate `revenuecat-webhook` and `strava-webhook`. Run with `cd apps/backend && deno test --no-check supabase/functions/_shared/webhook_security.test.ts supabase/functions/revenuecat-webhook/lib.test.ts` (or via the same `denoland/deno:alpine-2.4.4` Docker image used by the function host on a workstation without local Deno).

- **`_shared/webhook_security.test.ts`** — 14 tests. `timingSafeEqual` (equal / unequal-same-length / length-mismatch / no-short-circuit-on-first-mismatch), `validateFreshness` (recent / 7-day boundary / too-old / clock-skew tolerance / custom window + skew args), `isValidUuid` (8-4-4-4-12 hex, rejects malformed), `isAnonymousAppUserId` (`$RCAnonymousID` prefix detected, others false). The `timingSafeEqual` and `validateFreshness` helpers were extracted out of the two webhook `index.ts` files so the production code path now imports the tested module directly — no duplicate definition can drift.
- **`revenuecat-webhook/lib.test.ts`** — 13 tests for `mapEventToTier(eventType, productId, currentTier)`. Pins every activating event → `pro`, lifetime-product detection (`pro_lifetime` / `lifetime_special` / `pro_lifetime_v2` substring match), null product id defaulting to `pro`, EXPIRATION + CANCELLATION → `free` for non-lifetime users, EXPIRATION + CANCELLATION → `null` (no change) for lifetime holders so a parallel-sub cancel can't downgrade a lifetime member, null `currentTier` falling through to `free` (the conservative default — better to apply the deactivation than leave a cancelled user on `pro`), unknown event types → `null`, plus a sanity test that the activating + deactivating taxonomy lists are disjoint so routing isn't iteration-order dependent.

The handler bodies themselves (HTTP envelope, `createClient`, `webhook_events` insert / `23505` dedupe path, side-effect writes) are not unit-tested in isolation — that surface is end-to-end and currently exercised manually via the workflow described in [apps/backend/CLAUDE.md § Testing without real credentials](../apps/backend/CLAUDE.md#testing-without-real-credentials). The pure helpers above cover the security-critical decision points: signature comparison, replay window, identity validation, tier transition. Anything load-bearing on those four lives in tested code now.

### `apps/web/tests-e2e/` — Playwright suite (111 tests across 51 files)

End-to-end browser tests that drive the real SvelteKit app against a real local Supabase. Unit tests pin pure helpers and SQL pins RLS at the database; this suite catches the next failure mode — **a UI fetch path that bypasses or misuses an otherwise-correct policy** (a wrong join, a dropped filter, a client-side lookup that trusts the URL, an optimistic update that never round-trips). Browser-only on purpose — mobile / watch don't have an equivalent harness (Flutter `integration_test` is too slow + flaky on CI to be worth the cycles right now).

**Stack:** `@playwright/test` 1.59.1, Chromium-only, run via `pnpm test:e2e` from `apps/web`. Webkit + Firefox would 3× the runtime; cross-browser bug yield on a SvelteKit static site is low. Single worker (`fullyParallel: false`, `workers: 1`) — concurrent tests against shared Supabase data race. The dev server (vite, port 7777) is auto-started by Playwright's `webServer` block; spec files attach pre-saved auth state so the only place the `/login` form runs is `globalSetup`. Total wall-clock for the full suite: ~110 s.

**One thing to know about sign-out:** the `globalSetup` fixture signs each user in once and saves cookies + the refresh token to `.auth/<user>.json`. Every test that uses `test.use({ storageState: USER_X.storageStatePath })` loads that file fresh. **Any test that triggers `auth.logout()` (which calls `supabase.auth.signOut()`) will revoke the current session's refresh token server-side — and that's the same token sitting in the saved file** (yes, even with `scope: 'local'` — supabase-js still hits the server logout endpoint). Subsequent tests for that user load the file, get the now-revoked token, and fail to authenticate. The rule the suite uses today: any sign-out test starts with an EMPTY storage state and signs in via the form first to mint an ephemeral session — that session's refresh token is what gets revoked, and the saved file's token is never touched. See `cross-cutting/sign-in-out.spec.ts` for the pattern.

**Why `vite dev` and not `vite preview`:** `adapter-static` + `fallback: 'index.html'` returns the SPA shell for any unmatched route (e.g. `/runs/<id>`). The fallback HTML computes its asset base via `new URL("..", location).pathname` — for `/runs/<id>` that resolves to `/runs`, breaking `_app/` asset URLs. Production fixes this with a CloudFront viewer-request rewrite; `vite preview` doesn't have that, so dev mode is the right server for headless e2e.

**Auth fixture (`fixtures/auth.ts`)** — Playwright `globalSetup` signs each seeded user in once via the real form and saves their storage state to `.auth/<user>.json`. Specs then `test.use({ storageState: USER_X.storageStatePath })` instead of re-running the login flow per test. Three users from `seed.sql` (`runner@test.com` free, `alex@test.com` free, `morgan@test.com` pro) cover owner / cross-user-viewer / paywall-pro cases.

**Pinned UUIDs (`fixtures/seeded-data.ts`)** — `RUNNER_PUBLIC_RUN_ID`, `ALEX_PRIVATE_RUN_ID`, `RUNNER_PUBLIC_ROUTE_ID` are deterministic UUIDs hardcoded into `seed.sql` so cross-user, share-page, and privacy-clipping tests can address known rows without first listing-and-picking. The pinned public run is also exempted from the cross-user kudos / comment seeds (`id != '...'` filter on the engagement inserts) so the kudos toggle test starts at zero kudos.

#### Layout

The suite mirrors `apps/web/src/routes/`, with two flat concern folders for things that don't fit a single page. The convention: any test that needs a second browser context goes under `cross-user/`; any test that touches >1 route or storage-state file goes under `cross-cutting/`; everything else lives at `<route>.spec.ts` (or `<route>/<sub>.spec.ts` for routes with detail pages).

```
tests-e2e/
  fixtures/                    — globalSetup, helpers, seeded constants, users
  landing.spec.ts              — /
  login.spec.ts                — /login (failed sign-in; sign-up: ?signup=1; forgot-password full round-trip via Mailpit; happy sign-in path in cross-cutting/sign-in-out)
  dashboard.spec.ts            — /dashboard
  feed.spec.ts                 — /feed
  coach.spec.ts                — /coach (mount, dropdowns, send → mocked SSE assistant bubble)
  live.spec.ts                 — /live/[id] (anon spectator: mount + planted-pings backlog hydrate → status flips to LIVE + stat strip fills)
  runs/
    list.spec.ts               — /runs (filter, sort, search, multi-select, create, delete)
    detail.spec.ts             — /runs/[id] (edit, cancel, single-run delete via the trash icon)
    save-as-route.spec.ts      — /runs/[id] Save-as-route CRUD (prompt → /routes/[new])
    social.spec.ts             — /runs/[id] owner sees kudos count + comment list (RunSocial mounts for own runs)
  routes/
    list.spec.ts               — /routes (search, filter, tab switch)
    detail.spec.ts             — /routes/[id] (star, public toggle, tag add+remove)
    import.spec.ts             — /routes Import-route modal: drop a GPX → preview → Save → land on /routes/[new]
  plans/
    list.spec.ts               — /plans (list + drill into /plans/[id])
    create.spec.ts             — /plans wizard end-to-end: create → land on detail → abandon → delete
    detail.spec.ts             — /plans/[id] (week grid, workout-day modal, PlanMetaEditor rename, publish-as-club-template)
    workout-detail.spec.ts     — /plans/[id]/workouts/[wid] (kind heading, back link)
  clubs/
    list.spec.ts               — /clubs (My + Browse tabs)
    detail.spec.ts             — /clubs/[slug] (Members tab, create/delete CRUD via /clubs/new)
    approval.spec.ts           — /clubs/[slug] admin approves OR rejects a pending join request
    event-create.spec.ts       — /clubs/[slug] admin creates event via the in-page modal (EventEditor)
    event-delete.spec.ts       — /clubs/[slug]/events/[id] admin deletes event → navigates back to club
    event-rsvp.spec.ts         — /clubs/[slug]/events/[id] RSVP round-trip on a planted event
    invite.spec.ts             — /clubs/join/[token] redeems a Friends-of-Jared invite link → lands on the private club
    join.spec.ts               — /clubs/[slug] open-policy join from Browse → post on feed → leave
    members.spec.ts            — /clubs/[slug] Members tab admin role-change dropdown round-trip
    post-delete.spec.ts        — /clubs/[slug] admin posts to feed → deletes via row icon
    posts.spec.ts              — /clubs/[slug] threaded reply: top-level post by runner → reply by alex → both render
  settings/
    account.spec.ts            — display name, parkrun number, password
    preferences.spec.ts        — theme, units, map style, privacy zones
    integrations.spec.ts       — Strava, parkrun, Garmin (list render + parkrun connect/disconnect round-trip + Strava OAuth-redirect path)
    devices.spec.ts            — current-browser row + "This device" badge
    licenses.spec.ts           — open-source license list
    upgrade.spec.ts            — Pro pricing, RevenueCat checkout
  share/
    run.spec.ts                — /share/run/[id] anon + authed-non-owner view
    route.spec.ts              — /share/route/[id] anon view
  u/
    profile.spec.ts            — /u/[id] (self vs cross-user view, Followers + Following tab list rendering + click-through)
    notifications.spec.ts      — /u/[me]?tab=notifications inbox: list renders, Mark all read empties Unread filter
  cross-user/                  — multi-context (two browsers, two users)
    kudos.spec.ts              — alex kudos runner, reload persists, rescind
    comments.spec.ts           — top-level + nested-reply round-trips
    follows.spec.ts            — morgan follows runner, counter increments, unfollow
    notifications.spec.ts      — kudos → bell badge update + popover entry
  cross-cutting/               — span >1 page or >1 session
    auth-walls.spec.ts         — RLS leak checks, anon redirects, ?return_to round-trip
    sign-in-out.spec.ts        — form sign-in + popover sign-out (uses ephemeral session, see preamble)
    navigation.spec.ts         — sidebar collapse persistence
    privacy-zones.spec.ts      — owner Share guardrail when track crosses a zone (cancel + confirm paths) + cross-user clipping via the clip-public-track EF
    cross-feature.spec.ts      — runs↔goals (goal-card 100%) + runs↔plans (day-cell + progress ring) + cross-user kudos→owner /runs/[id]
    dashboard-journey.spec.ts  — kitchen-sink reactivity: plant goal → add run → goal pct lifts → edit goal → delete run reverts every widget
    plans-journey.spec.ts      — mark 2 workouts done in sequence → revert 1 → progress ring + day-grid stay in lockstep
    clubs-journey.spec.ts      — create → post on Feed tab → /clubs lists it → delete → /clubs reverts
    feed-journey.spec.ts       — alex unfollows runner → /feed empty → re-follow → /feed has entries again
  cross-user/sagas/            — multi-step multi-user journeys with ephemeral users
    club-join.spec.ts          — alice creates club, bob+carl join, alice sees members, alice deletes
```

**Saga infrastructure** (`fixtures/saga-users.ts` + `fixtures/simulate.ts`). Sagas are multi-step multi-user journeys that need more users than the three pinned in `seed.sql` and/or actions only mobile/watch can do on the canonical web stack. Two helpers make sagas tractable:

- **`createSagaUsers(n, opts?)` / `deleteSagaUsers(users)`** — admin-creates `n` ephemeral auth.users rows + matching `user_profiles`, signs each in via the real form once to capture storage state (parallel, single browser process). `deleteSagaUsers` sweeps non-cascading owner tables (`clubs`, `events`, `club_posts`, `route_reviews`, `training_plans`, `routes`, `runs`) before the auth.users delete, then unlinks the storage-state files. Uses the service-role key from `supabase status -o env` (cached for the test process). Cost: ~5-7 s setup for 3 users; sign-in dominates.
- **`simulate.insertRun(...)`** — service-role helper for actions only mobile/watch can do on the canonical web stack ([decisions § 24](decisions.md)). Currently: `insertRun` (with optional gzipped track upload to the `runs` Storage bucket — mirrors the recorder's sync path), `deleteRun` (with track cleanup), `insertEvent` / `deleteEvent` (used by the `clubs/event-rsvp.spec.ts` round-trip and any future saga that needs an event row without driving the create-event modal), `insertKudos` / `insertComment` (engagement on a planted run — used by `runs/social.spec.ts` and `u/notifications.spec.ts` to fan out via the notify_* triggers without driving the UI), `insertLivePings` (plant a sequence of `live_run_pings` rows so the /live/[id] spectator page hydrates from a backlog without spinning up a real broadcaster — used by `live.spec.ts`), `setUserSetting` / `clearUserSettingKey` (user_settings.prefs upsert when the canonical UI requires a hard-to-drive interaction like the privacy-zone MapLibre picker), `setClubMemberStatus` (flip a club_members row's status — used by `clubs/approval.spec.ts` to restore alex to pending after the runner-approves test), `clearNotifications` / `setNotificationsUnread` (the notifications table has no automatic cleanup, accumulates across runs, and the bell badge caps at "9+" — tests that assert exact unread counts must clear or normalise first). Each helper bypasses RLS via the service-role client; keep the surface narrow — anything a real user could do via the web UI through a non-canvas interaction should go through the UI in the saga, not here.
- **`fixtures/mailpit.ts`** — local Supabase ships an embedded Mailpit on `http://localhost:54324` (config.toml's `[inbucket]` section). Auth flows that send email — sign-up confirmations, password recovery, magic links — deliver into Mailpit instead of a real SMTP relay. The helper exposes `clearMailpit()` (DELETE /api/v1/messages — call in `beforeEach` so accumulated mail from prior runs doesn't shadow the under-test email), `waitForEmail({ to, subjectIncludes })` (polls /api/v1/messages with a short interval until a matching message arrives), and `extractLink(msg)` (greps the first absolute URL out of the HTML/Text body — Supabase recovery / magic-link / signup-confirmation emails embed exactly one action URL so the naive first-match is reliable). Used by the `forgot password` test in `login.spec.ts` to drive the full request → email → reset → sign-in-with-new-password round-trip; future tests that need to verify what the auth system actually emailed (e.g. signup-confirmation flow if `enable_confirmations` flips on, magic-link sign-in) should reuse these.

**Saga conventions** (validated by `cross-user/sagas/club-join.spec.ts`):
1. Mint users in `beforeAll`, delete in `afterAll`. Per-test creation is too slow.
2. One `test()` per saga journey — the saga IS the assertion; splitting it would re-run setup repeatedly AND leak shared state.
3. One browser context per user. Same browser process, separate cookies + localStorage so each context acts as an isolated session.
4. **Don't use `waitForLoadState('networkidle')` on pages with a Supabase realtime subscription** (e.g. `/clubs/[slug]` subscribes for member-count updates). The websocket keeps the network busy and `networkidle` never fires. Wait for the concrete element you need to interact with via `expect(locator).toBeVisible()` instead.
5. **Tighten URL-match regexes when waiting for slug navigation** — Playwright's `waitForURL` returns the instant the regex matches the current URL. A permissive `\/clubs\/[a-z0-9-]+$/` matches `/clubs/new` (where alice already is) before the create-and-navigate completes. Anchor on something only the destination URL has — e.g. require a digit in the slug.

The page-mirror layout makes "what tests do I have for `/runs/[id]`?" trivial (one file) and "where does my new test go?" obvious (matching folder, or `cross-user/` if the test needs a second context, or `cross-cutting/` if it spans pages). Add new files as the depth grows — e.g., `routes/builder.spec.ts` when `/routes/new` gets coverage, or `cross-user/sagas/club-event-run.spec.ts` for the multi-step multi-user flows that need ephemeral users.

**Idempotency** — every test that mutates data either rolls back at the end (rename / kudos rescind / comment delete / display-name restore / follow-then-unfollow / filter restore / theme restore / sidebar restore / star restore / mark-all-read / comment-reply parent-delete) or creates-and-deletes its own row (manual run CRUD). The suite is safe to re-run without `supabase db reset` between runs. If a test fails partway and leaves orphaned state, the next reset cleans it up.

**Thirteen production bugs + one test-fragility were fixed during the suite's authoring passes.** Each was a real defect, not test scaffolding (the test-fragility was a brittle assert that masked an existing leak rather than a code bug, but it deserves a note since fixing it required adding the `clearNotifications` helper and a beforeEach):

- **`RunShareView.svelte`** lacked a `try/catch` around the non-owner branch's `fetchClippedTrackForRun` call; an EF outage would crash the entire share page render. Fix: wrap the call, fall back to `track = []`.
- **`/login/+page.svelte`** — Svelte 5's `onsubmit` binding hydrates after first paint, so a Playwright click before hydration completed fired the form's native GET handler instead of the JS submit. Fix: gate the submit button on a post-`onMount` `hydrated` flag, plus `waitForLoadState('networkidle')` in the test helper.
- **`/runs/+page.svelte` + `/runs/[id]/+page.svelte`** — `auth.svelte.ts` flips `loading=false` before its async `fetchUser()` resolves, so the `$effect` could fire with `auth.user == null` and skip the data fetch. The dashboard already polled for `auth.user` separately; these two pages didn't. Fix: gate on `(auth.loading || !auth.user)`, with a 1s polling loop on `[id]`.
- **`/settings/account/+page.svelte`** — same auth-race shape as above. The `displayName` / `parkrunNumber` `$state` declarations initialise from `auth.user?.X ?? ''` at module-evaluate time. On a hard reload before auth resolved, both fields seeded as empty strings and never re-populated, so a user typing a new value into the email-only profile would clobber their saved display name. Fix: poll for `auth.user` in `onMount` (~1 s budget), then populate the fields explicitly.
- **`/settings/preferences/+page.svelte`** — same auth-race shape, but more visible: `if (!auth.user) return` early-bailed `onMount` left `loading = true` forever. On hard reload the entire form was hidden behind a perpetual "Loading…" message — every preference (units / pace / map-style / theme via `loadTheme()` worked, but the rest of the form below was dead). Fix: same poll-for-auth pattern as `/settings/account`. The same bug shape was also fixed in `/settings/devices/+page.svelte` (no test yet, but the page had identical structure).
- **`/settings/preferences` toggle-button accessibility** — the Distance Unit + Theme toggles wrapped three buttons inside a `<label>` with a `<span class="label-text">` heading. The implicit-label association makes the FIRST button inherit the entire label content as its accessible name — the Auto button was announced to screen readers as `"Theme Light Dark, button"` (label heading + sibling button text), and the Kilometres button as `"Distance Unit Miles"`. Fix: replace `<label>` with `<div class="field">` (CSS already exists for that class) and put `role="group" aria-label="…"` on the inner `.toggle-row`. The Playwright test for the theme toggle would never have passed without this fix; a screen-reader user would be unable to identify which option they were on.
- **`/clubs/+page.svelte`** — yet another auth-race. `fetchMyClubs()` returns `[]` silently when `auth.user?.id` is null, so a hard reload onto `/clubs` during the auth race rendered "You haven't joined a club yet" forever, even for the user who owns three seeded clubs. Fix: poll for `auth.user` in `onMount` (~1 s budget) before kicking off `loadMine()` / `loadBrowse()`. Same shape as `/settings/account` + `/settings/preferences` + `/settings/devices`. The recurrence is the signal — the underlying issue is that `auth.svelte.ts` flips `loading=false` before the async `fetchUser()` resolves, so any `onMount` that reads `auth.user` synchronously is at risk. We're patching pages individually for now; a long-term fix would be a single `auth.ready()` helper that pages can `await`.
- **`/clubs/[slug]/+page.svelte`** — same auth-race shape, on the slug page. `fetchClubBySlug()` resolves the club row using `supabase.auth.getSession()` to populate `viewer_role`; on a hard reload during the auth race the row landed with `viewer_role = null`, making the derived `isMember` and `isAdmin` flags both false. The post composer is gated on `isMember` and the admin affordances (New event, Delete club, Delete post) are gated on `isAdmin` — so the owner of `sydney-run-club` who hard-reloaded onto the page saw a read-only view of their own club. There's no reactive re-fetch when auth lifts later. Fix: poll for `auth.user` in `onMount` (~1 s budget) before kicking off `load()`. Surfaced by the new post-create-then-delete test in `clubs/post-delete.spec.ts` which couldn't find the composer textarea in a full-suite run.
- **`/clubs/join/[token]/+page.svelte`** — same auth-race shape as the others, on the highest-stakes entry point: a private-club invite link. The page checked `if (!auth.loggedIn)` from `onMount` without polling, so a signed-in user clicking an emailed invite during the auth race landed on the "Sign in to accept this invite" branch even though they were already signed in — and the sign-in CTA's `?return_to=` would round-trip them back to the same broken state. Surfaced by the new `clubs/invite.spec.ts` test which navigates directly to the redemption URL with morgan signed in. Eighth page hit by the same auth-race pattern; the long-term fix is still a single `auth.ready()` helper that pages can `await`.

- **Three leave-the-app dead-ends fixed in one round.**
  1. **`/+layout.svelte` auth guard dropped the destination on redirect.** `goto('/login')` was called with no `return_to`, so a signed-out user clicking a stale `/runs/<id>` link from email or Slack got bounced to `/login`, then dropped on `/dashboard` after sign-in — they had to navigate back manually. The `/login` page already had a `safeReturnTo()` helper reading the param. Fix: encode `$page.url.pathname + $page.url.search` into `?return_to=` when the destination isn't already the default `/dashboard` or `/`.
  2. **`/runs/[id]` rendered a blank shell for missing rows.** The Svelte template was `{#if loading} ... {:else if run} ...detail... {/if}` with NO `{:else}` — so a deleted run, or another user's run hidden by RLS, fell through to a blank page with just the sidebar visible. Added a `{:else}` "Run not found" branch with a Back-to-runs link. The same audit also tightened the cross-user-isolation test in `auth-walls.spec.ts` to assert the not-found heading appears (positive evidence that RLS turned the row into null), not just the absence of the run's title.
  3. **`/routes/[id]` had the same shape.** A deleted or RLS-hidden route rendered an empty SplitPane with a blank stats panel. Same fix — added a "Route not found" branch.

  Surfaced by the new not-found tests in `runs/detail.spec.ts` + `routes/detail.spec.ts` and the `?return_to=` round-trip test in `cross-cutting/auth-walls.spec.ts`. Each is a regression a real user would hit, not a synthetic test scenario.

- **`/settings/integrations/+page.svelte`** — yet another auth-race. `fetchIntegrations()` returns `[]` silently when `auth.user?.id` is null, and the page calls it from `onMount` without polling. On a hard reload during the auth race, every provider row rendered with `connected=false` and showed a "Connect" button — even for a user with parkrun and Strava connected per seed. The Strava sync-now and disconnect affordances were reachable only by re-navigating into the page after auth resolved. Fix: poll for `auth.user` in `onMount` (~1 s budget) before kicking off `refreshIntegrations()`. This is the seventh page where this exact pattern has bitten us — the long-term fix is still a single `auth.ready()` helper, but for now we're patching pages individually. Surfaced by the new parkrun connect/disconnect round-trip in `settings/integrations.spec.ts` which expected the seeded "Disconnect" button to be present and saw "Connect" instead.
- **`cross-user/notifications.spec.ts` bell-badge brittleness** (test-only, not a code bug). The bell test snapshots runner's unread count, has alex kudos, then asserts `before+1`. Two latent issues converged: (1) the `notifications` table has no automatic cleanup, so test runs leak — kudos / comment / follow notifications from previous runs (or any test that doesn't roll back the engagement that triggered the row) accumulate. (2) The bell badge caps display at `"9+"` for any unreadCount > 9 (NotificationBell.svelte). Once accumulation pushed the count past 9 the badge said `9+` instead of the literal number, the toHaveText assertion failed, the test died before its kudos rescind cleanup, and the next run's kudos / cross-feature tests then saw the pinned RUNNER_PUBLIC_RUN_ID with leftover kudos and broke too. Fix: added a `clearNotifications(userId)` helper to `simulate.ts` and a `beforeEach` to the bell test that wipes runner's notifications, so `before` is always 0 and `after` is always 1. The new `u/notifications.spec.ts` inbox test plants a fresh kudos + comment via `simulate.insertKudos` / `insertComment` for the same reason — both tests now own their notification state instead of inheriting accumulated drift.
- **`/dashboard/+page.svelte` + `/coach/+page.svelte`** — same auth-race, narrower poll. Both polled `for (... auth.loading; ...)` instead of `(auth.loading || !auth.user)`, so when `auth.svelte.ts` flipped `loading=false` before `fetchUser()` resolved, the dashboard's `Promise.all([fetchRuns(), ...])` ran with `auth.user == null` and `fetchRuns()` returned `[]` — the four stat cards (`This Week`, `Total Runs`, `Longest Run`, `This Week Pace`) all rendered as `0` even for runner who has 12 seeded runs. Recent Runs and the Activity heatmap were both empty too. Coach had the same shape: `fetchMyPlans()` returned `[]`, leaving the plan switcher empty on a hard reload. Fix: include `!auth.user` in the poll predicate on both pages. Surfaced by the distance-unit-propagation test in `settings/preferences.spec.ts` which navigates settings → dashboard → asserts mileage values render in mi.
- **`auth.svelte.ts` logout scope** — `auth.logout()` called `supabase.auth.signOut()` with no options, which defaults to `scope: 'global'` and revokes refresh tokens for ALL of the user's sessions across every device. Signing out of the web also killed the user's mobile + watch sessions, forcing re-auth everywhere — which is rarely what the user means when clicking Sign out on the web (sign-out-everywhere belongs on a separate "sign out of all devices" affordance). Fix: pass `{ scope: 'local' }` so only the current browser context is signed out. (Note: this fix was the prompt for adding the "One thing to know about sign-out" preamble at the top of this section. `scope: 'local'` still revokes the *current* refresh token server-side, which is the same one stored in the e2e suite's `.auth/<user>.json` — so the sign-out test in `cross-cutting/sign-in-out.spec.ts` starts from an EMPTY storage state and signs in via the form first to mint an ephemeral session that's safe to revoke.)
- **`check_rate_limit` + `check_rate_limit_tiered` service-role bypass** — both functions read the role claim via `current_setting('request.jwt.claim.role', true)`, but newer PostgREST (the one the local stack now ships) deprecates the per-claim individual settings and only sets the JSON blob `request.jwt.claims`. So the legacy lookup returned NULL, `v_role <> 'service_role'` was always true, the bypass never fired, and every fail-closed Edge Function (`clip-public-track`, `delete-account`, `export-data`) rejected ALL anon callers with HTTP 503 because the IP-bucket rate-limit RPC raised 'not authorized' instead of accepting the service-role-keyed admin call. Fix in migration `20260726_001_rate_limit_role_jwt_claims.sql`: read the role from BOTH sources via the same coalesce shape supabase's bundled `auth.role()` helper uses, keeping backwards compat with any deployment still on the legacy claim. Surfaced by the cross-user privacy-clipping test in `cross-cutting/privacy-zones.spec.ts` (the very test that needed the EF to work).
- **`clip-public-track` row lookup leaked through the RLS rug-pull** — migration `20260701_001` dropped the `public runs are readable by anyone` SELECT policy on `runs` (after every reader had been switched to the column-redacted `public_runs` view), but the EF was still doing `userClient.from('runs').select('user_id, track_url, is_public').eq('id', runId)`. With the policy gone, that query returns zero rows for any non-owner caller — every clip request 404'd. The auth-walls suite STUBS the EF (`page.route` → `points: []`) so it never noticed; the new e2e clipping test exercises the EF for real and surfaced this. Fix: switch the row read to `userClient.from('public_runs')` (the same view every other public-run reader uses). Behaviour is identical for the EF's needs — only `is_public = true` rows are returned, and all three columns the EF reads (`user_id`, `track_url`, `is_public`) are exposed by the view.

These would have shipped silently — they don't show up in unit tests because the failures are in the integration between auth state, network calls, Svelte 5's hydration timing, accessible-name computation, and Supabase session-scope semantics. This is the bug-yield the suite was put in for.

#### End-to-end smoke test (manual)

Unit tests don't exercise the real OSRM engine. The `apps/job_worker/osrm/` directory ships a `make smoke` target that does:

1. Stand up OSRM (`make download && make build && docker compose up -d` once per region).
2. Stand up local Supabase (`cd apps/backend && supabase start`).
3. Run the worker with `OSRM_URL=http://127.0.0.1:5000` set.
4. From `apps/job_worker/osrm/`: `make smoke`.

The script uploads a Melbourne-region track, inserts a run (firing the trigger that queues a `map_match` job), polls `run_matched_tracks` until `status='matched'`, and prints raw vs matched coordinates side-by-side so a passthrough fallback is visible. Failure modes (OSRM unreachable, wrong region, worker not running, identical raw/matched coords) are reported with actionable messages. See [`apps/job_worker/osrm/README.md` § Smoke test](../apps/job_worker/osrm/README.md#smoke-test) for the full recipe and tunables.

This is **not** wired into CI — both the OSM extract download and the OSRM build are too heavy for the GitHub runner. It's a developer-machine sanity check before shipping a matcher change.

---

## Patterns

Three patterns show up across the suite. Adopt them when adding new tests so the style stays consistent.

### 1. `@visibleForTesting` hooks for untestable subsystems

`RunRecorder` opens a real geolocator stream in `prepare()`, which requires platform channels and can't run in `flutter test` without a mock. Instead of mocking the geolocator, we expose test-only entry points on the class itself:

```dart
@visibleForTesting
void debugPrepareWithoutStream({...});

@visibleForTesting
void debugInjectPosition(Position pos) => _onPosition(pos);

@visibleForTesting
List<Waypoint> get debugTrack => List.unmodifiable(_track);

@visibleForTesting
double get debugDistanceMetres => _distanceMetres;

@visibleForTesting
Duration get debugElapsed => _stopwatch.elapsed;

@visibleForTesting
Waypoint? get debugCurrentWaypoint => _currentWaypoint;
```

Tests construct a bare `RunRecorder`, call `debugPrepareWithoutStream(...)` with whatever filter params they need, call `debugInjectPosition(pos)` to feed the same `_onPosition` pipeline the live stream would, then assert on `debugTrack`, `debugDistanceMetres`, `debugElapsed`, etc.

The `@visibleForTesting` annotation (`package:flutter/foundation.dart`) doesn't hide the members at runtime — it just makes the analyzer warn if anything outside of tests calls them. That's exactly the boundary we want.

**When to use**: any class that wraps a platform-channel plugin (geolocator, pedometer, path_provider, permission_handler). Exposing a hook is usually cheaper than mocking the plugin.

### 2. Dependency injection for filesystem / path_provider

`LocalRunStore.init` takes an optional `Directory? overrideDirectory`:

```dart
Future<void> init({Directory? overrideDirectory}) async {
  if (overrideDirectory != null) {
    _dir = overrideDirectory;
  } else {
    final appDir = await getApplicationDocumentsDirectory();
    _dir = Directory('${appDir.path}/runs');
  }
  ...
}
```

Tests use a `setUp` / `tearDown` pair with `Directory.systemTemp.createTempSync(...)`:

```dart
late Directory tempDir;

setUp(() {
  tempDir = Directory.systemTemp.createTempSync('local_run_store_test_');
});

tearDown(() {
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
});

test('round-trip', () async {
  final store = LocalRunStore();
  await store.init(overrideDirectory: tempDir);
  ...
});
```

Each test gets a fresh, isolated directory. Real file I/O — no mocks, no in-memory filesystem abstraction. Good enough for unit-speed and catches real edge cases like JSON serialisation, file-name collisions, and directory listing order.

**When to use**: any class that reads or writes files via `path_provider`. Preferred over mocking `PathProviderPlatform`.

### 3. Synthetic `Position` helper for GPS-driven tests

Geolocator's `Position` has a dozen required fields. Each test file defines a `makePosition` helper so individual test bodies stay readable:

```dart
const lat = 47.37;
const lngBase = 8.54;
const metrePerDegLng = 111320 * 0.6773; // cos(47.37°)

Position makePosition({
  required double metresEast,
  required int secondsFromStart,
  double accuracy = 5,
}) {
  return Position(
    longitude: lngBase + metresEast / metrePerDegLng,
    latitude: lat,
    timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
    accuracy: accuracy,
    altitude: 400,
    altitudeAccuracy: 2,
    heading: 90,
    headingAccuracy: 5,
    speed: 2.5,
    speedAccuracy: 1,
  );
}
```

Expressing positions as `(metresEast, secondsFromStart)` instead of raw lat/lng + wall-clock DateTimes makes intent clear — "6 m in 2 s at 3 m/s" is obviously a run segment.

**When to use**: any test involving GPS positions or waypoints. The same trick works for `Waypoint` in `run_stats_test.dart`.

---

## How to add a new test

### For a pure function

Easiest case — no mocks, no hooks, no filesystem.

1. Create `test/<feature>_test.dart` in the package that owns the function.
2. Import `package:flutter_test/flutter_test.dart` and the code under test.
3. Write `group` + `test` blocks with `expect` assertions.
4. Run `flutter test test/<feature>_test.dart`.

Model to copy: **`run_stats_test.dart`**.

### For a class that wraps a plugin (sensors, permissions, storage)

Don't mock the plugin. Add a hook.

1. In the class, add a `@visibleForTesting` method that bypasses the plugin init. Name it `debug<Operation>`.
2. Add `@visibleForTesting` getters for any internal state the test needs to observe.
3. Import `package:flutter/foundation.dart` in the production file for the annotation.
4. In the test, construct the class directly, call `debug<Operation>()`, exercise the public API, assert on the internal-state getters.

Model to copy: **`run_recorder_test.dart`**.

### For a class that touches the filesystem

Inject the directory.

1. Add an `overrideDirectory` (or similar) parameter to whatever method takes the path from `path_provider`.
2. In tests, `setUp` with `Directory.systemTemp.createTempSync(...)` and `tearDown` with `deleteSync(recursive: true)`.
3. Pass the temp dir into the override.

Model to copy: **`local_run_store_test.dart`**.

### Run the new test

```bash
# The single file, fast
flutter test test/your_new_test.dart

# Or with filtering by test name
flutter test --plain-name "your new scenario"

# Or the whole package
flutter test

# Or the whole workspace
cd /path/to/project-running
melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test
```

---

## Schema codegen — how to test the drift detector

The `database.types.ts` (TypeScript) and `db_rows.dart` (Dart) row classes are regenerated from the Supabase migrations on every schema change. The point of generating them is to force a compile error if a client drifts. To verify the safety net still works:

```bash
# 1. Create a scratch migration that renames a column
cd apps/backend
supabase migration new scratch_rename_distance
echo "alter table runs rename column distance_m to total_distance_m;" \
    >> supabase/migrations/*_scratch_rename_distance.sql
supabase db reset

# 2. Regenerate both row files
cd ../..
npm run gen:types
dart run scripts/gen_dart_models.dart

# 3. Expect both clients to fail their builds with useful errors
cd apps/web && npm run check          # errors in mock-data.ts, data.ts, etc.
cd ../.. && melos exec -- dart analyze # errors in api_client.dart

# 4. Roll back — delete the scratch migration and reset
rm apps/backend/supabase/migrations/*_scratch_rename_distance.sql
cd apps/backend && supabase db reset
cd ../..
npm run gen:types
dart run scripts/gen_dart_models.dart
git status                             # should show no diff on the generated files
```

If step 3 produces a clean build, something in the generator pipeline has broken and drift is no longer being caught — treat this as a test failure and investigate before merging anything else.

To test just the TypeScript side of the CI gate locally:

```bash
cd apps/backend
npm run gen:types:check   # exit 0 = in sync, non-zero = drift with a diff printed
```

Full reference for the generators, workflow, and troubleshooting in [schema_codegen.md](schema_codegen.md).

---

## What's *not* covered (honest)

- **`RunScreen` finish + save UI flow.** Idle, countdown, recording-state-entry, and live-position ingestion are all covered (`run_screen_test.dart` 4 tests + `run_screen_recording_flow_test.dart` 5 tests). Tapping Finish + asserting the saved Run lands in `LocalRunStore` is not — the finish surface does an animated transition + a Storage upload that needs a real Supabase client. The data-pipeline equivalent is covered by `recording_integration_test.dart` (recorder → LocalRunStore → SyncService → fake API), so the regression risk is hedged.
- **Device-instrumented `integration_test` package tests.** None yet. `recording_integration_test.dart` covers the same golden path as a heavy widget test, which catches the same regressions cheaper. A true device-driven `integration_test` would add value for tile-cache, foreground-service, and background-sync paths that need real Android primitives.
- **`ApiClient` wire-level methods.** The DI seam exists — `ApiClient.withClient(SupabaseClient)` named constructor lets tests inject a fake without booting `Supabase.initialize` (4 tests in `api_client_di_test.dart`). The wire methods themselves (`saveRun`, `getRuns`, `fetchTrack`, `signIn`, `_uploadTrack`, etc.) still need a mock framework like `pkg:mocktail` (or local-Supabase integration tests against `127.0.0.1:54321`) to drive — the chained `from(...).select(...).eq(...).maybeSingle()` builders are too deep to roll by hand. The codec layer (`_runFromRow`, `_routeFromRow`, waypoint round-trip) is covered by `api_client_codecs_test.dart`, which is where the bug-yield is highest; the wire layer is mostly thin "build query, send, deserialize" code where the codec is the meaningful part.
- **`SocialService` and `TrainingService` ChangeNotifier glue.** Pure helpers + the role-derivation booleans on `ClubView` are covered by `social_service_test.dart` (13 tests). The Supabase-touching methods on both classes (browse / fetch / RSVP / create-event / publish-template / etc.) are NOT — both classes resolve `Supabase.instance.client` inline rather than taking it as a constructor parameter. Closing this gap needs a DI seam refactor (~30+ method touchpoints across the two classes), at which point the same fake-client pattern used in `sync_service_test.dart` becomes available. Service-level errors here are bounded — failure modes are stale lists or missed-RSVPs, not data leaks (RLS gates the actual rows; see the pgtap suite).
- **Edge Function HTTP envelope.** The pure security-critical helpers (`timingSafeEqual`, `validateFreshness`, `mapEventToTier`, etc.) are covered by `_shared/webhook_security.test.ts` + `revenuecat-webhook/lib.test.ts` (27 deno tests). The handler bodies that wire those helpers to `serve()`, `createClient`, and the `webhook_events` dedupe insert are exercised manually only — see [apps/backend/CLAUDE.md § Testing without real credentials](../apps/backend/CLAUDE.md#testing-without-real-credentials).

If you want to expand coverage, the best targets in priority order: (1) bring in `mocktail` and add wire-level `ApiClient` tests through the DI seam; (2) extend `run_screen_recording_flow_test.dart` past the Finish tap by mocking the storage-upload boundary; (3) stand up a true `integration_test` harness for the device-led paths; (4) add a constructor-injected `SupabaseClient` to `SocialService` + `TrainingService` and write fake-client tests for their ChangeNotifier glue.

---

## Continuous integration

Tests run in CI via `melos exec` directly — the per-script lookup that `melos run` uses is broken on Melos 7 (see the gotcha in the root [`CLAUDE.md`](../CLAUDE.md)), so the workflow drives the binary by command instead. From [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

```yaml
- run: melos bootstrap
- run: melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test
- run: melos exec -- dart analyze
```

The scopes pin coverage to the two packages that own meaningful test bodies; widening the glob doesn't add coverage and slows the runner. `melos exec -- dart analyze` walks every Flutter package and gates on the analyzer. See [architecture.md — CI/CD](architecture.md#cicd-pipeline) for the rest of the pipeline wiring.

Five jobs run on every PR + push to `main`: `test-packages` (Flutter), `parity-types` (TS schema drift + web TS unit tests), `build-watch-wear` (Wear OS Kotlin assemble + unit tests), `schema-codegen-drift` (Dart + Kotlin row-class regen + diff), and `e2e-web` (Playwright). The `e2e-web` job stands up the local Supabase stack (`supabase start` + `supabase db reset --local` to apply seed.sql — `supabase start` alone does NOT run the seed file), installs workspace deps with `pnpm`, caches the Chromium download keyed on `pnpm-lock.yaml`, writes `apps/web/.env` from `supabase status -o env`, and runs `pnpm test:e2e`. On failure it uploads `playwright-report/` + `test-results/` (traces + screenshots + videos for retried tests) for 7 days. Total wall-clock: ~3-4 minutes on the free runner.

The pgtap RLS suite is **not yet wired into CI**. Run it locally with `cd apps/backend && supabase test db --local` before opening a PR that touches an RLS policy or a SECURITY DEFINER function. CI gating is on the [`testing.md` follow-up list](#whats-not-covered-honest).

---

## Troubleshooting

**"No tests were found"** — the test file has no `void main()` function or no `test(...)` calls. Check the file has a top-level `main()` that invokes `group`/`test`.

**"Cannot read pubspec.lock"** — run `flutter pub get` at the repo root. The workspace uses pubspec overrides managed by Melos; `melos bootstrap` is the canonical setup.

**Tests pass locally but fail in CI** — most commonly from wall-clock assumptions. The recorder used to have exactly this bug in its speed clamp (wall-clock dt went near zero under load). If you see flaky timing tests, use GPS-reported timestamps from the `Position` rather than `DateTime.now()`, and be suspicious of any direct `DateTime.now()` subtraction in production code. The same lesson hit `_calculatePace` — see decisions.md §46 — and the architecture guard `_currentWaypoint constructor uses pos.timestamp, not DateTime.now()` in `packages/run_recorder/test/architecture_guards_test.dart` pins the policy.

**Heavy parsers must run in `compute()` isolates.** Found during a UI-freeze audit: `StravaImporter.importFromZip`, `BackupService.createBackup` / `restore`, and the single-file route import in `routes_screen` were all running ZIP/GZip/XML/FIT parsing synchronously on the main isolate — a 5-year Strava export froze the UI for tens of seconds. All four sites now dispatch through `compute()` (see decisions.md §48). The architecture guards under `apps/mobile_android/test/architecture_guards_test.dart#heavy parsers run in compute() isolates` will fail if a future refactor inlines any of these calls back onto the UI thread. New parser-style code that touches user-supplied data of unbounded size should consult §48 before adding the call.

**The wall-clock vs GPS-time audit (one-time):** every `DateTime.now()` call across `packages/run_recorder/`, `packages/api_client/`, and `apps/mobile_android/lib/` was reviewed and triaged into four buckets — see decisions.md §46 for the live bug and the policy. Quick reference for new code:

- **Pure metadata / display** (run start time, lap timestamp, `imported_at`, share-file `<time>`, run-id generation, date pickers, "today" string) — wall-clock is correct.
- **Throttle / cooldown** (accuracy-drop log, pace-drift cue, pace alert, lock-screen-notification 1 Hz, live-broadcaster ping) — both sides wall-clock, internally consistent.
- **DB-stored timestamp vs wall-clock** (event "future from now", plan-day-index, race-elapsed badge, relative-time helpers) — UX-acceptable; depends on user device clock being roughly correct via NTP.
- **Duration math** (`_calculatePace`, lap durations) — must use a monotonic source (`Stopwatch.elapsed`) or GPS time (`pos.timestamp`). This is the bucket the original bug lived in. `LapSplit.cumulativeDuration` already uses `_stopwatch.elapsed`; the only other consumer was `_calculatePace` (fixed in §46) and the GPX `<time>` parser (fixed in §47).

**Dart analyzer complains that a `debug*` method on a production class isn't called** — the `@visibleForTesting` annotation suppresses this in test files but the warning still fires at the declaration site. Add `// ignore: invalid_use_of_visible_for_testing_member` only if you need to call from non-test code (you almost certainly don't).

---

## Tests to add when the competitor-parity backlog lands

`docs/roadmap.md § Competitor-parity backlog` lists 12 features that aren't phased yet. When any of them ships, **the scope below is the minimum test surface** for that item to count as done. These are not nice-to-haves — they're the tests the CI job is expected to gate the PR on.

| Backlog feature | Pure-function tests | Integration / widget tests | Backend / schema tests |
|---|---|---|---|
| Training plan runner | Plan-to-workout expansion (given `plan_weeks + plan_workouts`, return today's workout for a given date + tz). VDOT-driven pace target generator. Adherence scorer (planned vs actual mileage). Structured-interval state machine (rep / recovery transitions). | Run-screen widget test: start a plan workout, simulate a completed run, assert the planned workout flips to "done" with side-by-side stats. | Migration: plan rows cascade-delete when a user deletes themselves; RLS: one user can't read another user's plan. |
| External platform sync | OAuth URL builder (per provider). Token refresh scheduler (given `token_expiry`, return next refresh time). Duplicate-run matcher (by `external_id` + timestamp fuzz). | Edge Function integration tests against a mock Strava/Garmin API; verify webhook → DB round-trip. | `integrations` RLS: users can't read other users' refresh tokens. |
| Segments + leaderboards | PostGIS line-matching stub (given two line-strings, return overlap fraction — pure SQL test with PostGIS fixtures). Effort-time computation from track slice. | Insert a run that crosses a segment → assert a `segment_effort` row appears. Leaderboard query returns correct ordering across a seeded fixture. | Segment RLS: private segments invisible to non-owners. |
| Heatmap / discovery | Tile-aggregation function: given N tracks, produce a tile's density array deterministically. Opt-out filter: a user's opt-out excludes their tracks from the aggregate. | Regression: a user who flips opt-out after aggregation no longer appears in next rebuild. | — |
| Trail / offline nav | Turn-cue generator: given a route + current position, produce the next-turn string. Offline-pack manifest: given a bounding box, list the tile URLs. | Widget test: step a simulated GPS trace along a route, assert the off-route banner fires at the correct threshold (the existing `live_run_map` tests would extend here). | — |
| Social graph | Follow-graph traversal (one hop). Feed query ordering (pinned runs, time-sorted, dedup). Kudos idempotency (second tap doesn't double-count). | Widget test: follow a user, navigate to feed, assert their latest run appears with correct kudos state. | `follows` RLS: a user can only create / delete their own follow row. Privacy-zone blur: start point returned as zone-center when viewer is not the owner. |
| Gear tracking | Mileage-total aggregation across a run set. Retirement-reminder trigger (given gear + threshold + current mileage). | Add gear → record a run with that gear selected → assert total updates; assert reminder fires at threshold. | Gear RLS: users only see their own gear. |
| Photos | Timestamp-to-waypoint matcher (given a photo EXIF time + a track, return the nearest waypoint). Thumbnail-URL generator. | Upload flow widget test: pick a photo, assert it appears on the run detail map pinned to the right location. | Storage bucket policy: anon can read thumbnails only if the run is public. |
| Audio-coached runs | Cue-schedule expander (given a workout + start time, emit cue events at the right offsets). Download manager: list expected assets for a workout; verify all-present check. | Record a run with an audio workout → assert the cue-schedule fired with the recorded elapsed times (mock the AudioCues emitter). | — |
| Race calendar + results | Race-proximity query (given lat/lng + radius, return races). Result-matching (given a run + a race, return confidence score). | Import a sample race → record a matching run → assert `race_results` row created and linked. | — |
| Advanced analytics | VDOT from a race result. Banister CTL/ATL/TSB from a week of runs. Race-time prediction from VDOT. Weekly mileage rollup (the existing `period_summary_test.dart` is the template). | Dashboard widget test: seed a fixture of runs, assert CTL/ATL curves render within tolerance. | — |
| Premium billing | Tier gate: given a `SubscriptionTier`, which features are enabled (pure data-driven). Webhook-payload parser (test against Stripe's fixture events). | Checkout flow e2e: click Upgrade → mock webhook → assert `subscription_tier` flips to `premium` on the profile within 5s. | Webhook replay-attack test: a re-posted event doesn't double-apply. Customer-portal link is user-scoped. |

### Conventions to keep

- Each new pure-function test file lives next to the code under `test/` in its package, matching the existing `run_stats_test.dart` pattern.
- SQL tests (RLS, PostGIS segment matching) go under `apps/backend/supabase/tests/` with `pgtap`; the CI job runs them via `supabase db test`.
- Edge Function tests use `deno test` and live under `apps/backend/supabase/functions/<name>/index.test.ts`.
- Widget tests use `WidgetTester.pumpWidget` + the existing synthetic-`Position` helpers from `test/helpers.dart`.
- No mocks for databases we control — local Supabase (54322) is the authoritative fixture. Mock only third-party HTTP (Strava, Stripe).
