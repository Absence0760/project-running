# Testing

Authoritative reference for the test suite — where tests live, how to run them, patterns we use, and when to run what.

For the behaviour being tested, see [run_recording.md](run_recording.md). For how to run the app itself, see [local_testing_android_app.md](local_testing_android_app.md).

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

Total: **41 tests across 3 files**, all Dart unit tests (no widget tests, no integration tests, no golden tests yet).

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

### `apps/mobile_android/test/local_run_store_test.dart` — 14 tests

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
