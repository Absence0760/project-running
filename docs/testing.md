# Testing

Authoritative reference for the test suite — where tests live, how to run them, patterns we use, and when to run what.

For the behaviour being tested, see [run_recording.md](run_recording.md). For how to run the app itself, see [../apps/mobile_android/local_testing.md](../apps/mobile_android/local_testing.md).

---

## TL;DR

```bash
# Run every test in the workspace
melos run test

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
```

`flutter test` has no built-in `--watch` flag. For a tight edit-save-test loop, either rerun the single file manually (sub-second) or wire up an editor integration — the Flutter plugin for VS Code and Android Studio both support running individual tests from gutter icons and auto-re-running on save.

**When to run:**

- **While editing the file you're testing** — run that one test file (`flutter test test/foo_test.dart`). Sub-second feedback loop.
- **Before committing** — `melos run test` across the workspace. Catches cross-package breakage.
- **Before pushing a PR** — `melos run analyze && melos run test`. Both must pass.
- **In CI** — both commands run automatically (see [architecture.md — CI/CD](architecture.md#cicd-pipeline)).

---

## What's covered today

Total: **94 tests across 6 files** (80 in mobile_android + 14 in run_recorder), all Dart unit tests (no widget tests, no integration tests, no golden tests yet).

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

### `packages/run_recorder/test/run_recorder_test.dart` — 14 tests

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

### `apps/mobile_android/test/local_run_store_test.dart` — 16 tests

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

### `apps/mobile_android/test/route_simplify_test.dart` — 8 tests

Tests for Ramer-Douglas-Peucker track simplification in `lib/route_simplify.dart`:

- Fewer than 3 points returned unchanged
- Collinear points dropped
- `computeElevationGain` accumulates only positive deltas

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
melos run test
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

- **Widget tests.** `RunScreen`, `LiveRunMap`, `CollapsiblePanel`, the finished-run view, the stats panels, hold-to-stop gesture — all rendered UI is uncovered. `apps/mobile_android/test/widget_test.dart` used to be a `flutter create` stub; it's been deleted. Widget tests using `WidgetTester.pumpWidget` + `find.byType` would be the right level.
- **Integration tests.** No tests exercise the full GPS → recording → save → sync → display flow end-to-end. `integration_test` package + a mock location provider would be the right approach. None exist today.
- **`RunRecorder._calculatePace`, `_routeRemaining`, `_offRouteDistance`.** The pace calculation and route helpers have no direct tests. Their logic is exercised via `_emitSnapshot` but only through the tests that assert on `distanceMetres` and `track`. Dedicated tests would be a good follow-up.
- **`ApiClient`, `SyncService`, `LocalRouteStore`.** Nothing on the sync path, the routes store, or the Supabase client has tests. Most of these would want a fake HTTP client or a tempDir override.
- **GPX/KML import (`gpx_parser` package).** Parses real files at runtime without any fixture-based tests.
- **`live_run_map.dart:_smoothTrack`** (the 1-2-3-2-1 polyline smoother). Pure function, trivially testable with the waypoint helper pattern — just not done yet.

If you want to expand coverage, those are the best targets in priority order: `_smoothTrack` (cheapest) → `_calculatePace` → `gpx_parser` → widget tests for `run_screen`'s state transitions.

---

## Continuous integration

Tests run in CI via the `melos run test` script defined in `melos.yaml`:

```yaml
scripts:
  test:
    run: melos exec -- flutter test
    description: Run tests in all Flutter packages
```

`melos exec -- flutter test` walks every Flutter package in the workspace (defined by the top-level `melos.yaml`'s `packages` list) and runs `flutter test` in each one that has a `test/` directory. Packages without tests are silently skipped. See [architecture.md — CI/CD](architecture.md#cicd-pipeline) for the pipeline wiring.

---

## Troubleshooting

**"No tests were found"** — the test file has no `void main()` function or no `test(...)` calls. Check the file has a top-level `main()` that invokes `group`/`test`.

**"Cannot read pubspec.lock"** — run `flutter pub get` at the repo root. The workspace uses pubspec overrides managed by Melos; `melos bootstrap` is the canonical setup.

**Tests pass locally but fail in CI** — most commonly from wall-clock assumptions. The recorder used to have exactly this bug in its speed clamp (wall-clock dt went near zero under load). If you see flaky timing tests, use GPS-reported timestamps from the `Position` rather than `DateTime.now()`, and be suspicious of any direct `DateTime.now()` subtraction in production code.

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
