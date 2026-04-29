# Review: apps/mobile_android/test/

One high-confidence false-positive test (em-dash case never asserted), one architecture guard that passes even when the rule it encodes is partially violated, one test that duplicates private production code without an import seam, and several stale doc counts — no broken tests, no disabled tests, no skip markers.

## Scope
- Files reviewed: 19 test files in `apps/mobile_android/test/` + cross-referenced production files in `apps/mobile_android/lib/`, `apps/mobile_android/CLAUDE.md`, `docs/testing.md`, `docs/conventions.md`
- Focus: outdated tests, broken/disabled tests, coverage holes, test quality, doc drift, architecture guards
- Reviewer confidence: high — all test files read in full, all referenced production symbols verified against source

---

## High

### H1. fitness_card_test: em-dash test never asserts the em-dash
- **File(s)**: `apps/mobile_android/test/fitness_card_test.dart:101-124`
- **Category**: bug (false confidence)
- **Problem**: The test is named "uses an em-dash placeholder when VDOT cannot be computed" and the comment explains `currentVdot` returns null so the em-dash renders. The test never asserts `find.text('—')`. It only asserts `find.text('Fitness')` and `find.text('2')`. If the production `fmt(null)` call in `fitness_card.dart:47-48` were changed to display `'N/A'` or `'0.0'`, this test would still pass. It gives false confidence that the null-VDOT rendering is tested.
- **Evidence**:
  ```dart
  testWidgets('uses an em-dash placeholder when VDOT cannot be computed',
      (tester) async {
    // ...two runs, one outside 90-day window...
    await _pump(tester, runs: runs, now: now);
    expect(find.text('Fitness'), findsOneWidget);   // only asserts card is up
    expect(find.text('2'), findsOneWidget);          // only asserts qualifying count
    // NO assertion on '—' anywhere
  });
  ```
- **Proposed change**:
  ```diff
    expect(find.text('Fitness'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  + // Both VDOT and VO₂ max must render as em-dash when currentVdot is null.
  + expect(find.text('—'), findsNWidgets(2));
  ```
- **Risk if applied**: None. Adding the assertion can only catch a regression; it cannot create one. The production `fmt(null)` returns `'—'` per `fitness_card.dart:31`, so the assertion will pass today.
- **Verification**: `flutter test test/fitness_card_test.dart` — should pass immediately after adding the assertion.

---

### H2. Architecture guard for `_onPrefsChange` is under-specified: passes even if countdown/paused guards are removed
- **File(s)**: `apps/mobile_android/test/architecture_guards_test.dart:121-135`
- **Category**: bug (false confidence)
- **Problem**: The guard ensures `_onPrefsChange` skips rebuilds during recording. Production code at `run_screen.dart:421-424` guards three states: `recording`, `countdown`, and `paused`. The test only checks for the presence of the string `_ScreenState.recording` in the method body. If someone removed the `countdown` or `paused` branches — the two states where a full rebuild is equally wasteful — the test would still pass. Dropping the `paused` guard in particular would cause a setState rebuild every 10 seconds during a paused run (same runStore notify storm the guard was written to prevent).
- **Evidence**:
  ```dart
  // test (architecture_guards_test.dart:130-135):
  expect(
    body,
    contains('_ScreenState.recording'),
    reason: '_onPrefsChange must bail out while recording...',
  );

  // production (run_screen.dart:421-424):
  if (_state == _ScreenState.recording ||
      _state == _ScreenState.countdown ||
      _state == _ScreenState.paused) {
    return;
  }
  ```
- **Proposed change**:
  ```diff
    expect(body, contains('_ScreenState.recording'), ...);
  + expect(body, contains('_ScreenState.countdown'),
  +     reason: '_onPrefsChange must bail during countdown — '
  +         'same rebuild storm applies while waiting to start.');
  + expect(body, contains('_ScreenState.paused'),
  +     reason: '_onPrefsChange must bail while paused — '
  +         'runStore.notifyListeners fires every 10s regardless.');
  ```
- **Risk if applied**: None. These are additive assertions on an existing method. The production code already has the guards.
- **Verification**: `flutter test test/architecture_guards_test.dart` — passes immediately; confirms the guards exist and will catch future removal.

---

## Medium

### M1. fit_export_test duplicates a private function instead of importing it
- **File(s)**: `apps/mobile_android/test/fit_export_test.dart:4-21`
- **Category**: duplication / maintenance risk
- **Problem**: `_fitCrc` is a private top-level function in `run_share_card.dart`. Because it's private, the test copies it verbatim and wraps it in a `computeCrc` helper that does not exist in production. The test's comment says "Keep in sync." Manual sync is a maintenance failure mode. If `_fitCrc` in production is corrected (table entry change, shift-direction fix) without touching the test, the test continues to pass against the old algorithm. The production FIT files will be rejected by sports watches; the test will not catch it.

  Additionally, `fit_export_test.dart` is not listed in `apps/mobile_android/CLAUDE.md` or `docs/testing.md`.
- **Evidence**:
  ```dart
  // fit_export_test.dart:3 — verbatim copy:
  // Mirror of _fitCrc from widgets/run_share_card.dart. Keep in sync.
  int fitCrc(int crc, int byte) { ... }
  ```
  Production at `run_share_card.dart:694-703` is identical today, but the comment is the only enforcement.
- **Proposed change**: Promote `_fitCrc` to package-private by removing the leading underscore and annotating it `@visibleForTesting`. Then delete the copy from the test and import the real function:
  ```diff
  // run_share_card.dart:694
  - int _fitCrc(int crc, int byte) {
  + @visibleForTesting
  + int fitCrc(int crc, int byte) {
  ```
  ```diff
  // fit_export_test.dart:4-13 — delete the copy, add import
  - // Mirror of _fitCrc from widgets/run_share_card.dart. Keep in sync.
  - int fitCrc(int crc, int byte) { ... }
  + import 'package:mobile_android/widgets/run_share_card.dart';
  ```
  The `computeCrc` loop in the test can remain — it's test-only scaffolding and expresses the `startOffset` contract clearly.
- **Risk if applied**: The `@visibleForTesting` annotation will emit an analyzer warning if `fitCrc` is called from anywhere outside tests. That's intentional — it enforces the boundary.
- **Verification**: `flutter test test/fit_export_test.dart && dart analyze lib/widgets/run_share_card.dart` — both should pass; any future change to `_fitCrc`/`fitCrc` immediately affects the test.

---

### M2. CLAUDE.md falsely claims no widget tests exist
- **File(s)**: `apps/mobile_android/CLAUDE.md:126`
- **Category**: doc drift
- **Problem**: The line reads "No widget tests exist on this app — that's the biggest coverage gap." There are 14 `testWidgets` calls across three files: `plan_calendar_test.dart` (3), `workout_execution_band_test.dart` (6), `fitness_card_test.dart` (5). The claim was accurate before these files were added but was not updated.
- **Evidence**:
  ```
  # CLAUDE.md:126
  No widget tests exist on this app — that's the biggest coverage gap.
  ```
  Contradicted by:
  - `test/plan_calendar_test.dart` — 3 `testWidgets` calls
  - `test/workout_execution_band_test.dart` — 6 `testWidgets` calls
  - `test/fitness_card_test.dart` — 5 `testWidgets` calls
- **Proposed change**:
  ```diff
  - See [../../docs/testing.md](../../docs/testing.md) for how to run them and the patterns they use. No widget tests exist on this app — that's the biggest coverage gap.
  + See [../../docs/testing.md](../../docs/testing.md) for how to run them and the patterns they use. Widget tests exist for `FitnessCard`, `WorkoutExecutionBand`, `WorkoutReviewSection`, and `PlanCalendar` (14 `testWidgets` calls total); all other screens and widgets are uncovered.
  ```
- **Risk if applied**: None.
- **Verification**: Visual check only.

---

### M3. CLAUDE.md reports wrong test counts for architecture_guards and local_run_store
- **File(s)**: `apps/mobile_android/CLAUDE.md:109` and `apps/mobile_android/CLAUDE.md:123`
- **Category**: doc drift
- **Problem**: `CLAUDE.md:109` says `local_run_store_test.dart — 16 tests`; actual count is 17 (`deleteMany` and `deleteMany no-op` tests were added). `CLAUDE.md:123` says `architecture_guards_test.dart — 18 tests`; actual count is 20 (the `local inits run in parallel` group adds 4 tests, not 2 as the diff from 18 suggests).
- **Evidence**:
  ```bash
  grep -c '^\s*test\b' apps/mobile_android/test/local_run_store_test.dart
  # 17
  grep -c '^\s*test\b' apps/mobile_android/test/architecture_guards_test.dart
  # 20
  ```
- **Proposed change**:
  ```diff
  - `local_run_store_test.dart` — 16 tests: store persistence, sync state, in-progress save/load, edge cases
  + `local_run_store_test.dart` — 17 tests: store persistence, sync state, in-progress save/load, deleteMany batch, edge cases
  ```
  ```diff
  - `architecture_guards_test.dart` — 18 tests: static source-level assertions...
  + `architecture_guards_test.dart` — 20 tests: static source-level assertions...
  ```
- **Risk if applied**: None.
- **Verification**: Visual check.

---

### M4. recurrence_test.dart and importer_external_id_test.dart are undocumented
- **File(s)**: `apps/mobile_android/CLAUDE.md` (§ Tests), `docs/testing.md` (§ What's covered today)
- **Category**: doc drift
- **Problem**: Two test files exist in `test/` but appear nowhere in the documentation index:
  - `recurrence_test.dart` — 8 tests for `lib/recurrence.dart` (weekly/biweekly/monthly `expandInstances`, `count` cap, `until` cap, non-recurring event)
  - `importer_external_id_test.dart` — 2 tests: `StravaImporter.importFromZip` external_id prefix (live integration with a ZIP built in-memory), and a source-text guard for `HealthConnectImporter`

  Any future session looking at `recurrence.dart` or the importers won't know these tests exist.
- **Proposed change**: Add entries to `apps/mobile_android/CLAUDE.md` after the `metadata_registry_test.dart` line:
  ```diff
  + - `recurrence_test.dart` — 8 tests: weekly / biweekly / monthly `expandInstances`, hour/minute local-tz preservation, `count` cap, `until` cap, non-recurring single-instance
  + - `importer_external_id_test.dart` — 2 tests: `StravaImporter` ZIP import produces `strava:<id>` prefix; source-text guard confirms `HealthConnectImporter` uses `healthconnect:<uuid>` prefix
  ```
  Add the same entries to `docs/testing.md` under § What's covered today.
- **Risk if applied**: None.
- **Verification**: Visual check.

---

### M5. docs/testing.md "What's covered today" is substantially stale
- **File(s)**: `docs/testing.md:46`
- **Category**: doc drift
- **Problem**: The summary line states "107 Dart unit tests in mobile_android (8 test files)" and "No widget tests, no integration tests, no golden tests yet." The actual state is 19 test files with at least 180 tests (17+13+23+20+8+18+9+15+8+17+3+6+11+5+20+2+2+8+3 = 188 counting all files), and widget tests do exist. The "8 test files" figure is roughly half the actual number. Sessions relying on this doc to understand coverage will have a distorted picture.

  Additionally, the doc lists detailed breakdowns for only 8 of the 19 test files (`run_stats`, `local_run_store`, `period_summary`, `goals`, `route_simplify`, `ble_heart_rate`, `training`, and `local_run_store` for iOS). The following test files have no entry at all in `docs/testing.md`: `fitness_test.dart`, `hr_zones_test.dart`, `pace_segments_test.dart`, `plan_calendar_test.dart`, `workout_execution_band_test.dart`, `workout_review_section_test.dart`, `fitness_card_test.dart`, `metadata_registry_test.dart`, `architecture_guards_test.dart`, `recurrence_test.dart`, `importer_external_id_test.dart`, `fit_export_test.dart`.
- **Proposed change**: Update the summary paragraph and add sections for the undocumented test files. The CLAUDE.md already has entries for most of these — copy that content into `docs/testing.md`. At minimum, update the summary line:
  ```diff
  - Total: **at least 161 tests across 12 documented files** — 107 Dart unit tests in mobile_android (8 test files), 17 in mobile_ios ...  No widget tests, no integration tests, no golden tests yet.
  + Total: **at least 350 tests across 20+ documented files** — ~188 Dart tests in mobile_android (19 test files, including 14 widget tests), 17 in mobile_ios, 37 in run_recorder, 2 in core_models, and 21 TypeScript unit tests in the web app. No integration tests, no golden tests yet.
  ```
  (Exact counts: run the `grep -c` command in the Verification step to get a precise number before committing.)
- **Risk if applied**: None.
- **Verification**: `grep -c '^\s*test\b\|^\s*testWidgets\b' apps/mobile_android/test/*.dart` — sum the output for the exact count to put in the doc.

---

## Low

### L1. fitness_test: test name says "manually-entered" but the run source is parkrun
- **File(s)**: `apps/mobile_android/test/fitness_test.dart:63-70`
- **Category**: inconsistency
- **Problem**: The test is named "ignores manually-entered runs (no source signal)" but creates a run with `source: RunSource.parkrun`. The comment on line 65 does acknowledge `parkrun` isn't in the qualifying set, but the test name is misleading. The thing being tested is source-based filtering on runs excluded from VDOT, not "manual entry." There is no `RunSource.manual` or `RunSource.race` in the test at all. A future editor adding a `RunSource.manual` value and needing to verify it's excluded won't find this test by name.
- **Evidence**:
  ```dart
  test('ignores manually-entered runs (no source signal)', () {
    // Even though a 15-min 5k looks great, manual entries don't qualify.
    final r = _r(
      distance: 5000,
      durationS: 900,
      source: RunSource.parkrun,   // ← not "manually-entered"
    );
    expect(currentVdot([r]), isNull);
  });
  ```
- **Proposed change**:
  ```diff
  - test('ignores manually-entered runs (no source signal)', () {
  -   // Even though a 15-min 5k looks great, manual entries don't qualify.
  -   // (`RunSource.race` and `parkrun` aren't in the qualifying set either.)
  + test('excludes parkrun and race sources from VDOT qualifying set', () {
  ```
- **Risk if applied**: None — rename only.
- **Verification**: `flutter test test/fitness_test.dart`.

---

### L2. fitness_card_test: `find.text('2')` asserts count = 1 but is fragile against CTL/ATL/TSB rounding
- **File(s)**: `apps/mobile_android/test/fitness_card_test.dart:94` and `apps/mobile_android/test/fitness_card_test.dart:123`
- **Category**: brittle assertion
- **Problem**: Both the populated-card test and the em-dash-placeholder test use `expect(find.text('2'), findsOneWidget)` to assert the qualifying-run count stat shows `'2'`. The FitnessCard also renders CTL, ATL, and TSB as `toStringAsFixed(0)`. If the training load math happens to round ATL, CTL, or TSB to `'2'` for the given synthetic inputs, the assertion fails with a confusing "found 2 widgets" error. Currently the 2-run inputs (25 days and 5 days back) produce fractional loads well below `1.5`, so they round to `'0'` or `'1'` and the test passes. But this is an accidental property of the input data, not an explicit constraint.
- **Evidence**:
  ```dart
  // Line 94 — the assertion wants to test qualifying run count:
  expect(find.text('2'), findsOneWidget);
  // But CTL/ATL/TSB could also render as '2' depending on load math.
  ```
- **Proposed change**: Assert on the `Runs` stat label text and the number together, or use `find.descendant` to scope the search:
  ```diff
  - expect(find.text('2'), findsOneWidget);
  + // The 'Runs' stat specifically shows '2':
  + final runsStatFinder = find.ancestor(
  +     of: find.text('Runs'), matching: find.byType(FitnessStat));
  + expect(find.descendant(of: runsStatFinder, matching: find.text('2')),
  +     findsOneWidget);
  ```
  Alternatively, keep `findsOneWidget` but add a comment documenting the accidental dependency on load values being small.
- **Risk if applied**: None. Tighter scoping can only reduce false failures.
- **Verification**: `flutter test test/fitness_card_test.dart`.

---

## Coverage holes (informational — not assigned severities per the existing doc's own admission)

`docs/testing.md § What's not covered` already documents these gaps accurately. The three most data-loss-risky uncovered paths that aren't acknowledged at all in either doc:

1. **`sync_service.dart` — no test for conflict resolution edge cases.** The architecture guard confirms `_lastModifiedOf` is called in `saveFromRemote`, but there is no test that actually creates a local-newer and remote-newer conflict and asserts the correct winner. A unit test using `LocalRunStore` with `overrideDirectory` and two `Run` objects with controlled `metadata.last_modified_at` values would close this.

2. **`recurrence.dart` — no test for `until` + `count` interaction.** `recurrence_test.dart` tests them independently but not together. An event with both `until` and `count` set should stop at whichever limit comes first. Currently untested.

3. **`FIT export correctness beyond CRC** — `fit_export_test.dart` only tests the CRC algorithm. The actual record bytes, field definitions, and message lengths in `_buildFitFile` in `run_share_card.dart` have no tests. A corrupted distance field (off-by-one in the byte layout) would silently produce invalid FIT files that Garmin Connect and Strava reject.

---

## Counts

H: 2  M: 5  L: 2
