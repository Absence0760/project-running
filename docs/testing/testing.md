# Testing

Authoritative reference for the test suite — where tests live, how to run them, patterns we use, and when to run what.

For the behaviour being tested, see [run_recording.md](../features/run_recording.md). For how to run the app itself, see [../apps/mobile_android/local_testing.md](../../apps/mobile_android/local_testing.md).

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
- **In CI** — both commands run automatically (see [architecture.md — CI/CD](../architecture/architecture.md#cicd-pipeline)).

---

## What's covered today

Total: **~3,000 unique Dart mobile tests across ~263 test files, executed by both mobile targets** (mobile_android and mobile_ios share a byte-for-byte identical Dart codebase — see the iOS / android `CLAUDE.md` files), plus the run_recorder / api_client (~130 tests across 13 files) / core_models package suites, **~1,950 TypeScript unit tests across ~163 files** in the web app, ~1,130 Playwright e2e tests across ~229 spec files that drive the real web app against a local Supabase, **~530 Wear OS Kotlin/JUnit tests across ~49 files**, and **~1,140 pgTAP assertions across 147 SQL files** against the Postgres schema (49 of them `rls_*.sql`, carrying ~390 of those assertions; the rest cover rate-limits, job kinds, reports, segment-leaderboard tiers, and the personal-records cache — brackets / DNF / embedded-best / mile logic plus the trigger-maintained, trigger-only-write cache invariants), plus **~210 Deno tests across ~15 files** next to the Edge Functions. Both mobile apps run the same test files; `flutter test` compiles them once per target, so end-to-end CI exercises roughly twice the mobile test count. **`apps/watch_ios` carries ~80 XCTest methods across 9 files** in `WatchAppTests/` (run formatting, complication formatter, active-run bridge, checkpoint codable + track store, workout-manager track JSON + recovery, transfer state, and `WatchRunPayloadFixtureTests` — the Swift side of the cross-platform watch-payload fixture loop, which reads the same `fixtures/watch_run_payload.json` as the Wear OS / mobile / web tests, so drift is now caught on watchOS too). They run in CI via the `test-watch-ios` job (`xcodebuild test` on a macOS runner against the shared `WatchApp` scheme), added 2026-06-16. `recording_integration_test.dart` covers the data-pipeline golden path (GPS → recorder → LocalRunStore → SyncService → API) and `run_screen_recording_flow_test.dart` drives the corresponding UI flow (tap START → countdown → recording state with LiveRunMap mounted → Finish hold → run saved via `runStore.save`). No `integration_test`-package tests (device-instrumented) yet, no golden tests. Counts here are point-in-time — they drift fast. Run `grep -cE '^\s*(test|testWidgets)\(' apps/mobile_android/test/*.dart` for the live per-target count and `diff -rq apps/mobile_android/test apps/mobile_ios/test` to confirm the trees stay in lockstep.

Test files use **relative imports** (`import '../lib/widgets/run_photos.dart'`) instead of `package:mobile_android/...` so the same file resolves on both targets — both apps' pubspecs differ only in `name`, and the Dart analyzer would reject `package:mobile_android/...` when building the iOS target.

The exhaustive, file-by-file inventory of what every test file covers (plus the Playwright spec layout and the log of production bugs the suite caught) lives in **[test_inventory.md](test_inventory.md)** — it drifts fast, so it's split out of this durable guide.


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

Full reference for the generators, workflow, and troubleshooting in [schema_codegen.md](../architecture/schema_codegen.md).

---

## What's *not* covered (honest)

- **`RunScreen` finish + save UI flow — now covered.** Idle, countdown, recording-state-entry, live-position ingestion, **and the Finish hold → `_stop()` → `runStore.save(run)` path** are all covered (`run_screen_test.dart` 4 tests + `run_screen_recording_flow_test.dart` 6 tests). The Finish-save test invokes the rendered hold-to-stop button's wired `onHoldComplete` (the 800 ms `Ticker` is unreliable to drive under the fake clock) inside a `tester.runAsync` block (the recorder's position-stream cancel only completes on the real event loop) against a `_CapturingRunStore` spy (the real store's `save` does filesystem I/O that doesn't resolve under fake-async), then asserts a run was saved with the chosen activity type. The data-pipeline equivalent stays covered by `recording_integration_test.dart` (recorder → LocalRunStore → SyncService → fake API).
- **Device-instrumented `integration_test` package tests.** None yet. `recording_integration_test.dart` covers the same golden path as a heavy widget test, which catches the same regressions cheaper. A true device-driven `integration_test` would add value for tile-cache, foreground-service, and background-sync paths that need real Android primitives.
- **`ApiClient` wire-level methods.** The DI seam exists — `ApiClient.withClient(SupabaseClient)` named constructor lets tests inject a fake without booting `Supabase.initialize` (4 tests in `api_client_di_test.dart`). The **priority five** methods (`signIn`, `getRuns`, `fetchTrack`, `saveRun`, `_uploadTrack`) are now covered by `api_client_integration_test.dart` — 3 tests against a live local Supabase via the seed user (`runner@test.com / testtest`), gated by `SUPABASE_TEST_URL` env. The saveRun test exercises the full Storage roundtrip (`saveRun` → `_uploadTrack` → DB row → `getRuns` → `fetchTrack`) and surfaced two real bugs on first run: (1) `_uploadTrack` + `uploadTrackBytes` set `contentType: 'application/json'` for gzipped JSON bytes, which the `runs` bucket MIME allowlist (migration 20260815_001) 415's — fixed in commit alongside the test; (2) the seed.sql sets `track_url` to exercise the path-shape CHECK but doesn't upload an actual file (kept that way; the saveRun test uses a fresh upload it owns end-to-end). The remaining 100+ `ApiClient` methods are still uncovered — the codec layer (`_runFromRow`, `_routeFromRow`, waypoint round-trip) is covered by `api_client_codecs_test.dart`, which is where the bug-yield is highest; the rest of the wire layer is mostly thin "build query, send, deserialize" code where the codec is the meaningful part.
- **`SocialService` and `TrainingService` ChangeNotifier glue.** Pure helpers + the role-derivation booleans on `ClubView` are covered by `social_service_test.dart` (13 tests). The Supabase-touching methods on both classes now have a DI seam — `SocialService.withClient(SupabaseClient)` and `TrainingService.withClient(SupabaseClient)` — mirroring `ApiClient.withClient`. Wire-level integration coverage lives in `apps/mobile_android/test/services_integration_test.dart` (21 tests, gated on `SUPABASE_TEST_URL`, run by the `api-client-integration` CI job that boots local Supabase). Covers: `browseClubs` (x2 — query + empty-query), `fetchMyClubs`, `fetchClubBySlug` (x2 — known + unknown), `fetchClubRoutes`, `fetchClubPosts`, `fetchPostReplies`, `createPost`+`deletePost` roundtrip, `fetchUpcomingEvents`, `fetchEventById`, `fetchAttendees`, `fetchRecentRuns`, plus `TrainingService.fetchMyPlans`, `fetchActiveOverview`, `fetchPlan` (x2 — known + unknown), `fetchWorkout`, `fetchPlanForWorkout`, `updateWorkout` roundtrip, `fetchClubTemplates`. Remaining uncovered methods: write paths that touch event_results / race sessions / club admin transitions (`joinClub`, `leaveClub`, `approveJoinRequest`, `denyJoinRequest`, `createEvent`, `rsvpEvent` + `clearRsvp`, `submitEventResult`, `armRace` / `startRace` / `endRace`), and TrainingService write paths (`createPlan`, `publishPlanAsTemplate` + `clonePlanTemplate`, `markCompleted`, `deletePlan`, `updateStatus`). ~15 methods left; each is one block per method, not a refactor. Service-level errors here are bounded — failure modes are stale lists or missed-RSVPs, not data leaks (RLS gates the actual rows; see the pgtap suite).
- **Edge Function HTTP envelope.** The pure security-critical helpers (`timingSafeEqual`, `validateFreshness`, `hmacHex`, `mapEventToTier`, etc.) are covered by `_shared/webhook_security.test.ts` + `_shared/body_limit.test.ts` + `revenuecat-webhook/lib.test.ts` (45 deno tests). Wire-level auth-rejection coverage of the three webhook / cron handlers that bypass the platform `verify_jwt` gate (refresh-tokens, strava-webhook, revenuecat-webhook) lives in `_shared/handler_envelope.test.ts` (9 tests) — gated by `SUPABASE_TEST_URL` and driven by the new `edge-functions` CI job which boots Supabase, replaces the auto-started edge runtime with `supabase functions serve --env-file` (the auto-started runtime ignores `.env.local` and 503's every secret-gated call), and hits the function endpoints over HTTP. The full happy-path with valid HMACs / freshness / dedupe is still exercised manually only — see [apps/backend/CLAUDE.md § Testing without real credentials](../../apps/backend/CLAUDE.md#testing-without-real-credentials).

If you want to expand coverage, the best remaining targets in priority order: (1) stand up a true `integration_test` harness for the device-led paths; (2) keep widening the `SocialService` / `TrainingService` wire-level suite (the seam + 21-test scaffold from `services_integration_test.dart` covers the read paths; the remaining ~15 write paths are still uncovered — each is one block per method).

---

## Continuous integration

Tests run in CI via `melos exec` directly — the per-script lookup that `melos run` uses is broken on Melos 7 (see the gotcha in the root [`CLAUDE.md`](../../CLAUDE.md)), so the workflow drives the binary by command instead. From [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml):

```yaml
- run: melos bootstrap
- run: melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test
- run: melos exec -- dart analyze
```

The scopes pin coverage to the two packages that own meaningful test bodies; widening the glob doesn't add coverage and slows the runner. `melos exec -- dart analyze` walks every Flutter package and gates on the analyzer. See [architecture.md — CI/CD](../architecture/architecture.md#cicd-pipeline) for the rest of the pipeline wiring.

Eighteen jobs run on every PR + push to `main`: `test-packages` (Flutter), `test-worker` (Go job worker), `test-graph-cycle` (Go graph-cycle map sidecar), `parity-types` (migration-version-key uniqueness guard + web TS unit tests + CHECK-constraint guard run up front with no DB, then TS schema drift against the live stack — the source-only checks deliberately run *before* `supabase start` so a broken stack can't silently skip the web unit suite, as a migration collision did for ~2 days in run 26822355308), `build-web` (a production-mode `vite build` of `apps/web` as a **compile gate — it never deploys**; the prod/preview release stays tag-gated in `release-web.yml` on `web@*`. Added after run 26844715187, where a Svelte 5.56.0 compile error reached `main` because the only `vite build` lived in the PR-only `web-bundle-budget.yml` and a direct push skipped it, so the broken route surfaced only by chance through one Playwright shard; this job rebuilds every route on push *and* PR so a compile error fails loudly here instead. Feeds placeholder `PUBLIC_*` env values — the build resolves those through `$env/static/public` at build time, so real secrets are irrelevant and absent), `parity-matrix` (`scripts/check_parity_matrix.dart` — keeps the platform-feature matrix in `docs/product/parity.md` honest), `build-watch-wear` (Wear OS Kotlin assemble + unit tests), `test-watch-ios` (watchOS `xcodebuild test` on a macOS runner — the `WatchAppTests` suite), `build-firmware` (Rust custom-watch firmware), `build-mobile-android` (release APK smoke), `twin-parity` (mobile_android ↔ mobile_ios byte-identical check), `schema-codegen-drift` (Dart + Kotlin row-class regen + diff), `api-client-integration` (real Supabase: `api_client` wire-level + mobile services), `edge-functions` (Deno: pure helpers + HTTP envelope), `pgtap-rls` (pgTAP RLS suite), `e2e-web` (Playwright, **sharded 14 ways** — `--shard=N/14` across a 14-entry matrix, so it's 14 parallel runner jobs under one job id), and the two dedicated Playwright lanes `e2e-web-livehub` + `e2e-web-sso` described below. The `e2e-web` job stands up the local Supabase stack (`supabase start` applies the migrations *and* runs seed.sql; we deliberately avoid `supabase db reset`, whose mid-flight storage-container restart + health-poll is a chronic CI flake, and just assert the seed user landed afterward), installs workspace deps with `pnpm`, caches the Chromium download keyed on `pnpm-lock.yaml`, writes `apps/web/.env` from `supabase status -o env`, and runs `pnpm test:e2e`. On failure it uploads `playwright-report/` + `test-results/` (traces + screenshots + videos for retried tests) for 7 days. Total wall-clock: ~3-4 minutes on the free runner. Every stack-using job (`parity-types`, `schema-codegen-drift`, `api-client-integration`, `edge-functions`, `pgtap-rls`, `e2e-web`) boots the stack through the shared `./.github/actions/start-supabase` composite action rather than an inline copy. Its retry force-removes any container still publishing a stack port **and tears down any leftover `supabase_network_*` docker network**, then gates on both being clear before re-running — `supabase stop` alone does **not** free an orphaned host port after a partial start ([supabase/cli#3265](https://github.com/supabase/cli/issues/3265)), which let run 26860851075 (e2e shard 7) die when both attempts re-hit `failed to bind host port for 0.0.0.0:54322: address already in use`. The container force-remove was not enough on its own: a partial start can also strand the stack's docker *network* with a dangling endpoint that reserves 54322 at the docker layer with **no container and nothing in LISTEN**, so the `ss`-based probe sees every port free yet the bind still fails — the recurrence in run 27567813578 (e2e shard 10). The gate now treats a stranded stack network as a holder `ss` can't see: it cleans it and verifies it's gone before the next attempt.

Two **dedicated** Playwright lanes run their own focused slices outside the sharded `e2e-web` job, each with its own config that boots an extra webServer: `e2e-web-livehub` (`playwright.livehub.config.ts` — the Go live-hub WebSocket path) and `e2e-web-sso` (`playwright.sso.config.ts` — the OAuth/SSO login path, added 2026-06-10). The SSO lane drives the real `signInWithOAuth → /auth/callback → exchangeCodeForSession → session → /auth/confirm-age` path against a local `oauth2-mock-server`: GoTrue special-cases `google`/`apple`, so the mock is wired as the generic `keycloak` provider (`config.toml [auth.external.keycloak]`, inert unless the `SSO_MOCK_OIDC_*` env is set), and the only un-exercised piece is the provider *identity* (a literal Google login). Full rationale + the keycloak-stands-in-for-Google caveat: `apps/web/tests-e2e/sso/README.md`.

The `pgtap-rls` job runs `cd apps/backend && supabase test db --local` against the migrations-only local stack (no `db reset` — every test file is wrapped in its own `begin; … rollback;` and uses synthetic fixture UUIDs that don't collide with `seed.sql`). A regression in any RLS policy or SECURITY DEFINER function fails the PR.

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

`docs/product/roadmap.md § Competitor-parity backlog` lists 12 features that aren't phased yet. When any of them ships, **the scope below is the minimum test surface** for that item to count as done. These are not nice-to-haves — they're the tests the CI job is expected to gate the PR on.

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
- SQL tests (RLS, PostGIS segment matching) go under `apps/backend/supabase/tests/` with `pgtap`; the `pgtap-rls` CI job runs them via `supabase test db --local`.
- Edge Function pure-helper tests use `deno test` and live next to the helper (`apps/backend/supabase/functions/_shared/*.test.ts` or `apps/backend/supabase/functions/<name>/lib.test.ts`). HTTP-level handler-envelope tests live at `apps/backend/supabase/functions/_shared/handler_envelope.test.ts` and need a running `supabase functions serve --env-file` — the `edge-functions` CI job sets this up.
- Widget tests use `WidgetTester.pumpWidget` + the existing synthetic-`Position` helpers from `test/helpers.dart`.
- No mocks for databases we control — local Supabase (54322) is the authoritative fixture. Mock only third-party HTTP (Strava, Stripe).
