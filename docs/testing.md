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
```

`flutter test` has no built-in `--watch` flag. For a tight edit-save-test loop, either rerun the single file manually (sub-second) or wire up an editor integration — the Flutter plugin for VS Code and Android Studio both support running individual tests from gutter icons and auto-re-running on save.

**When to run:**

- **While editing the file you're testing** — run that one test file (`flutter test test/foo_test.dart`). Sub-second feedback loop.
- **Before committing** — `melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test` across the workspace. Catches cross-package breakage.
- **Before pushing a PR** — `melos exec -- dart analyze && melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test`. Both must pass.
- **In CI** — both commands run automatically (see [architecture.md — CI/CD](architecture.md#cicd-pipeline)).

---

## What's covered today

Total: **~488 unique Dart mobile tests across 73 test files, executed by both mobile targets** (mobile_android and mobile_ios share a byte-for-byte identical Dart codebase — see the iOS / android `CLAUDE.md` files), plus 44 tests in run_recorder (across 4 files), 2 in core_models, and ~77 TypeScript unit tests across 7 files in the web app. Both mobile apps run the same 73 test files; `flutter test` compiles them once per target, so end-to-end CI exercises ~975 mobile test runs. No integration tests, no golden tests yet. Counts here are point-in-time — they drift fast. Run `grep -cE '^\s*(test|testWidgets)\(' apps/mobile_android/test/*.dart` for the live per-target count and `diff -rq apps/mobile_android/test apps/mobile_ios/test` to confirm the trees stay in lockstep.

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

### `apps/mobile_android/test/sync_service_test.dart` — 10 tests

Covers the `_trySync` loop on `SyncService` via the new `@visibleForTesting debugTrySync` hook. A `_FakeApiClient` subclasses `ApiClient` and overrides `userId`, `saveRunsBatch`, and `deleteRunById`; `LocalRunStore` runs against a real `tempDir` (same pattern as `local_run_store_test.dart`).

**Guard clauses (3 tests):** no-op when `apiClient` is null, no-op when not signed in (`userId == null`), no-op when there is nothing to do.

**Push path (2 tests):** every unsynced run goes through one `saveRunsBatch` call and is marked synced afterwards, and a `saveRunsBatch` failure is swallowed without flipping the unsynced flag.

**Pending-delete drain (3 tests):** a successful delete removes the row from cloud / local / pending set, one failing delete does not poison the rest of the queue (others still drain), and `deleteRunById` is called once per pending id.

**Combined paths (2 tests):** a single tick handles both an unsynced push and a pending-delete drain in one cycle, and a reentrant call landing while a sync is in flight short-circuits on the `_syncing` guard so the batch isn't pushed twice.

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

### `apps/mobile_ios/test/` — same 72 files, byte-for-byte

After the April 2026 mobile-codebase unification, `apps/mobile_ios/test/` is kept identical to `apps/mobile_android/test/` via `diff -rq`. Every test file documented above runs on the iOS target too. Per-target counts: `flutter test` compiles separately, so each test file is executed twice when you run both apps. Don't add iOS-specific test files — every test belongs in both apps. The architecture-guard tests under `apps/mobile_android/test/architecture_guards_test.dart` read `lib/screens/run_screen.dart` from the working directory, so they pin the same invariants on both targets.

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

- **Widget tests (key remaining gaps).** `RunScreen` and `LiveRunMap` have no widget tests; those require platform-channel mocks (geolocator, pedometer) to exercise the recording path. All other screens and the majority of widgets now have widget tests (109 `testWidgets` calls across 22 files). The original four — `FitnessCard`, `PlanCalendar`, `WorkoutExecutionBand`, `WorkoutReviewSection` — have been joined by `HomeScreen`, `DashboardScreen`, `ImportScreen`, and many more.
- **Integration tests.** No tests exercise the full GPS → recording → save → sync → display flow end-to-end. `integration_test` package + a mock location provider would be the right approach. None exist today.
- **`ApiClient` HTTP / Storage / RPC paths.** Pure helpers (codecs, row-to-domain) are now covered (see `api_client_codecs_test.dart`); the wire-level methods (`saveRun`, `getRuns`, `fetchTrack`, `signIn`, `_uploadTrack`, etc.) still hit `Supabase.instance.client` directly, which would need a fake HTTP transport or a constructor that takes a `SupabaseClient` to be testable.
- **`SyncService` lifecycle wiring.** The `_trySync` loop is covered (`sync_service_test.dart`); the `WidgetsBindingObserver` lifecycle bridge and the `Connectivity().onConnectivityChanged` subscription still fire only when `start()` runs against a real binding.

If you want to expand coverage, the best target is to refactor `ApiClient` to take a `SupabaseClient` parameter so a fake transport is injectable, then drive the wire-level methods through it.

---

## Continuous integration

Tests run in CI via `melos exec` directly — the per-script lookup that `melos run` uses is broken on Melos 7 (see the gotcha in the root [`CLAUDE.md`](../CLAUDE.md)), so the workflow drives the binary by command instead. From [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

```yaml
- run: melos bootstrap
- run: melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test
- run: melos exec -- dart analyze
```

The scopes pin coverage to the two packages that own meaningful test bodies; widening the glob doesn't add coverage and slows the runner. `melos exec -- dart analyze` walks every Flutter package and gates on the analyzer. See [architecture.md — CI/CD](architecture.md#cicd-pipeline) for the rest of the pipeline wiring.

---

## Troubleshooting

**"No tests were found"** — the test file has no `void main()` function or no `test(...)` calls. Check the file has a top-level `main()` that invokes `group`/`test`.

**"Cannot read pubspec.lock"** — run `flutter pub get` at the repo root. The workspace uses pubspec overrides managed by Melos; `melos bootstrap` is the canonical setup.

**Tests pass locally but fail in CI** — most commonly from wall-clock assumptions. The recorder used to have exactly this bug in its speed clamp (wall-clock dt went near zero under load). If you see flaky timing tests, use GPS-reported timestamps from the `Position` rather than `DateTime.now()`, and be suspicious of any direct `DateTime.now()` subtraction in production code. The same lesson hit `_calculatePace` — see decisions.md §46 — and the architecture guard `_currentWaypoint constructor uses pos.timestamp, not DateTime.now()` in `packages/run_recorder/test/architecture_guards_test.dart` pins the policy.

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
