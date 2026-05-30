# Test inventory

The exhaustive, file-by-file list of what each test file covers, the Playwright spec layout, and the log of production bugs the e2e suite caught. Split out of [testing.md](testing.md) (the durable testing guide) because these per-file descriptions and counts drift fast. Regenerate live counts with `grep -cE '^\s*(test|testWidgets)\(' apps/mobile_android/test/*.dart` (Dart), `npx tsx --test` discovery (web), and `supabase test db --local` (pgTAP).

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

The structured-workout step engine — step expansion (warmup → reps → recovery → cooldown), auto-advance, halfway / last-50 m progress signals, skip / abandon, and pace-adherence "wayBehind" classification. See [workout_execution.md](../features/workout_execution.md) for the runner state machine + UI contract.

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

### `apps/mobile_android/test/offline_mode_workflow_test.dart` — 14 tests

End-to-end workflows that pin the "Fully offline mode — record without an account, sync later if you ever sign in" headline feature. Composes `LocalRunStore` + `SyncService` over realistic user journeys. See `decisions.md § 67` for the owner-tag design.

**Record without account → sign in later (4 tests):** saving while signed out leaves the `created_by_user_id` tag null; signing in + draining adopts every untagged run to the new user; partial-failure on first drain only marks the succeeded subset; record-offline → sign-in → record-more produces a mix of adopted + tagged runs that all push together.

**Shared-device cross-user contamination guard (5 tests):** user A records → signs out → user B drains → ZERO foreign pushes (the load-bearing assertion); user A returns + drains → A's runs finally push; mixed queue (A-tagged + B-tagged + untagged) signed in as B → only B + untagged push, A stays queued; foreign-only drain is success, not failure (no backoff); sign-out preserves the queue (we don't wipe).

**Cold start (2 tests):** signed-out save → process restart → cold start preserves queue + unsynced count; classic returning-user flow (record day 1 offline → kill app → cold start day 2 → sign in → drain).

**Edit-while-offline (1 test):** an edit before signing in propagates the edited title through the eventual drain.

**SyncService gate clauses (2 tests):** no api configured → no drain attempt; signed-out api → no drain attempt.

### `apps/mobile_android/test/backup_format_compat_test.dart` — 12 tests

Cross-language wire-format compatibility test. The Go service at `apps/job_worker/internal/dataexport/server.go` produces `run-app-backup` v1 archives via `BuildBackupZip`; the mobile `BackupService.restore` reads them. These two implementations live in different languages and can drift on JSON shape, ZIP entry encoding, or manifest fields. This file hand-crafts an archive that mirrors what the Go writer produces — `json.MarshalIndent` 2-space encoding, `zip.Store` for raw gzipped tracks, manifest emitted last — and runs the Dart reader against it.

**Manifest (2 tests):** every manifest field Go emits parses cleanly; `exported_from = "go-service"` is accepted without warning.

**Optional pointer fields (3 tests):** Go's `ExportRun` + `ExportRoute` structs serialise nil pointers as `null`/omitted; Dart restore must tolerate both. Tests pin: runs with all fields populated round-trip intact (including `external_id`, `is_public`, `title`, `avg_bpm`); routes with every optional pointer set round-trip (waypoints, distance, elevation, surface, slug, tags, featured, run_count, is_starred, description, club_id, created_at, updated_at); routes with NO optional fields restore with model defaults (no crashes).

**Track entries (4 tests):** the load-bearing case — raw gzipped JSON bytes archived with `zip.Store` (no deflate) decode to waypoints on the Dart side; per-point `bpm` in a track survives byte-for-byte (today the Dart `Waypoint` model drops it — the test pins that contract, ready to flip when restore extends to read `bpm`); 100-point dense track round-trips without truncation; a run with no `track_url` still imports as an empty-track row.

**Profile (2 tests):** Go's `stripProfileID` runs before serialise — the archive must not carry `profile.id`; empty `settings_prefs` object encodes + parses cleanly.

**Regression (1 test):** end-to-end mixed-source backup — 3 runs (2 with tracks), 2 routes, profile + prefs — restores fully. Caught the bug where offline restore was silently dropping `is_starred` / `description` / `club_id` from route rows; fixed in `apps/mobile_android/lib/backup.dart` by plumbing the missing keys through.

### `apps/mobile_android/test/wear_routes_fixture_test.dart` — 4 tests

Cross-platform contract test for the phone→watch routes payload. Reads the canonical fixture at `fixtures/wear_routes_payload.json` (shared with the Wear OS Kotlin test `WearRoutesFixtureTest.kt`, 13 tests on the watch side). Pins: encoder produces the wire format byte-equivalent to the fixture's `expected_payload_json`; the JSON round-trips through `jsonEncode`/`jsonDecode` without loss; Unicode + emoji in route names survive; the pipeline filters out non-starred routes via `pickRoutesForWatchPush`. If you change the fixture, update both platform tests in the same commit.

The `wear_routes_bridge_test.dart` adds three further groups beyond the basic attach/detach/payload coverage:

- **payload-diff cache (10 tests):** the bridge caches the last shipped `routes_json` and skips channel invocations when the next encoded payload matches byte-for-byte. Pins: re-saving the same row does NOT fire a second push; saving an unstarred route when no starred change happened does NOT push; mutation that doesn't affect the wire fields is a no-op; starring a new route invalidates the cache; unstarring fires; star→unstar→re-star fires three times (not deduped — the cache is last-sent only); a swallowed PlatformException or MissingPluginException does NOT update the cache so the next attempt re-fires; detach resets the cache so a fresh attach always pushes once; re-attach within the same bridge also resets.
- **burst + lifecycle characterization (8 tests):** 5 starred saves of different routes → 5 pushes (no throttling today); 100 identical re-saves → ZERO additional pushes (diff cache catches all); 100 alternating star/unstar → 100 pushes; mixed starred + plain interleaved fires once per actual starred-set change; saveBatch with 50/50 starred+plain fires ONE push (notify-once contract); detach mid-burst stops all subsequent pushes; detach during in-flight push doesn't crash and stops further pushes after; hot-restart pattern (attach→detach→new bridge attach) works; two bridge instances on the same store push independently.
- **end-to-end wire round-trip (4 tests):** the captured `routes_json` from the channel is structurally identical to `encodeRoutesForWatch` direct output; XML/JSON-special characters round-trip via jsonEncode's built-in escaping; `updated_at_ms` is monotonic non-decreasing across consecutive pushes (the watch's stale-push gate depends on this); every captured payload satisfies the wire-format contract — JSON array of objects with exactly `{id, name, distance_m, waypoints}` keys, and every waypoint with exactly `{lat, lng}`.

### `apps/mobile_android/test/wear_routes_bridge_test.dart` — 54 tests

Pin the listener-attach / push-on-change / starred-only filter contract on the phone-side `WearRoutesBridge`. Uses `TestDefaultBinaryMessengerBinding.setMockMethodCallHandler` to intercept the `run_app/wear_routes` `MethodChannel` — no DI seam needed.

**attach (6 tests):** immediately pushes the current starred subset; pushes on every `save()` to the store; payload contains `id` + `name` + `distance_m` + `waypoints[{lat,lng}]`; only starred routes land in the payload (plain routes filtered out); empty starred list still pushes (lets the watch clear its cache); `updated_at_ms` stamps roughly current epoch millis.

**detach (3 tests):** removes the listener so subsequent store changes don't push; detach-without-attach is a no-op; double-detach is a no-op.

**re-attach (2 tests):** second `attach` replaces the first listener — no leak (verifies a single save fires ONE push, not two); attach-after-detach is also clean.

**platform error handling (3 tests):** `MissingPluginException` is silently swallowed (iOS / unregistered plugin); `PlatformException` is silently swallowed (Data Layer unavailable); a swallowed exception does NOT detach the listener (subsequent saves still push).

**integration with LocalRouteStore (3 tests):** `saveBatch` triggers exactly one push (single listener notification); `delete` of a starred route triggers a fresh push without the deleted id; starring an existing route triggers a push that includes it.

### `apps/job_worker/internal/supabase_dataexport_test.go` — 21 tests

HTTP-level coverage for the four `SupabaseClient` methods added in the May 2026 backup work: `FetchExportRoutes`, `FetchExportProfile`, `FetchUserSettingsPrefs`, `DownloadRawTrackBytes`. Uses `httptest.NewServer` to mimic the Supabase REST + Storage surface; asserts that requests are shaped correctly (path, query params, headers) AND decoded responses match the wire contract.

**FetchExportRoutes (5 tests):** happy path with two-row response (path, select param, auth + apikey headers correct); empty result returns non-nil empty slice; 5xx returns `*HTTPError`; malformed JSON returns error; user_id is URL-encoded (legacy non-uuid case with `+`).

**FetchExportProfile (4 tests):** happy path returns parsed map (display_name + preferred_unit); not-present row returns (nil, nil) so the export builder can include null without ceremony; column-restricted fields (`subscription_tier`, `subscription_at`, `parkrun_number`) are absent from the SELECT query; pass-through `*HTTPError` on 403.

**FetchUserSettingsPrefs (3 tests):** happy path returns the parsed prefs map (incl. hr_zones array round-trip); no-row response returns non-nil empty map (degrade-to-empty); null prefs column also returns empty map.

**DownloadRawTrackBytes (4 tests):** bytes round-trip verbatim (no decode, matches the contract); 404 returns `*HTTPError`; auth headers present (apikey + Authorization); 1MB body round-trips without truncation.

**Cross-cutting (5 tests):** `FetchExportRoutes` with every optional pointer field set decodes to non-nil pointers (DistanceM, ElevationM, Surface, IsPublic, Slug, Featured, RunCount, IsStarred, Description, ClubID, CreatedAt, UpdatedAt); context cancellation propagates; all 4 new methods carry both apikey + Authorization headers via the shared `do()` helper (defensive guard against a future refactor that bypasses it).

### `apps/web/src/lib/restore_orchestrator.test.ts` — 25 tests

Pure-logic coverage of the restore orchestrator extracted from `backup.ts`. The Supabase upserts live behind a small `RestoreBackend` interface; tests substitute a counter-tracking fake so the loop is observable without booting supabase-js. Production wires a thin supabase-js adapter (`supabaseRestoreBackend()` in `backup.ts`); tests wire the fake (`makeFakeBackend()`).

**profile + settings (5 tests):** profile present → `upsertProfile` fires with stripped fields + user id; null profile → no call; `upsertProfile` error becomes a warning, downstream stages still process; non-empty `settingsPrefs` triggers `upsertSettings`; empty prefs is a no-op; settings error → warning + downstream continues.

**runs + tracks (10 tests):** happy-path single run uploads track BEFORE upserting row (order pin); run with no track in archive still upserts the row with `track_url=null`; uploadTrack failure → warning, row still upserts; upsertRun failure → warning, other rows continue (partial-success contract); `generateNewIds` replaces every run id; with `generateNewIds`, the track upload path uses the NEW id even though the archive is keyed by ORIGINAL id; event_id resolution — unknown ids nulled, known ids preserved; `fetchValidEventIds` is only called when ids are present; resolver error bubbles (current contract pinned); `coalesceActivityType` inserts `'run'` when metadata missing the key, and preserves explicit values.

**routes (3 tests):** happy-path upserts with new user_id stamped; `generateNewIds` replaces route ids; failure on one route doesn't sink the others.

**progress events (2 tests):** stages emit in order (profile → runs → routes → done); running totals report 0 → 1 → 2 for a 3-run input.

**edge cases (3 tests):** empty parsed backup is a no-op (zero backend calls); 100-run backup processes all rows in order without dropping + finishes well under 2 s; `coalesceActivityType` clones the metadata input rather than mutating it.

### `apps/mobile_android/test/backup_server_client_test.dart` — 13 tests

Pluggable-fetcher coverage for `BackupServerClient.fetchBackupToFile`, the HTTP client that drives the Go service's `POST /v1/export?format=backup` path. Tests inject canned request + download fetchers so the round-trip is observable without sockets. Covers: isConfigured edges (empty vs non-empty baseUrl); preconditions (unconfigured / empty token throw `BackupServerError`); round-trip (POSTs `{format: 'backup'}` with the bearer token at the right URL, then downloads the signed URL to the supplied File; trims trailing slash on baseUrl); failure modes (non-200 export response, missing signed URL, empty-string signed URL, downloadFetcher exception propagation); and count extraction across int / num / missing JSON shapes. Backs the server-first → local-fallback dance in `BackupService.createBackup`.

### `apps/mobile_android/test/backup_test.dart` — 41 tests

Round-trip + invariant coverage for `BackupService.createBackup` + `restore`. 24 existing manifest / offline-restore / progress / api:null tests; 7 **writeBackupZipStreaming** tests added with the streaming + parallel writer refactor in May 2026 (see `decisions.md § 66`); and a 10-test **tryServerBackup** orchestration group added with the server-first / local-fallback wiring.

The streaming-writer group exercises the testable seam extracted from `createBackup`: writes a valid backup that round-trips through the existing restore decoder; emits stage + tracks progress callbacks in order; downloads tracks in bounded-concurrency batches (peak `inFlight` counter ≤ supplied `concurrency`, observable parallelism with 20 tasks); a single download failure doesn't sink the rest of the backup; `runsWithTracks=[]` produces a valid manifest-only ZIP; overwrites an existing output file rather than appending junk; rejects `concurrency < 1`.

The **tryServerBackup** group covers the static helper that decides whether to attempt `POST /v1/export?format=backup`: returns false for null / empty-baseUrl serverClient, null / empty accessToken (without ever invoking the request fetcher); returns true + writes the file on server success; cleans up partial output on failure so the local writer sees a clean slate; surfaces non-200 + 5xx + connection-reset paths as `false` without throwing; emits `server` + `done` progress events on success and `server` without `done` on failure; cleanup is best-effort (no-file case doesn't throw). The fake `BackupServerClient` pluggable fetchers make the round-trip observable from outside without sockets — pairs with `backup_server_client_test.dart`'s lower-level coverage of `fetchBackupToFile`.

### `apps/mobile_android/test/csv_run_importer_test.dart` — 26 tests

Pure-Dart coverage of `CsvRunImporter.parse` — the lossy summary path that round-trips Settings → "Export runs as CSV". Two header shapes are exercised: the 5-column mobile/web Settings export and the 17-column backend `/export-data` GDPR shape. The parser is offline-first by design (no API, no Supabase) and idempotent on re-import via a stable `external_id`. See `decisions.md § 65`.

**5-column form (6 tests):** single-row round-trip stamps `metadata.imported_from='csv'` + `imported_at` + default `activity_type='run'` + synthetic `external_id` prefix; preserves multi-row order; unknown `source` cell falls back to `RunSource.app`; the synthetic `external_id` is deterministic, differs by start time, and matches across two parses of the same input.

**17-column backend form (3 tests):** preserves the original `id`, `external_id` (e.g. `strava:1234567890`), and the full `metadata` JSON column; tolerates quoted commas + escaped quotes inside the metadata cell; malformed metadata JSON is dropped without sinking the row (the importer surfaces a warning, the `activity_type='run'` default still lands).

**Error handling (7 tests):** missing required columns surfaces a single header-level error; invalid date row is skipped + reported (1-based row number); invalid distance/duration row is skipped + reported; empty input + header-only input both return empty results; blank lines between data rows are skipped; rows shorter than the header are reported, not parsed.

**Header tolerance (2 tests):** `started_at` is accepted as an alias for `date`; column names are case-insensitive.

**Adversarial input (8 tests):** 1000-row CSV parses in under a second (O(n²) regression guard); Unicode + emoji + accents in title round-trip intact through quoted cells; RFC-4180 quoted-comma + escaped-double-quote (`""`) survives; mixed valid + invalid rows produce a partial result (good rows + per-row errors with 1-based row numbers, not all-or-nothing); CRLF line endings (Excel / Windows tools) parse cleanly; negative numerics pass through to the upsert layer (DB CHECK is source of truth, not the parser); trailing whitespace round-trips leniently; deeply-nested 17-column `metadata` (laps array, hr zones) round-trips JSON-equivalent.

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

### `apps/mobile_android/test/local_route_store_test.dart` — 31 tests

Persistence tests for `LocalRouteStore` mirroring the `local_run_store_test.dart` pattern — `init(overrideDirectory: ...)` with a tempDir, real file I/O, no mocks. Covers init (directory creation, non-`.json` file filtering, corrupt-file tolerance), save (file write, round-trip across fresh instances, replace-on-same-id, newest-first ordering, single-listener-call invariant), `saveBatch` (parallel write + single notify, empty-iterable no-op, overlapping-id replace), `delete` (disk + memory + unknown-id), the unmodifiable `routes` view, and the **offline pin** group (15 tests) — `pinOffline` / `unpinOffline` idempotency, listener notification, sidecar round-trip across cold start, delete clears the pin, unmodifiable views, pin-without-route is allowed and surfaces when the route lands; pin survives saveBatch overwrite of the same id; concurrent pin/unpin pairs serialise correctly and the sidecar matches in-memory; tolerates a corrupt-JSON / wrong-shape / mixed-types sidecar on cold start without crashing; 100-pin round-trip stays well under 2 s and survives cold start intact. The local-only flag semantics are pinned by `decisions.md § 64`.

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

**`debugRunFromRow` (8 tests):** basic field mapping, `track_url` stashed onto `metadata` for lazy-fetch by callers, null metadata + null `track_url` leaves `Run.metadata` null, existing metadata keys survive alongside the stashed `track_url`, every `RunSource` value parses correctly, unknown `source` falls back to `RunSource.app` (matches the [`apps/web/src/lib/types.test.ts`](../../apps/web/src/lib/types.test.ts) defensive contract), `externalId` and `createdAt` pass through.

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

### `apps/web/src/lib/backup.test.ts` — 7 tests

TypeScript unit tests for the streaming + parallel-download backup writer (`lib/backup_writer.ts`). Run with `npx tsx --test src/lib/backup.test.ts` from `apps/web`. Exercises the pure writer seam without supabase-js: round-trip through JSZip to confirm manifest + runs + routes + profile + tracks all land; bounded-concurrency contract observed via a counter-tracking fetcher (peak in-flight ≤ `concurrency`, observable parallelism); single-track failure doesn't sink the rest (manifest counts reflect what landed); empty `runsWithTracks` produces a valid manifest-only archive; `concurrency < 1` rejected; progress events ordered (`tracks` → `writing` → `done`); profile `id` field stripped to keep the archive re-homeable.

### `apps/web/src/lib/backup_reader.test.ts` — 23 tests

Pure-Dart-equivalent tests for the read side at `lib/backup_reader.ts` — `parseBackupArchive` + `stripServerManagedProfileFields` + `coalesceActivityType` + `extractEventIds`. Run with `npx tsx --test src/lib/backup_reader.test.ts`. Builds synthetic archives in-memory with a thin `buildArchive` helper; the Uint8Array `JSZip.loadAsync` accepts in Node (the parameter type is widened to accept it explicitly).

**parseBackupArchive (11 tests):** missing `manifest.json` throws; wrong format throws; future-version throws; missing `version` field accepted as v0 for back-compat; happy path returns runs + routes + profile + settingsPrefs + lazy `getTrackBytes`; `getTrackBytes` returns null for unknown id; missing `runs.json` / `routes.json` / `profile.json` yields safe defaults; `profile.json` with `null` profile field is tolerated; manifest carries metadata keys (exported_by_user_id, exported_from, counts) through verbatim.

**stripServerManagedProfileFields (3 tests):** drops `subscription_tier` + `subscription_at` + `parkrun_number`; no-op when none of those keys are present and returns a fresh object; preserves nested objects (hr_zones) untouched.

**coalesceActivityType (5 tests):** inserts `'run'` when metadata is null / undefined / missing the key / non-string-typed / not a map; preserves explicit string-typed values; clones the input instead of mutating it.

**extractEventIds (2 tests):** distinct ids extracted; nulls / undefineds / empty strings / non-strings / missing-key entries all dropped.

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

Mirror of `apps/mobile_android/test/fitness_test.dart`. Pure tests for `lib/fitness.ts`. `qualifyingRuns` covers sub-3km / sub-5min drop, every recognised `source` accepted plus a non-recognised value rejected. `vdotFromRun` covers sub-1km / sub-2min returning null, ~50 for a 20-min 5k, ~54 for a 3-hour marathon, faster pace → higher VDOT. `currentVdot` covers picking the best in-window qualifying run and ignoring runs older than 90 days. `vo2MaxFromVdot` is identity passthrough. `thresholdPaceSecPerKmFromVdot` covers null in / null out, VDOT 50 in the 240-260 s/km band, and higher VDOT yielding a faster threshold (catches the formula bug fixed during this pass — see [decisions.md § 54](../architecture/decisions.md#54-fix-thresholdpacesecperkmfromvdot-formula)). `runTss` covers the sub-100m / sub-30s / zero-threshold returning 0, threshold pace = 100 TSS at 1 hour (Coggan reference), and faster-than-threshold raising TSS faster than linearly. `trainingLoad` covers null inputs / no qualifying runs all-null, non-null curves with at least one qualifying run, TSB rises during a 14-day taper. `computeSnapshot` covers the rollup contract + empty input. `recoveryAdvice` covers null inputs, sub-10 CTL → consistency-building advice, and the five-band TSB ladder producing five distinct strings.

### `apps/web/src/lib/coach/types.test.ts` — 4 tests

Smoke tests for the coach config / tier shape. `emptyUsage` returns a fresh zeroed object every call (no shared reference; mutation doesn't leak across calls). `TIER_LIMITS.free` keeps a finite daily cap so anonymous abuse can't drain quota. `TIER_LIMITS.pro` carries a finite daily cap that's strictly higher than free's, with larger token + runs windows. Anchors the paywall contract — flipping any of these silently would change rate-limit behaviour without code review.

### `apps/web/src/lib/coach/limits.test.ts` — 22 tests

Pure tests for the validation / clamping helpers extracted from `coach/handler.ts` so they can run under `tsx --test` without booting `createClient`. `parseAuthHeader` covers `Bearer ` prefix stripping (case-insensitive on the prefix), null / undefined / empty input, bare `Bearer ` returning null, and tokens-without-prefix being passed through verbatim. `clampRunsLimit` covers undefined / null returning the default, non-finite (NaN, Infinity, non-numeric strings) returning the default rather than the tier cap, the tier max ceilings (free=30, pro=75), the floor at 1 (zero-runs context is never useful), fractional input being truncated, string-typed integer coercion, and pro tier honouring larger requests up to its cap. `jsonError` covers the canonical pre-stream response shape, extra fields landing alongside `error`, and the spread-order behaviour where `extra.error` wins over the literal. `rateLimitHeaders` covers the free-tier finite limit / remaining, remaining clamping to 0 when usage exceeds the cap, the pro-tier finite cap (10/day) reporting correctly, and pro remaining clamping to 0 when usage exceeds the pro cap. `personalityAddendum` covers the `drill_sergeant` and `analytical` tone overrides + the empty-string default for null / undefined / unknown styles.

### `apps/web/src/lib/settings_overlay.test.ts` — 9 tests

Pure tests for the universal + per-device prefs overlay helper extracted from `settings.ts` so it can run under `tsx --test` without dragging in the SvelteKit `$env/static/public` virtual import. `effective<T>` covers the fallback path when neither bag has the key, universal-wins-over-fallback, device-overrides-universal, device-null fall-through to universal (null is treated as "missing", not "unset to nothing"), device-undefined fall-through, universal-null-with-no-device fallback, falsy-but-concrete values (0, '', false) winning over fallback, object / array values round-tripping, and the type-parameter being a viewer-side hint with no runtime cast.

### `apps/web/src/lib/watch_payload_fixture.test.ts` — 6 tests

Cross-platform contract test against `fixtures/watch_run_payload.json`. The same fixture is decoded by `apps/mobile_android/test/watch_payload_fixture_test.dart`, its `mobile_ios` mirror, and the Wear OS Kotlin test (`apps/watch_wear/.../WatchRunPayloadFixtureTest.kt`). Editing the fixture without updating all three platform tests is a deliberate hard-fail. Web's slice asserts: source parses to a valid `RunSource`, `metadata.activity_type` is a registered value, `avg_bpm` is positive, laps use the canonical 1-based `index` + cumulative-BEFORE `start_offset_s` shape with deltas accumulating correctly, and the row + payload sources agree.

### `apps/watch_wear/.../*Test.kt` — ~395 Wear OS Kotlin/JUnit tests across 32 files

Run with `cd apps/watch_wear/android && ./gradlew testDebugUnitTest`. Pure-JVM tests — no Android instrumentation, no Robolectric. The team deliberately avoided UI-test infrastructure (see `apps/watch_wear/CLAUDE.md`'s "layouts can't be unit-tested without Robolectric"); the pattern is to extract pure helpers from the Android-bound classes and exercise them at the JVM level.

**Sync / auth coverage (~95 tests)** — the highest-impact surface. `DrainQueueLoopTest.kt` (18) covers the offline-runs drain orchestrator extracted from `RunViewModel.drainQueue`: per-error-class branches (drop / skip / stop / refresh-and-retry), the one-shot 401 refresh-then-retry, partial-failure mid-loop, transient-vs-permanent backoff arming, side-effect ordering. `DrainBackoffTest.kt` (7) — exponential backoff math. `SupabaseErrorClassificationTest.kt` (16) — error → `DrainAction` mapping, the post-stop "unauthorized" regression guard. `StoredSessionTest.kt` (10) — auth session cache + `isExpired` math. `SessionBridgeTest.kt` (4) — Data Layer auth handover from the paired phone. `RoutesBridgeJsonTest.kt` + sibling fixtures (68 tests across 5 classes) — pure-JVM coverage of every load-bearing piece of the phone→watch route push pipeline. The Wearable DataLayer listener itself can't run on a host JVM, so the testable seam is the JSON contract + the pure-logic gates that surround it. Five classes:

  - **`RoutesBridgeJsonTest`** (17 tests) — `parseRoutesJson` contract. Baseline 9 tests (empty array, malformed JSON, single-route round-trip, <2 waypoint drop, missing id/waypoints drop, name + distance fallbacks, individual malformed waypoint drops, multi-route order) plus 8 hardening tests (forward-compat — extra top-level fields ignored; Unicode in name + id round-trips; 500-route payload under 500 ms; duplicate ids preserved for caller dedupe; string-coerced numerics accepted; truly-garbage non-numeric values drop the waypoint and route; negative + extreme coordinates pass through; top-level non-array yields empty list).
  - **`RoutesPushApplyTest`** (17 tests) — pure-logic guards over `shouldApplyRoutesPush` + `sortRoutesByRecency`. Stale-push protection (first push applied when no prior; strictly-newer wins; equal-timestamp re-delivery rejected; older delivery rejected; negative/zero treated as one-shot but doesn't override later real-stamp; monotonic sequence). Recents re-ordering (empty recents preserves order; recent floats to front; multiple recents preserve LRU order; unknown id silently skipped; empty input; idempotent; output length matches input; output contains exactly same id set; SavedRoute identity preserved; 100-route + 10-recent sort under 50 ms).
  - **`RoutesPushApplySequenceTest`** (10 tests) — composes the gate + the sort over realistic event sequences. Monotonic sequence applies every push; out-of-order push leaves earlier state intact; same-timestamp re-delivery is a no-op; empty push at newer timestamp clears the list; recents float matching ids to front of each push; recents that vanish from a subsequent push silently dropped; cold-start zero-timestamp push applied as one-shot; 100-push stress with alternating future/past timestamps; out-of-order delivery C-A-B applies only C; recents updated mid-sequence affects only later pushes.
  - **`RoutesPushTest`** (4 tests) — `RoutesPush` data class equality + the "no leak surface" guard (extra JSON top-level fields the phone never sends don't materialise into SavedRoute fields).
  - **`WearRoutesFixtureTest`** (13 tests) — cross-platform fixture parity + end-to-end pipeline. Reads `fixtures/wear_routes_payload.json` (also consumed by `apps/mobile_android/test/wear_routes_fixture_test.dart`). Baseline 7 tests pin the parser handles the canonical wire format, Unicode survives, both int + double distance encodings are tolerated, waypoint counts match, every parsed route has ≥2 waypoints, and the fixture's three contract keys (`input_routes`, `expected_payload_json`, `expected_parsed_routes`) stay in lockstep. Plus 6 pipeline tests that compose `parseRoutesJson` + `shouldApplyRoutesPush` + `sortRoutesByRecency` over the fixture wire — full apply sequence, Unicode preservation end-to-end, two-push stale-gate sequence with the fixture as the newer payload, empty wire payload tolerated, byte-identical re-delivery is parser-safe, narrow SavedRoute shape pins (no leak surface for user_id / clubId / isStarred from a future encoder bloat).
  - **`RoutesBridgeWiringTest`** (13 tests) — source-grep guards on the production wiring. `RunViewModel` calls `observeRoutesBridge` in `init`; constructs a `RoutesBridge(application)`; the observer uses BOTH `current()` (cold-start hydrate) and `events.collect` (live updates); consults `shouldApplyRoutesPush` AND tracks `lastAppliedRoutesPushMs` so the gate is effective; writes through `routeStore.save`. `RoutesBridge.kt` declares `/saved_routes` PATH, the two DataMap keys (`routes_json` + `updated_at_ms`), exposes `Flow<RoutesPush>` (not `Flow<List<SavedRoute>>`), and the helpers are file-level `internal`. RunViewModel.sortByRecency delegates to the file-level fn. No `.take(N)` truncation slips into the parser. `SupabaseUrlBuildersTest.kt` (13) — pinned URLs / bodies the watch sends (starred-first routes query + fallback, the `refresh_token`-only body, the mandatory `grant_type=refresh_token` query). `SaveRunRowMapTest.kt` (10) — the `runs.insert` row map every saveRun POSTs (column set, `source="watch"`, `external_id = runId` for retry idempotency, is_public omit-vs-set semantics). `EncodeJsonMapTest.kt` (18) — the hand-rolled JSON encoder every POST flows through (string escaping, null handling, numeric type preservation, `JsonObject` no-double-quoting). `QueuedRunSerializationTest.kt` (10) — the DataStore wire format for offline-queued runs (the V1 → V2 shape contract).

**Recording / GPS / sensors (~110 tests)** — `RouteMathTest.kt` (17) — off-route distance + remaining-km math, `ElapsedMathTest.kt` (8) — pause/resume elapsed time, `StreaksTest.kt` (16) — streak math, `MercatorTilesTest.kt` (13) — Web Mercator + tile coords, `TrackOverlayBufferTest.kt` (7) — rolling buffer geometric halving, `TrackWriterTest.kt` (9) — streaming GPS to disk, `RecordingRepositoryTest.kt` (10) — process-singleton StateFlow, `CheckpointSerializationTest.kt` (9) — crash-recovery snapshot, `PaceAlertTest.kt` (14) — the rate-limited pace-drift trigger (30 s/km drift + 30 s rate-limit, the no-fire-preserves-timestamp regression guard), `FinishedLapsBuilderTest.kt` (10) — per-lap split vs cumulative math + the bonus-row gate, `HeartRateMonitorTest.kt` (18) — BPM validity gate + the Health Services value cascade, `GpsRetryDecisionTest.kt` (11) — the 30 s mid-run-silent self-heal trigger including the load-bearing "initial cold-acquire is NOT a stall" guard, `PedometerMathTest.kt` (10) — step-counter baseline subtraction.

**Untrusted-input parsers (~25 tests)** — `ParseRouteWaypointsTest.kt` (22) covers the cross-process route-waypoints parser (Intent extra from another process — fail-quiet contract: null / malformed / wrong-shape / partial all return empty list, never crash). `SavedRouteTest.kt` (9) — route deserialization.

**UX / phrasing (~38 tests)** — `TtsPhrasesTest.kt` (17) — pinned voice-cue dialect matching `apps/mobile_android/lib/audio_cues.dart` (singular/plural switch on `1 kilometre`, integer-truncated pace, decimal-separator locale-independence, the runner's-muscle-memory `Run started` constant). `ActiveRunTileFormattersTest.kt` (7) — tile formatters. `UniversalSettingsTest.kt` (30) — settings overlay including HR zone resolution precedence (`hrZones > maxHrBpm * %s > Tanaka 208 − 0.7×age > null`). `WatchRunMetadataTest.kt` (12) — `buildRunMetadata` JSON shape.

**Cross-platform + arch guards (~30 tests)** — `WatchRunPayloadFixtureTest.kt` (3) Kotlin slice of the `fixtures/watch_run_payload.json` contract pinned across Dart + TS + Kotlin (no Swift slice — see the watchOS gap above). `RaceSessionClientTest.kt` (7) — race ping + result client shape. `RouteMiniMapWiringTest.kt` (15) and `ScreenWiringTest.kt` (15) — source-grep arch guards on the data-flow + UI-wiring chains. Layouts can't be unit-tested without Robolectric, but the arch guards pin that key callbacks (`markLap`, `vm::resume`, `recoverCheckpoint`, `HoldToStopButton`) stay wired so a refactor can't silently drop them.

Pattern across all the test files: production-code extractions live in dedicated files (`DrainQueueLoop.kt`, `PaceAlert.kt`, `EncodeJsonMap` / `SupabaseUrlBuilders` at file-level in `SupabaseClient.kt`, etc.) and the wrapper methods on `RunViewModel`, `RunRecordingService`, `Pedometer`, `HeartRateMonitor` delegate to them. **Behaviour is preserved exactly** — the extractions are testability-only, not refactors.

The handful of Wear OS surfaces NOT covered (need instrumentation): `Pedometer` sensor binding itself, `HeartRateMonitor.MeasureCallback` registration with Health Services, `GpsRecorder` `FusedLocationProviderClient` callback, foreground-service lifecycle, Compose UI screen rendering (the team deliberately stayed off Robolectric — `ScreenWiringTest`'s source-grep approach is the cheap-but-effective alternative).

### `apps/job_worker/internal/*_test.go` — Go unit tests

Run with `go test ./...` from `apps/job_worker`. No network or Postgres dependency — the worker tests use a fake `Backend`, the matcher tests use `httptest.Server` to stand in for OSRM. Files:

- **`worker_test.go`** — table-driven coverage of the claim → handle → finish loop. Pins the transient/permanent classifier (`isTransient` branches on `HTTPError.StatusCode`, falls back to message sniffing for dial errors), the re-upload race (`TestWorker_ReuploadDuringMatchDiscardsResult` for the pre-write recheck path; `TestWorker_StaleSourceTrackURLDiscardsResult` for the `source_track_url` CAS path), the auto-link scoring policy (`TestWorker_AutoLinksWhenConfident` — must satisfy both endpoint-offset < 200 m AND |distance ratio| < 0.20 against `runs.distance_m`), and the **per-job HandleTimeout contract** (`TestWorker_HandleTimeoutDefersStuckJob` — synthetic stuck Storage download against a 50 ms HandleTimeout exits via `context.DeadlineExceeded` → `isTransient` → `defer_job`, never `finish_job`; pins the run-to-completion-OR-cancel guarantee documented in decisions.md § 58).
- **`matcher_test.go`** — pins `PassthroughMatcher` contract: input not aliased into output, empty in → nil out, stable algorithm/version strings.
- **`matcher_osrm_test.go`** — 10 tests covering `OSRMMatcher`: chunking (250 points → 3 calls, stitched), tail-of-1 passthrough, NoMatch translation (`code != "Ok"` → nil, downstream `'skipped'`), HTTP error surfacing (`*HTTPError` for 5xx), malformed-JSON wrapping, trailing-slash normalisation. The real engine isn't reachable from a unit test (multi-GB pre-extracted graph), so the tests stand up an `httptest.Server` that returns canned `/match` JSON.

### `apps/mobile_android/test/social_service_test.dart` — 13 tests

Pure-unit coverage for the value classes and helpers exposed by `lib/social_service.dart`. Covers `ClubView.isAdmin` / `isEventOrganiser` / `isRaceDirector` / `isMember` (the booleans that drive admin-only buttons + race-director Arm/Fire on `club_detail_screen` + `event_detail_screen`) — pinning that owner / admin both grant the full ladder, that `event_organiser` and `race_director` are siloed, that `member` carries no special affordances, and that an unrecognised viewerRole string is treated as not-admin so a future role we haven't taught the client about doesn't accidentally inherit admin powers. Plus 6 tests for `parseBydayCodes` (the byday-jsonb parser used by `_enrichEvents` + `fetchNextRsvpedEvent`): valid 'MO','WE','FR' shape, order + duplicate preservation, non-array fallback, empty + all-unknown → null (caller treats as "no override"), mixed known/unknown filters to known.

The Supabase-touching surface of `SocialService` (`browseClubs`, `fetchMyClubs`, the enrichment pipelines, RSVP writes, post creation) is NOT covered here — the class resolves `Supabase.instance.client` inline, so meaningful unit coverage of those branches needs a DI seam refactor (constructor-injected `SupabaseClient`, mirroring the `ApiClient.withClient` pattern). Tracked in [What's not covered](testing.md#whats-not-covered-honest).

### `apps/backend/supabase/tests/rls_*.sql` — pgtap RLS suite (279 tests across 37 files)

pgTAP tests against the highest-blast-radius RLS policies, run by `cd apps/backend && supabase test db --local`. Gated in CI by the `pgtap-rls` job. Each file is wrapped in `begin; ... rollback;` so it's idempotent against the running local DB; tests filter to fixture user_ids so they don't trip on `seed.sql` rows. Pattern: insert two test users into `auth.users`, then `set local role authenticated; set local "request.jwt.claims" = '{"sub":"<uuid>"}';` to switch identity. Anon paths use `set local role anon`.

- **`rls_runs_test.sql`** — 16 tests. Owner CRUD; non-owner direct `SELECT` on `runs` returns zero (the wire-leak SELECT policy was deliberately dropped in 20260701_001 — public visibility now flows through the `public_runs` view, see [decisions.md § 33](../architecture/decisions.md)); `public_runs` view exposes redacted public rows + strips audit / training-plan-linkage keys (`strava_id`, `plan_workout_id`); anon SELECT on `runs` is empty but on `public_runs` returns the public row; `is_run_visible_to(run_id, caller)` SECURITY DEFINER helper used by 5 sibling policies returns true for any caller on a public run.
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
- **`rls_event_attendees_test.sql`** — 10 tests pinning the RSVP policies after migrations `20260417_001` (per-instance PK), `20260428_001` (organiser-add path), `20260617_001` (drop legacy duplicate policy), `20260629_001` (self-RSVP visibility gate). Active member SELECTs the roster, stranger sees zero; active member self-RSVP succeeds; **stranger self-RSVP to an invisible private-club event is rejected** (the 20260629_001 closure — pre-fix, an enumerator could plant RSVPs against any event_id); forged-user_id RSVP rejected; event organiser can register a walk-up attendee (positive control on the organiser-add branch); plain member cannot register another user; user can UPDATE their own RSVP status; **organiser cannot UPDATE another user's RSVP** (own-row is the only write path — the walked-up user owns their own RSVP); user can DELETE their own RSVP. The per-instance PK `(event_id, user_id, instance_start)` from 20260417_001 is implicit in every fixture / assertion.
- **`rls_events_test.sql`** — 9 tests pinning the base row-level policies on `events` (companion to `rls_events_meet_point_test.sql`, which covers the column-grant lockdown). Active member can SELECT events of their private club, stranger sees zero; `event_organiser` can INSERT / UPDATE / DELETE (positive control); plain member cannot — **and `race_director` cannot either**. The race_director / event_organiser role split from 20260428_001 is the load-bearing decision pinned here: directors arm + start + end races but do NOT publish events, organisers do the opposite. A regression that widens `is_event_organiser` to include `race_director` (or `member`) gets caught. Also pins the `created_by = auth.uid()` author-forge guard against a legitimate organiser misattributing the row.
- **`rls_club_posts_test.sql`** — 9 tests pinning the threaded-feed policies. Active member SELECT works; stranger SELECT on a private club's feed returns zero; any active member can INSERT a **top-level OR reply** (the 20260428_001 "members can post" catch-all is the sole binding INSERT rule after `20260820_001` dropped the two 20260417_001 dead-code policies — they were dead from the moment 20260428_001 landed because their allow set was a strict subset of the catch-all); stranger and **pending requester** are both rejected (the `is_club_member` exclusion of pending status is the load-bearing write guard); forged author_id rejected; author can DELETE their own post; **club owner cannot DELETE a member post** (no admin-DELETE policy — moderation is via member removal, asymmetric with `club_members` where admins can DELETE other rows).
- **`rls_club_members_test.sql`** — 10 tests pinning the membership-row policies after migrations `20260417_001` (active / pending status) + `20260702_001` (join-policy gate). Pending requester reads their own row (the own-row escape hatch needed for "Request pending" UI); active member reads the full private-club roster; stranger sees zero rows of a private club's roster; self-join an open club as `member`/`active` succeeds; self-join with `role='admin'` is rejected (the **role pin** is the load-bearing privilege-escalation closure — 20260702_001 landed because the original policy let any self-joiner claim admin); self-join a request-policy club with `status='active'` is rejected (must be pending — admin approval flow); forged-`user_id` planting rejected; admin can UPDATE another row, plain member cannot; user can DELETE their own row to leave the club. Invite-only INSERT paths are out of scope here — they flow through the `join_club_by_token` SECURITY DEFINER RPC.
- **`rls_clubs_test.sql`** — 9 tests pinning the row-level policies on `clubs` (companion to `rls_clubs_invite_token_lockdown_test.sql`, which covers column grants + the `get_club_invite_token` RPC). Owner + active-member can SELECT a private club, stranger sees only the public one; forged-`owner_id` INSERT is rejected (which also blocks the `enroll_club_owner` trigger from elevating the victim into an owner-role membership row); admin (non-owner) can UPDATE but **cannot DELETE** — the asymmetry between the `is_club_admin` UPDATE policy and the `owner_id = auth.uid()` DELETE policy is load-bearing and pinned explicitly. Plain-member UPDATE and stranger DELETE are silent no-ops; owner DELETE is the positive control. Cross-user fixture setup uses pre-role-switch INSERTs to bypass RLS (same pattern as the other suites — `auth.users` rows + the auto-enroll trigger don't require `auth.uid()`).
- **`rls_segments_test.sql`** — 10 tests pinning the final policy stack on `segments` after migrations `20260526_001` + `20260703_001` (route through `is_route_visible_to`) + `20260819_001` (function moved to `private`). Author + stranger can SELECT a segment on a public route; stranger cannot SELECT a segment on a private route; forged-`created_by` INSERT rejected; INSERT against an invisible private route rejected (closes the same shape as `route_reviews`); author can UPDATE their own segment but a stranger UPDATE is a silent no-op; the `length_m >= 100` CHECK (decisions §37) fires on a tiny segment. Anon SELECT covered for both the public + private cases — same regression-guard story as `rls_route_reviews_test.sql`.
- **`rls_route_reviews_test.sql`** — 10 tests pinning the final policy stack on `route_reviews` after migrations `20260627_001` (INSERT visibility gate) + `20260703_001` (route through `is_route_visible_to`) + `20260819_001` (function moved to `private` schema, anon grant restored). Reviewer can read their own row + a non-author can read on a public route; forged-`user_id` INSERT is rejected; INSERT against an invisible private route is rejected (closes the cross-user pollution shape); cross-user UPDATE / DELETE are silent no-ops; the rating 1..5 CHECK and the `(route_id, user_id)` UNIQUE both fire. **Anon read paths are now covered** — before 20260819_001, anon SELECT on `route_reviews` SEGV'd the PG 17.6 backend because the 20260711_001 revoke left the SELECT policy invoking a function anon couldn't EXECUTE; tests 9 + 10 are the regression guard if the function move is reverted.
- **`rls_function_hygiene_test.sql`** — 9 tests pinning the function-grant + search_path closures from migrations `20260710_001` (search_path on `weekly_mileage` + `personal_records`), `20260711_001_definer_grant_hygiene.sql` (revoke EXECUTE on `is_route_visible_to` + `recompute_event_ranks` from anon and PUBLIC), `20260713_001_is_run_visible_to_anon_grant.sql` (restore the anon EXECUTE that pass-1 dropped on `is_run_visible_to`), `20260812_001_is_run_visible_to_private_schema.sql` (move `is_run_visible_to` to the `private` schema — closes the PostgREST RPC oracle without breaking the share page), and `20260819_001_is_route_visible_to_private_schema.sql` (same pattern for `is_route_visible_to`, after the 20260711_001 anon revoke turned out to break anon SELECT on `route_reviews` + `segments` — manifested as a PG 17.6 SEGV instead of a clean 42501). Pinned with `has_function_privilege('<role>', '<fn>', 'execute')` so a future Supabase auto-grant or a `grant ... to anon, authenticated` mistake fails CI, plus existence checks against `pg_proc` to assert the public-schema versions of both visibility helpers stay dropped.

These twenty-three files cover the tables + RPCs + triggers where a single-row leak / single-trigger bypass would be a privacy, impersonation, or revenue incident. They do NOT exhaustively cover every table (37 in total) — the original seven gaps (`clubs`, `club_members`, `club_posts`, `events`, `event_attendees`, `route_reviews`, `segments`) are now closed; remaining uncovered tables are lower-blast-radius (`run_kudos` / `run_comments` / `run_photos` are pinned indirectly via the `engagement_chain` helper, plus auxiliary tables like `webhook_events`, `rate_limits`, etc. that don't carry user content). Add a file when you touch a sensitive policy, or when an audit lands.

### `apps/backend/supabase/functions/**/*.test.ts` — 54 deno tests across 4 files

Run all of them with `cd apps/backend && deno test --no-check supabase/functions/_shared/webhook_security.test.ts supabase/functions/_shared/body_limit.test.ts supabase/functions/revenuecat-webhook/lib.test.ts` and (with `SUPABASE_TEST_URL=http://127.0.0.1:54321 supabase functions serve --env-file .env.local`) `deno test --no-check --allow-net --allow-env supabase/functions/_shared/handler_envelope.test.ts`. The `edge-functions` CI job runs all four files on every PR.

- **`_shared/webhook_security.test.ts`** — 17 tests. `hmacHex` against the RFC 4868 §2.7.2 case 4 reference vector (with byte-exact `Uint8Array` inputs — the function accepts `string | Uint8Array` on both `secret` and `body`); `timingSafeEqual` (equal / unequal-same-length / length-mismatch / no-short-circuit-on-first-mismatch); `validateFreshness` (recent / 7-day boundary / too-old / clock-skew tolerance / custom window + skew args); `isValidUuid` (8-4-4-4-12 hex, rejects malformed); `isAnonymousAppUserId` (`$RCAnonymousID` prefix detected, others false). The `timingSafeEqual` and `validateFreshness` helpers were extracted out of the two webhook `index.ts` files so the production code path now imports the tested module directly — no duplicate definition can drift.
- **`_shared/body_limit.test.ts`** — 9 tests for `readJsonWithLimit` and `readTextWithLimit` covering small / at-limit / over-limit bodies, chunked-transfer bypass, and the `tooLarge` response shape.
- **`revenuecat-webhook/lib.test.ts`** — 19 tests, two functions. `mapEventToTier(eventType, productId, currentTier)`: every activating event → `pro`, lifetime-product detection (substring match), null product id → `pro` default, EXPIRATION + CANCELLATION → `free` for non-lifetime, → `null` for lifetime (parallel-sub cancel can't downgrade), null `currentTier` → `free` (conservative default), unknown event types → `null`, **BILLING_ISSUE → null tier (no downgrade during grace period)**, **SUBSCRIPTION_PAUSED / TRANSFER → null tier (no-op events)**, plus the disjoint-taxonomy sanity test. `mapEventToBillingIssue(eventType, now?)`: BILLING_ISSUE → ISO timestamp string (set the flag); RENEWAL / UNCANCELLATION / EXPIRATION / CANCELLATION → `null` (clear the flag — payment recovered or subscription ended); other events → `undefined` (no write). One combined test pins the independence: BILLING_ISSUE moves the flag but NOT the tier, so a future refactor that re-couples them fails here.
- **`_shared/handler_envelope.test.ts`** — 9 HTTP-level tests covering the auth-rejection branches of the three webhook / cron handlers that bypass the platform `verify_jwt` gate. refresh-tokens (403 on missing / wrong / non-Bearer Authorization), strava-webhook (403 on POST / GET with no `?secret=` and POST with wrong `?secret=`), revenuecat-webhook (405 on GET, 401 missing_signature, 401 bad_signature). The CI job replaces the auto-started edge runtime with `supabase functions serve --env-file` because the auto-started runtime ignores `.env.local` and 503's every secret-gated call — the rejection branches are only reachable when the secret is configured.

The happy-path 200s with valid HMAC / freshness / dedupe still need real secrets to drive and are exercised manually only — see [apps/backend/CLAUDE.md § Testing without real credentials](../../apps/backend/CLAUDE.md#testing-without-real-credentials).

### `apps/web/tests-e2e/` — Playwright suite (~774 tests across ~142 files)

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
  explore.spec.ts              — /explore (redirects to /routes?tab=explore)
  dashboard-period.spec.ts     — /dashboard/period/[type]/[date] (week + month deep links + invalid-date fallback)
  login.spec.ts                — /login (failed sign-in; sign-up: ?signup=1; forgot-password full round-trip via Mailpit; happy sign-in path in cross-cutting/sign-in-out)
  dashboard.spec.ts            — /dashboard
  feed.spec.ts                 — /feed
  coach.spec.ts                — /coach (mount, dropdowns, send → mocked SSE assistant bubble)
  live/
    spectator.spec.ts          — /live/[id] (anon: shell mount + planted-pings backlog hydrate → LIVE + named runner via public_profiles + stat strip; finished-state for a run whose duration places it >2 min in the past; private + bogus-id not-broadcasting)
    event.spec.ts              — /live/event/[id]/[instance] (pre-race empty state; running race + 3 runners → status pill, leaderboard sorted distance-desc with per-user avatar tint)
  runs/
    list.spec.ts               — /runs (filter, sort, search, multi-select, create, delete; bulk-delete actually-deletes round-trip)
    new.spec.ts                — /runs/new standalone create form (RunEditor → land on /runs/[new])
    detail.spec.ts             — /runs/[id] (edit, cancel, single-run delete via the trash icon)
    cascade.spec.ts            — backend boundary: deleting a run sweeps every cascading child (kudos, comments, photos, segment_efforts, live_run_pings, run_matched_tracks, notifications) + the Storage object; run_photos cascade
    photos.spec.ts             — /runs/[id] RunPhotos: owner upload + caption edit + delete (with DB + Storage assertions)
    save-as-route.spec.ts      — /runs/[id] Save-as-route CRUD (prompt → /routes/[new])
    track-missing.spec.ts      — row + Storage divergence resilience: plant a row with `track_url` pointing at a non-existent Storage object (mirrors a mid-sync crash where the row insert succeeded but the gzipped track upload failed); /runs/[id] must render the run header + distance/duration without crashing on the failed track download. Pins the data-layer's try/catch around fetchTrack
    social.spec.ts             — /runs/[id] owner sees kudos count + comment list (RunSocial mounts for own runs); owner posts comment on own run
  routes/
    list.spec.ts               — /routes (search, filter, tab switch)
    detail.spec.ts             — /routes/[id] (star, public toggle, tag add+remove, review submit + DB upsert)
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
    event-delete.spec.ts       — /clubs/[slug]/events/[id] admin deletes event → navigates back to club; cascade-delete sweep of event_attendees + event_results
    event-recurring.spec.ts    — /clubs/[slug]/events/new recurrence depth (weekly + multi-day byday, monthly, past until-date, byday persists across recurrence-type switches)
    event-rsvp.spec.ts         — /clubs/[slug]/events/[id] RSVP round-trip + UPSERT contract; per-instance RSVP across a weekly recurring event (Going/Maybe/Declined land on three distinct instance_start rows, reload preserves each); Submit-my-time picker → run-attached leaderboard row; Record DNF; admin per-event post update; anon visitor reads public-club event without RSVP buttons
    invite.spec.ts             — /clubs/join/[token] redeems a Friends-of-Jared invite link → lands on the private club
    invite-rotation.spec.ts    — backend boundary: admin Rotate-invite-token → old token rejected by join_club_by_token, new token accepted
    join.spec.ts               — /clubs/[slug] open-policy join from Browse → post on feed → leave
    members.spec.ts            — /clubs/[slug] Members tab: admin role-change dropdown + admin Remove-member kick
    post-delete.spec.ts        — /clubs/[slug] admin posts to feed → deletes via row icon
    posts.spec.ts              — /clubs/[slug] threaded reply: top-level post by runner → reply by alex → both render
  settings/
    account.spec.ts            — display name + parkrun number + Resting HR save round-trips
    export.spec.ts             — /settings/account Data Export: CSV + JSON button downloads (filename + body shape — header row, seeded data rows, no user_id leak in JSON) + Backup ZIP magic-bytes wrapper check + Backup ZIP interior shape (manifest.json + profile.json + runs.json + routes.json all present, manifest carries a version key)
    preferences.spec.ts        — theme, units, pace format, map style (each save round-trip)
    privacy-zones.spec.ts      — /settings/preferences privacy-zones CRUD: service-role plant a zone via user_settings.prefs.privacy_zones, reload, verify the zone-row renders with seeded coords + radius, click Remove + Save → reload → zone gone from UI AND prefs blob; empty-state copy when prefs has no zones. The MapLibre tap-to-add picker isn't drivable in Playwright, so the seed path is via service-role; the share-time guardrail is covered separately in cross-cutting/privacy-zones.spec.ts
    integrations.spec.ts       — Strava, parkrun, Garmin (list render + parkrun connect/disconnect round-trip + Strava OAuth-redirect path)
    devices.spec.ts            — current-browser row + "This device" badge + inline label edit round-trip
    licenses.spec.ts           — open-source license list
    upgrade.spec.ts            — Pro pricing, RevenueCat checkout
  share/
    run.spec.ts                — /share/run/[id] anon + authed-non-owner view; private-run not-found for anon; sign-up CTA click-through; run-meta render
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
    architecture-guards.spec.ts — Node-side static guards: every authed +page.svelte that fetches in onMount waits for `auth.user` (catches the auth-race pattern that bit 9+ pages); login snapshots `return_to` at mount; /live/[id] data path runs independently of map.on(load); pushPing guards every map.* call with `if (!map)`
    billing-issue-banner.spec.ts — global "Update your card to keep Pro" banner end-to-end: service-role plant `user_profiles.billing_issue_at`, banner visible on /dashboard with relative-days copy ("3 days ago"); no flag → no banner; "today" copy for a flag set within 24h; non-service-role UPDATE of billing_issue_at raises 42501 (lock_subscription_columns defence in depth — prevents client-side suppression of the banner)
    job-tier-priority.spec.ts  — tier-aware job-queue scheduling. Plant runner (free) + morgan (pro) runs back-to-back; assert morgan's map_match `scheduled_at` is at least 25 s earlier than runner's (the helper offsets free by +30 s). Direct unit test of the `job_scheduled_at_for_user(uuid)` helper (pro → ≈ now, free → now+30s, unknown user → free fallback). Manual rematch via `enqueue_run_rematch` RPC also honours the same tier offset (pinned because rematch is a separate enqueue site)
    jobs-stuck-alert.spec.ts   — read-only operator surface for stuck jobs (decisions.md § 58 contract). Idle queue → stuck_count=0; a planted job with locked_at 6 min ago surfaces via both `find_stuck_jobs()` and `jobs_stuck_summary()`; custom threshold arg honoured (2-min-old job is stuck under `interval '1 minute'` but not under the 5-min default); the pg_cron `jobs-stuck-alert` schedule is registered + active with cadence `*/10 * * * *`
    auth-walls.spec.ts         — RLS leak checks (cross-user run + private-club isolation), anon-redirect walks (/dashboard, /runs, /coach, /plans, /clubs, /settings/account), ?return_to round-trip
    behaviors.spec.ts          — small focused checks: kudos+rescind UNIQUE round-trip, display-name UI edit verified at the DB layer, club post round-trip shape pinned via DB read, public_runs view contract (anon visibility limited to is_public=true rows)
    cross-user-mutations.spec.ts — User B cannot UPDATE / DELETE User A's runs / routes / kudos / comments via supabase-js, and a non-member cannot INSERT a club_post into a private club (RLS UPDATE/DELETE/INSERT pinned end-to-end at the wire, not just SELECT)
    db-constraints.spec.ts     — UNIQUE / CHECK / partial-index / FK walks (training_plans_one_active, run_kudos PK, user_follows PK, club_members PK, clubs.slug, runs.source enum, routes.surface enum, club_members.role enum, subscription_tier narrow union, plan date-range CHECKs, route_reviews.rating range, event_results.finisher_status / duration_s, training_plans.status, notifications.kind, device_tokens.platform, plan_workouts.week_id FK, club_members.user_id FK to auth.users) + lock_subscription_columns paywall-bypass guard
    kudos-concurrency.spec.ts  — fire 5 simultaneous run_kudos inserts for the same (user, run) pair via supabase-js; assert exactly one row lands and every non-winner is either silent (supabase-js swallowed the dedupe) or 23505. A regression that surfaced 4xx-other-than-23505 here would crash the optimistic toggleKudos UI handler
    metadata-registry.spec.ts  — web parity with mobile_android/test/metadata_registry_test.dart: greps web TS/Svelte for every `metadata.X` access and asserts each key is documented in `docs/backend/metadata.md`. Catches cross-platform drift on the schemaless `runs.metadata` jsonb bag
    paywall-wire.spec.ts       — `/api/coach` daily-limit gate via real user JWTs: free user planted at message_count=2 → 3rd request 429s with `error: 'daily_limit'`, `tier: 'free'`, `limit: 2`; pro user at the free cap (2) doesn't 429 (Pro has a higher 10/day cap); pro user planted at message_count=10 → 11th request 429s with `tier: 'pro'`, `limit: 10`; anon POST → 401. Auto-skips when `BYPASS_PAYWALL=true` in `apps/web/.env.local`
    tier-cache-resilience.spec.ts — companion to paywall-wire: where that pins the static states (free vs pro), this pins the *dynamic* property — flip morgan free → pro mid-session via service-role write and watch the very next /api/coach request observe the new state using the SAME JWT (no re-sign-in). Catches a regression that would cache subscription_tier at sign-in or in a module-level memo
    public-runs-view.spec.ts   — `public_runs` view privacy-strip contract end-to-end: plant a public run with every strip-listed metadata key (24 keys: strava_id, garmin_id, plan_workout_id, race_name, perceived_effort, …), read as anon via supabase-js, assert each strip-listed key is absent and the retained keys (activity_type, avg_bpm) survive; anon CANNOT read is_public=false rows
    runs-external-id-dedupe.spec.ts — `runs.external_id` UNIQUE constraint resilience: 5 simultaneous service-role inserts with the same external_id must produce exactly one row, every loser raising 23505 (not a different error code); a second post-success replay also gets a clean 23505. Pins the import-pipeline backstop for Strava manual-sync + strava-webhook racing the same activity
    storage-boundaries.spec.ts — `runs` Storage bucket RLS via supabase-js: anon cannot download a private run's track via the bucket directly; cross-user authed download is denied; cross-user upload to another user's `{user_id}/` prefix is rejected. Defence-in-depth on top of the row-level RLS
    strava-import-guards.spec.ts — `strava-import` Edge Function pre-side-effect input validation (10 tests): missing Authorization → 401; missing/invalid action → 400; connect-action shape errors (code, scope, redirect_uri) → 400 with per-branch error code; **fail-closed-when-misconfigured**: with STRAVA_ALLOWED_REDIRECTS unset the EF returns 503 strava_not_configured rather than falling through to "allow any redirect"; sync lookbackDays out-of-range → 400
    realtime.spec.ts           — service-role INSERT into club_posts pushes through Realtime to a subscribed /clubs/[slug] page (postgres_changes filter + debounced reload)
    smoke.spec.ts              — surface smoke: every key page mounts past its loading shell with one stable selector visible (dashboard / feed / runs / routes / plans / clubs / coach / all settings tabs / detail pages / anon landing+login variants)
    surfaces.spec.ts           — detail-surface checks (back-link nav, owner-only affordances, tab switches, sidebar nav round-trips)
    triggers.spec.ts           — enroll_club_owner, notify_run_kudos, notify_run_comment, notify_user_follow, notify_run_comment_reply — all five fan-out triggers verified via service-role DB read after either a UI action or a service-role plant
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
    account-deletion.spec.ts   — saga user plants a run + gzipped track, drives /settings/account → Delete Account → Confirm; asserts the auth.users row, the runs row, the user_profiles row, AND the Storage object are all gone after the click. Caught the privacy compliance bug fixed in migration 20260728_001 (eight FKs to auth.users lacked ON DELETE CASCADE; admin.deleteUser 500'd for every user)
```

**Saga infrastructure** (`fixtures/saga-users.ts` + `fixtures/simulate.ts`). Sagas are multi-step multi-user journeys that need more users than the three pinned in `seed.sql` and/or actions only mobile/watch can do on the canonical web stack. Two helpers make sagas tractable:

- **`createSagaUsers(n, opts?)` / `deleteSagaUsers(users)`** — admin-creates `n` ephemeral auth.users rows + matching `user_profiles`, signs each in via the real form once to capture storage state (parallel, single browser process). `deleteSagaUsers` sweeps non-cascading owner tables (`clubs`, `events`, `club_posts`, `route_reviews`, `training_plans`, `routes`, `runs`) before the auth.users delete, then unlinks the storage-state files. Uses the service-role key from `supabase status -o env` (cached for the test process). Cost: ~5-7 s setup for 3 users; sign-in dominates.
- **`simulate.insertRun(...)`** — service-role helper for actions only mobile/watch can do on the canonical web stack ([decisions § 24](../architecture/decisions.md)). Currently: `insertRun` (with optional gzipped track upload to the `runs` Storage bucket — mirrors the recorder's sync path), `deleteRun` (with track cleanup), `insertEvent` / `deleteEvent` (used by the `clubs/event-rsvp.spec.ts` round-trip and any future saga that needs an event row without driving the create-event modal — `insertEvent` accepts `recurrence_freq` / `recurrence_byday` / `recurrence_until` for planting recurring events in one call), `insertKudos` / `insertComment` (engagement on a planted run — used by `runs/social.spec.ts` and `u/notifications.spec.ts` to fan out via the notify_* triggers without driving the UI), `insertLivePings` (plant a sequence of `live_run_pings` rows so the /live/[id] spectator page hydrates from a backlog without spinning up a real broadcaster — used by `live.spec.ts`), `setUserSetting` / `clearUserSettingKey` (user_settings.prefs upsert when the canonical UI requires a hard-to-drive interaction like the privacy-zone MapLibre picker), `setClubMemberStatus` (flip a club_members row's status — used by `clubs/approval.spec.ts` to restore alex to pending after the runner-approves test), `clearNotifications` / `setNotificationsUnread` (the notifications table has no automatic cleanup, accumulates across runs, and the bell badge caps at "9+" — tests that assert exact unread counts must clear or normalise first). Each helper bypasses RLS via the service-role client; keep the surface narrow — anything a real user could do via the web UI through a non-canvas interaction should go through the UI in the saga, not here.
- **`fixtures/mailpit.ts`** — local Supabase ships an embedded Mailpit on `http://localhost:54324` (config.toml's `[inbucket]` section). Auth flows that send email — sign-up confirmations, password recovery, magic links — deliver into Mailpit instead of a real SMTP relay. The helper exposes `clearMailpit()` (DELETE /api/v1/messages — call in `beforeEach` so accumulated mail from prior runs doesn't shadow the under-test email), `waitForEmail({ to, subjectIncludes })` (polls /api/v1/messages with a short interval until a matching message arrives), and `extractLink(msg)` (greps the first absolute URL out of the HTML/Text body — Supabase recovery / magic-link / signup-confirmation emails embed exactly one action URL so the naive first-match is reliable). Used by the `forgot password` test in `login.spec.ts` to drive the full request → email → reset → sign-in-with-new-password round-trip; future tests that need to verify what the auth system actually emailed (e.g. signup-confirmation flow if `enable_confirmations` flips on, magic-link sign-in) should reuse these.

**Saga conventions** (validated by `cross-user/sagas/club-join.spec.ts`):
1. Mint users in `beforeAll`, delete in `afterAll`. Per-test creation is too slow.
2. One `test()` per saga journey — the saga IS the assertion; splitting it would re-run setup repeatedly AND leak shared state.
3. One browser context per user. Same browser process, separate cookies + localStorage so each context acts as an isolated session.
4. **Don't use `waitForLoadState('networkidle')` on pages with a Supabase realtime subscription** (e.g. `/clubs/[slug]` subscribes for member-count updates). The websocket keeps the network busy and `networkidle` never fires. Wait for the concrete element you need to interact with via `expect(locator).toBeVisible()` instead.
5. **Tighten URL-match regexes when waiting for slug navigation** — Playwright's `waitForURL` returns the instant the regex matches the current URL. A permissive `\/clubs\/[a-z0-9-]+$/` matches `/clubs/new` (where alice already is) before the create-and-navigate completes. Anchor on something only the destination URL has — e.g. require a digit in the slug.

The page-mirror layout makes "what tests do I have for `/runs/[id]`?" trivial (one file) and "where does my new test go?" obvious (matching folder, or `cross-user/` if the test needs a second context, or `cross-cutting/` if it spans pages). Add new files as the depth grows — e.g., `routes/builder.spec.ts` when `/routes/new` gets coverage, or `cross-user/sagas/club-event-run.spec.ts` for the multi-step multi-user flows that need ephemeral users.

**Idempotency** — every test that mutates data either rolls back at the end (rename / kudos rescind / comment delete / display-name restore / follow-then-unfollow / filter restore / theme restore / sidebar restore / star restore / mark-all-read / comment-reply parent-delete) or creates-and-deletes its own row (manual run CRUD). The suite is safe to re-run without `supabase db reset` between runs. If a test fails partway and leaves orphaned state, the next reset cleans it up.

**Seventeen production bugs + one test-fragility were fixed during the suite's authoring passes.** Each was a real defect, not test scaffolding (the test-fragility was a brittle assert that masked an existing leak rather than a code bug, but it deserves a note since fixing it required adding the `clearNotifications` helper and a beforeEach):

- **`RunShareView.svelte`** lacked a `try/catch` around the non-owner branch's `fetchClippedTrackForRun` call; an EF outage would crash the entire share page render. Fix: wrap the call, fall back to `track = []`.
- **`/login/+page.svelte`** — Svelte 5's `onsubmit` binding hydrates after first paint, so a Playwright click before hydration completed fired the form's native GET handler instead of the JS submit. Fix: gate the submit button on a post-`onMount` `hydrated` flag, plus `waitForLoadState('networkidle')` in the test helper.
- **`/runs/+page.svelte` + `/runs/[id]/+page.svelte`** — `auth.svelte.ts` flips `loading=false` before its async `fetchUser()` resolves, so the `$effect` could fire with `auth.user == null` and skip the data fetch. The dashboard already polled for `auth.user` separately; these two pages didn't. Fix: gate on `(auth.loading || !auth.user)`, with a 1s polling loop on `[id]`.
- **`/settings/account/+page.svelte`** — same auth-race shape as above. The `displayName` / `parkrunNumber` `$state` declarations initialise from `auth.user?.X ?? ''` at module-evaluate time. On a hard reload before auth resolved, both fields seeded as empty strings and never re-populated, so a user typing a new value into the email-only profile would clobber their saved display name. Fix: poll for `auth.user` in `onMount` (~1 s budget), then populate the fields explicitly.
- **`/settings/preferences/+page.svelte`** — same auth-race shape, but more visible: `if (!auth.user) return` early-bailed `onMount` left `loading = true` forever. On hard reload the entire form was hidden behind a perpetual "Loading…" message — every preference (units / pace / map-style / theme via `loadTheme()` worked, but the rest of the form below was dead). Fix: same poll-for-auth pattern as `/settings/account`. The same bug shape was also fixed in `/settings/devices/+page.svelte` (no test yet, but the page had identical structure).
- **`/settings/preferences` toggle-button accessibility** — the Distance Unit + Theme toggles wrapped three buttons inside a `<label>` with a `<span class="label-text">` heading. The implicit-label association makes the FIRST button inherit the entire label content as its accessible name — the Auto button was announced to screen readers as `"Theme Light Dark, button"` (label heading + sibling button text), and the Kilometres button as `"Distance Unit Miles"`. Fix: replace `<label>` with `<div class="field">` (CSS already exists for that class) and put `role="group" aria-label="…"` on the inner `.toggle-row`. The Playwright test for the theme toggle would never have passed without this fix; a screen-reader user would be unable to identify which option they were on.
- **`/clubs/+page.svelte`** — yet another auth-race. `fetchMyClubs()` returns `[]` silently when `auth.user?.id` is null, so a hard reload onto `/clubs` during the auth race rendered "You haven't joined a club yet" forever, even for the user who owns three seeded clubs. Fix: poll for `auth.user` in `onMount` (~1 s budget) before kicking off `loadMine()` / `loadBrowse()`. Same shape as `/settings/account` + `/settings/preferences` + `/settings/devices`. The recurrence is the signal — the underlying issue is that `auth.svelte.ts` flips `loading=false` before the async `fetchUser()` resolves, so any `onMount` that reads `auth.user` synchronously is at risk. We're patching pages individually for now; a long-term fix would be a single `auth.ready()` helper that pages can `await`.
- **`/clubs/[slug]/+page.svelte`** — same auth-race shape, on the slug page. `fetchClubBySlug()` resolves the club row using `supabase.auth.getSession()` to populate `viewer_role`; on a hard reload during the auth race the row landed with `viewer_role = null`, making the derived `isMember` and `isAdmin` flags both false. The post composer is gated on `isMember` and the admin affordances (New event, Delete club, Delete post) are gated on `isAdmin` — so the owner of `sydney-run-club` who hard-reloaded onto the page saw a read-only view of their own club. There's no reactive re-fetch when auth lifts later. Fix: poll for `auth.user` in `onMount` (~1 s budget) before kicking off `load()`. Surfaced by the new post-create-then-delete test in `clubs/post-delete.spec.ts` which couldn't find the composer textarea in a full-suite run.
- **`lock_subscription_columns` trigger silently bypassed by every authenticated caller (CRITICAL — paywall bypass).** Migration `20260624_001` installs a BEFORE-UPDATE trigger that's supposed to reject `subscription_tier` mutations from non-service-role callers, so a user can't PATCH their own user_profiles row to upgrade themselves to Pro. The trigger reads the JWT role via `current_setting('request.jwt.claim.role', true)` — the LEGACY single-claim format. Newer PostgREST (the one local dev + production are now on) only sets the JSON blob `request.jwt.claims` and leaves the per-claim individual settings empty. So `v_role` always coalesced to `''`, the function's `service-role and direct-SQL (empty role)` bypass at the top fired for every authenticated request, and the gate fell through. **Net effect: any signed-in user could upgrade themselves to Pro in 30 seconds with curl** (or one line in the browser console). The exact same shape as bug #10 (rate-limit role-claim regression). Fix in migration `20260727_001_lock_subscription_columns_jwt_claims.sql`: read the role from BOTH sources via the same `coalesce(nullif(legacy), claims_jsonb->>'role')` pattern that the rate-limit fix used. Surfaced by the new `cross-cutting/db-constraints.spec.ts` test which signs in as runner via supabase-js and attempts the self-upgrade through a real user JWT (the admin client can't catch this because service-role legitimately bypasses the trigger).

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

- **`/plans/[id]/+page.svelte` + `/clubs/[slug]/events/[id]/+page.svelte`** — the same auth-race shape that bit nine other pages, surfaced by the new `cross-cutting/architecture-guards.spec.ts` static guard. Both pages fetched in `onMount` without polling for `auth.user`, so on a hard reload during the auth race the plan-detail page rendered an empty week grid + no PlanMetaEditor button (the owner-only affordance was hidden because `viewer_user_id` came back null), and the event-detail page rendered the wrong RSVP state + no admin Delete-event button. Fix on both: poll for `auth.user` in `onMount` (~1 s budget) before kicking off `load()`. The new arch-guard test walks every authed `+page.svelte` and asserts each one waits for `auth.user` before its first fetch — so this is now a static check rather than a "find by flake" path. Same long-term mitigation still wanted: a single `auth.ready()` helper that pages can `await`.

- **`delete-account` Edge Function 500'd for every user (CRITICAL — privacy compliance)** — the EF calls `auth.admin.deleteUser(user.id)` after draining Storage. That admin call issues a hard DELETE on `auth.users`; Postgres enforces every FK that points back at that row. Eight tables held a `references auth.users` *without* `on delete cascade`: `runs.user_id`, `routes.user_id`, `integrations.user_id`, `user_profiles.id`, `route_reviews.user_id`, `clubs.owner_id`, `events.created_by`, `club_posts.author_id`. Every authenticated user has a `user_profiles` row by virtue of `auth.svelte.ts`'s upsert-on-first-sign-in, so admin.deleteUser raised 23503 on that FK before any of the others could even fire. The EF caught it, logged, and returned 500 `{"error":"delete failed"}` — denying the GDPR / CCPA right-to-erasure that the EF exists to satisfy. **For every user. In production.** Migration `20260728_001_cascade_auth_users_fks.sql` re-creates each FK with `on delete cascade` so the user owns the rows and deleting their account deletes the rows. Surfaced by `cross-user/sagas/account-deletion.spec.ts` which planted an ephemeral user + run + gzipped track, drove the /settings/account UI flow, and watched the EF response come back 500. The `saga-users.ts` fixture had been masking this for months because `deleteSagaUsers` explicitly sweeps the same eight tables (its OWNER_TABLES list) before its own teardown — so the unit-test surface and the saga's own setup never hit the path the EF actually takes. Same anti-pattern as the rate-limit role-claim and paywall-bypass discoveries: looks-correct, never-verified end-to-end. Documented in [decisions.md § 56](../architecture/decisions.md#56-account-deletion-cascades-through-every-public-fk-to-authusers).

These would have shipped silently — they don't show up in unit tests because the failures are in the integration between auth state, network calls, Svelte 5's hydration timing, accessible-name computation, and Supabase session-scope semantics. This is the bug-yield the suite was put in for.

#### End-to-end smoke test (manual)

Unit tests don't exercise the real OSRM engine. The `apps/job_worker/osrm/` directory ships a `make smoke` target that does:

1. Stand up OSRM (`make download && make build && docker compose up -d` once per region).
2. Stand up local Supabase (`cd apps/backend && supabase start`).
3. Run the worker with `OSRM_URL=http://127.0.0.1:5000` set.
4. From `apps/job_worker/osrm/`: `make smoke`.

The script uploads a Melbourne-region track, inserts a run (firing the trigger that queues a `map_match` job), polls `run_matched_tracks` until `status='matched'`, and prints raw vs matched coordinates side-by-side so a passthrough fallback is visible. Failure modes (OSRM unreachable, wrong region, worker not running, identical raw/matched coords) are reported with actionable messages. See [`apps/job_worker/osrm/README.md` § Smoke test](../../apps/job_worker/osrm/README.md#smoke-test) for the full recipe and tunables.

This is **not** wired into CI — both the OSM extract download and the OSRM build are too heavy for the GitHub runner. It's a developer-machine sanity check before shipping a matcher change.

---