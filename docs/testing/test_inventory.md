# Test inventory

The exhaustive, file-by-file list of what each test file covers, the Playwright spec layout, and the log of production bugs the e2e suite caught. Split out of [testing.md](testing.md) (the durable testing guide) because these per-file descriptions and counts drift fast. Regenerate live counts with `grep -cE '^\s*(test|testWidgets)\(' apps/mobile_android/test/*.dart` (Dart), `npx tsx --test` discovery (web), and `supabase test db --local` (pgTAP).

**The per-file counts in the census above the round log were re-measured on 2026-09-05** and are the DECLARATION count each recompute command reports — 49 of the 111 measurable ones were wrong when they were checked, several by a factor of four ([decisions § 1217](../architecture/decisions.md)). They no longer drift silently: `scripts/check_test_inventory_counts.mjs` (`npm run check:test-inventory`, in the `workflow-lint` job) re-derives every one of them from the file it names and fails the PR on a disagreement, on a heading that names a file it cannot find, and on a heading that names no file at all. A count written against a PARAMETERISED declaration — `l10n_generated_parity_test.dart`'s `1 + 3 per catalogue`, `catalogues.test.ts`'s one per locale — is the runtime count, not the declaration count, and says so. **The per-round sections below the `Suite totals` divider are historical records of what one round added; their counts are deliberately NOT refreshed** (the note under the `security_guards.test.ts` headings says the same).

### `apps/mobile_android/test/run_stats_test.dart` — 27 tests

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

### `packages/run_recorder/test/run_recorder_test.dart` — 73 tests

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
- Single-hop jump > 100 m rejected when it arrives within the 10 s gap window (a corrupt teleport)
- **Time-based gap re-anchor (#330)** — a > 100 m hop after a ≥ 10 s gap rebases the anchor and resumes tracking without crediting the un-sampled gap; consecutive post-gap fixes don't stay stuck on the stale anchor; a short-dt (< 10 s) or zero-dt > 100 m hop still fails closed

**Pause / resume (3 tests):**
- Pause drops incoming positions entirely (track doesn't grow, distance doesn't accumulate)
- Resume clears `_lastTrackedPosition` so the pause-duration gap isn't counted
- `Stopwatch` stops during pause — asserted with `Future.delayed(50ms)` on both sides

**Indoor / no-GPS mode (3 tests):**
- `RunSnapshot.currentPosition` is nullable (construct with `null` and read back)
- The 1-second timer emits snapshots with `currentPosition: null` when `begin()` runs without any injected fix — the stopwatch ticks even for a treadmill run
- An injected fix after begin populates `currentWaypoint` normally (indoor → outdoor transition)

**Not covered (require mocking `GeolocatorPlatform.instance`):** typed errors thrown from `prepare()`, the `_gpsRetryTimer` retry loop, position-stream `onError` cleanup, `stop`/`dispose` cancelling the retry timer.

### `packages/run_recorder/test/calculate_pace_test.dart` — 16 tests

Tests for the rolling-pace helper exposed via `RunRecorder.debugPaceSecondsPerKm`. Pins the null returns (empty track, fewer than 5 points, total tracked distance below 50 m, paused state), pins the GPS-derived pace value (5 fixes 50 m apart at 10 s intervals → 200 s/km regardless of wall-clock), demonstrates the trailing-window slide (8 fixes with two slow opening segments + six fast trailing segments still yields a fast pace because the early slow part falls outside the ~200 m window), and asserts the snapshot stream's `currentPaceSecondsPerKm` matches `debugPaceSecondsPerKm`.

When the test was first written, `_currentWaypoint.timestamp` was set from `DateTime.now()`; a tight inject loop collapsed all five waypoint timestamps to the same millisecond, and `_calculatePace` returned null because `segmentTime <= 0`. The recorder was changed to `pos.timestamp` for the waypoint timestamp (matching the speed-clamp's GPS-time policy) so the function works correctly under fix-batching / CPU contention. See § Troubleshooting.

### `packages/run_recorder/test/route_helpers_test.dart` — 33 tests

Tests for `_routeRemaining` and `_offRouteDistance` exposed via `debugRouteRemaining` / `debugOffRouteDistance`. Routes are constructed at the equator so equirectangular projection (used for the perpendicular-distance and segment-projection math) and haversine (used to total segment lengths) align to within ~0.5 m for the 0.001°-spaced fixtures. `_routeRemaining` block (9 tests): null returns (no route, single-waypoint route), at start = full length, at segment midpoint = unwalked tail, on the boundary between segments = total minus the first leg, at end ≈ 0, past end clamps to 0, perpendicular offset projects onto the nearest segment, multi-segment route sums correctly. `_offRouteDistance` block (8 tests): null returns, on a waypoint ≈ 0, inline along the route ≈ 0, perpendicular offset returns the perpendicular distance, past the end returns distance to the last waypoint, multi-segment route picks the closest segment, degenerate zero-length waypoint pair is tolerated.

### `packages/run_recorder/test/laps_serialiser_test.dart` — 6 tests

Round-trips the canonical `metadata.laps` shape through `lapsToCanonicalJson` and `parseLapsFromJson`. Pins the per-lap-delta fields (1-based `index`, `start_offset_s` cumulative-BEFORE, `distance_m` + `duration_s` per-lap deltas) so a refactor of the serialiser can't quietly regress the cross-platform contract. Ties into the watch-payload fixture test on every platform — see [§ Cross-platform fixture contract](manual_testing.md#cross-platform-fixture-contract) in the manual testing guide.

### `packages/run_recorder/test/architecture_guards_test.dart` — 12 tests

Static source-level guards on the recorder package itself: no banned imports, no `print` in production, the public-API surface stays minimal, etc. Same shape as `apps/mobile_android/test/architecture_guards_test.dart` — read the `reason:` strings before rubber-stamping a fix; failures usually mean a recent change reversed an optimisation we deliberately codified.

### `packages/run_recorder/test/workout_runner_test.dart` — 42 tests

The structured-workout step engine — step expansion (warmup → reps → recovery → cooldown), auto-advance, halfway / last-50 m progress signals, skip / abandon, and pace-adherence "wayBehind" classification. See [workout_execution.md](../features/workout_execution.md) for the runner state machine + UI contract.

### `packages/run_recorder/test/geolocator_platform_fake_test.dart` — 19 tests

Closes the documented "typed errors thrown from `prepare()`" gap. Replaces `GeolocatorPlatform.instance` with a fake that extends `GeolocatorPlatform` (so `PlatformInterface.verify` passes) and exposes setters for `serviceEnabled` / `permissionState` / `requestPermissionResult` plus an `emit(Position)` and `emitError(Object)` method that pushes through the live position stream. The error-path tests cover `LocationServiceDisabledError` when services are off, `LocationPermissionDeniedError(forever: false)` when the request returns denied, and `LocationPermissionDeniedError(forever: true)` when permission is denied-forever — plus the "already granted" path that skips the request. The happy-path tests cover `prepare()` opening the position stream, positions flowing through the filter chain (pre-begin updates the dot but not the track; post-begin first fix becomes the track anchor; subsequent fixes accumulate distance), stream `onError` not crashing the recorder, and `dispose()` cancelling the subscription so subsequent emits don't extend the track.

### `apps/mobile_android/test/local_run_store_test.dart` — 94 tests

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

### `apps/mobile_android/test/sim_watch_link_test.dart` — 11 tests

Decoder for the custom-watch phone-link status frames (schema v1 from `watch_core::link`, `apps/custom_watch/core/src/link.rs` — the sim's TCP bridge today, the step-6 BLE characteristic later). Pins: a full frame parses field-for-field (fixture strings captured from the live sim); `"fix": null` stays null rather than becoming a zeroed fix; null optional fields (`course_deg`/`alt_m`/`tod_s`) survive; garbage lines return null instead of throwing; the byte-stream decoder skips malformed lines and reassembles frames split across chunk boundaries (a UART bridge gives no framing guarantees); the decoder consumes a `Uint8List`-typed stream (the shape a real `Socket` emits — the bind-not-transform choice); a socket that lands after `close()` (screen disposed mid-connect) is destroyed rather than leaked; the default host is the loopback on non-Android hosts.

### `apps/mobile_android/test/sim_watch_screen_test.dart` — 12 tests

The dev-only Sim Watch screen (Settings → Developer) against a fake link. Pins: connect renders frames as they arrive (uptime, then position/speed/sats/altitude when a fix lands); a failed connection surfaces the error text rather than silently idling; disconnect closes the link and returns to the connect affordance; and the settings gate both ways — the tile shows against a loopback backend URL and is absent against a production-shaped one (same `isLocalSupabaseUrl` rail as the seed auto-login). Test gotcha pinned in-file: never `await controller.close()` on a single-subscription stream whose listener was cancelled — the done future only completes once a listener consumes it, and the test hangs forever.

### `apps/mobile_android/test/wear_routes_fixture_test.dart` — 4 tests

Cross-platform contract test for the phone→watch routes payload. Reads the canonical fixture at `fixtures/wear_routes_payload.json` (shared with the Wear OS Kotlin test `WearRoutesFixtureTest.kt`, 13 tests on the watch side). Pins: encoder produces the wire format byte-equivalent to the fixture's `expected_payload_json`; the JSON round-trips through `jsonEncode`/`jsonDecode` without loss; Unicode + emoji in route names survive; the pipeline filters out non-starred routes via `pickRoutesForWatchPush`. If you change the fixture, update both platform tests in the same commit.

The `wear_routes_bridge_test.dart` adds three further groups beyond the basic attach/detach/payload coverage:

- **payload-diff cache (10 tests):** the bridge caches the last shipped `routes_json` and skips channel invocations when the next encoded payload matches byte-for-byte. Pins: re-saving the same row does NOT fire a second push; saving an unstarred route when no starred change happened does NOT push; mutation that doesn't affect the wire fields is a no-op; starring a new route invalidates the cache; unstarring fires; star→unstar→re-star fires three times (not deduped — the cache is last-sent only); a swallowed PlatformException or MissingPluginException does NOT update the cache so the next attempt re-fires; detach resets the cache so a fresh attach always pushes once; re-attach within the same bridge also resets.
- **burst + lifecycle characterization (8 tests):** 5 starred saves of different routes → 5 pushes (no throttling today); 100 identical re-saves → ZERO additional pushes (diff cache catches all); 100 alternating star/unstar → 100 pushes; mixed starred + plain interleaved fires once per actual starred-set change; saveBatch with 50/50 starred+plain fires ONE push (notify-once contract); detach mid-burst stops all subsequent pushes; detach during in-flight push doesn't crash and stops further pushes after; hot-restart pattern (attach→detach→new bridge attach) works; two bridge instances on the same store push independently.
- **end-to-end wire round-trip (4 tests):** the captured `routes_json` from the channel is structurally identical to `encodeRoutesForWatch` direct output; XML/JSON-special characters round-trip via jsonEncode's built-in escaping; `updated_at_ms` is monotonic non-decreasing across consecutive pushes (the watch's stale-push gate depends on this); every captured payload satisfies the wire-format contract — JSON array of objects with exactly `{id, name, distance_m, waypoints}` keys, and every waypoint with exactly `{lat, lng}`.

### `apps/mobile_android/test/wear_routes_bridge_test.dart` — 66 tests

Pin the listener-attach / push-on-change / starred-only filter contract on the phone-side `WearRoutesBridge`. Uses `TestDefaultBinaryMessengerBinding.setMockMethodCallHandler` to intercept the `run_app/wear_routes` `MethodChannel` — no DI seam needed.

**attach (6 tests):** immediately pushes the current starred subset; pushes on every `save()` to the store; payload contains `id` + `name` + `distance_m` + `waypoints[{lat,lng}]`; only starred routes land in the payload (plain routes filtered out); empty starred list still pushes (lets the watch clear its cache); `updated_at_ms` stamps roughly current epoch millis.

**detach (3 tests):** removes the listener so subsequent store changes don't push; detach-without-attach is a no-op; double-detach is a no-op.

**re-attach (2 tests):** second `attach` replaces the first listener — no leak (verifies a single save fires ONE push, not two); attach-after-detach is also clean.

**platform error handling (3 tests):** `MissingPluginException` is silently swallowed (iOS / unregistered plugin); `PlatformException` is silently swallowed (Data Layer unavailable); a swallowed exception does NOT detach the listener (subsequent saves still push).

**integration with LocalRouteStore (3 tests):** `saveBatch` triggers exactly one push (single listener notification); `delete` of a starred route triggers a fresh push without the deleted id; starring an existing route triggers a push that includes it.

### `apps/job_worker/internal/supabase_dataexport_test.go` — 33 tests

HTTP-level coverage for the four `SupabaseClient` methods added in the May 2026 backup work: `FetchExportRoutes`, `FetchExportProfile`, `FetchUserSettingsPrefs`, `DownloadRawTrackBytes`. Uses `httptest.NewServer` to mimic the Supabase REST + Storage surface; asserts that requests are shaped correctly (path, query params, headers) AND decoded responses match the wire contract.

**FetchExportRoutes (5 tests):** happy path with two-row response (path, select param, auth + apikey headers correct); empty result returns non-nil empty slice; 5xx returns `*HTTPError`; malformed JSON returns error; user_id is URL-encoded (legacy non-uuid case with `+`).

**FetchExportProfile (4 tests):** happy path returns parsed map (display_name + preferred_unit); not-present row returns (nil, nil) so the export builder can include null without ceremony; column-restricted fields (`subscription_tier`, `subscription_at`, `parkrun_number`) are absent from the SELECT query; pass-through `*HTTPError` on 403.

**FetchUserSettingsPrefs (3 tests):** happy path returns the parsed prefs map (incl. hr_zones array round-trip); no-row response returns non-nil empty map (degrade-to-empty); null prefs column also returns empty map.

**DownloadRawTrackBytes (4 tests):** bytes round-trip verbatim (no decode, matches the contract); 404 returns `*HTTPError`; auth headers present (apikey + Authorization); 1MB body round-trips without truncation.

**Cross-cutting (5 tests):** `FetchExportRoutes` with every optional pointer field set decodes to non-nil pointers (DistanceM, ElevationM, Surface, IsPublic, Slug, Featured, RunCount, IsStarred, Description, ClubID, CreatedAt, UpdatedAt); context cancellation propagates; all 4 new methods carry both apikey + Authorization headers via the shared `do()` helper (defensive guard against a future refactor that bypasses it).

### `apps/web/src/lib/backup/restore_orchestrator.test.ts` — 32 tests

Pure-logic coverage of the restore orchestrator extracted from `backup.ts`. The Supabase upserts live behind a small `RestoreBackend` interface; tests substitute a counter-tracking fake so the loop is observable without booting supabase-js. Production wires a thin supabase-js adapter (`supabaseRestoreBackend()` in `backup.ts`); tests wire the fake (`makeFakeBackend()`).

**profile + settings (5 tests):** profile present → `upsertProfile` fires with stripped fields + user id; null profile → no call; `upsertProfile` error becomes a warning, downstream stages still process; non-empty `settingsPrefs` triggers `upsertSettings`; empty prefs is a no-op; settings error → warning + downstream continues.

**runs + tracks (10 tests):** happy-path single run uploads track BEFORE upserting row (order pin); run with no track in archive still upserts the row with `track_url=null`; uploadTrack failure → warning, row still upserts; upsertRun failure → warning, other rows continue (partial-success contract); `generateNewIds` replaces every run id; with `generateNewIds`, the track upload path uses the NEW id even though the archive is keyed by ORIGINAL id; event_id resolution — unknown ids nulled, known ids preserved; `fetchValidEventIds` is only called when ids are present; resolver error bubbles (current contract pinned); `coalesceActivityType` inserts `'run'` when metadata missing the key, and preserves explicit values.

**routes (3 tests):** happy-path upserts with new user_id stamped; `generateNewIds` replaces route ids; failure on one route doesn't sink the others.

**progress events (2 tests):** stages emit in order (profile → runs → routes → done); running totals report 0 → 1 → 2 for a 3-run input.

**edge cases (3 tests):** empty parsed backup is a no-op (zero backend calls); 100-run backup processes all rows in order without dropping + finishes well under 2 s; `coalesceActivityType` clones the metadata input rather than mutating it.

### `apps/mobile_android/test/backup_server_client_test.dart` — 14 tests

Pluggable-fetcher coverage for `BackupServerClient`, the transport for the Go service's **queued** Art 20 rail ([decisions § 724](../architecture/decisions.md)). Tests inject canned request + download fetchers so the round-trip is observable without sockets. Covers: `isConfigured` edges (empty vs non-empty baseUrl); preconditions (unconfigured / empty token throw `BackupServerError` on both `enqueueExport` and `fetchLatestExportJob`); the enqueue (POSTs `{format:'backup'}` with the bearer at `/v1/export/jobs`, accepts the server's 202, and returns a job the client can watch — nothing is downloaded, because the archive does not exist yet); a 429 carried as a rate limit the subject can act on, with an HTTP-date `Retry-After` deliberately NOT guessed at (showing a wrong wait is worse than showing none); a 500 that **surfaces rather than being swallowed**, which is the failure the whole migration exists to remove — the old synchronous client fell through to the narrower on-device archive on any non-200; the status read (GETs `/v1/export/jobs/latest`, normalises the body, reports `none` for a subject who never asked, and surfaces a non-2xx rather than reading it as `none`, which would erase an export that is building); and the download seam (streams the signed URL to the output file, propagates a failure). The status vocabulary itself is pinned in `export_job_test.dart` — the parity twin of web's `cloud_export_helpers.ts`.

### `apps/mobile_android/test/export_job_test.dart` — 31 tests

Mirror suite for the `cloud_export_helpers` ↔ `export_job.dart` parity pair: the URL builders, `exportJobFromResponse`, `isExportJobActive`, `exportPollDelayMs` and `exportJobShortfall`. The fail-closed cases are the point and both platforms pin them identically — a status this build does not recognise is TERMINAL carrying its own raw token (a client that keeps polling a status it cannot interpret polls until the battery dies), a `ready` job that arrived with no URL is a failure rather than a dead download button, an unreadable body claims nothing, non-numeric counts are dropped rather than rendered, and a `format` neither build knows is dropped rather than carried while the status survives ([§ 980](../architecture/decisions.md) — the web half reached that field through a cast, so its type asserted a vocabulary the value was never checked against). Two Dart-side extras over the web suite: `none` reads as a real answer rather than an error (the resume path on a fresh install must show nothing, not a failure), and the enqueue body reads on the same vocabulary as the status body, so one normaliser covers both.

### `apps/mobile_android/test/settings_account_export_test.dart` — 20 tests

Widget coverage of the queued Art 20 export on the Account screen, driving a scripted export service through the injected `exportClient` seam. The case they exist for is the ordinary one on a phone: the runner asks and the screen goes dark. **Resume** — an export that finished while the app was closed is simply waiting on mount, found through a status read with no POST and nothing persisted on the device. **Silence** — a subject who never asked is shown nothing about an export, and a resume read that fails is silent rather than claiming a failure. **Enqueue** — the tile POSTs to `/v1/export/jobs`, renders the building notice, and downloads nothing (the archive does not exist yet). **No silent demotion** — a refused enqueue surfaces its retry window and does NOT produce the on-device archive in its place. **Fail-closed rendering** — a `ready` job with no URL renders as a failure, a `stalled` one says so rather than claiming to still be building, and a truncated one discloses both counts. **Fresh signing** — tapping Download re-reads the status endpoint rather than reusing the URL the card was drawn with, which is signed for ten minutes from the read that produced it. Plus a copy assertion that the on-device notice names what that archive does not carry.

### `apps/mobile_android/test/backup_test.dart` — 65 tests

Round-trip + invariant coverage for `BackupService.createBackup` + `restore`. Manifest / offline-restore / progress / api:null tests; **writeBackupZipStreaming** tests added with the streaming + parallel writer refactor in May 2026 (see `decisions.md § 66`); and a 3-test **BackupOutcome** group covering what a finished archive may claim about itself. The former **tryServerBackup** orchestration group is gone with the helper ([decisions § 724](../architecture/decisions.md)): this class no longer reaches for the server rail at all, so there is no server-first / local-fallback dance left to test — the queued rail lives on the surface and is covered by `settings_account_export_test.dart`.

The streaming-writer group exercises the testable seam extracted from `createBackup`: writes a valid backup that round-trips through the existing restore decoder; emits stage + tracks progress callbacks in order; downloads tracks in bounded-concurrency batches (peak `inFlight` counter ≤ supplied `concurrency`, observable parallelism with 20 tasks); a single download failure doesn't sink the rest of the backup; `runsWithTracks=[]` produces a valid manifest-only ZIP; overwrites an existing output file rather than appending junk; rejects `concurrency < 1`.

The **BackupOutcome** group covers what the settings screen is allowed to claim about a finished archive: a whole local archive discloses nothing; a blob-short one reports what it could not fetch; an outcome with no summary claims nothing. Since [decisions § 724](../architecture/decisions.md) this class builds ONE thing — the on-device archive — so there is no server verdict here to read and no fall-back to hide. LOCALLY-built archive makes no completeness claim either way (the local writer has no server verdict to read); and the English disclosure copy names both counts plus `manifest.json`.

### `apps/mobile_android/test/csv_run_importer_test.dart` — 34 tests

Pure-Dart coverage of `CsvRunImporter.parse` — the lossy summary path that round-trips Settings → "Export runs as CSV". Two header shapes are exercised: the 5-column mobile/web Settings export and the 17-column backend `/export-data` GDPR shape. The parser is offline-first by design (no API, no Supabase) and idempotent on re-import via a stable `external_id`. See `decisions.md § 65`.

**5-column form (6 tests):** single-row round-trip stamps `metadata.imported_from='csv'` + `imported_at` + default `activity_type='run'` + synthetic `external_id` prefix; preserves multi-row order; unknown `source` cell falls back to `RunSource.app`; the synthetic `external_id` is deterministic, differs by start time, and matches across two parses of the same input.

**17-column backend form (3 tests):** preserves the original `id`, `external_id` (e.g. `strava:1234567890`), and the full `metadata` JSON column; tolerates quoted commas + escaped quotes inside the metadata cell; malformed metadata JSON is dropped without sinking the row (the importer surfaces a warning, the `activity_type='run'` default still lands).

**Error handling (7 tests):** missing required columns surfaces a single header-level error; invalid date row is skipped + reported (1-based row number); invalid distance/duration row is skipped + reported; empty input + header-only input both return empty results; blank lines between data rows are skipped; rows shorter than the header are reported, not parsed.

**Header tolerance (2 tests):** `started_at` is accepted as an alias for `date`; column names are case-insensitive.

**Adversarial input (8 tests):** 1000-row CSV parses in under a second (O(n²) regression guard); Unicode + emoji + accents in title round-trip intact through quoted cells; RFC-4180 quoted-comma + escaped-double-quote (`""`) survives; mixed valid + invalid rows produce a partial result (good rows + per-row errors with 1-based row numbers, not all-or-nothing); CRLF line endings (Excel / Windows tools) parse cleanly; negative numerics pass through to the upsert layer (DB CHECK is source of truth, not the parser); trailing whitespace round-trips leniently; deeply-nested 17-column `metadata` (laps array, hr zones) round-trips JSON-equivalent.

### `apps/mobile_android/test/strava_importer_zip_test.dart` — 31 tests

Comprehensive coverage for `StravaImporter.importFromZip`. Complements the smaller `importer_external_id_test.dart` (which only pinned the `external_id` prefix). Each test builds an in-memory zip with the `activities.csv` + a track file, then asserts on the resulting `Run`.

**Activity-type derivation (6 tests):** `Run`/`Walk`/`Hike` map directly, `Trail Running` still maps to `run`, case-insensitive (`WALKING` → `walk`), unknown activity type falls back to `run`.

**CSV column handling (6 tests):** missing `activities.csv` throws, missing `Filename` column throws, missing `Activity Date` column throws, header-only CSV → empty result with no errors, row with empty filename silently skipped, the `Distance (km)` header variant is recognised.

**Multi-row imports (3 tests):** multiple activities import as separate runs, one missing track file errors per-file but the rest still import, an unknown track extension is reported as a per-file error.

**Distance + duration fallback (3 tests):** distance falls back to CSV when GPX has no waypoints, duration falls back to CSV elapsed when track has fewer than 2 waypoints, duration uses GPX timestamps when CSV elapsed is 0 (regression for the "GPX `<time>` was never parsed" bug).

**Metadata + compression (3 tests):** `imported_from`/`strava_activity_type`/`title`/`activity_type`/`imported_at` populate, blank activity name falls back to "Strava import", `.gpx.gz` is decompressed before parsing.

### `apps/mobile_android/test/settings_sync_test.dart` — 38 tests

Covers the universal-bag and device-bag overlay logic on `SettingsSyncService` via two new `@visibleForTesting` delegates (`debugApplyUniversal`, `debugApplyDevice`). The applied-bag flow is the substantive logic — `pushX` / `updateX` are passthroughs to `SettingsService` which needs Supabase to test. Uses a real `Preferences` instance backed by `SharedPreferences.setMockInitialValues({})`.

**Universal bag (17 tests):** `preferred_unit` ("mi" → `useMiles=true`, "km" → false, integer-typed value ignored), `default_activity_type` (string updates local default, empty string rejected), `weekly_mileage_goal_m` (seeds a weekly distance goal when none exists, does NOT replace an existing one — the dashboard editor wins on edit, zero / negative values ignored), body weight, fueling rates, `privacy_default`, empty bag is a no-op, unknown keys ignored.

**Device bag (14 tests):** `voice_feedback_enabled` flips `audioCues`, `voice_feedback_interval_km` maps to `splitIntervalMetres` for both double and integer-typed values, non-bool `voice_feedback_enabled` is ignored, `keep_screen_on` round-trips, empty device bag is a no-op, and the `voice_cue_types` map overlay — absent ids stay on, a locally-toggled id the bag omits survives the merge, a **universal** map reaches the recorder (the web settings page can only write that bag), and a device entry overrides the universal one per cue ([decisions.md § 469](../architecture/decisions.md)). The master gate mirrors that shape since its own `UD` promotion ([decisions.md § 472](../architecture/decisions.md)): a **universal** `voice_feedback_enabled` reaches the recorder, a device value overrides the universal one, absent in both bags keeps the local default (on), and a non-bool universal value is dropped in both directions — never coerced on the recording stack's master cue gate.

**Initial state (2 tests):** `synced` is false and `service` is null before `onSignedIn`, every `pushX` / `updateX` is a no-op while settings is null (so a UI handler can safely call them before sign-in).

**Sign-out account reset (3 tests):** issue #231 — bag-mirrored `Preferences` reset to defaults, the prior user's cached bags dropped when the id is known, idempotent with no cache / no prior id.

### `apps/mobile_android/test/run_screen_recording_flow_test.dart` — 36 tests

Drives the full RunScreen UI flow on top of the existing data-pipeline integration test. Adds a mock-everything setUp that closes every platform-channel surface RunScreen touches when transitioning out of idle:

- `GeolocatorPlatform.instance` — fake (extends the platform interface).
- `WakelockPlusPlatformInterface.instance` — no-op subclass.
- MethodChannel `flutter.baseflow.com/permissions/methods` — returns "granted".
- MethodChannel `flutter_tts` — returns success.
- MethodChannel `run_app/run_notification` — returns null (lock-screen update channel).
- EventChannels `step_count` and `step_detection` (pedometer) — silent streams via the underlying MethodChannel `listen` / `cancel`.
- `dotenv` sets `TILE_URL_TEMPLATE` to an unsupported scheme so LiveRunMap's dio tile fetches fail synchronously rather than leaving pending fake-async timers that would trip the teardown guard once the Finish-save test enters `tester.runAsync`.

Tests: tapping START transitions the screen into countdown state (text "3" appears, START button gone); the countdown ticks 3 → 2 → 1 across three seconds (Timer.periodic at 1 Hz); after the countdown elapses the screen leaves countdown state (the large "3" is no longer the focal text); LiveRunMap mounts once recording begins (the invariant from `run_screen_test.dart` flips after `_begin()`); positions emitted by the geolocator fake during recording flow into the recorder without throwing; **holding Finish saves the run through `runStore.save`** — invokes the rendered `_HoldToStopButton`'s wired `onHoldComplete` (the 800 ms `Ticker` is unreliable under the fake clock) inside `tester.runAsync` (the recorder's position-stream cancel only completes on the real event loop) against a `_CapturingRunStore` spy (the real store's `save` does filesystem I/O that doesn't resolve under fake-async), then asserts exactly one run was captured carrying the chosen `activity_type`. The **treadmill live-mode toggle** group covers: the toggle stays hidden at idle even with a belt paired (it lives in the recording view); the belt-sample pump feeds `RunRecorder.setTreadmillSample` and `clearTreadmillMode` reverts it (driven via `BleTreadmill.debugEmitSample` against a begun recorder — the recording view itself is unreachable under flutter_test, so the wiring is exercised directly); and a sample-stream error is absorbed by the L4 `onError` guard (`debugEmitSampleError`). The toggle's in-view rendering + status banners are not widget-testable because `_buildLive` requires GPS/permission plugins that don't load under flutter_test.

### `apps/mobile_android/test/recording_integration_test.dart` — 3 tests

Integration test for the GPS → record → save → sync golden path. Reuses the `_FakeGeolocatorPlatform` pattern from `packages/run_recorder/test/geolocator_platform_fake_test.dart` (extends `GeolocatorPlatform` and feeds synthetic positions). Drives the full pipeline:

1. `RunRecorder` consumes the synthetic feed through the real `prepare()` → `begin()` → filter chain.
2. The recorded track is persisted to a `LocalRunStore` rooted at a fresh tempDir.
3. `SyncService.debugTrySync` drains the unsynced run through a capturing `_CapturingApiClient` that records the batch.

Three scenarios: the happy-path full pipeline (GPS feed → recorder → store → sync → API), a stream error mid-recording (recorder cancels its subscription on error; the partial track is still saveable), and the offline path (api null → run stays unsynced for a later attempt).

Stops short of driving the full `RunScreen` UI, which would need additional mocks for Pedometer / WakelockPlus / flutter_tts / flutter_local_notifications. The data pipeline is the regression target — UI mocking is documented as a follow-up below.

### `apps/mobile_android/test/sync_service_test.dart` — 61 tests

Covers the `_trySync` loop on `SyncService` via the new `@visibleForTesting debugTrySync` hook. A `_FakeApiClient` subclasses `ApiClient` and overrides `userId`, `saveRunsBatch`, and `deleteRunById`; `LocalRunStore` runs against a real `tempDir` (same pattern as `local_run_store_test.dart`).

**Guard clauses (3 tests):** no-op when `apiClient` is null, no-op when not signed in (`userId == null`), no-op when there is nothing to do.

**Push path (2 tests):** every unsynced run goes through one `saveRunsBatch` call and is marked synced afterwards, and a `saveRunsBatch` failure is swallowed without flipping the unsynced flag.

**Pending-delete drain (3 tests):** a successful delete removes the row from cloud / local / pending set, one failing delete does not poison the rest of the queue (others still drain), and `deleteRunById` is called once per pending id.

**Combined paths (2 tests):** a single tick handles both an unsynced push and a pending-delete drain in one cycle, and a reentrant call landing while a sync is in flight short-circuits on the `_syncing` guard so the batch isn't pushed twice.

**Lifecycle wiring (2 tests):** `didChangeAppLifecycleState(resumed)` triggers a sync; `paused` / `inactive` / `detached` do not.

**Connectivity wiring (5 tests):** drives the connectivity branch directly via `@visibleForTesting debugOnConnectivity`. `[wifi]` triggers a sync; `[mobile]` and `[ethernet]` also trigger; `[none]` and `[bluetooth]` alone do not; multi-result lists with at least one online entry fire (the common Android shape). Pins the guard policy: bluetooth-tethering is intentionally excluded from the "online" set since it isn't routable for upload.

**start / stop (2 tests):** `start()` registers as a binding observer, fires the startup `_trySync`, and routes subsequent lifecycle events through the observer. `stop()` removes the observer so further binding-level resume events don't fire syncs.

### `apps/mobile_android/test/local_route_store_test.dart` — 65 tests

Persistence tests for `LocalRouteStore` mirroring the `local_run_store_test.dart` pattern — `init(overrideDirectory: ...)` with a tempDir, real file I/O, no mocks. Covers init (directory creation, non-`.json` file filtering, corrupt-file tolerance), save (file write, round-trip across fresh instances, replace-on-same-id, newest-first ordering, single-listener-call invariant), `saveBatch` (parallel write + single notify, empty-iterable no-op, overlapping-id replace), `delete` (disk + memory + unknown-id), the unmodifiable `routes` view, and the **offline pin** group (15 tests) — `pinOffline` / `unpinOffline` idempotency, listener notification, sidecar round-trip across cold start, delete clears the pin, unmodifiable views, pin-without-route is allowed and surfaces when the route lands; pin survives saveBatch overwrite of the same id; concurrent pin/unpin pairs serialise correctly and the sidecar matches in-memory; tolerates a corrupt-JSON / wrong-shape / mixed-types sidecar on cold start without crashing; 100-pin round-trip stays well under 2 s and survives cold start intact. The local-only flag semantics are pinned by `decisions.md § 64`.

### `apps/mobile_android/test/local_run_store_write_serialisation_test.dart` — 7 tests · `local_route_store_write_serialisation_test.dart` — 8 tests

Two operations in flight over one store directory, in the shape a screen firing a save unawaited or a drain running against a live edit produces (`decisions.md § 828`). Both files fire the second call WITHOUT awaiting the first and then assert on disk **and** in memory: a `delete` / `deleteMany` is not undone by an in-flight `save` (it used to be, in both, with memory and disk agreeing on the resurrected row), two instances over one directory order against each other (the `background_sync.dart` shape a per-instance chain would miss), and the read-modify-write sidecars survive eight overlapping saves — on the route store that is the §67 owner-tag test, which failed about one run in three before the fix and left as few as two of eight routes untagged and drainable into another account. The route file also pins that no `.lock` sidecar is left behind (§ 829) and that a failed operation does not reject the ones queued behind it.

The run file carries the L0/L1 half: it holds the store's chain open through a `Completer` that is never completed and asserts an in-progress recording tick still appends, recovers and clears while a chained `save` sits queued behind the gate. A timing assertion was tried first and is the wrong instrument — `saveInProgress` spawns a `compute` isolate, so ordering against a fast chained body is not deterministic. The static half of the same contract lives in `architecture_guards_test.dart`.

### `apps/mobile_android/test/track_smoother_test.dart` — 9 tests

Pure-function tests for the top-level `smoothTrack(List<LatLng>)` helper extracted from `widgets/live_run_map.dart` (1-2-3-2-1 weighted polyline smoother used to reduce GPS jitter on the live map). Pins: short-track passthrough (length < 5), first-two-and-last-two preservation, the explicit `(a + 2b + 3c + 2d + e) / 9` weighted-mean formula, co-linear evenly-spaced points are unchanged, the no-mutation contract (returns a new list), length-0/1 inputs handled, length-5 input smooths exactly index 2, and constant-coordinate input (weights sum to 9) returns its input.

### `apps/mobile_android/test/period_summary_test.dart` — 26 tests

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

### `apps/mobile_android/test/goals_test.dart` — 32 tests

Pure-function tests for `evaluateGoal` and `RunGoal` JSON serialisation in `lib/goals.dart`:

- Period bounds (week start = Monday 00:00, month end wraps to next year)
- Distance target: empty list, runs outside period, sum, goal reached, ahead/behind pace
- Avg pace target: cycling-only runs excluded, meeting/exceeding/missing target, distance-weighted
- Run count and time targets
- Multi-target goal: each target evaluated independently, overall complete only when all met
- `RunGoal.toJson` / `fromJson` round-trip, legacy single-target migration

### `apps/mobile_android/test/fit_export_test.dart` — 3 tests

Round-trips the `lib/fit_export.dart` writer that produces FIT files for sharing recorded runs to Garmin Connect / TrainingPeaks. Pins the binary header layout (`.FIT` magic, protocol version, profile version, data record schema) and a small synthetic-track encode → decode → equality assertion.

### `apps/mobile_android/test/route_simplify_test.dart` — 30 tests

Tests for Ramer-Douglas-Peucker track simplification in `lib/route_simplify.dart`:

- Fewer than 3 points returned unchanged
- Collinear points dropped
- `computeElevationGain` accumulates only positive deltas
- `simplifyToBudget` (the mobile-only priority-DP simplifier behind the watch course push, decisions §370): never exceeds the point budget, keeps both endpoints exactly so the tail is never cut, preserves order, spends the budget on the corners rather than evenly along the line, collapses a fully degenerate track, and rejects a budget below two

### `apps/mobile_android/test/watch_course_test.dart` — 23 tests

The `CRS1` course wire format in `lib/watch_course.dart` — the phone's encode side of the watch course push:

- `encodeCourse` against the frozen goldens shared byte-for-byte with the firmware's `watch_core::course_store` tests, with and without the elevation series
- The v3 CRC trailer is derived (not a pinned literal) and changes when one point moves
- Signed lat/lon and below-sea-level / out-of-range elevation encoding
- Refusals: an elevation series that isn't one sample per point, fewer than two points, more than `kMaxCoursePoints`
- `chunkCourse` offsets reassemble the frame, including a full-capacity elevation frame across many chunks
- `courseFromWaypoints` shaping: a short route passes through, a dense one is thinned to the cap with its real endpoints intact (never cut), elevation rides along only when every carried point has one (a single missing or non-finite sample drops the whole profile), and fewer than two positions is refused with a reason

### `apps/mobile_android/test/route_detail_watch_course_test.dart` — 18 tests

Widget tests for the Send-to-watch entry in `lib/screens/route_detail_screen.dart`'s share menu, over a fake `WatchBleTransport` and a `devBackendUrl` driving both sides of the dev gate:

- The action shows against a loopback backend and is absent against a production one (decisions §71 / §209 — no hardware exists)
- A short route pushes every point, scans once, disconnects once, and reports the count
- An over-long route is thinned to `kMaxCoursePoints` with the route's real end on the wire, and the banner names both counts
- A one-position route is refused with nothing written and no scan
- A failed write surfaces the failure (never a success banner) and still disconnects
- A non-owner's push carries the privacy-CLIPPED trace, not the stored polyline (decisions §33)

### `apps/mobile_android/test/ble_heart_rate_test.dart` — 14 tests

Pure-function tests for `parseBleHeartRateMeasurement` in `lib/ble_heart_rate.dart`, the BLE Heart Rate Service characteristic 0x2A37 parser:

- 8-bit BPM decoding (flags byte with various sensor-contact + EE bits)
- 16-bit BPM little-endian decoding
- 16-bit at low value (some straps always report 16-bit)
- Empty payload returns null
- Truncated payload returns null
- Single-byte payload returns null

### `apps/mobile_android/test/training_test.dart` — 65 tests

Dart mirror of `apps/web/src/lib/training/training.test.ts`. The Dart engine (`lib/training.dart`) must produce the same paces and phase assignments as the TypeScript engine for the same inputs. Covers the same functions:

- `vdotFromRace`: 3 tests (VDOT 50, VDOT 54, faster = higher)
- `riegelPredict`: 2 tests (identity, projection)
- `pacesFromGoalPace`: 2 tests (zone ordering, 4:00/km band)
- `resolveTrainingPaces`: 2 tests (recent 5k anchor, fallback)
- `phaseFor`: 2 tests (phase splits, final week)
- `generatePlan`: 7 tests (week count, day distribution, taper volume, race week, intervals, no-input fallback, stepback)

### `apps/mobile_android/test/training_load_test.dart` — 28 tests

Dart mirror of `apps/web/src/lib/training_load.test.ts`. The Dart engine (`lib/training_load.dart`) must produce the same Fitness / Fatigue / Form curves as the TypeScript engine for the same inputs. Covers `computeStress` (distance fallback ~50 for an easy 5k, TRIMP path lights up with `avg_bpm` + resting + max, zero-input → 0), `aggregateDailyStress` (sums same-day runs), `computeTrainingLoadSeries` (emits exactly `windowDays` entries, TSB rises during a 14-day taper, all-zero with no runs), and `hasTrimpSignal` (no `avg_bpm` / has `avg_bpm` + prefs / prefs missing).

### `apps/mobile_android/test/segments_test.dart` — 21 tests

Dart mirror of `apps/web/src/lib/segments.test.ts`. Pure tests for the segment-effort walker in `lib/segments.dart#computeEffortFromTrack`. Same `straightTrack` synthetic helper (meridian-aligned, constant pace) so haversine cumulative distance is predictable. Covers a clean segment, run shorter than segment end, sub-2-point tracks, zero / negative segment windows, sparse-sampling guard (median step > segLen / 5), missing timestamps in the interpolation bracket, mid-segment interpolation, and sample-aligned endpoints.

### `apps/mobile_android/test/privacy_test.dart` — 9 tests

Dart mirror of `apps/web/src/lib/privacy.test.ts`. Pure tests for `lib/privacy.dart`. Covers `isInAnyZone` (empty zones, centre, far point) and `clipPointsToZones` (empty zones returns input, drops leading + trailing in-zone, keeps interior, every-point-in-zone returns empty, multi-zone union).

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
- **`watch_ingest_single_decoder_guard_test.dart` (2 tests):** Pins that one payload has ONE decoder: `WatchIngest` normalises the WCSession envelope and both entry points delegate to it. Two hand-written decoders for one payload is what let a `track` sent as JSON text be dropped on the signed-out replay path (decisions § 1254).

### `apps/mobile_android/test/undo_queue_test.dart` — 14 tests

The Dart twin of web `core/undo_queue.test.ts`, case for case in the same order (parity pair, decisions § 523). Same fake clock + timer pair, so every assertion is deterministic; same 14 properties — `defer` does NOT commit, `undo` cancels the mutation entirely, the window elapsing commits and does not restore, a failed commit restores AND reports, a second destruction commits the first and disarms its timer (one slot), a stale `undo` after the window closed is a no-op, `flush` is idempotent, `pause`/`resume` spend only the remaining time and keep `id` + `windowMs` stable, a `0` window arms no timer, a negative window clamps to no-limit, and `undoWindowSFromPref` round-trips every offered choice while absent / corrupt / unrecognised values fall back to 8 s and **never** to no-limit. The Dart corrupt-value list additionally covers `8.5` and `true`, which JS's `typeof`/`Number.isFinite` gate rejects for free.

### `apps/mobile_android/test/undo_bar_test.dart` — 11 tests

The mobile host, and the accessibility measurement the host's design rests on. Wiring: the pill appears while the mutation is held, Undo cancels it and banners "Restored", the dismiss button commits now, a failed commit restores and reports, a second destruction takes the one slot, and `undo_window_s = 0` / a corrupt value behave as the pref contract says.

Three tests are the load-bearing ones. **The pill stays in the compiled semantics tree** while a dialog is up, and again while a modal bottom sheet is up — walked off `semanticsOwner.rootSemanticsNode`, not off a widget finder, because the trap here is that the widget is *painted* either way. **A `SnackBar` raised under the same barrier is NOT** — the dump contains the dialog and neither the snack nor the screen behind it, because a modal barrier's `BlockSemantics` drops the whole route beneath it and a snack bar lives inside that route's `Scaffold`. That is the evidence for hosting the offer in a root `Overlay` entry instead, and it is why mobile needed no analogue of web's Tab-ring widening (decisions § 521) to let an in-sheet delete adopt undo. A further test pops a route mid-window and asserts the offer survives **and** the commit still lands — the pending mutation must never be silently discarded.

### `apps/mobile_android/test/settings_undo_window_test.dart` — 5 tests

The `undo_window_s` editor + read path. The row shows 8 s on a fresh install; picking "Until I dismiss it" writes the universal bag AND `Preferences`; picking 30 s survives a cold start offline; a corrupt stored value reads back as 8 s and never as no-limit. The fifth drives `debugApplyUniversal` directly: a present-but-corrupt bag value normalises to 8, `0` is honoured, and an **absent** key leaves a deliberate local choice alone rather than resetting it.

### `apps/mobile_android/test/profile_notification_undo_test.dart` — 4 tests

The notification dismiss, the strongest undo case in the app (a system-minted row). Dismissing one row offers undo and reaches the server only when the window closes; Undo cancels it outright; dismissing a **collapsed group** is one intent, so one bar and one **batched** `deleteNotifications` call rather than N round-trips; and the dismiss opens no confirm dialog.

Undo adoption on the other five mobile surfaces is pinned inside each surface's own suite, replacing the confirm/cancel pairs that pinned the old shape: `route_conditions_test.dart`, `gear_wear_log_test.dart` + `gear_form_sheet_test.dart` (the in-sheet case), `nutrition_screen_test.dart` (including a commit-failure leg through a throwing store, and the retargeted second half of the #501 focus-leak test, whose vehicle used to be the delete confirm), `run_social_section_test.dart`, `route_detail_review_delete_test.dart` (whose replacement asserts the stronger property the confirm never offered — after Undo the server was never called, so the row keeps its own id) and `route_markers_panel_test.dart`. `architecture_guards_test.dart` adds five structural guards: every `commit` closure is context-free, every `restore` is mount-guarded, the host is a root overlay entry and never a `ScaffoldMessenger`, and the recording surface + account deletion keep confirm-then-gone.

### `apps/mobile_android/test/calendar_day_arithmetic_guard_test.dart` — 2 tests

The DST date-cursor guard (`decisions.md § 589`). Scans every file under `lib/` and fails with file:line for any `.add`/`.subtract(Duration(days:))` — stepping a local date by a fixed 24 hours lands at 23:00 the previous day across a fall-back, which is how the plan-detail week strip dropped its seventh day, the dashboard heatmap shifted every column, `recap._mondayOf` split a week's runs across two buckets, and the "Yesterday" heading stopped appearing.

A `DateTime.now()` or `.toUtc()` receiver is exempt structurally — an instant has no local midnight to drift off. Everything else opts out with an inline `// elapsed-time:` marker naming the reason, read from the line itself or the contiguous comment block above it; the marker is local rather than a file allowlist because several files carry both shapes. The second test proves the matcher still fires, so a refactor that breaks the regex can't pass by matching nothing.

This is the timezone-independent half of the fix: the behavioural repros in `current_week_strip_test.dart` only bite under `TZ=America/New_York`, and CI runs in UTC.

### `apps/mobile_android/test/post_await_setstate_guard_test.dart` — 2 tests

The async-gap guard (issue #734). One test pins the detector itself against ten shapes — the bare `await` → `setState`, an early-return guard, a positive `if (mounted)`, a `context.mounted` guard, an await that comes *after* the setState, an escaping block (`if (x) { await f(); return; }`), a closure body, an await inside a `try` read from both the code after it and the `catch`, and a commented-out mention. The second scans every file under `lib/` and fails with file:line for any `setState` whose enclosing function reaches it across an unguarded await.

Structural rather than a backwards regex: it walks a frame per brace so a closure is not a continuation of its enclosing method, and an escaping block does not hand its awaits to the code after it. Tuned for precision over recall — a guard that lives in a helper the method calls is not seen, and the allowlist is empty deliberately. Runs in about a second over the whole tree.

### `apps/mobile_android/test/offline_store_wipe_test.dart` — 8 tests

What sign-out must leave behind on a shared device. The original four cover the screen-owned `OfflineSyncStore` types that `main.dart` holds no singleton for (issue #228): the registry builds one instance of each, every one of their directories is emptied, a store whose init throws does not strand the rest, and an atomic-write `.tmp` orphan — invisible to every `.json`-filtered listing in that layer, and for `LocalCrossingsStore` carrying a bib and weigh-in fields — does not survive either. Four more added for [decisions § 842](../architecture/decisions.md): `in_progress.json` is the one local artifact carrying no owner tag, and recovery stamps whatever it finds with whoever is signed in at the next cold start — so A's force-killed partial became B's run, GPS trace and all. `wipeInProgressRecording` clears it, is idempotent on an empty store, isolates its own failure (it runs beside four other wipes inside an auth listener that must not throw), and a source guard reads `main.dart`'s `signedOut` branch, which cannot be mounted from a test.

### `apps/mobile_android/test/offline_sync_store_drain_race_test.dart` — 9 tests

What `OfflineSyncStore` does between a network push and the disk it writes back to ([decisions § 841](../architecture/decisions.md)). The drain's identity tests were correct and ran outside the write chain, so a screen edit already QUEUED behind a busy chain was not yet resident when the check looked: the check passed, and the pre-push copy landed on top of the edit stamped `synced` — a permanent, invisible divergence, since a `synced` row is never pushed again. `editDuringPush` reproduces it deterministically by holding the chain open, releasing the push, and giving the real event loop enough turns for the mark to decide before the chain drains. Four cases on the gear store: the edit survives in memory AND on a reload, a row re-created during its own delete push is not dropped with the tombstone, and — the negative control that stops the fix being "never mark" — a row nobody touched is still marked `synced` and `hasPending` clears. Two on the food store, which is the vehicle for `rewriteAll`'s prune because it builds a synced row's clock from the server's `last_modified_at`, so two identical fetches really do encode identically and the diff-skip really does fire: a row pruned and handed back unchanged must be rewritten, and an unchanged refresh must still write nothing.

### `apps/mobile_android/test/capture_png_test.dart` — 5 tests

The share-card rasteriser and the branch that used to lose a failure ([decisions § 843](../architecture/decisions.md)). Four sheets each carried `if (byteData == null) return;` inside a `try` whose `catch` shows a share-failed banner, so a null encoding cleared the spinner and said nothing — indistinguishable from a cancel and from a success. `pngBytesOrThrow(null)` throws and `pngBytesOrThrow(data)` returns its bytes (the null branch is only reachable at all because it is split out — a real `RenderRepaintBoundary` cannot be asked to produce one); `capturePngBytes` over a mounted boundary yields bytes carrying the PNG signature, and over an unmounted one throws so the caller's banner fires. Plus a source guard that `ImageByteFormat.png` appears nowhere under `lib/` but that module, because the defect was four copies of one line.

### `apps/mobile_android/test/route_share_card_test.dart` — 9 tests

The one surface whose artifact leaves the app entirely, and which nothing had ever rendered — `_ShareCardContent` was private, so every test naming this file was a guard reading its source as a string ([decisions § 843](../architecture/decisions.md)). Two properties are worth pinning about a picture nobody can correct after the fact. **Units:** distance followed the km/mi preference and the climb was hard-coded metres, so a mile-unit runner posted "6.21 mi" beside "128 m"; the suite reads both under each preference and asserts the metric spelling is absent under miles, plus that a flat route omits the climb rather than printing a zero. **Map-vs-glyph:** `routeShareCardHasMap` and the card's own fallback are two spellings of one threshold, and the sheet waits for basemap tiles iff the predicate says so — a disagreement is either a spinner waiting for tiles that never arrive or a part-black basemap baked into the PNG, so the boundary is walked at 0/1/2/3 waypoints. Also that the drawn line is exactly the waypoints handed in, since the PNG is the one artifact a privacy zone cannot be re-applied to.

### `apps/mobile_android/test/challenge_progress_bar_test.dart` — 25 tests

What a challenge value is CALLED and what UNIT it is printed in. `check_constraint_unions.mjs` holds `challengeMetricLabel` / `challengeValueLabel` to `challenges_metric_ck`'s vocabulary, but it reads case LABELS — an arm that exists and formats the wrong quantity is invisible to it. So: every metric in `kChallengeMetrics` gets a distinct name (a sixth metric falling through the `default:` would be named "Distance" on three surfaces at once) and a distinct value string; a count is a count rather than "0.01 km"; an elevation is not a distance; distance and elevation both follow the km/mi preference while a count and a day tally do not; and the duration formatter is walked across the one-hour boundary. The widget half pins the three claims the bar must not make: a fill on a goal-less board, a "Complete" pill below the goal, and a pace verdict with no window to pace against — including that a completed challenge is not then told it is behind, and that an unopened or closed window is not graded.

### `apps/mobile_android/test/l10n_generated_parity_test.dart` — 22 tests (1 + 3 per catalogue)

The seven ARB catalogues against the checked-in `lib/l10n/gen/` ([decisions § 844](../architecture/decisions.md)). `l10n_parity_test.dart` measures the ARBs against each other and `architecture_guards_test.dart` measures the locale set; neither measures the hand-run `gen-l10n` step between them, so an ARB whose wording changed without a regeneration ships the previous sentence in every locale and a hand-edit to a `gen/` file is invisible from both directions. Reads the generated Dart back — there is no reflection to ask an `AppLocalizations` for a getter named at runtime — and asserts the member set in both directions plus, for every non-ICU message, the literal itself with `$name` rewritten to `{name}`: 3,761 of 3,826 messages per catalogue. Each group carries a floor on how many members it parsed, so a change in what `gen-l10n` emits fails the guard rather than emptying it.

### `apps/mobile_ios/test/` — 544 files, byte-for-byte

After the April 2026 mobile-codebase unification, `apps/mobile_ios/test/` is kept identical to `apps/mobile_android/test/` via `diff -rq`. Every test file documented above runs on the iOS target too **locally** — `melos run test` has no scope filter — but **not in CI**: the `test-packages` job scopes `melos exec` to `run_recorder`, `mobile_android`, `api_client`, `gpx_parser`, `ui_kit` and `core_models`, and `mobile_ios` is not among them. That is not a gap for byte-identical Dart, but it is why a test gated on an `ios/` file being present asserts nothing on any CI run — two such groups existed and were removed in favour of `scripts/check_ios_native_declarations.mjs` (decisions.md § 742). Per-target counts: `flutter test` compiles separately, so each test file is executed twice when you run both apps locally. Don't add iOS-specific test files — every test belongs in both apps. The architecture-guard tests under `apps/mobile_android/test/architecture_guards_test.dart` read `lib/screens/run_screen.dart` from the working directory, so they pin the same invariants on both targets.

### `packages/api_client/test/api_client_di_test.dart` — 4 tests

Smoke tests for the `@visibleForTesting ApiClient.withClient(SupabaseClient)` named constructor — the DI seam that lets tests inject a fake `SupabaseClient` without booting `Supabase.initialize`. Pins: `userId` reads from the injected client (null when not signed in), `userEmail` reads from the injected client, two `withClient` instances stay independent (the override is an instance field, not static), and the default `ApiClient()` constructor still falls back to the global (which throws when `Supabase.initialize` hasn't run — the throw is the test value, confirming the seam only fires for `withClient`).

### `packages/api_client/test/api_client_codecs_test.dart` — 34 tests

Covers the four pure helpers on `ApiClient` exposed via `@visibleForTesting` static accessors (`debugWaypointToJson`, `debugWaypointFromJson`, `debugRunFromRow`, `debugRouteFromRow`). The methods drive the wire format for the gzipped track blob in the `runs` Storage bucket and the row-to-domain conversion that powers every list / detail screen — code that previously had no direct coverage because it hides behind `Supabase.instance.client`.

**Waypoint codec (7 tests):** round-trip with all optional fields, timestamp encodes UTC ISO 8601, local-time timestamps are normalised to UTC on encode, omits `bpm` key when `null`, decodes integer-typed `lat`/`lng` into `double`, treats `null`-vs-absent `ele` the same, malformed timestamp falls back to `null` (via `DateTime.tryParse`).

**`debugRunFromRow` (8 tests):** basic field mapping, `track_url` stashed onto `metadata` for lazy-fetch by callers, null metadata + null `track_url` leaves `Run.metadata` null, existing metadata keys survive alongside the stashed `track_url`, every `RunSource` value parses correctly, unknown `source` falls back to `RunSource.app` (matches the [`apps/web/src/lib/types.test.ts`](../../apps/web/src/lib/types.test.ts) defensive contract), `externalId` and `createdAt` pass through.

**`debugRouteFromRow` (9 tests):** basic field mapping, null `elevation_m` collapses to `0` (not null), explicit `elevation_m` is preserved, null `is_public` is treated as `false`, explicit `is_public=true` round-trips, `tags` pass through verbatim, `featured` + `run_count` + `is_starred` populate as expected, waypoint elevation passes through (or is null when absent).

The tests run under `flutter test` because `api_client` transitively depends on `supabase_flutter` (which pins Flutter); the test bodies themselves use only `package:test/test.dart`.

### `packages/gpx_parser/test/route_parser_test.dart` — 60 tests

Pure-parser coverage for `RouteParser` (GPX/KML/TCX/GeoJSON) and `FitParser`. GPX block (9 tests): `<trkpt>` happy path with elevation gain summed correctly, `<rtept>` and `<wpt>` fallbacks when no track points, malformed `lat="bad"` skipped, `name` defaults to "Imported route", elevation gain ignores descents, `<time>` parsed onto `Waypoint.timestamp`, missing `<time>` leaves it null, empty document returns an empty waypoint list. KML block (4 tests): LineString with elevation, missing `<coordinates>` element, non-numeric triples dropped, 2D coordinates leave elevation null. TCX block (3 tests): `<Trackpoint><Position>` with altitude + timestamps, missing `<Position>` skipped, `<Notes>` fallback when `<Name>` is absent. GeoJSON block (5 tests): `[lng, lat, ele]` order, 2D coordinates, missing geometry, missing `properties.name`, malformed coordinate entries skipped. FIT block (4 tests): too-short bytes throw, `.FIT` signature mismatch throws, header size other than 12/14 throws, valid empty header parses to an empty route.

### `packages/core_models/test/run_source_test.dart` — 2 tests

Regression for the `RunSource.watch` enum-map regen. Constructs a `Run` with `source: RunSource.watch`, asserts `toJson()['source'] == 'watch'` and `fromJson({'source': 'watch'}).source == RunSource.watch`. Existed to catch the crash that would otherwise hit `_$RunSourceEnumMap[instance.source]!` on any serialisation of a watch-originated run.

### `apps/web/src/lib/training/training.test.ts` — 71 tests

TypeScript unit tests for the training plan engine, written against Node's `node:test` API (no test runner dependency). Run with `npx tsx --test src/lib/training/training.test.ts` from `apps/web`.

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

**`phaseFor` (4 tests):**
- 16-week plan splits ~30/40/20/10 base/build/peak/taper
- Final week is always race
- Every total from the editor floor (4) to 30 seats a taper, keeps phases in order, and sums exactly to the total
- A 10-week (and 5-week) plan tapers instead of peaking into race week

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

### `apps/web/src/lib/segments/segments.test.ts` — 44 tests

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

### `apps/web/src/lib/learn/*.test.ts` — 56 tests across 4 files (Learn/guides, `learn.md`, decisions §161)

Run with `npx tsx --test src/lib/learn/guides.test.ts src/lib/learn/learn_meta.test.ts` from `apps/web`. Web-only (no Dart twin).

- **`guides.test.ts`** — the build guard for a new guide: reads the `.md` files off disk (the glob index isn't tsx-resolvable) and parses their YAML frontmatter, asserting every guide has the required fields (title / description / category / slug / order / updated), `slug === filename stem`, `updated` is an ISO date, `category` is in `CATEGORIES`, `cta.feature` (when present) is a known CTA target, and English slugs are unique. A malformed guide fails CI here, not in prod.
- **`learn_meta.test.ts`** — the SEO wire shape: `normaliseSiteUrl` / `buildLearnCanonical` (trailing-slash + leading-slash normalisation, root-relative when base empty), `buildGuideTitle` / `buildGuideDescription` (site-name suffix + empty fallback), and `buildGuideJsonLd` (valid `Article` JSON, Home→Learn→category→article breadcrumb, and the `<`/`>`/`&` escape so a guide title can't break out of the `<script>` tag).

`sitemap.test.ts` is also extended with `learnEntries` coverage (hub 0.8 / category 0.6 / guide 0.7 + frontmatter lastmod, and the lastmod survives `buildSitemap`).

### `apps/web/src/lib/routes/privacy.test.ts` — 9 tests

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

### `apps/web/src/lib/backup/backup.test.ts` — 15 tests

TypeScript unit tests for the streaming + parallel-download backup writer (`lib/backup_writer.ts`). Run with `npx tsx --test src/lib/backup.test.ts` from `apps/web`. Exercises the pure writer seam without supabase-js: round-trip through JSZip to confirm manifest + runs + routes + profile + tracks all land; bounded-concurrency contract observed via a counter-tracking fetcher (peak in-flight ≤ `concurrency`, observable parallelism); single-track failure doesn't sink the rest (manifest counts reflect what landed); empty `runsWithTracks` produces a valid manifest-only archive; `concurrency < 1` rejected; progress events ordered (`tracks` → `writing` → `done`); profile `id` field stripped to keep the archive re-homeable.

### `apps/web/src/lib/backup/backup_reader.test.ts` — 23 tests

Pure-Dart-equivalent tests for the read side at `lib/backup_reader.ts` — `parseBackupArchive` + `stripServerManagedProfileFields` + `coalesceActivityType` + `extractEventIds`. Run with `npx tsx --test src/lib/backup_reader.test.ts`. Builds synthetic archives in-memory with a thin `buildArchive` helper; the Uint8Array `JSZip.loadAsync` accepts in Node (the parameter type is widened to accept it explicitly).

**parseBackupArchive (11 tests):** missing `manifest.json` throws; wrong format throws; future-version throws; missing `version` field accepted as v0 for back-compat; happy path returns runs + routes + profile + settingsPrefs + lazy `getTrackBytes`; `getTrackBytes` returns null for unknown id; missing `runs.json` / `routes.json` / `profile.json` yields safe defaults; `profile.json` with `null` profile field is tolerated; manifest carries metadata keys (exported_by_user_id, exported_from, counts) through verbatim.

**stripServerManagedProfileFields (3 tests):** drops `subscription_tier` + `subscription_at` + `parkrun_number`; no-op when none of those keys are present and returns a fresh object; preserves nested objects (hr_zones) untouched.

**coalesceActivityType (5 tests):** inserts `'run'` when metadata is null / undefined / missing the key / non-string-typed / not a map; preserves explicit string-typed values; clones the input instead of mutating it.

**extractEventIds (2 tests):** distinct ids extracted; nulls / undefineds / empty strings / non-strings / missing-key entries all dropped.

### `apps/web/src/lib/training/training_load.test.ts` — 32 tests

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

**Test-runner constraint:** `tsx --test` runs raw TypeScript through the Node loader and does not understand Svelte runes. That means `*.svelte.ts` modules (`units.svelte.ts`, `stores/auth.svelte.ts`, `stores/toast.svelte.ts`) cannot be imported — the `$state(...)` call at module load fails with `ReferenceError: $state is not defined`. Keep test-targeted modules (`training.ts`, `fitness.ts`, etc.) free of imports from `.svelte.ts` files. The unit-aware formatters `fmtKm` / `fmtPace` live in `units.svelte.ts` for that reason; UI code imports them from `$lib/format/units.svelte` directly. Adding vitest with the Svelte plugin would lift this restriction — not done yet.

### `apps/web/src/lib/core/undo_queue.test.ts` — 14 tests

The deferred-commit undo contract (issue #666 U8, decisions § 514). A fake clock + timer pair drives `createUndoQueue`, so every assertion is deterministic: `defer` does NOT commit; `undo` cancels the mutation entirely (commit never runs, `restore` does); the window elapsing commits and does NOT restore; a failed commit restores AND reports; a second destruction commits the first and disarms its timer (the one-slot rule); a stale `undo` after the window closed is a no-op rather than a false claim that the row came back; `flush` is idempotent. The WCAG 2.2.1 half is pinned too — `pause` disarms and a 60 s hover consumes none of the window, `resume` re-arms with only the remainder, the published `id` + `windowMs` stay stable across a pause so the bar's CSS countdown does not restart, a `0` window arms no timer at all and is still undoable ten minutes later, and a negative window clamps to no-limit rather than firing instantly. Plus `undoWindowSFromPref`: every offered choice round-trips, and absent / corrupt / unrecognised values fall back to the 8 s default and **never** to no-limit.

The reactive shell (`stores/undo.svelte.ts`) and the bar itself are covered e2e — see `nutrition.spec.ts`, `route-conditions.spec.ts`, `runs/social.spec.ts` and `cross-user/comments.spec.ts` below, plus round 12's four adopters: `u/notifications.spec.ts`, `routes/review.spec.ts`, `routes/markers.spec.ts` and `settings/gear.spec.ts` (the last carrying the keyboard-only in-modal leg).

### `apps/web/src/lib/undo_modal_trap_guard.test.ts` — 7 tests

Source-level guards for the in-modal half of the undo contract (decisions § 516), the question round 11 left open. Three pin the mechanism: `Modal.svelte`'s Tab ring collects focusables from any rendered `[data-modal-trap-include]` host outside the dialog, skips a host already inside it, and concatenates **dialog-first** (WCAG 2.4.3 — the offer is a consequence of an action in the dialog, and the order must not follow the host's position in the layout); and `UndoBar.svelte` carries the attribute on the *always-mounted* live region rather than on the conditional bar, so it is present before an offer exists. Four more pin the confirm-OR-undo classification per adopting surface — the gear wear-log, notification dismiss, route review and route marker deletes each call `deferDestructive` and no longer carry the confirm state they replaced. The point of the file is that a future round cannot quietly re-derive "in-modal deletes must keep their confirm": the dead end was resolved, and breaking either half of the resolution fails here rather than shipping an affordance only pointer users can reach.

### `apps/web/src/lib/metadata_registry_guard.test.ts` — 1 test

Web half of the four-platform `runs.metadata` drift guard (Dart `metadata_registry_test.dart`, Kotlin `MetadataRegistryTest.kt`, Swift `MetadataRegistryTests.swift`). Walks `apps/web/src` (production `.ts` / `.svelte` only), strips comments, and collects every key reached via `METADATA_KEYS.<x>`, a `metadata['x']` subscript, a `run.metadata.x` dotted read, or a depth-1 `metadata: { x: … }` object literal — then fails on any key with no table row in `docs/backend/metadata.md`. Replaced the weaker `tests-e2e/cross-cutting/metadata-registry.spec.ts`, which needed the whole Playwright harness for a static source scan, missed object-literal writes and `METADATA_KEYS` indirection, and counted any backticked token anywhere in the doc as "documented".

### `apps/web/src/lib/raw_text_end_tag_guard.test.ts` — 2 tests

Every HTML end tag written into a regex under `apps/web/src` or `apps/web/lambda` must close the way a parser does — `</name` followed by whitespace, `/` or `>`, then junk to the first `>` (CodeQL `js/bad-tag-filter`). Scoped to the raw-text / RCDATA elements plus `head`, which is where the damage lands: a lazy body that cannot see its close runs on to the next one in the document, and `</head>` is a splice point whose loss drops a whole `<head>` injection. 20 occurrences today; 19 were intolerant before [decisions § 1086](../architecture/decisions.md). XML end tags are deliberately out of scope. The second test fails a declared exemption that no longer names an intolerant spelling.

### `apps/web/src/lib/response_body_parse_guard.test.ts` — 1 test

Every `await res.json()` / `.text()` in production web source must sit inside a `try`, carry a `.catch`, or be registered with a count and a reason. The rule cannot be keyed on the return type — `lookupBarcode` returns `Promise<T | null>` and throws on a parse failure deliberately — so the register is hand-written and fails in both directions: an unguarded parse in an unregistered file, and a registered file whose count moved. 33 sites, 8 registered as throw-contracted across three files. [decisions § 1087](../architecture/decisions.md).

### `apps/web/src/lib/runs/hr_coverage.test.ts` — 6 tests

`hrCoveragePercent`, the grading behind run detail's heart-rate-coverage copy ([decisions § 1088](../architecture/decisions.md)). Pins that `0` is a measurement (sensor enabled, nothing delivered) and absent is not, that a nonzero fraction never rounds down into that reading, that 100 is a ceiling, and that a value outside the writer's `0..1` contract is refused rather than rendered as "covered 8500% of this run".

### `apps/web/src/lib/types.test.ts` — 12 tests

`parseRunSource` defensive-fallback contract — every valid `RunSource` value passes through; null, undefined, empty string, unknown string, and case-mismatched input all fall back to `'app'`.

### `apps/web/src/lib/routes/route_simplify.test.ts` — 23 tests

Mirror of `apps/mobile_android/test/route_simplify_test.dart`. Pure tests for the Ramer-Douglas-Peucker simplifier in `lib/route_simplify.ts`. Covers the short-track passthrough (< 3 points), the clean straight-line collapse to two endpoints, sharp-corner preservation above epsilon, sub-epsilon jitter collapse on a straight line, the first/last retention contract, the no-mutation guarantee, and `computeElevationGain` (positive-delta-only sum, descending-only profile = 0, null-elevation skip with chain-breaking, empty / single-point input).

### `apps/web/src/lib/routes/elevation.test.ts` — 16 tests

Pure tests for the Open-Meteo elevation helpers (`lib/elevation.ts`). `calculateElevationGain` covers positive-delta accumulation, flat profile = 0, descending profile = 0, empty / single-point input, and the rounding contract (sum of three +0.4 deltas → 1). `sampleCoordinates` covers passthrough below `maxPoints`, equal-count passthrough, exact-`maxPoints` cap when input is larger (with first + last endpoints retained), and the `indices ↔ sampled` alignment invariant.

### `apps/web/src/lib/routes/gpx.test.ts` — 13 tests

Pure tests for the GPX / KML / run-GPX writers in `lib/gpx.ts`. `toGpx` covers the GPX 1.1 namespace + creator, one trkpt per coordinate, the lat/lon attribute mapping (input `[lng, lat]` → `lat="..." lon="..."`), missing-elevation falls back to 0, XML escaping in the name (`& < >`), and an empty-coordinates input emits a well-formed empty trkseg. `toRunGpx` covers per-point `<time>` emission when present, omission of `<ele>` when null and `<time>` when missing, the metadata `<time>` carrying `startedAtIso` (not the local clock), and name escaping. `toKml` covers the KML 2.2 namespace + the `lng,lat,ele` coordinate-string ordering, missing-elevation = 0, and name escaping in both Document and Placemark scopes.

### `apps/web/src/lib/core/gear_undo_scope.test.ts` — 2 tests

Source guard over the undo queue's one adopter ([§ 984](../architecture/decisions.md)). `createUndoQueue` calls `restore` on undo OR on a commit that later fails, and the two land at very different times — the commit runs when the window closes, by which point the runner may have opened another pair's gear modal, and a bare re-assignment then paints one pair's observations under another's name. Pins that `removeWearLog`'s restore no-ops when `wearLogsEpoch` has moved, that the epoch is CAPTURED before the destruction is deferred (a live read always equals itself), and that every replacement of `wearLogs` goes through the one `setWearLogs` that bumps it — a new assignment written in the obvious shape would otherwise make the check vacuous for that path alone. Source-level because `/settings/gear/+page.svelte` cannot be executed under `tsx --test`.

### `apps/web/src/lib/runs/run_stats.test.ts` — 21 tests

Pure tests for `lib/run_stats.ts` (web-only — Android computes splits inline in `run_detail_screen.dart`). `movingTimeSeconds` covers empty / single-point input = 0, threshold-passing segments counted, sub-threshold (stopped) segments dropped, mixed running + 60 s stop counts only running, the custom `minSpeedMps` override, same-timestamp pairs (`dt == 0`) skipped, and points without `ts` skipped. `elevationGainMetres` was deleted in round 34 ([§ 1004](../architecture/decisions.md)): the run-detail page calls `computeElevationGain` directly, as `run_detail_screen.dart` already did, and every one of its behavioural cases was already covered in `routes/route_simplify.test.ts`. What replaced them here is a source guard over the page — it must derive `realElevationGain` from a `computeElevationGain(` call, import it from the module that owns the rule rather than a re-export, and no longer name the adapter. `computeRealSplits` covers short-track + no-timestamp early returns, the even-paced 3 km run producing three full splits at the right pace and distance (with one-sample overshoot tolerance — see source comment), the final partial split being emitted when remainder > 50 m, the final partial < 50 m being dropped, per-split elevation gain carrying through, and tracks without elevation leaving every split's `elevation_m` null.

### `apps/web/src/lib/social/recurrence.test.ts` — 30 tests

Mirror of `apps/mobile_android/test/recurrence_test.dart`. Pure tests for `lib/recurrence.ts`. `expandInstances` covers the non-recurring single-instance fork (in / out of window), weekly events producing 4-5 instances in a month, biweekly producing fewer than weekly, `recurrence_count` cap, `recurrence_until` cap, monthly producing one per month in window, instances never preceding `starts_at`, and monthly with `recurrence_count`. `nextInstanceAfter` covers the next-instance lookup and the null past-`recurrence_until` case. `describeRecurrence` covers the null-freq "One-off event" string, the monthly "Repeats monthly" string, weekly + byday output in ISO order regardless of input order, and biweekly without byday.

### `apps/web/src/lib/social/event_occurrence.test.ts` — 14 tests

Web-only (no Dart twin — mobile does not read `event_exceptions` outside its own event-detail screen). Pure tests for `lib/social/event_occurrence.ts`, the layer that subtracts cancelled occurrences from a recurrence expansion. `isOccurrenceCancelled` covers both ISO renderings of one instant matching (PostgREST `+00:00` vs a client `.000Z`), a different instant / empty list / null / undefined not matching, and an unparseable cancelled instant never matching. `nextLiveInstance` covers the nothing-cancelled fast path, skipping the cancelled next occurrence, skipping a run of consecutive cancellations, a cancellation further out leaving the next one alone, already-past cancellations not eating the search budget, every remaining occurrence cancelled returning null, an exhausted series returning null either way, and a cancelled one-off. `upcomingCancelledOccurrences` covers future-only + oldest-first ordering, an unparseable instant being dropped rather than sorted to an edge, and an occurrence starting exactly now counting as ahead.

### `apps/web/src/lib/training/goals.test.ts` — 30 tests

Mirror of `apps/mobile_android/test/goals_test.dart`. Pure tests for `lib/goals.ts`. `periodStart` / `periodEnd` cover Monday-default + Sunday-override week anchoring, month start = 1st, week end = start + 7 days, December → January wrap. `formatPaceSecPerKm` covers em-dash for non-positive / non-finite, m:ss/km formatting with zero-padded seconds, half-up rounding. `evaluateGoal` covers empty list = 0%, runs outside the period excluded, distance target accumulation + complete-on-hit, pace target excluding cycling rides from the distance-weighted average, pace target with no qualifying runs reporting 0% + em-dash currentLabel, lower-is-better partial progress, time + runCount targets, multi-target complete-only-when-every-hit, `overallPercent` as the mean of target percents, and zero / negative targets being filtered out of the targets list. `newGoalId` covers uniqueness across 100 calls. `loadGoals` / `saveGoals` cover empty when no data, save / load round-trip preservation, per-user keying isolating two users on the same browser, null userId returns empty, the legacy unscoped-key migration on first load (with the legacy key removed afterwards), accepting both legacy camelCase and canonical snake_case wire shapes, and corrupt-JSON returning empty.

### `apps/web/src/lib/training/fitness.test.ts` — 48 tests

Mirror of `apps/mobile_android/test/fitness_test.dart`. Pure tests for `lib/fitness.ts`. `qualifyingRuns` covers sub-1.5km / sub-5min drop (floor lowered from 3 km so comeback runners rebuilding at 1.5-2 km/run still get a fitness signal — persona round-5), a sustained 1.5-2 km comeback run admitted, every recognised `source` accepted plus a non-recognised value rejected. `vdotFromRun` covers sub-1km / sub-2min returning null, ~50 for a 20-min 5k, ~54 for a 3-hour marathon, faster pace → higher VDOT. `currentVdot` covers picking the best in-window qualifying run and ignoring runs older than 90 days. `vo2MaxFromVdot` is identity passthrough. `thresholdPaceSecPerKmFromVdot` covers null in / null out, VDOT 50 in the 240-260 s/km band, and higher VDOT yielding a faster threshold (catches the formula bug fixed during this pass — see [decisions.md § 54](../architecture/decisions.md#54-fix-thresholdpacesecperkmfromvdot-formula)). `runTss` covers the sub-100m / sub-30s / zero-threshold returning 0, threshold pace = 100 TSS at 1 hour (Coggan reference), and faster-than-threshold raising TSS faster than linearly. `trainingLoad` covers null inputs / no qualifying runs all-null, non-null curves with at least one qualifying run, TSB rises during a 14-day taper. `computeSnapshot` covers the rollup contract + empty input. `recoveryAdvice` covers null inputs, sub-10 CTL → consistency-building advice, and the five-band TSB ladder producing five distinct strings.

### `apps/web/src/lib/coach/types.test.ts` — 4 tests

Smoke tests for the coach config / tier shape. `emptyUsage` returns a fresh zeroed object every call (no shared reference; mutation doesn't leak across calls). `TIER_LIMITS.free` keeps a finite daily cap so anonymous abuse can't drain quota. `TIER_LIMITS.pro` carries a finite daily cap that's strictly higher than free's, with larger token + runs windows. Anchors the paywall contract — flipping any of these silently would change rate-limit behaviour without code review.

### `apps/web/src/lib/coach/context.test.ts` — 20 tests

Source-grep guards + pure-helper behaviour for the coach context builder. Pins the audit-compliance invariants in source (subscription_tier never projected; DOB/HR gated on `health_data_consent_at`; runner_context never emits known secret names; the `food_log` nutrition query lives inside the `if (healthConsentGranted)` block — Art 9). Behavioural tests cover the two Tier-1 multi-modal summary helpers: `summarizeRecentLifts` (rolls gym sets into per-session summaries, ignores bodyweight sets in volume, caps at `COACH_LIFTS_CAP`) and `summarizeNutrition` (7-day daily averages over days logged, drops out-of-window rows, null on empty, null per-macro when no row carries it).

### AI-disclosure consent — `apps/web/src/lib/core/ai_disclosure.test.ts` (16) · `apps/mobile_android/test/ai_disclosure_test.dart` (11) · `apps/mobile_android/test/ai_disclosure_consent_test.dart` (5 widget)

The versioned AI-processing consent record (decisions § 571 + § 573). The web suite covers the pure grading plus the server-side `gateAiDisclosure`; the Dart file mirrors the client half test-for-test — a v1 Coach acceptance grading `stale` against the route-AI rung, either half of a half-written record denying as `missing`, a version outside the build's ladder denying as `unknown` rather than as more-than-enough, and a parse of the migration that fails the build if `kAiDisclosureCurrentVersion` drifts from `ai_disclosure_current_version()` in SQL. `ai_disclosure_consent_test.dart` drives the mobile surfaces: Settings → Account offers the disclosure whenever the record is not current (and only then), accepting records the **current** version and takes the server's returned record, a refused write leaves the dialog open and the record untouched (§ 560), withdrawal clears it and re-offers, and the Coach gate opens for a v1 holder without re-prompting. The iOS twin runs both files byte-for-byte.

### `apps/web/src/lib/gym/lift_load.test.ts` — 3 tests

Pure bridge from the gym data layer (`GymSetWithDate` rows) to the training-load model input (`LiftForLoad`). `liftsFromSetHistory` groups flat set rows by workout, drops rows with no workout date (can't land on a calendar day), and an integration test confirms grouped lifts raise the fitness/fatigue/form curve while the run-only series stays recoverable (separability).

### `apps/web/src/lib/nutrition/nutrition_targets.test.ts` — 19 tests

Pure tests for the Mifflin-St Jeor nutrition target engine (`nutrition_targets.ts`, TS↔Dart parity pair with `apps/mobile_android/lib/nutrition_targets.dart` — equal counts). `mifflinStJeorBmr` (+5 male / −161 female / −78 neutral offset), `computeNutritionTargets` (moderate activity factor, protein 1.8 g/kg, fat 30%, carbs fill the remainder, goal delta, sedentary<very_active, the 1200 kcal floor, null on missing/non-physical metrics), `ageFromDob` (whole-year age decremented before the birthday, null on malformed/out-of-range), and the activity-level factor ordering.

### `apps/web/src/lib/nutrition/food_search.test.ts` — 40 tests

Pure tests for the Open Food Facts client (`food_search.ts`, injectable-fetcher seam; Dart twin `food_search_test.dart`). `parseOffSearch` maps products + drops nameless/calorie-less ones + keeps the first brand, tolerates string-typed nutriments, returns `[]` on malformed input; `scalePortion` scales per-100g to a gram portion (rounded, 0 g → 0); `searchFoods` skips the fetcher on an empty query, parses a canned response, **throws on a non-OK response and propagates a network throw** (so the caller can show a retry state instead of a misleading empty), and treats valid-but-empty JSON as genuinely empty (`[]`). The failure-vs-empty UI split is e2e-pinned in `nutrition.spec.ts`.

### `apps/web/src/lib/nutrition/nutrition_totals.test.ts` — 6 tests

Pure tests for the daily nutrition aggregation (`nutrition_totals.ts`; Dart twin `nutrition_totals_test.dart`). `sumMacros` sums fields treating null as zero (zeros for an empty day); `groupByMealSlot` orders slots and omits empty ones (null slot folds into snack); `ringFraction` clamps to [0,1] and returns null on a missing/zero target.

### Mobile nutrition tests (Dart) — `apps/mobile_android/test/food_search_test.dart` (41) · `nutrition_totals_test.dart` (4) · `nutrition_targets_test.dart` (19, mirror) · `nutrition_screen_test.dart` (25 widget) · `nutrition_log_sheet_test.dart` (11 widget)

Dart twins of the web nutrition pure logic (equal counts) plus the mobile-only screen/widget coverage: `nutrition_screen_test.dart` (empty state with rings + water cards, a logged meal under its slot with calories, water increment via the `SharedPreferences` mock) and `nutrition_log_sheet_test.dart` (manual entry logs to the store, Open Food Facts results render via the injected fetcher). The iOS twin runs the same files byte-for-byte.
### `apps/web/src/lib/runs/age_grade.test.ts` — 12 tests

Pure tests for the age-grade helper (`age_grade.ts`, TS↔Dart parity pair with `apps/mobile_android/lib/age_grade.dart` — equal counts; Dart twin `age_grade_test.dart`). `matchStandardDistance` (exact + nearest-match disambiguation of 8 km vs 5 mile, GPS over-read within the ±2 % tolerance, out-of-tolerance + non-positive → null, marathon over-read), `ageOnDate` (year decremented before the birthday, counts on the day, null on malformed input), `computeAgeGrade` (100 % at the open standard in the 1.0-factor band, 50 % at double the standard, masters male 10k + female 5k hand-computed against the embedded 2025 factors, null outside the 5–99 / standard-distance / positive-duration / binary-sex domain), `ageGradeForRun` end-to-end from DOB + run start + sex with `formatAgeGradePercent`. Numerics are anchored to the embedded USATF-MLDR 2025 factor values. The iOS twin runs the same file byte-for-byte.

### `apps/web/src/lib/coach/limits.test.ts` — 41 tests

Pure tests for the validation / clamping helpers extracted from `coach/handler.ts` so they can run under `tsx --test` without booting `createClient`. `parseAuthHeader` covers `Bearer ` prefix stripping (case-insensitive on the prefix), null / undefined / empty input, bare `Bearer ` returning null, and tokens-without-prefix being passed through verbatim. `clampRunsLimit` covers undefined / null returning the default, non-finite (NaN, Infinity, non-numeric strings) returning the default rather than the tier cap, the tier max ceilings (free=30, pro=75), the floor at 1 (zero-runs context is never useful), fractional input being truncated, string-typed integer coercion, and pro tier honouring larger requests up to its cap. `jsonError` covers the canonical pre-stream response shape, extra fields landing alongside `error`, and the spread-order behaviour where `extra.error` wins over the literal. `rateLimitHeaders` covers the free-tier finite limit / remaining, remaining clamping to 0 when usage exceeds the cap, the pro-tier finite cap (10/day) reporting correctly, and pro remaining clamping to 0 when usage exceeds the pro cap. `personalityAddendum` covers the `drill_sergeant` and `analytical` tone overrides + the empty-string default for null / undefined / unknown styles.

### `apps/web/src/lib/settings/settings_overlay.test.ts` — 15 tests

Pure tests for the universal + per-device prefs overlay helper extracted from `settings.ts` so it can run under `tsx --test` without dragging in the SvelteKit `$env/static/public` virtual import. `effective<T>` covers the fallback path when neither bag has the key, universal-wins-over-fallback, device-overrides-universal, device-null fall-through to universal (null is treated as "missing", not "unset to nothing"), device-undefined fall-through, universal-null-with-no-device fallback, falsy-but-concrete values (0, '', false) winning over fallback, object / array values round-tripping, and the type-parameter being a viewer-side hint with no runtime cast.

### `apps/web/src/lib/watch_payload_fixture.test.ts` — 6 tests

Cross-platform contract test against `fixtures/watch_run_payload.json`. The same fixture is decoded by `apps/mobile_android/test/watch_payload_fixture_test.dart`, its `mobile_ios` mirror, and the Wear OS Kotlin test (`apps/watch_wear/.../WatchRunPayloadFixtureTest.kt`). Editing the fixture without updating all three platform tests is a deliberate hard-fail. Web's slice asserts: source parses to a valid `RunSource`, `metadata.activity_type` is a registered value, `avg_bpm` is positive, laps use the canonical 1-based `index` + cumulative-BEFORE `start_offset_s` shape with deltas accumulating correctly, and the row + payload sources agree.

### `apps/web/src/lib/i18n/*.test.ts` — 117 tests across 14 files

Run with `npx tsx --test 'src/lib/i18n/*.test.ts'` from `apps/web`. The headline is the DECLARATION sum `grep -cE` reports and is what `check_test_inventory_counts.mjs` re-derives; the per-suite figures below are RUNTIME counts, because four of these suites loop over `SUPPORTED_LOCALES` and declare one `test(` where the runner reports seven. The web i18n runtime (decisions §108) plus its declaration-site guards. **Seven locales ship** — `en, de, fr, es, ja, pt-BR, pt-PT` — and four of these suites are parameterised over `SUPPORTED_LOCALES`, so a new locale adds tests rather than needing them written: `messages_parity.test.ts` (7 — one per locale: the catalogue loads, carries exactly `en.ts`'s key set with no empty values, and keeps every `{placeholder}`), `rate_limit_message.test.ts` (23 — six `en` cases pinning the exact sentences, two per locale, plus three that derive the bucket set from the `enforce_create_rate_limit` call sites in the migrations: every throttled bucket must name its own act rather than degrade to `rateLimit.generic`, the suite's own bucket list must be the SQL's, and no `BUCKET_KEY` entry may name a bucket that has stopped being throttled), and `error_framing.test.ts` (8) + `nutrition_add_failed.test.ts` (9), one case per locale each that the framed-error keys exist, are translated, and keep the `{error}` slot. `locale.test.ts` (9) covers pure negotiation — q-weight ordering, exact-then-base resolution, and that **both** Portuguese catalogues are reachable by their own tag. `locale_reach.test.ts` (20) holds every site that names the locale set to `SUPPORTED_LOCALES`: a catalogue file + `LOCALE_LABELS` entry + `CATALOGUE_LOADERS` loader for exactly the supported set, the Settings language picker derived rather than listed, every localized Learn guide suffix a locale we ship, every base language reaching a locale unless `BASE_FALLBACK_EXEMPT` records why (its one entry is `pt-BR` — `BASE_TO_LOCALE.pt` points at `pt-PT`, so Brazilian is reached by its exact tag, which is the tag every browser and both phone platforms actually send), and a source scan that fails any file spelling the locale set out instead of deriving it, with a matcher fixture so the scan cannot silently stop matching. It also carries the **Portuguese-variant** guards that grew with the derived pt-PT catalogue, none of which any other locale needs: that neither catalogue reads as the variant it is not (`BRAZILIAN_ONLY` / `EUROPEAN_ONLY` word lists, with `VARIANT_SENSE_EXEMPT` naming the keys where a word carries its other sense), that a sense-split word survives only where that sense was recorded, that the wrist and watch pt-PT catalogues read as European too, that **both** catalogues address the reader in one register (tu markers, enclitic, proclitic and preterite — both, because a tu marker in the reference makes the derived scan blind, decisions §784), that pt-PT uses no tu imperative its Brazilian twin does not (derived by stem, not listed), that a pt-PT fragment keeps the edge whitespace its Brazilian twin assembles with, that a gender-flipped European noun agrees with the determiner governing it, and — added 2026-09-01 ([decisions § 873](../architecture/decisions.md)) — that **no catalogue value opens with a capital where another value interpolates it mid-sentence**, scanned out of source (`m('outer', { slot: m('inner') })`, brace-matched, `??`-fallback shape included) and measured **cross-locale** rather than pt-PT-against-pt-BR, with `INTERPOLATED_CAPITAL_EXEMPT` (3 entries — slots that normally hold a person's name, an event title, or a whole sentence), German excluded because it capitalises every common noun, a matcher fixture over five sources, and and a liveness test that drops an exemption covering nothing. `interpolate.test.ts` (20) covers `{var}` substitution plus the inline `{n, plural, one {…} other {…}}` CLDR selection. `enum_vocabulary.test.ts` (6), `destination_names.test.ts` (2) and `notification_phrasing.test.ts` (3) are the §547 / §572 naming guards — each loops every locale internally, so its count does not move when a locale ships.

### `apps/web/src/lib/i18n/catalogues.test.ts` — 11 tests

Which catalogue each shipped locale actually reaches. `messages_parity.test.ts` loads every locale through `CATALOGUE_LOADERS` and checks the KEY SET, which two locales sharing one catalogue satisfy perfectly — planting `'pt-PT': () => import('./locales/pt-BR')` leaves that suite green while a Lisbon reader is answered in Brazilian, the exact divergence the European catalogue was added to close ([decisions § 755](../architecture/decisions.md), § 848). Pinned four ways: module identity (ESM caches the namespace, so the loader's object is the direct import's object only when the path is right), no two locales resolving one catalogue, the lexical split the two Portuguese catalogues exist over (`shell.skipToMain` is `Pular` in Brazil and `Saltar` in Portugal; `prefs.kicker` is `Configurações` vs `Definições`, with a >100-string floor on how much else differs), and a source row per loader.

### `apps/web/src/lib/backup/shortfall.test.ts` — 10 tests

What `/settings/account` may say about a backup that came up short ([decisions § 845](../architecture/decisions.md)). `buildBackupZip` merges the writer's own shortfall (a track blob that would not download) with the caller's (a row read that died half-way, § 675/§ 676) into one `incomplete` list, and the page read only the blob counts off it — so an archive short of two thousand runs whose tracks all downloaded rendered "missing 0 of 0 GPS tracks". Covers: a whole archive discloses nothing; a tracks-only shortfall states the count and names no section; a short `runs` or `routes` read is disclosed with the section named and NO track sentence; both kinds together; dedupe + sort; `tracks` named with no count to state falls back to being listed rather than disclosed as silence; a table-driven case that every shortfall earns at least one sentence; nonsense counts clamp; and a source guard that the page routes through the grader and both message keys stay reachable.

### `apps/web/src/lib/backup/backup.test.ts` — 15 tests

The streaming + parallel-download writer and its paged row reads (was 14). The added case is a source guard on `createBackup`, which needs supabase-js and cannot be executed here: every `supabase` read behind the archive must bind its `error`, and the graded errors must reach `incompleteSections`. § 675/§ 676 paged and flagged the runs + routes reads and left the `get_my_profile` RPC and the `user_settings` read discarding theirs, so a failed read shipped a null profile and an empty prefs bag under a manifest still claiming `complete: true`.

### `apps/web/src/lib/backup/cloud_export_transport.test.ts` — 9 tests

Which rail an export request takes and what it may assume about the answer. `cloud_export_helpers.test.ts` covers every pure piece `cloud_export.ts` composes; nothing covered the composition, which is where [§ 717](../architecture/decisions.md) and § 724 live. Pins that the deleted synchronous `POST /v1/export` has neither a builder nor a caller (a call site reaching for it again is a production 404 nothing here would see), that the two hub URLs are distinct, that all three declared export formats build a body (`backup` was never built before), that both hub calls resolve a session first, that an unconfigured hub answers `none` rather than throwing on a status read that runs on mount, that a 429 carries the `retry-after` it was given, that the enqueue answer is normalised rather than cast — a cast lets an unrecognised status poll for ever — and, since [§ 983](../architecture/decisions.md), that nothing a server said reaches the caller as a message: every throw out of the module is a `CloudExportError` carrying one of exactly three codes, and `edgeFunctionExport` unwraps the envelope instead of rethrowing supabase-js's fixed "Edge Function returned a non-2xx status code", which the failure toast used to interpolate verbatim.

### `apps/web/src/lib/runs/weigh_in_flag.test.ts` — 4 tests

The Art 9 weigh-in gate and the surface it gates ([decisions § 150](../architecture/decisions.md)). `core/env_flag.test.ts` walks every `*_flag.ts` and pins the parse, so the fail-closed default was covered; whether body weight, the medical-hold flag and the organiser consent action are UNREACHABLE with `PUBLIC_WEIGH_IN_ENABLED` off was covered by nothing. Resolves Svelte `{#if}` / `{:else}` / `{#each}` block nesting rather than searching for substrings, so an affordance two `{#each}` levels inside the guard reads as guarded and one moved out of it does not; carries must-flag / must-spare fixtures so a scanner that stopped matching the template cannot pass by finding nothing. Also pins that `saveWeighIn` refuses before the consent tick and that the refusal precedes the upsert carrying `p_health_consent`.

### `apps/web/src/lib/integrations/strava_surface_guard.test.ts` — 4 tests

What the Strava OAuth + sync call sites may do with a response ([decisions § 766](../architecture/decisions.md), § 846). `strava.ts` imports `$env` and supabase-js and cannot be executed here, and the defect being guarded — `data as StravaSyncResult` in place of the parser — compiles silently. Pins: both `strava-import` responses graded rather than cast; `syncStrava`'s default is `STRAVA_LOOKBACK_DEFAULT_DAYS` rather than a fourth declaration of a bound the module calls one contract across three rails; the OAuth state is consumed, compared and THROWN on before the code is exchanged (RFC 6749 § 10.12 — a check after the exchange has already linked the victim's session to the attacker's account); and both import paths record the truncation past the toast, not just the sync one.

### `apps/web/src/lib/integrations/strava_zip_strictness.test.ts` — 5 tests

The Strava ZIP importer's promise-keeping at the call site. `strava_track_member.test.ts` pins every refusal `resolveStravaTrackMember` makes and none of it binds `strava-zip.ts`, which imports supabase-js. The defect [§ 676](../architecture/decisions.md) fixed was a `try {} catch (_) {}` around the two parsers, so an unreadable member imported as a summary-only run that reads as complete and is never re-imported; re-adding one compiles and reads as defensive. Pins the resolver routing, no `catch` (statement or promise-level) in the track block, the ONE deliberate leniency (a failed inflate falls through to a trackless import rather than returning early past `saveRun` — the phantom-import bug), and that a refused row increments `failed` and reaches `ImportFailureReport`. Comments are stripped before every scan, or the prose naming the refused shapes satisfies the guards by itself. Also pins that the required-column check refuses a header naming no activity type ([§ 979](../architecture/decisions.md)) — `indexHeader` answers -1 and `row[-1]` is `undefined`, so a fall-through imported a migrant's rides, swims and yoga as runs and counted them as imported.

### `apps/web/src/lib/segments/effort_rank.test.ts` — 19 tests

The segment-effort standing (was 13). Six added cases cover the coercion hole [§ 847](../architecture/decisions.md) closed: a boolean, a single-element array or any other non-numeric in the `rank` position must be dropped rather than coerced (`Number(true)` and `Number([1])` are both `1`, which is the gold crown); a numeric string is still a real answer because PostgREST serves a `bigint` count as one; a fraction is no answer, since the RPC returns `1 + count(...)`; a rank below 1 is no answer and 1 remains the floor; a repeated `effort_id` keeps the last row; and an unusable rank does not evict a usable one for another effort.

### `apps/web/src/lib/social/challenge_goal.test.ts` — 20 tests

The stored-goal contract (was 16). Four added cases read the SQL rail the pair claims to mirror — `challenges_goal_ck`'s own comment says "Mirrored client-side by `checkChallengeGoal` / `maxStreakDaysInWindow` on both platforms" and nothing read it. The migration's strict `> 0` floor, the fact that only `streak_days` is window-bounded on both rails, and the window ceiling DERIVED from the migration text (`floor(epoch / 86400) + 1`, inclusive) and evaluated against the client over a spread of windows rather than restated beside it. Planting `+ 0` in the migration fails by name.

### `apps/web/src/lib/social/notification_link.test.ts` — 16 tests

The notification → deep-link routing (was 13). `row.kind` is typed `string` so the module stays free of a runtime import from `core/data.ts`, which also means `tsc` gives no exhaustiveness and the module is not a registered rail for `notifications.kind` in `check_constraint_unions.mjs`. Three added cases parse the live kind set from the last migration that re-adds `notifications_kind_check` and assert every value is routed by an explicit `case` rather than the `default` arm, that every routed kind reaches a destination when given its ids, and that the `DELIBERATELY_UNLINKED` register (its one entry is `content_hidden`) does not name a kind the column has dropped.

### `apps/web/src/lib/social/feed_merge.test.ts` — 15 tests

The chunked following-feed reads (was 12). Three added cases: `FEED_FOLLOWEE_CHUNK` and `packages/api_client/lib/src/chunk.dart`'s `kInFilterChunk` each name the other as a mirror in their own docs and nothing compared them — the pair is in neither the parity-pair registry nor `check_shared_constants.mjs`, so bumping one alone is a silent split and the platform that went too high loses whole reads on a gateway that answers 200 with an empty match ([decisions § 653](../architecture/decisions.md)). Plus the negative-limit clamp (`slice(0, -1)` drops the last row and returns the rest) and the documented later-chunk-wins fold, which every other case cannot see because it merges disjoint ids.

### `apps/web/src/lib/track_preview_mount_guard.test.ts` — 7 tests · `live_region_mount_guard.test.ts` — 3 tests

Both gained a non-vacuity control (was 5 and 2). Each guard reports an empty offender list when it works AND when it sees nothing at all, and only the matcher half had fixtures: a walk that reaches no file, an `aria-live` filter that stops matching the app's own markup, or a `<TrackPreview` matcher that stops seeing a mount each turns the guard into a green check over an unscanned tree ([§ 762](../architecture/decisions.md)'s rule, applied to two guards that predate it). The `TrackPreview` control is a POSITIVE one taken off the real permitted wrappers rather than a fixture, so it cannot drift away from what it checks.

### `apps/watch_wear/android/app/src/test/kotlin/**/*Test.kt` — 747 Wear OS Kotlin/JUnit tests across 73 files

Run with `cd apps/watch_wear/android && ./gradlew testDebugUnitTest`. Pure-JVM tests — no Android instrumentation, no Robolectric. **Six of them read files outside this Gradle build** (the phone's two `Wear*Bridge.kt`, `apps/web/src/lib/core/env_flag.ts`, `docs/backend/metadata.md`, the `activity_type` migration and the two client label catalogues), plus the manifest, and none was a declared input of the test task until [decisions § 946](../architecture/decisions.md) — so a local run reported UP-TO-DATE and SUCCESSFUL on exactly the drift those guards exist to catch. They are declared now; if you add a guard that reads anything outside `app/src`, add it to `guardedCrossTreeFiles` / `guardedCrossTreeSets` in `app/build.gradle.kts` in the same change or it will not re-run when its subject changes. `ScreenWiringTest` also now pins the pre-run signed-out notice ([decisions § 948](../architecture/decisions.md)): the `!authed` branch renders `not_signed_in` and NOT `offline`, read branch-scoped so the sibling `!online && authed` branch a few lines above cannot satisfy it — two conditions sharing one string breaks nothing, so only an assertion about which branch says which can see it. The team deliberately avoided UI-test infrastructure (see `apps/watch_wear/CLAUDE.md`'s "layouts can't be unit-tested without Robolectric"); the pattern is to extract pure helpers from the Android-bound classes and exercise them at the JVM level.

**Sync / auth coverage (~95 tests)** — the highest-impact surface. `DrainQueueLoopTest.kt` (18) covers the offline-runs drain orchestrator extracted from `RunViewModel.drainQueue`: per-error-class branches (skip / stop / refresh-and-retry), the one-shot 401 refresh-then-retry, partial-failure mid-loop, transient-vs-permanent backoff arming, side-effect ordering, the 409-is-a-permanent-skip-not-a-drop guard (issue #404). `DrainBackoffTest.kt` (7) — exponential backoff math. `SupabaseErrorClassificationTest.kt` (19) — error → `DrainAction` mapping, the post-stop "unauthorized" regression guard. `StoredSessionTest.kt` (10) — auth session cache + `isExpired` math. `SessionBridgeTest.kt` (13) — Data Layer auth handover from the paired phone: the sealed-event shape, the dual TYPE_CHANGED / TYPE_DELETED listener, and the receive-side grading ([decisions § 879](../architecture/decisions.md)). The grading half is pure — `DataMap` is a Play Services type no host JVM can build, so `SessionPayload.fromFields(String?, …, Long)` takes the five load-bearing strings directly and each is refused null, empty and whitespace-only, with a zero expiry pinned as NOT a refusal (the `StoredSession.isExpired` contract) and a source guard that both call sites route through the adapter and that no `?: ""` coercion survives. `DataLayerContractTest.kt` (5) reads BOTH rails of both Wearable Data Layer contracts — the phone's `WearAuthBridge.kt` / `WearRoutesBridge.kt` against the watch's `SessionBridge.kt` / `RoutesBridge.kt` — and compares the `PATH` constants and the `DataMap` key sets symmetrically, replacing a hardcoded literal under a comment telling the other rail what to do ([§ 883](../architecture/decisions.md)); a vacuity case comes first because set equality is satisfied by two empty sets. `RoutesBridgeJsonTest.kt` + sibling fixtures (68 tests across 5 classes) — pure-JVM coverage of every load-bearing piece of the phone→watch route push pipeline. The Wearable DataLayer listener itself can't run on a host JVM, so the testable seam is the JSON contract + the pure-logic gates that surround it. Five classes:

  - **`RoutesBridgeJsonTest`** (17 tests) — `parseRoutesJson` contract. Baseline 9 tests (empty array, malformed JSON, single-route round-trip, <2 waypoint drop, missing id/waypoints drop, name + distance fallbacks, individual malformed waypoint drops, multi-route order) plus 8 hardening tests (forward-compat — extra top-level fields ignored; Unicode in name + id round-trips; 500-route payload under 500 ms; duplicate ids preserved for caller dedupe; string-coerced numerics accepted; truly-garbage non-numeric values drop the waypoint and route; negative + extreme coordinates pass through; top-level non-array yields empty list).
  - **`RoutesPushApplyTest`** (17 tests) — pure-logic guards over `shouldApplyRoutesPush` + `sortRoutesByRecency`. Stale-push protection (first push applied when no prior; strictly-newer wins; equal-timestamp re-delivery rejected; older delivery rejected; negative/zero treated as one-shot but doesn't override later real-stamp; monotonic sequence). Recents re-ordering (empty recents preserves order; recent floats to front; multiple recents preserve LRU order; unknown id silently skipped; empty input; idempotent; output length matches input; output contains exactly same id set; SavedRoute identity preserved; 100-route + 10-recent sort under 50 ms).
  - **`RoutesPushApplySequenceTest`** (10 tests) — composes the gate + the sort over realistic event sequences. Monotonic sequence applies every push; out-of-order push leaves earlier state intact; same-timestamp re-delivery is a no-op; empty push at newer timestamp clears the list; recents float matching ids to front of each push; recents that vanish from a subsequent push silently dropped; cold-start zero-timestamp push applied as one-shot; 100-push stress with alternating future/past timestamps; out-of-order delivery C-A-B applies only C; recents updated mid-sequence affects only later pushes.
  - **`RoutesPushTest`** (4 tests) — `RoutesPush` data class equality + the "no leak surface" guard (extra JSON top-level fields the phone never sends don't materialise into SavedRoute fields).
  - **`WearRoutesFixtureTest`** (13 tests) — cross-platform fixture parity + end-to-end pipeline. Reads `fixtures/wear_routes_payload.json` (also consumed by `apps/mobile_android/test/wear_routes_fixture_test.dart`). Baseline 7 tests pin the parser handles the canonical wire format, Unicode survives, both int + double distance encodings are tolerated, waypoint counts match, every parsed route has ≥2 waypoints, and the fixture's three contract keys (`input_routes`, `expected_payload_json`, `expected_parsed_routes`) stay in lockstep. Plus 6 pipeline tests that compose `parseRoutesJson` + `shouldApplyRoutesPush` + `sortRoutesByRecency` over the fixture wire — full apply sequence, Unicode preservation end-to-end, two-push stale-gate sequence with the fixture as the newer payload, empty wire payload tolerated, byte-identical re-delivery is parser-safe, narrow SavedRoute shape pins (no leak surface for user_id / clubId / isStarred from a future encoder bloat).
  - **`RoutesBridgeWiringTest`** (13 tests) — source-grep guards on the production wiring. `RunViewModel` calls `observeRoutesBridge` in `init`; constructs a `RoutesBridge(application)`; the observer uses BOTH `current()` (cold-start hydrate) and `events.collect` (live updates); consults `shouldApplyRoutesPush` AND tracks `lastAppliedRoutesPushMs` so the gate is effective; writes through `routeStore.save`. `RoutesBridge.kt` declares `/saved_routes` PATH, the two DataMap keys (`routes_json` + `updated_at_ms`), exposes `Flow<RoutesPush>` (not `Flow<List<SavedRoute>>`), and the helpers are file-level `internal`. RunViewModel.sortByRecency delegates to the file-level fn. No `.take(N)` truncation slips into the parser. `SupabaseUrlBuildersTest.kt` (13) — pinned URLs / bodies the watch sends (starred-first routes query + fallback, the `refresh_token`-only body, the mandatory `grant_type=refresh_token` query). `SaveRunRowMapTest.kt` (10) — the `runs.insert` row map every saveRun POSTs (column set, `source="watch"`, `external_id = runId` for retry idempotency, is_public omit-vs-set semantics). `EncodeJsonMapTest.kt` (18) — the hand-rolled JSON encoder every POST flows through (string escaping, null handling, numeric type preservation, `JsonObject` no-double-quoting). `QueuedRunSerializationTest.kt` (10) — the DataStore wire format for offline-queued runs (the V1 → V2 shape contract).
  - **`PostRunDiscardConfirmTest`** (3 tests) — the armed-confirm gate on the post-run Discard. One tap on a 52 dp `x` used to destroy an unsynced run outright; the arm replaces the bottom cluster with a labelled `Discard?` chip and moves the commit target bottom-END to bottom-CENTRE, so a fat-finger double tap lands on empty space (decisions § 1253).

**Recording / GPS / sensors (~110 tests)** — `RouteMathTest.kt` (17) — off-route distance + remaining-km math, `ElapsedMathTest.kt` (8) — pause/resume elapsed time, `StreaksTest.kt` (16) — streak math, `MercatorTilesTest.kt` (13) — Web Mercator + tile coords, `TrackOverlayBufferTest.kt` (7) — rolling buffer geometric halving, `TrackWriterTest.kt` (9) — streaming GPS to disk, `RecordingRepositoryTest.kt` (10) — process-singleton StateFlow, `CheckpointSerializationTest.kt` (9) — crash-recovery snapshot, `CheckpointRecoveryTest.kt` (9) + `CheckpointRecoveryWiringTest.kt` (5) — the grading that stands between a surviving checkpoint and the "Recover unsaved run?" prompt (already-queued and track-file-gone both mean the run is captured somewhere strictly better, so recovering would upsert a stale summary over the finished row; a live recording's checkpoint is ignored rather than cleared) plus the seal that refuses to stub a missing track into `[]` and blank Storage, and the source-grep guards that the ViewModel grades on both entry points and re-grades on accept (`decisions.md § 590`), `PaceAlertTest.kt` (14) — the rate-limited pace-drift trigger (30 s/km drift + 30 s rate-limit, the no-fire-preserves-timestamp regression guard), `FinishedLapsBuilderTest.kt` (10) — per-lap split vs cumulative math + the bonus-row gate, `HeartRateMonitorTest.kt` (18) — BPM validity gate + the Health Services value cascade, `GpsRetryDecisionTest.kt` (11) — the 30 s mid-run-silent self-heal trigger including the load-bearing "initial cold-acquire is NOT a stall" guard, `PedometerMathTest.kt` (10) — step-counter baseline subtraction.

**Untrusted-input parsers (~25 tests)** — `ParseRouteWaypointsTest.kt` (22) covers the cross-process route-waypoints parser (Intent extra from another process — fail-quiet contract: null / malformed / wrong-shape / partial all return empty list, never crash). `SavedRouteTest.kt` (9) — route deserialization.

**UX / phrasing (~38 tests)** — `TtsPhrasesTest.kt` (13) — pinned voice-cue dialect matching `apps/mobile_android/lib/audio_cues.dart` (integer-truncated pace in either unit via `paceMinSecFor`, the km→mi spoken-distance conversion, decimal-separator locale-independence, the runner's-muscle-memory `Run started` constant). The split *cadence* lives in `UnitFormatTest.kt` (`completedSplits` — a mi runner is cued once per mile, pinned by walking a 5 K a metre at a time and counting 5 km cues vs 3 mile cues), and `TtsSplitUnitWiringTest.kt` (4) is the source-grep guard that the service feeds `preferredUnit` into both the trigger and the phrase and that no unit-less `tts_*` resource survives — the announcer's `Resources` lookup needs Robolectric, which this module deliberately doesn't carry (`decisions.md § 467`). `ActiveRunTileFormattersTest.kt` (7) — tile formatters. `UniversalSettingsTest.kt` (30) — settings overlay including HR zone resolution precedence (`hrZones > maxHrBpm * %s > Tanaka 208 − 0.7×age > null`). `WatchRunMetadataTest.kt` (12) — `buildRunMetadata` JSON shape.

**Localization guards (21 tests)** — `L10nResourceParityTest.kt` (5) asserts every translated `values-*/strings.xml` declares exactly the default key set with no empty values, matching positional format args, and apostrophes escaped the way aapt needs. `ActivityTypeVocabularyTest.kt` (6) asserts the activity words equal the phone ARB's and the web catalogue's locale for locale, over the seven locales the wrist ships (`en/de/fr/es/ja/pt-BR/pt-PT`), and pins the phone catalogues the wrist does not mirror — `unmirroredPhoneCatalogues` is `emptySet()` since European Portuguese landed, checked in both directions so an unmirrored phone locale and a stale exemption each fail. `StringResourceContractTest.kt` (4) asks whether the default set is the RIGHT set, one level below the parity guard: every key carrying a `km` path segment must have the `mi` key that swapping that segment names and vice versa (segment-wise, because the unit is not always the last word — `distance_km_to_go`), both halves of a pair must be referenced from source (a pair that exists and is half-wired is indistinguishable from the bug at the resource level), and no key may be translated into seven catalogues and named by no call site. It found both directions at once: `distance_km_recorded` had no mile sibling, so the crash-recovery prompt told a miles runner "6.44 km recorded"; and `tile_stat_row` / `pace_placeholder` / `pace_per_km_compact` were 21 dead entries translators maintained, two of them hardcoding `/km` ([§ 882](../architecture/decisions.md)). `LocaleReachTest.kt` (7) + `WearLocalesTest.kt` (3) are the declaration-site guards (`decisions.md § 748`): `WearLocales` reads the resource directory and every site that names the locale set — `locales_config.xml`, the manifest's `localeConfig` reference, both test-side lists — is derived from it or held to it, a `values-*` directory under an unrecognised qualifier is reported rather than skipped, and a build-script locale filter is refused. `src/main/res` and the build scripts are declared inputs of the test task in `app/build.gradle.kts`, without which a resource-only change leaves `testDebugUnitTest` UP-TO-DATE and green on exactly the change these guards exist to catch.

**Build + manifest guards (9 tests)** — `EnvFlagParityTest.kt` (4) holds the Gradle script's `envFlag` to the accepted-affirmative set it READS off `apps/web/src/lib/core/env_flag.ts`, rather than to a list restated in the test: the script matched `"true"` alone, and both flags it carries are negatives, so `DISABLE_HR=1` failed OPEN and left the emulator's synthetic heart rate in the runs table ([§ 880](../architecture/decisions.md)). `ManifestPermissionCoverageTest.kt` (5) DERIVES the runtime-request obligation from the manifest — every declared permission must be requested, be install-time, or carry a registered reason, and an exemption naming a permission the manifest no longer declares fails too — which is how `POST_NOTIFICATIONS` was found declared and never asked for ([§ 881](../architecture/decisions.md)); it also pins the service's `foregroundServiceType` against the `FOREGROUND_SERVICE_*` permissions the manifest claims. Both read `build.gradle.kts` and `AndroidManifest.xml`, which are declared inputs of the test task.

**Cross-platform + arch guards (~30 tests)** — `WatchRunPayloadFixtureTest.kt` (3) Kotlin slice of the `fixtures/watch_run_payload.json` contract pinned across Dart + TS + Kotlin (no Swift slice — see the watchOS gap above). `RaceSessionClientTest.kt` (7) — race ping + result client shape. `RouteMiniMapWiringTest.kt` (15) and `ScreenWiringTest.kt` (15) — source-grep arch guards on the data-flow + UI-wiring chains. Layouts can't be unit-tested without Robolectric, but the arch guards pin that key callbacks (`markLap`, `vm::resume`, `recoverCheckpoint`, `HoldToStopButton`) stay wired so a refactor can't silently drop them.

Pattern across all the test files: production-code extractions live in dedicated files (`DrainQueueLoop.kt`, `PaceAlert.kt`, `EncodeJsonMap` / `SupabaseUrlBuilders` at file-level in `SupabaseClient.kt`, etc.) and the wrapper methods on `RunViewModel`, `RunRecordingService`, `Pedometer`, `HeartRateMonitor` delegate to them. **Behaviour is preserved exactly** — the extractions are testability-only, not refactors.

Three source-level resilience guards were added on 2026-09-03 in the same idiom ([decisions §§ 1052-1055](../architecture/decisions.md)): `tiles/ActiveRunTileResilienceTest` (the tile nudge is wrapped, logs, and is the single door — 2 of its 3 claims die on the unguarded form), `ViewModelStreamResilienceTest` (every `\w+Bridge.events` stream and `store.queue` carries a `.catch`, derived from the source so a third bridge is covered automatically, plus no empty catch body anywhere in `RunViewModel`), and two new claims in `SensorStreamResilienceTest`. `HeartRateAvailabilityTest` is a real unit test rather than a source guard — `DataTypeAvailability` is a pure Kotlin value class that loads on the host JVM — and it fails when the SDK's own `VALUES` list grows past the five the mapping was written against.

The handful of Wear OS surfaces NOT covered (need instrumentation): `Pedometer` sensor binding itself, `HeartRateMonitor.MeasureCallback` registration with Health Services, `GpsRecorder` `FusedLocationProviderClient` callback, foreground-service lifecycle, Compose UI screen rendering (the team deliberately stayed off Robolectric — `ScreenWiringTest`'s source-grep approach is the cheap-but-effective alternative).

### `apps/job_worker/internal/**/*_test.go` — 842 tests across 78 files (Go unit tests)

Run with `go test ./...` from `apps/job_worker`. No network or Postgres dependency — the worker tests use a fake `Backend`, the matcher tests use `httptest.Server` to stand in for OSRM. Gated in CI by the `test-worker` job (`go vet` + `go test ./...`), so a Go-side guard like `internal/personal_data_export_guard_test.go` (the GDPR Art 20 export-completeness tripwire — fails the build when a new `user_id`-bearing table isn't wired into `exportPersonalDataSpecs` or the reasoned exclusion list) now fails a PR, not just a local run. Files:

- **`worker_test.go`** — table-driven coverage of the claim → handle → finish loop. Pins the transient/permanent classifier (`isTransient` branches on `HTTPError.StatusCode`, falls back to message sniffing for dial errors), the re-upload race (`TestWorker_ReuploadDuringMatchDiscardsResult` for the pre-write recheck path; `TestWorker_StaleSourceTrackURLDiscardsResult` for the `source_track_url` CAS path), the auto-link scoring policy (`TestWorker_AutoLinksWhenConfident` — must satisfy both endpoint-offset < 200 m AND |distance ratio| < 0.20 against `runs.distance_m`), and the **per-job HandleTimeout contract** (`TestWorker_HandleTimeoutDefersStuckJob` — synthetic stuck Storage download against a 50 ms HandleTimeout exits via `context.DeadlineExceeded` → `isTransient` → `defer_job`, never `finish_job`; pins the run-to-completion-OR-cancel guarantee documented in decisions.md § 58).
- **`matcher_test.go`** — pins `PassthroughMatcher` contract: input not aliased into output, empty in → nil out, stable algorithm/version strings.
- **`matcher_osrm_test.go`** — 16 tests covering `OSRMMatcher`: chunking (250 points → 3 calls, stitched), tail-of-1 passthrough, NoMatch translation (`code != "Ok"` → nil, downstream `'skipped'`), HTTP error surfacing (`*HTTPError` for 5xx), malformed-JSON wrapping, trailing-slash normalisation. The real engine isn't reachable from a unit test (multi-GB pre-extracted graph), so the tests stand up an `httptest.Server` that returns canned `/match` JSON.
- **`dataexport/runs_projection_test.go`** — 3 tests over the projection the Art 20 export builds each `runs` row from. Round 39 widened both transports to select the whole table and inverted the direction — each format now declares what it OMITS — so these are coverage claims rather than column lists: every field of the generated `runs` Row reaches the CSV, the backup JSON or a named omission, and an omission that no longer names a real column fails.
- **`export_run_row_test.go`** — 1 test pinning that the Go writer's run row carries every column the projection promises, so a column added to the table cannot reach the archive as an absent key.
- **`handler_export_blob_reap_test.go`** — 16 tests over the export-blob reaper: which blobs are eligible, that a job still running is never reaped, and that a delete failure is reported without stopping the sweep.

### `apps/job_worker/main_test.go` — 1 test

The first test in the worker's `main` package. Everything else under `apps/job_worker` lives in `internal/`, so the binary's own wiring — the flag parsing and the handler registration that decides which endpoints exist at all — had never been executed by a test. Round 39.

### `apps/job_worker/internal/personal_data_export_shape_guard_test.go` — 2 tests (10 subtests)

Structural guard for the GDPR Art 20 export spec, one level below `personal_data_export_guard_test.go`: that one asks whether every personal-data TABLE is in the spec, this one asks whether the entries it carries can actually run. Two failure modes, both silent. A projection or filter naming a column a migration renamed away makes PostgREST answer 400, and `StreamExportPersonalDataTables` deliberately TOLERATES a per-table read failure — so the section is recorded short rather than the export lost, and only a reader comparing the manifest to their own memory would notice. A dotted filter (`runs.user_id`, `events.host_user_id`) reaches through a parent table, and PostgREST applies it as a restriction only when the embed is `!inner`; a plain embed leaves the read returning every row in the table with a null embed, which on `run_kudos_received` is every kudos in the database inside one subject's archive. `exportSpecProblems` grades `(specs, replayed columns)` purely, so the rejection is pinned against deliberately broken specs — a missing filter column, a typo'd projection, an outer embed, an unknown table, a duplicate archive entry name — rather than only asserted about the shipped ones. The migration replay applies drops and renames, and the shipped-spec case fails if it stops finding a known column or starts reporting a dropped one.

### `apps/job_worker/internal/worker_dispatch_coverage_test.go` — 2 tests

`jobs_kind_chk` is the producer side of the queue and `dispatch` is the consumer side; they live in different files and nothing compared them. A kind the CHECK admits with no `case` is claimed, failed as an unknown kind, retried to exhaustion and lost — indistinguishable from an outage, and the user-visible effect is that an export or a safety alert simply never happens. A `case` for a kind the CHECK forbids is dead code nothing can enqueue. The forward direction DRIVES `dispatch` over every admitted kind rather than reading its source, with an unroutable kind as a negative control so the assertion is shown to discriminate before it is applied; the reverse reads the switch's labels (there is no way to enumerate them at run time) and a size comparison catches the duplicate `case` neither direction can see.

### `apps/job_worker/internal/email_render_arity_test.go` — 6 tests (3 subtests)

Every safety subject, heading and body paragraph is a format string, so are the four SMS variants and the four digest stat labels, and nothing compared any of them to the argument list the renderer supplies. `fmt.Sprintf` does not fail on a mismatch — it writes the mismatch into the output, so a translation missing one `%s` ships `%!(EXTRA string=…)` into the "is my runner OK" mail a safety contact opens. Rendered through the real functions across all seven locales and both arms of the `overdue` / `off_route` split, which pick different paragraphs with different argument counts. The `emailShared` completeness check is REFLECTIVE rather than a hand-written field list: the list the package had covered 6 of the 15 fields, so a blank `footerAccountDeleted` or `digestStatRuns` would have shipped unseen and a sixteenth field is covered the moment it exists. A closing case breaks a `de` catalogue entry three ways and an `fr` SMS variant once, and asserts each is caught.

### `apps/graph_cycle/internal/graph/preference_test.go` — 8 tests (3 added here)

`ParsePreference` reads the token a client sends and `String` writes the one the response reports back as `preferenceApplied`; two switches over one vocabulary, edited separately, and neither direction of a mismatch surfaces as an error — a token the parser does not know is accepted as `PrefNone` and silently dropped, and one only the writer knows names a preference no client can ask for again. `prefCost` is swept over all 256 attribution bytes rather than the three a fixture builds, because the soft-cost promise (no preference may disconnect the graph) is a claim about every attribution the packed byte can hold. `preferredShare` is exercised over the degenerate loops the search can hand it — nil, zero-length, non-adjacent, over-credited — and over an all-arterial loop, which is the discriminating half: without it the wholly-preferred case is satisfied by a function that returns 1 unconditionally. It found the unclamped cul-de-sac branch ([decisions § 849](../architecture/decisions.md)).

### `scripts/check_xcstrings_parity.test.mjs` — 10 tests

The watchOS String Catalog guard (`apps/watch_ios/scripts/check_xcstrings_parity.sh`) is the only thing between a half-declared locale and the App Store, and it had no test. No Swift test can reach the failure it exists to catch: an undeclared locale is neither a compile error nor a crash — iOS simply never loads it, so the watch shows English and the Mac job that builds and runs the Swift suite passes. This repo cannot run a Swift test outside that one macOS job either. So the guard is measured by mutating a copy of the real tree in each of the ways a locale ships half-declared — dropped from `CFBundleLocalizations`, dropped from `knownRegions`, an entry that never translated a shipped locale, a blank value, a plural missing its singular, a seventh locale added to one entry only, an empty catalog, a plist with no array at all — with the unmutated copy as the positive control. The `ja` singular exemption is asserted to still be narrow, so it cannot quietly widen into the thing that passes the guard. Run as a second step of the `watch-ios-locale-parity` job with its own `::error::`, per [decisions § 764](../architecture/decisions.md).

### `scripts/check_watch_ios_source.test.mjs` — 65 tests

`apps/watch_ios` is compiled by one job, on a macOS runner, and every claim about it otherwise rests on reading. `scripts/check_watch_ios_source.mjs` makes the six such claims a bare `node` on Linux can honestly make, and every failure it exists to catch is silent on the platform: a `Text("…")` with no String Catalog entry falls back to the key, so the watch renders English in every locale and nothing throws; an entitlement nothing exercises builds, links and ships, and is refused months later by App Review; two copies of one formatter drifting apart leaves the Swift suite green because `ActiveRunComplication.swift` is in no target and `@testable import WatchApp` therefore links only the other copy; and a metadata key one end of the WCSession run hand-off sends and the other never lifts out costs the row a column with nothing raised anywhere. So the guard is measured the way its sibling above is — a copy of the real tree mutated into each shape it must refuse, with the unmutated copy as the positive control. Sixteen cases are those mutations, one per refusal in each direction: a literal with no key, an accessibility hint with no key, a catalog entry nothing references, a purpose string dropped while its call stays and one declared with no call, a background mode each way, the HealthKit entitlement dropped, an unclaimed entitlement (the live `healthkit.background-delivery` defect, replanted), an App Group entitlement present but empty, a formatter that drifted and one deleted outright, an App Group renamed in Swift but not in the README, and a metadata key dropped on each end. Three assert the guard does NOT fire where it must not — `Text(verbatim:)` needs no entry (or the fix the guard recommends would fail the guard recommending it), a literal inside a comment is not a key, and a key reached only through `String(localized:)` is not reported as dead. Two are vacuity: a tree with no Swift, and an empty catalog. The rest measure the parsers directly, each against the specific way it was first written wrong — comment stripping that ate `http://` out of a URL literal, an interpolation matcher that stopped at the inner paren of `\(Int(bpm.rounded()))` and reported a live call site as missing, a dictionary scan that ended at a nested `]` and lost `last_modified_at`. `parseFlatPlist` is additionally asserted against the two real files it reads, because a hand-rolled reader written to avoid a dependency is only worth having if it answers what the dependency would. Run as a fourth step of the ungated `watch-ios-locale-parity` job with its own `::error::`. See [decisions § 884](../architecture/decisions.md) – [§ 888](../architecture/decisions.md).

Ten cases added 2026-09-02 for the seventh claim, the route-push envelope going the other way on the same `WCSession` ([decisions § 966](../architecture/decisions.md)). It has THREE ends in three languages and three apps — `apple_watch_route_bridge.dart` names the keys as method-channel arguments, `WatchIngestBridge.routeUserInfo` lifts them out and repacks them, `ArmedRoute.decode` reads them back — and every rejection in that chain drops the WHOLE push, so a key renamed on any one rail is a route the runner is told was armed and that never reaches the wrist. Three mutations rename a key on each rail in turn and assert the message names both the rail that has it and the rail that does not; two are vacuity (the Dart `invokeMethod` call renamed, the decode's subscript receiver renamed), each of which must report an unread rail rather than three agreeing sets; one asserts the claim is SKIPPED rather than half-made when only the two Swift ends are available, since two of three agreeing is not the claim; and the last four drive the three new parsers directly — `swiftPayloadKeys` over both the subscripts and the repacked literal (a key read and not forwarded is a field dropped inside one function), `dartInvokeKeys` across the nested `[for (…) …]` comprehensions that would stop a naive bracket scan at the first `]`, and `methodBody` against an indented method with modifiers in front of `func`, which the existing column-zero `functionBody` cannot find.

### `apps/watch_garmin/scripts/check_garmin_source.sh` — 5 source-level claims, and `scripts/check_garmin_source.test.mjs` — 28 tests

The Connect IQ tier had no automated verification of any kind: no CI job builds it, no CI job runs its `(:test)` suite, and the SDK is installed on no machine in this project — so `source-test/GradeAdjustedPaceTest.mc`'s twenty-five cases are **authored and have never been executed by anyone**, and the only thing in the repo that read the tier at all was `check_watch_wire_vectors.mjs`'s four Minetti constants. This guard is bash + python3, needs no SDK, and holds the five things a Linux runner can honestly say about Monkey C: that `GradeTracker` re-anchors on a negative run and `onTimerReset` clears it (the [§ 944](../architecture/decisions.md) grade-freeze, whose symptom is a confident wrong pace and no error anywhere); that every file under `source-test/` carries `(:test)` and `monkey.jungle` still excludes that annotation, since `base.sourcePath` compiles the directory into every build and only the exclusion keeps test code off a watch with tens of KB of headroom; that a permission-gated Toybox module is declared in `manifest.xml` before it is used, because the runtime refuses such a call mid-activity and the build says nothing; that the cross-rail constants are declared by name AND used by name, which is what makes them readable by a rail at all ([§ 945](../architecture/decisions.md)); and that the string table and its call sites agree in both directions. It is measured the way its watchOS siblings are, by mutation: the negative-run branch deleted, one anchor left behind, the callback renamed, the callback emptied, `reset()` clearing only the grade, `excludeAnnotations` pointed elsewhere, `source-test` dropped from the source path, an unannotated file added under it, a gated module imported with no permission, an orphaned string, a referenced-but-undefined string, both class names renamed as the vacuity control, and three more against the named-constant claim (the ceiling reverted to a bare literal, the literal re-inlined at the use site while the constant stays, and `MIN_SEGMENT_M` inlined in the tracker) — each produced the message naming its own defect, with the unmutated tree green either side. Those mutations are now a committed suite rather than a hand pass: `scripts/check_garmin_source.test.mjs` stages a copy of the real tree, mutates it into each shape the guard must refuse, and asserts the exit code and the message, with the unmutated copy as the positive control and three vacuity cases (a renamed view class, an empty string table, a deleted `monkey.jungle`). Writing it found a live defect in the guard: `body_of` located a declaration by SUBSTRING, so `function onTimerResetX` satisfied the claim that `onTimerReset` is overridden and `class GradeTrackerV2` satisfied the claim that `GradeTracker` exists — the same silent failure the claims exist to catch, one level up ([decisions § 963](../architecture/decisions.md)). Both halves are pinned. Guard and suite run as the two steps of the ungated **`watch-garmin-source`** job, each with its own `::error::` per [§ 764](../architecture/decisions.md). It does not compile Monkey C, so nothing here is evidence that the app builds.

### `scripts/tsconfig_coverage.test.mjs` — 7 tests (3 added)

The guard's verdict is `deepEqual(missed, [])`, which an EMPTY walk satisfies exactly as a fully-covered one does — a `git ls-files` answering nothing, a filter excluding everything, or a widened glob translation would each report the repo typechecked while typechecking none of it, and the file had no case that made the decision say no. The walk now states what it saw before it judges it (a count floor plus two named sentinels), a negative control asserts the same matcher pipeline still refuses a tree no root names, and the glob translation is measured on its own: `**` spans directories and a single `*` does not, a sibling sharing a prefix is a different tree, a bare directory covers everything beneath it and nothing beside it, `?` is never a separator. See [decisions § 850](../architecture/decisions.md).

### `scripts/check_watch_doc_counts.test.mjs` — 33 tests

The guard reads 24 firmware symbols out of the Rust that declares them and holds 111 statements across 17 present-tense custom_watch docs to them ([decisions § 867](../architecture/decisions.md)). Its two directions are measured separately, because each covers a failure the other structurally cannot see: a template whose tail carries the wrong number, and a count-shaped phrase no template claimed at all. Ten cases are mutations, six of them against a throwaway copy of the real tree asserting the process exit code — a doc number bumped, the `Page` enum grown while the docs stay correct (both the built-in ring and the composed total move, and both are named), an unregistered count appended to a doc, a registered sentence deleted so its template goes dead, a derived constant frozen to the literal it currently equals (which still equals it, and is exactly the change that makes the doc's number a coincidence), and a new doc dropped into `docs/custom_watch/` that neither `DOC_FILES` nor `DATED_LOGS` claims. The remaining three drive `check` over fixtures: a stale exemption, an exemption naming a file outside `DOC_FILES`, and a resolver that cannot read its source, which must be reported rather than skipped. A positive control (the unmutated copy) and a negative one (a doc set with no counts in it at all, which must fail as dead templates rather than pass) bracket the set, so the suite is shown to discriminate before it is trusted. Runs as a second step of the ungated `parity-matrix` job with its own `::error::` ([§ 869](../architecture/decisions.md)); a code-gated job would skip it on the doc-only diffs it exists to police.

### `packages/core_models/test/atomic_io_test.dart` — 17 tests (6 added)

The suite round-tripped the contents and counted temp siblings; nothing measured the property the `.tmp`-then-rename dance exists to provide. A reader now races a stream of 1.5 MB writes and every read must decode a whole document — replacing the rename with a bare `writeAsString` makes it fail with an unterminated string at 819201 characters. Four more the sweep never had: it must not eat a store row however the name is spelled (`a.tmp.json`, `b.lock.json`), it must leave an AGED subdirectory alone (the age gate does not protect one, the `is! File` guard does), an undeletable orphan is reported without stopping the sweep, and the temp name a REAL write creates is captured off an inotify watch rather than transcribed — so a writer that renamed its suffix, which would make every crash orphan permanent, fails here. Each confirmed against a mutation of the subject.

### `packages/core_models/test/store_write_chain_test.dart` — 15 tests (4 added)

A closure that throws SYNCHRONOUSLY takes a different path out of `runZoned` than the async one the existing failure case uses; if it escaped, the link would never complete and every write queued behind it would hang. Order across a failure was untested too — asserting only that the next operation resolves passes even if it ran first, which on a store directory is the delete-overtakes-write race the chain exists to close. `storeWritesSettled` is itself a queued no-op, so calling it from inside a serialised body inherits the re-entrancy grant and returns rather than waiting on itself. The per-key interleave is measured by TIMING rather than by order alone: one shared chain would still order each key internally, so only the fast key draining before the slow key's second write distinguishes them. Confirmed against two mutations — a shared chain fails four cases, removing the `try`/`catch` fails three.

### `apps/custom_watch/core/src/settings_menu.rs` — 22 tests (2 added)

*host-tested* per [`docs/custom_watch/quality_standards.md`](../custom_watch/quality_standards.md) — the `cargo test` host lane, no silicon and no simulator. `ITEMS` is a hand-written array and `MENU_ITEMS` its hand-written length; the array literal type-checks the two against each other and nothing checked either against the `MenuItem` enum. A variant added to the enum but not to `ITEMS` compiles — `edit`'s exhaustive match is satisfied by the arm the author did write — and the row then exists in the firmware and can never be selected, because the cursor only ever walks `ITEMS`. The new case is exhaustive by construction, so a ninth variant stops the crate building until it is listed and then fails until it is seated. Beside it, both guarded rows (`PAIR PHONE`, `FACTORY ERASE`) must stay on screen at every cursor position: the two-press guards put a destructive key behind a legend naming it, and a body window that scrolled the row past the fold would leave that legend describing a row the wearer cannot see. It holds today because eight items over a seven-row window leave two window positions and both guarded rows sit inside both; a ninth row opens a third, and this says which rows fell out of it.

### `apps/custom_watch/core/src/route_geometry.rs` — 36 tests (6 added)

*host-tested* per [`docs/custom_watch/quality_standards.md`](../custom_watch/quality_standards.md) — the `cargo test` host lane, no silicon and no simulator. A one-way port of the web canonical, which moved three times without it ([decisions § 899](../architecture/decisions.md)). The out-and-back case is the one worth reading: ranking candidate segments by a perpendicular measured inside each segment's own planar frame compares numbers scaled by different cosines, so 1 cm of sideways jitter moved the answer 3474.8 m onto the wrong limb — and the case beside it pins that the fix did not degenerate into "always the first segment". A non-finite fix used to come back as `Some(0.0)`, which is the START of the course rather than an unknown position. Two antimeridian cases: a leg interpolated across 180° landed at 0.01°, half a world away, and a point past the line projected to the end of the course instead of its midpoint. Four of the six were confirmed to fail against the arithmetic they replace. The suite is 36 against web's 43 because `markerPointAtDistance`, the marker-authoring inverse, has no wrist surface and is not ported.

### `apps/custom_watch/core/src/route_simplify.rs` — 28 tests, `track_projection.rs` — 11, `run_heatmap.rs` — 10 (5 added across the three)

*host-tested*. The remaining [§ 468](../architecture/decisions.md) antimeridian sites, mirrored onto the wrist a month late ([decisions § 901](../architecture/decisions.md)). RDP's perpendicular converts each longitude to metres east of the PRIME meridian and subtracts after, so a straight line across the line kept every interior point it should have collapsed and one 0.06° leg measured 40,023 km; both bounding boxes read a straddling track as spanning 359.99°, which collapses a thumbnail to a dot and fits a heatmap to the planet. The projection case asserts a box straddling the line projects **identically** to the same box a degree west, which is a stronger claim than "not 360°" and is what catches a half-fix. Four of the five failed against the arithmetic they replace; the fifth is the guard against over-fixing — a real 50 m deviation across the line must still survive RDP — and passes either way by design.

### `apps/custom_watch/core/src/run_stats.rs` — 23 tests (2 added, 1 replaced) and `grade_adjusted_pace.rs` — 34 (1 added)

*host-tested*. `elevation_gain_metres` paired adjacent points, so `[1000, None, 2000]` had no pair carrying two elevations and a kilometre of climb read as 0 m. The existing case asserted that defect and is replaced by web's own replacement for it rather than kept; the multi-point-gap case carries an embedded descent, which is the guard that the carry-forward cannot manufacture gain. Three fail against the adjacent-pair loop, two pass either way. Beside it, `watch_core` has exactly one haversine and seven modules call it: rounding can put `a` a hair above 1 for a near-antipodal pair and `sqrt(1 - a)` is then NaN, propagating through a distance, a pace and a cut-off margin without throwing. Measured on `(-87.5, 0, 87.5, 180)`: NaN before, 20015086.796 after. See [decisions § 902](../architecture/decisions.md).

### `apps/custom_watch/core/src/locale_defaults.rs` — 6 tests (2 added)

*host-tested*. The Sunday-first region table is a transcription of web's, and the port was frozen before web replaced the hand-written 16-region list with the 56 CLDR reports ([decisions § 903](../architecture/decisions.md)). One case names the 19 regions the old list got wrong — AR listed and Monday-first, plus 18 Sunday-first regions omitted. The other is a sort-and-dedupe check on the table itself: a transcription slip narrows the set by a region, and no behaviour test written against the regions someone thought to name would notice.

### `apps/job_worker/internal/worker_panic_test.go` — 4 tests

Round 31. Go does not recover a panic for you, and the worker loop runs in `main`'s own goroutine alongside the live-spectator hub, the export endpoints, the Strava webhook, the unsubscribe endpoint and the bounce webhook — all on one binary. The suite drives a `Matcher` that panics through the real `map_match` dispatch and pins that `Run` still returns, that the job reports back `failed` rather than staying claimed at `status='running'` where `claim_next_job` can never look at it again, that a panic whose text says `i/o timeout` is still permanent (`isTransient` substring-sniffs, so this is the one case that would otherwise be deferred), that the stack reaches the log, and that a runtime nil-dereference is caught and not only an explicit `panic()`. Four mutations: the barrier removed (the whole package panics), the `isTransient` short-circuit removed, the stack dropped from the log line, and a recover that reports the job `done`. [decisions § 924](../architecture/decisions.md).

### `apps/job_worker/internal/livehub/auth_disclosure_test.go` — 2 tests

Round 31. `livehub.authorize` echoed the authorizer's own error into the 403 body, and that error separates `auth: unknown run`, `auth: not the run owner` and `auth: blocked by run owner` — so the response told a blocked person that a specific runner had blocked them, on an endpoint anonymous spectators reach by design. Both directions are asserted: each of the three reasons produces a body naming none of them while the operator's log still carries it, and a push refusal and a snapshot refusal produce byte-identical bodies, so the response is not an oracle for which action was attempted either. Three mutations: the reason echoed again, the log line stripped of it, and the body differentiated by action. [decisions § 928](../architecture/decisions.md).

### `apps/graph_cycle/internal/api/server_bounds_test.go` — 8 tests, `apps/graph_cycle/internal/graph/build_test.go` — 11 tests (1 added)

Round 31. The HTTP boundary of the loop-generator sidecar, which had no test for anything past its validation table. The searches had no clock of their own — `main.go`'s `WriteTimeout` fails the connection write without cancelling the handler context — so a `SearchTimeout` field now bounds them and both handlers are pinned to answer **503** on a deadline and **499** on a caller that left, never `found: false`: that flag is the product's loop-poor claim and a search that ran out of clock has established nothing about the neighbourhood. Beside it: a body carrying a second JSON value is rejected (it used to be accepted with the tail discarded), the untested `maxBodyBytes` cap is asserted in both directions plus the decode-then-overrun case, `/nearest` refuses `NaN` / `Inf` (which `strconv.ParseFloat` happily returns), and two concurrency cases exercise the graph's "immutable after Build, read concurrently without locking" claim, which nothing had. In the graph package, `NearestNode` spun for **33 s on a 9x9 grid** given a non-finite query — `haversineM` returns NaN, no candidate ever wins, the early break can never fire, and the ring range comes from an `int32` conversion of NaN — measured by mutating the request-level check away; the guard is in `NearestNode` now and its test bounds the call at 2 s. Seven mutations across the two files, all red. [decisions § 927](../architecture/decisions.md).

### `apps/custom_watch/core/src/track_projection.rs` — 11 tests (5 added) and `route_simplify.rs` — 28 (4 added, 1 replaced)

Round 31, *host-tested*. Both modules had been edited hours earlier by the round-30 sweep, so the date comparison that produced the firmware followups list read them as in sync — the divergences here are ones the port never had, not ones it lost. `track_projection`'s `or_epsilon` was the falsy-only JS `value || 1e-6`, which catches an exact zero and lets a `1e-7` span through: a centimetre of jitter fitted the whole 92 px band where web collapses it to about 8 px. `isTrackRenderable`, the module's other export and the gate in front of the projection, had never been ported at all; its four web cases come across, including the antimeridian one where a raw min/max reads a stationary cluster as a 359.99° span and passes exactly the standing-still track the gate exists to catch. In `route_simplify`, `compute_elevation_gain` carried neither of the two rules web's own doc calls load-bearing — no `ELEVATION_GAIN_MIN_DELTA_M` noise gate, and a `None` broke the chain instead of carrying the last reading across — and `summarize_route_from_track` graded the SIMPLIFIED polyline, so a straight road over a summit collapsed to two endpoints and its 50 m climb read as 0. A test named "null elevations are skipped" asserted a gain of 0 across the dropout, encoding the divergence as intent; it is replaced by web's own case. Seven mutations across the two modules, all red. [decisions § 925](../architecture/decisions.md).

### `apps/custom_watch/core/src/training_load.rs` — 36 tests (2 added) and `race_predictor.rs` — 15 (2 added)

Round 31, *host-tested*. Two panics reachable from data rather than from a coding mistake, on a device where a panic is a reset. `predict_race_ladder` seeds both anchor loops with `f64::INFINITY` and takes the strict `<`, so a candidate whose Riegel equivalent IS infinity never wins — a positive-but-denormal distance overflows `libm::pow` — and `best.unwrap()` panicked on a function whose doc already promises `None` for a pool it cannot anchor; the second case pins that one clean effort beside the bad row still predicts, so the guard fails closed on the pool and not on the presence of one row. `compute_calibration` graded the numerator, and `km <= 0.0` is false for a NaN distance, so `trimp / NaN` reached the list: one such row made the window's fallback rate NaN and a second beside it panicked `median`'s `partial_cmp().unwrap()`. Both rails are pinned separately — the source guard by the infinite-distance case, the `total_cmp` comparator by the NaN one. [decisions § 926](../architecture/decisions.md).

### `apps/mobile_android/test/social_service_test.dart` — 35 tests

Pure-unit coverage for the value classes and helpers exposed by `lib/social_service.dart`. Covers `ClubView.isAdmin` / `isEventOrganiser` / `isRaceDirector` / `isMember` (the booleans that drive admin-only buttons + race-director Arm/Fire on `club_detail_screen` + `event_detail_screen`) — pinning that owner / admin both grant the full ladder, that `event_organiser` and `race_director` are siloed, that `member` carries no special affordances, and that an unrecognised viewerRole string is treated as not-admin so a future role we haven't taught the client about doesn't accidentally inherit admin powers. Plus 6 tests for `parseBydayCodes` (the byday-jsonb parser used by `_enrichEvents` + `fetchNextRsvpedEvent`): valid 'MO','WE','FR' shape, order + duplicate preservation, non-array fallback, empty + all-unknown → null (caller treats as "no override"), mixed known/unknown filters to known.

The Supabase-touching surface of `SocialService` (`browseClubs`, `fetchMyClubs`, the enrichment pipelines, RSVP writes, post creation) is NOT covered here — the class resolves `Supabase.instance.client` inline, so meaningful unit coverage of those branches needs a DI seam refactor (constructor-injected `SupabaseClient`, mirroring the `ApiClient.withClient` pattern). Tracked in [What's not covered](testing.md#whats-not-covered-honest).

### `apps/mobile_android/test/social_service_search_fallback_test.dart` — 3 tests

Pins the degrade-don't-throw contract on the two `SocialService` methods whose `catch` is the point of the method, via `SocialService.withClient` against a loopback `dart:io` PostgREST stand-in — the live-stack `services_integration_test.dart` can't fail one read independently of another, which is what these turn on. Two tests cover `searchClubs`: the `search_clubs` RPC failing (the branch that always worked) and the `_enrichClubs` follow-up reads failing after the RPC succeeds (the branch that didn't — `return _enrichClubs(rows)` without `await` put those reads outside the `try`, so the `browseClubs` fallback was dead, decisions.md § 595). Both assert the fallback's rows come back rather than an exception. The third pins `fetchClubSlugForEvent`'s never-rethrow contract — contract coverage, not a discriminating regression test, because the inner club lookup swallows its own failures either way.

### `apps/backend/supabase/tests/rls_*.sql` — 493 planned assertions across 57 files (pgtap RLS suite)

pgTAP tests against the highest-blast-radius RLS policies, run by `cd apps/backend && supabase test db --local`. Gated in CI by the `pgtap-rls` job. Each file is wrapped in `begin; ... rollback;` so it's idempotent against the running local DB; tests filter to fixture user_ids so they don't trip on `seed.sql` rows. Pattern: insert two test users into `auth.users`, then `set local role authenticated; set local "request.jwt.claims" = '{"sub":"<uuid>"}';` to switch identity. Anon paths use `set local role anon`.

- **`rls_runs_test.sql`** — 16 tests. Owner CRUD; non-owner direct `SELECT` on `runs` returns zero (the wire-leak SELECT policy was deliberately dropped in 20260701_001 — public visibility now flows through the `public_runs` view, see [decisions.md § 33](../architecture/decisions.md)); `public_runs` view exposes redacted public rows + strips audit / training-plan-linkage keys (`strava_id`, `plan_workout_id`); anon SELECT on `runs` is empty but on `public_runs` returns the public row; `is_run_visible_to(run_id, caller)` SECURITY DEFINER helper used by 5 sibling policies returns true for any caller on a public run.
- **`rls_routes_test.sql`** — 8 tests. Same shape as runs: non-owner direct SELECT on `routes` is empty even for `is_public=true` (the policy was dropped in 20260703_001); `public_routes` view is the public read path.
- **`rls_user_settings_test.sql`** — 8 tests. Owner-only across `user_settings` + `user_device_settings`; tests forbid forged-`user_id` INSERT and pin that privacy_zones in `prefs` are owner-only (a leak here is a doxxing vector).
- **`rls_coach_messages_test.sql`** — 7 tests. Owner-only across SELECT / INSERT / UPDATE / DELETE; pins reaction-update gate; non-owner reads of another user's coach conversation return zero.
- **`rls_integrations_test.sql`** — 6 tests. Owner-only — actual OAuth tokens live in `vault.secrets` (referenced by `*_secret_id`), but provider link + sync state are sensitive enough on their own to gate.
- **`integration_tokens_caller_guard_test.sql`** — 6 tests. Caller guard on the SECURITY DEFINER `get_integration_tokens` / `set_integration_tokens` (they decrypt + return, and write, a user's vault-stored OAuth tokens and are granted to `authenticated`). Pins that an authenticated user cannot read/write another user's tokens, that the owner reads their own decrypted tokens, and that `service_role` via the **modern jsonb `role` claim** can read/rotate any user's tokens — the delete-account deauthorize path that regressed in `20260919_001` when the body checked only the legacy `request.jwt.claim.role`.
- **`rls_device_tokens_test.sql`** — 6 tests. Owner-only — APNs / FCM push tokens. Cross-user access would let an attacker route push notifications to arbitrary devices.
- **`rls_notifications_test.sql`** — 6 tests. No INSERT policy (notifications come from triggers running as SECURITY DEFINER); pins owner read / mark-read / delete and asserts authenticated-user direct INSERT is rejected.
- **`rls_live_run_pings_test.sql`** — 8 tests. Real-time location broadcasts. Non-owner cannot read pings of a private run; non-owner CAN read pings of a public run via `is_run_visible_to`; INSERT requires both `auth.uid() = user_id` AND ownership of `run_id`.
- **`rls_live_run_pings_trigger_test.sql`** — 9 tests pinning the `live_run_pings_drop_in_zone` BEFORE-INSERT trigger from migration `20260618_001`. Trigger exists with the right name + table, fires BEFORE INSERT (AFTER would be too late — Realtime would already have seen the row), function is SECURITY DEFINER (required to read the broadcaster's owner-only `user_settings.prefs.privacy_zones`), and behaviourally drops in-zone pings while keeping out-of-zone + no-zones-configured + empty-zones-array fast-paths. The spectator clients (`apps/web/src/routes/live/[id]/+page.svelte` + `apps/mobile_*/lib/screens/live_spectator_screen.dart`) render pings verbatim, so this trigger is the single line of defence between a runner's home/work coordinates and any anonymous spectator on a public live run.
- **`rls_fitness_snapshots_test.sql`** — 15 tests. Owner-only across SELECT + INSERT + DELETE (no UPDATE — append-only); the `source = 'client'` INSERT-CHECK ensures users can't forge snapshots that look like server / job output.
- **`rls_engagement_chain_test.sql`** — 21 tests. The four engagement tables that gate visibility through `is_run_visible_to(run_id, caller)`: `run_kudos`, `run_comments`, `run_photos`, `segment_efforts`. Pins that non-owner reads succeed on a public run + return zero on a private run for all three (kudos / comments / photos), that non-owner INSERT is allowed on the public run + rejected on the private run, that forged user_id / author_id / owner_id INSERTs are rejected even on a public run, that comment authors / photo owners can self-edit and self-delete, that the run owner can delete any comment on their run, that kudos givers can rescind their own kudos, and the same six-pattern matrix from anon (no kudos/comments/photos visible on private runs; visible on public via the helper). Plus the helper-contract sanity test — `is_run_visible_to(private, owner) = true`.
- **`rls_privacy_clipping_test.sql`** — 19 tests for the `clip_track_for_user` SECURITY DEFINER RPC + its `privacy_in_any_zone` + `privacy_distance_m` helpers. Pins the actual privacy invariant: leading + trailing in-zone points dropped, mid-track in-zone points (loop-home pattern) preserved, all-in-zone collapses to empty, never-touches-zone returned unchanged, no-zones-configured returns input unchanged, defensive shape (null / non-array / empty input → []), 50000-point input cap enforced, and the most important test — that the clip output never leaks zone metadata (`radius_m` / `privacy_zones` strings can never appear in the function's output, even though the SECURITY DEFINER context reads them). The wrapping `clip-public-track` Edge Function is untested in isolation — it's thin orchestration over this tested RPC + RLS-gated row lookup + Storage download.
- **`rls_paywall_test.sql`** — 20 tests for the revenue-critical paywall surface: `is_pro()` (true for pro / lifetime, false for free / unauthenticated); `check_rate_limit_tiered()` (free user denied at the free ceiling; pro user allowed past it on the same args; lifetime user treated as pro; cross-user calls rejected with `not authorized`; positive-args validation; `retry_after_seconds` is non-zero on denial; tier reported in the result row); and the `lock_subscription_columns` trigger pin — a `set local "request.jwt.claim.role" = 'authenticated'` UPDATE on `user_profiles.subscription_tier` raises `42501` and the row stays at `free`. This last one is the single test that stops a malicious user from self-upgrading to pro by editing their own row.
- **`rls_events_meet_point_test.sql`** — 4 tests for the `events.meet_lat` / `meet_lng` anon revoke from migration `20260723_001`. Pins that anon SELECT on the precise coords raises `42501`, that authenticated callers still see them, and that anon can still read `meet_label` (the canonical text display field). The original migration shape was `revoke select (cols) from anon` — a no-op when anon still has table-level SELECT — so this test fired during the regression-test pass and forced the migration to be rewritten as `revoke select on events from anon` + a column-level grant on the safe columns.
- **`rls_user_coach_usage_test.sql`** — 6 tests for the explicit DELETE deny policy from migration `20260722_001`. Pins that the owner can read their own row (SELECT policy works), DELETE attempts return zero affected rows (RLS deny), and the row survives the DELETE attempt — ensures a free user cannot reset the daily-cap counter by wiping their own `user_coach_usage` row.
- **`rls_plan_templates_test.sql`** — 5 tests for the `clone_plan_template` strip from migration `20260721_001`. A service-role insert seeds a template with non-null `vdot` + `current_5k_seconds` (simulating a future writer that bypasses the publish-side strip), then a club member clones it via the RPC and the test asserts the clone's `vdot` and `current_5k_seconds` are both null and that non-fitness fields (`name`, `days_per_week`) are preserved.
- **`rls_user_profiles_column_lockdown_test.sql`** — 5 tests for the `user_profiles` column lockdown from migration `20260707_001`. Pins that authenticated SELECT on each of `subscription_tier`, `parkrun_number`, `subscription_at` raises `42501`; that `display_name` (the cross-user join column) still works; and that `get_my_profile()` SECURITY DEFINER RPC returns the full self row including the locked-down columns. Same pattern-fix story as `rls_events_meet_point_test.sql` — the test exposed that the original migration's column-level revoke was a no-op and forced a rewrite to revoke-table + grant-safe-columns.
- **`column_grant_lockdown_registry_test.sql`** — 4 tests generalising the two entries above (and `rls_clubs_invite_token_lockdown_test.sql` / `rls_events_meet_point_test.sql` / `event_gym_template_grants_test.sql`) into one class guard. Registers all **25** columns the four column-SELECT-locked tables withhold from `anon` + `authenticated` — `user_profiles` 16, `checkpoint_crossings` 5, `events` 3, `clubs` 1 — each with the reason it is withheld, and asserts the catalogue's withheld set equals the registry per role in both directions. Pinning the *withheld* set rather than the granted one is what detects the shape's real failure: a re-grant is cumulative, so a column added after a lockdown is deny-by-default until an explicit `grant select (col)` lands, and `clubs.is_verified` shipped that way and 42501'd every non-service-role read of `clubs` (`20260909_001` → `20260913_001`). The same assertion catches a withholding granted away and a table-wide `grant select` landing on a locked table; two more assert no table outside the registry has the per-column shape and none of the four has regained table-level SELECT. See [decisions § 759](../architecture/decisions.md).
- **`export_surface_contract_test.sql`** — 33 tests over the Art 20 export surface (`20270602_001`, `20270603_001`, `20270703000002`) and the photo buckets beside it (`20270622000002`). The shipped bucket assertions prove `exports` has SOME size limit and SOME mime list; these pin the VALUES (private, 5 GiB, exactly csv + zip). The photo buckets are held to the strippable set on the APPLIED row rather than on the migration text `check_shared_constants` reads, and over a DERIVED population — every bucket accepting any `image/` type — so a fifth image bucket is held to [§ 557](../architecture/decisions.md) the day it appears rather than the day someone extends a list of four names; the exact-set probe carries its null arm (`null @> array[…]` is null, so the old form filtered a bucket that lost its allowlist out of its own check) and `image/heic` / `image/heif` are named outright across every bucket. `data_export_jobs` is asserted on both rails the migration deliberately gave it (RLS with no policies AND no client grant, with a service_role positive control), plus the 64-char `error_code` cap at 64 and 65, the one-in-flight partial unique index in both directions, and the Art 17 cascade the table comment claims. The sweep is DRIVEN rather than read, and drives the escape too: the fixture no longer sets storage-api's `protect_objects_delete` GUC, so `cleanup_stale_export_blobs` only reaches the objects because `20270703000002` sets it itself. A row-level trigger returning null then produces the shape the post-condition check exists for — a delete FILTERED rather than refused, which `get diagnostics` reports as zero and which used to go on to mark the job row `expired` while the archive survived — and the sweep must raise and leave the row `ready`. See [decisions § 839](../architecture/decisions.md), [§ 857](../architecture/decisions.md) and [§ 858](../architecture/decisions.md).
- **`create_rate_limit_claim_source_test.sql`** — 6 tests. WHICH source `enforce_create_rate_limit` reads to decide a caller is the service role. The two shipped rate-limit files set `set local role service_role` and a `role` key in the JSON blob in the same breath, so neither can separate the legacy per-claim setting, the blob, and `current_user`/the session role; a body with an added `current_setting('role')` fallback passes both with zero failures. Each source is driven alone against an already-spent `create_club` window, so "it landed" is a statement about the skip and not about the bucket. Includes the fail-closed control (a session running AS service_role with no role claim is still throttled), a role claim naming something else, and the unparseable-blob case (22P02 aborts the write rather than resolving to no role). See [decisions § 838](../architecture/decisions.md).
- **`view_client_write_grant_test.sql`** — 4 tests. The class guard the three grant registries cannot carry: they all filter `relkind in ('r','p')`, so every view in `public` is outside all of them, and only three of the twelve are `security_invoker` — the other nine execute as `postgres` (BYPASSRLS), where an auto-updatable view's write grant reaches the base table past RLS. Asserts no view or materialized view grants `anon`/`authenticated` INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES, with a population floor and a SELECT positive control so an empty write set is a withholding rather than an empty catalogue. `service_role` is deliberately out of scope (the local CLI image and CI's pinned 2.84.2 disagree about default privileges on views). Granting `insert on public_runs to anon` turns it red. See [decisions § 837](../architecture/decisions.md).
- **`public_runs_projection_test.sql`** — 8 tests. `columns_are` on the 21-column projection (a re-emit carrying a new base column through fails here; the assertion fails on a missing column too, so it is its own positive control), then the two CONDITIONAL columns: one public run row is moved between a public and a private anchor so each null is a withholding rather than a link the row never had. Covers `route_id` through `is_public_route_by_id` and `event_id` through `is_public_event_by_id` — the latter had no coverage through the view at all, and dropping its CASE wrapper passed every shipped assertion — plus the shadow-hidden branch of each helper, which a re-emit naming the older `is_route_visible_to` would drop. See [decisions § 837](../architecture/decisions.md).
- **`payment_ledger_write_allowlist_test.sql`** — 11 tests pinning the two money ledgers' write locks as allowlists (`20270702000001`). `event_orders` is the one payment table with a permissive client UPDATE policy, so the trigger is the whole of what stands between a buyer and their own order row; the enumeration it replaced omitted `id`, and the buyer of a paid order could rewrite its primary key — the key `events-checkout` puts in the Stripe session's `metadata.order_id` and `payment_refunds.event_order_id` joins on. The file starts from the affordance that must survive (the buyer stamps `refund_initiated_at`, and the stamp is read back, so every refusal after it is the lock and not a dead write path), then probes every other column one at a time with a type-correct distinct value, asserts the probe list COVERS the live column set (a column added later fails here until probed), asserts every probe actually ran, and asserts the row still carries the webhook's figures. The `donations` half measures both rails in the order they stand: a real signed-in session matches no row (there is no permissive policy), and the trigger — reached as the owner carrying an `authenticated` role claim — refuses an `amount_cents` and a `client_request_id` change that the pre-fix denylist allowed. Service-role positive controls on both ledgers. Against the pre-fix trigger definitions four assertions turn red. See [decisions § 836](../architecture/decisions.md).
- **`column_grant_write_lockdown_registry_test.sql`** — 6 tests, the write-side sibling of the entry above. Registers every column the four column-**write**-locked tables withhold from a client, per verb and per role with a reason each — `achievements` (8 from UPDATE), `challenge_participants` (4 from UPDATE, 2 from INSERT), `coach_messages` (6 from UPDATE, 4 from INSERT), `event_attendees` (3 from UPDATE, 2 from INSERT) — and asserts the catalogue's withheld set equals it in both directions. It guards two failure modes pointing opposite ways: the read side's drift mirrored (a column added after a lockdown is deny-by-default and silently **unwritable**, `42501` on a PATCH/POST), and the [§ 584](../architecture/decisions.md) asymmetry (a column-scoped UPDATE locks nothing while the client holds a wider INSERT on a table it may also DELETE from — how `challenge_participants.completed_at` was forgeable in two statements until `20270616_001`). The remaining four assertions: no table outside the registry carries the per-column write shape; no locked table has regained a table-level grant on the verb it locks; `anon` holds no column privilege `authenticated` lacks, on any column of any public table, for any DML verb (the one live divergence was `coach_messages` UPDATE); every insertable-but-not-updatable column is registered write-once with the reason writing it once is safe; and the append-only exemption (`global_segment_efforts`) is checked rather than trusted. Seven probes, each rolled back, trip all six by name. See [decisions § 763](../architecture/decisions.md).
- **`rls_plan_workouts_writes_test.sql`** — 6 tests for the `plan_weeks` / `plan_workouts` write split from migration `20260613_001_rls_hardening.sql`. Pins that a non-admin club member CAN SELECT a club template's workouts (read flow preserved) but CANNOT INSERT / UPDATE / DELETE them (the regression — pre-fix `for all using (...)` let any club member with read access write to the parent's children even when they had no write authority on the parent training_plan). Plus positive controls: owner can write their own personal plan; club admin can write into their own template.
- **`rls_event_results_test.sql`** — 4 tests for the `event_results` INSERT visibility check from migration `20260613_001_rls_hardening.sql`. Pre-fix, the policy only checked `auth.uid() = user_id` with no event-visibility predicate — a user with a guessed event_id could plant a self-attributed result on a private-club event they couldn't even read. The test pins that an attacker (random authed user) cannot write to a private-club event's leaderboard, but CAN write to a public-club event (positive control), and that a private-club member can write to their own private event (positive control). Forged user_id is rejected even on a public event.
- **`rls_admin_user_id_forge_test.sql`** — 5 tests for the club admin `user_id` forge guards on `routes` + `training_plans` from migration `20260614_001_rls_hardening_pt2.sql`. Pre-fix, the `for all` admin write policies on both tables had no explicit WITH CHECK constraining `user_id`, so an admin could attribute a row to any user — the documented "uploader" audit trail was forgeable. Test pins that admins can self-author on both tables (positive controls), cannot forge another user's id on either, and crucially that admin UPDATE on a member-owned route still works (the relaxed UPDATE rule must be preserved — admins legitimately need write authority on routes / templates owned by other club members; the forge guard is INSERT-side only).
- **`rls_public_runs_view_denylist_test.sql`** — 3 tests but a 24-key sweep. Inserts a public run carrying every metadata key the strip list claims to remove, then SELECTs through `public_runs` as anon and asserts none survive. Catches drift in either direction — a removed strip OR a new sensitive key written without a matching update. Adding a key to the strip list = add it to the array in the test. Companion to `rls_runs_test.sql` which pins the row-level visibility chain (this file is denylist-coverage only).
- **`rls_event_attendees_test.sql`** — 10 tests pinning the RSVP policies after migrations `20260417_001` (per-instance PK), `20260428_001` (organiser-add path), `20260617_001` (drop legacy duplicate policy), `20260629_001` (self-RSVP visibility gate). Active member SELECTs the roster, stranger sees zero; active member self-RSVP succeeds; **stranger self-RSVP to an invisible private-club event is rejected** (the 20260629_001 closure — pre-fix, an enumerator could plant RSVPs against any event_id); forged-user_id RSVP rejected; event organiser can register a walk-up attendee (positive control on the organiser-add branch); plain member cannot register another user; user can UPDATE their own RSVP status; **organiser cannot UPDATE another user's RSVP** (own-row is the only write path — the walked-up user owns their own RSVP); user can DELETE their own RSVP. The per-instance PK `(event_id, user_id, instance_start)` from 20260417_001 is implicit in every fixture / assertion.
- **`rls_events_test.sql`** — 23 tests pinning the base row-level policies on `events` (companion to `rls_events_meet_point_test.sql`, which covers the column-grant lockdown). Active member can SELECT events of their private club, stranger sees zero; `event_organiser` can INSERT / UPDATE / DELETE (positive control); plain member cannot — **and `race_director` cannot either**. The race_director / event_organiser role split from 20260428_001 is the load-bearing decision pinned here: directors arm + start + end races but do NOT publish events, organisers do the opposite. A regression that widens `is_event_organiser` to include `race_director` (or `member`) gets caught. Also pins the `author_id = auth.uid()` author-forge guard against a legitimate organiser misattributing the row.
- **`rls_club_posts_test.sql`** — 9 tests pinning the threaded-feed policies. Active member SELECT works; stranger SELECT on a private club's feed returns zero; any active member can INSERT a **top-level OR reply** (the 20260428_001 "members can post" catch-all is the sole binding INSERT rule after `20260820_001` dropped the two 20260417_001 dead-code policies — they were dead from the moment 20260428_001 landed because their allow set was a strict subset of the catch-all); stranger and **pending requester** are both rejected (the `is_club_member` exclusion of pending status is the load-bearing write guard); forged author_id rejected; author can DELETE their own post; **club owner cannot DELETE a member post** (no admin-DELETE policy — moderation is via member removal, asymmetric with `club_members` where admins can DELETE other rows).
- **`rls_club_members_test.sql`** — 14 tests pinning the membership-row policies after migrations `20260417_001` (active / pending status) + `20260702_001` (join-policy gate). Pending requester reads their own row (the own-row escape hatch needed for "Request pending" UI); active member reads the full private-club roster; stranger sees zero rows of a private club's roster; self-join an open club as `member`/`active` succeeds; self-join with `role='admin'` is rejected (the **role pin** is the load-bearing privilege-escalation closure — 20260702_001 landed because the original policy let any self-joiner claim admin); self-join a request-policy club with `status='active'` is rejected (must be pending — admin approval flow); forged-`user_id` planting rejected; admin can UPDATE another row, plain member cannot; user can DELETE their own row to leave the club. Invite-only INSERT paths are out of scope here — they flow through the `join_club_by_token` SECURITY DEFINER RPC.
- **`rls_clubs_test.sql`** — 9 tests pinning the row-level policies on `clubs` (companion to `rls_clubs_invite_token_lockdown_test.sql`, which covers column grants + the `get_club_invite_token` RPC). Owner + active-member can SELECT a private club, stranger sees only the public one; forged-`owner_id` INSERT is rejected (which also blocks the `enroll_club_owner` trigger from elevating the victim into an owner-role membership row); admin (non-owner) can UPDATE but **cannot DELETE** — the asymmetry between the `is_club_admin` UPDATE policy and the `owner_id = auth.uid()` DELETE policy is load-bearing and pinned explicitly. Plain-member UPDATE and stranger DELETE are silent no-ops; owner DELETE is the positive control. Cross-user fixture setup uses pre-role-switch INSERTs to bypass RLS (same pattern as the other suites — `auth.users` rows + the auto-enroll trigger don't require `auth.uid()`).
- **`rls_segments_test.sql`** — 10 tests pinning the final policy stack on `segments` after migrations `20260526_001` + `20260703_001` (route through `is_route_visible_to`) + `20260819_001` (function moved to `private`). Author + stranger can SELECT a segment on a public route; stranger cannot SELECT a segment on a private route; forged-`author_id` INSERT rejected; INSERT against an invisible private route rejected (closes the same shape as `route_reviews`); author can UPDATE their own segment but a stranger UPDATE is a silent no-op; the `length_m >= 100` CHECK (decisions §37) fires on a tiny segment. Anon SELECT covered for both the public + private cases — same regression-guard story as `rls_route_reviews_test.sql`.
- **`rls_route_reviews_test.sql`** — 10 tests pinning the final policy stack on `route_reviews` after migrations `20260627_001` (INSERT visibility gate) + `20260703_001` (route through `is_route_visible_to`) + `20260819_001` (function moved to `private` schema, anon grant restored). Reviewer can read their own row + a non-author can read on a public route; forged-`user_id` INSERT is rejected; INSERT against an invisible private route is rejected (closes the cross-user pollution shape); cross-user UPDATE / DELETE are silent no-ops; the rating 1..5 CHECK and the `(route_id, user_id)` UNIQUE both fire. **Anon read paths are now covered** — before 20260819_001, anon SELECT on `route_reviews` SEGV'd the PG 17.6 backend because the 20260711_001 revoke left the SELECT policy invoking a function anon couldn't EXECUTE; tests 9 + 10 are the regression guard if the function move is reverted.
- **`rls_function_hygiene_test.sql`** — 10 tests pinning the function-grant + search_path closures from migrations `20260710_001` (search_path on `weekly_mileage` + `personal_records`), `20260711_001_definer_grant_hygiene.sql` (revoke EXECUTE on `is_route_visible_to` + `recompute_event_ranks` from anon and PUBLIC), `20260713_001_is_run_visible_to_anon_grant.sql` (restore the anon EXECUTE that pass-1 dropped on `is_run_visible_to`), `20260812_001_is_run_visible_to_private_schema.sql` (move `is_run_visible_to` to the `private` schema — closes the PostgREST RPC oracle without breaking the share page), and `20260819_001_is_route_visible_to_private_schema.sql` (same pattern for `is_route_visible_to`, after the 20260711_001 anon revoke turned out to break anon SELECT on `route_reviews` + `segments` — manifested as a PG 17.6 SEGV instead of a clean 42501). Pinned with `has_function_privilege('<role>', '<fn>', 'execute')` so a future Supabase auto-grant or a `grant ... to anon, authenticated` mistake fails CI, plus existence checks against `pg_proc` to assert the public-schema versions of both visibility helpers stay dropped.

These twenty-three files cover the tables + RPCs + triggers where a single-row leak / single-trigger bypass would be a privacy, impersonation, or revenue incident. They do NOT exhaustively cover every table (37 in total) — the original seven gaps (`clubs`, `club_members`, `club_posts`, `events`, `event_attendees`, `route_reviews`, `segments`) are now closed; remaining uncovered tables are lower-blast-radius (`run_kudos` / `run_comments` / `run_photos` are pinned indirectly via the `engagement_chain` helper, plus auxiliary tables like `webhook_events`, `rate_limits`, etc. that don't carry user content). Add a file when you touch a sensitive policy, or when an audit lands.

### `apps/backend/supabase/functions/**/*.test.ts` — 950 deno tests across 70 files

Run the pure-helper slices with `cd apps/backend && deno test --no-check supabase/functions/_shared/*.test.ts` plus the per-function `lib.test.ts` / `wiring.test.ts` / `handler.test.ts` files (`auth-email`, `delete-account`, `donations-checkout`, `events-cancel`, `events-checkout`, `events-connect-onboard`, `export-data`, `parkrun-import`, `race-results-import`, `refresh-tokens`, `revenuecat-webhook`, `strava-import`, `strava-webhook`, `stripe-events-webhook`); the network-touching ones (e.g. `_shared/handler_envelope.test.ts`) need `SUPABASE_TEST_URL=http://127.0.0.1:54321 supabase functions serve --env-file .env.local` and the `--allow-net --allow-env` flags. The `edge-functions` CI job runs all of them on every PR.

- **`_shared/webhook_security.test.ts`** — 21 tests. `hmacHex` against the RFC 4868 §2.7.2 case 4 reference vector (with byte-exact `Uint8Array` inputs — the function accepts `string | Uint8Array` on both `secret` and `body`); `timingSafeEqual` (equal / unequal-same-length / length-mismatch / no-short-circuit-on-first-mismatch); `validateFreshness` (recent / 7-day boundary / too-old / clock-skew tolerance / custom window + skew args); `isAnonymousAppUserId` (`$RCAnonymousID` prefix detected, others false). `isValidUuid` moved to `_shared/input_validation.ts` when the four uuid/timestamptz 500s were closed — it is a PostgREST-cast guard, not a webhook concern. The `timingSafeEqual` and `validateFreshness` helpers were extracted out of the two webhook `index.ts` files so the production code path now imports the tested module directly — no duplicate definition can drift.
- **`_shared/webhook_security.test.ts` (round 31 additions)** — 4 more, over `shouldReleaseDedupe` and the three insert-first dedupers that depend on it ([decisions § 915](../architecture/decisions.md)). The 5xx boundary both ways (500 releases, 499 and every 4xx keep the row); and three cross-function guards **derived from the tree rather than listed**, so a fourth webhook that reserves a dedupe row is covered the day it lands: every `index.ts` that inserts a `webhook_events` row must also delete one, and the set the sweep finds is asserted (`revenuecat-webhook`, `strava-webhook`, `stripe-events-webhook`) so an emptied loop cannot pass for a clean sweep; the two that dispatch behind a release gate on `shouldReleaseDedupe(res.status)` and may not re-spell `>= 500` inline; and both carry a rethrow arm that releases before the throw, since `withSentry`'s 500 never passes through the status check. All six mutations were verified killing them.
- **`_shared/external_id_batch.test.ts`** — 11 tests over `reconcileImportBatch`, the step both run importers now share ([decisions § 914](../architecture/decisions.md)). A repeat INSIDE the batch is dropped with first-occurrence-wins (three copies still yield one row); an already-stored id is dropped as it always was; the two reasons are counted identically, because the caller reports one `skipped` number; `skipped` is the arithmetic complement of `fresh` across five shapes, the subtraction having been written out at each call site before; input order survives; a batch with nothing stored and nothing repeated passes every row through **by identity**, which is the positive control against a filter that happens to empty the batch; an empty batch is not an error; and the caller's stored-id array is not mutated. Two source guards on the call sites: both importers must import and call it, neither may re-derive `fresh` from a local `Set` (the shape each of them reached the bug by writing out), and the reconciliation must precede the single-statement insert. Six mutations verified killing them, including reverting each call site.
- **`_shared/input_validation.test.ts`** — 6 tests. `isValidUuid` (8-4-4-4-12 hex, rejects malformed / non-string) and `isValidTimestamptz` (accepts every shape the clients emit — `toISOString`, Dart `toIso8601String`, PostgREST read-back, naive literal; rejects a bare date, the JS `toString()` form `Date.parse` happily accepts but Postgres does not, and an in-shape out-of-range date like `2026-02-30` that V8 silently rolls forward). Both exist to turn a Postgres cast failure (`22P02` / `22007`, surfacing as a 500) into a 400.
- **`_shared/redirect_allowlist.test.ts`** — 18 tests over the redirect allowlist four Edge Functions share (`strava-import` on `STRAVA_ALLOWED_REDIRECTS`; `donations-checkout` / `events-checkout` / `events-connect-onboard` on `STRIPE_EVENTS_ALLOWED_REDIRECTS`). `parseRedirectAllowlist` (single / several / trimmed / blanks dropped — a parse that kept `''` would admit a caller claiming an empty `redirect_uri` / unset / whitespace-only). `isExactRedirectAllowed` **both ways**: the configured callback accepted, accepted from anywhere in a multi-entry list, a custom-scheme mobile callback accepted; and refused for a foreign origin, **another path under the same origin** (the window Strava's own path-prefix-loose domain check leaves open), a prefix or extension of an entry, a case-folded host or scheme, an empty allowlist, and a non-string claim. Four source guards: `strava-import` routes through the shared module, gates BEFORE the `/oauth/token` exchange, still fails closed on an unset allowlist, and no function re-spells the parse inline. Two lane guards pin `.env.development` + `.env.example`'s `STRAVA_ALLOWED_REDIRECTS` to the port `apps/web/tests-e2e/fixtures/base-url.ts` declares and the path the web client sends, so the dev callback URL has one source. All six of the mutations these exist to catch were verified killing them — see [decisions § 750](../architecture/decisions.md)
- **`_shared/param_validation_wiring.test.ts`** — 5 source-grep guards, in the `delete-account/wiring.test.ts` idiom. Pins that `events-cancel`, `events-checkout`, `donations-checkout`, and `race-results-import` each shape-check their caller-supplied uuid / timestamptz BEFORE the query that would cast it — and that the two anon-reachable functions (`donations-checkout`, `clip-public-track`) do it before spending the IP rate-limit bucket.
- **`export-data/resumable_upload.test.ts`** — 18 tests over the chunked tus Storage sink the Art 20 archive streams through (decisions §703). Every case drives a fake `fetch` and asserts the protocol: an empty archive declares `Upload-Length: 0` and never defers; an archive inside one chunk declares its length up front; exactly-one-chunk-of-bytes stays single-chunk (the flush is strictly-greater so the tail PATCH always has bytes to carry the declared total); a multi-chunk upload defers at creation and declares on the final PATCH only, with every non-final chunk exactly one chunk; an oversized single write splits on boundaries and tens of thousands of tiny writes coalesce (with a linearity guard — the pending queue is compacted by a head index, not `shift()`, because a CSV export hands over one array per run). The three fail-closed cases are the point: a mid-stream PATCH failure and a creation failure both throw **without ever declaring a length**, so tus never materialises the object, and a server that acknowledges a different `Upload-Offset` aborts rather than splicing bytes into the wrong place. Two integration cases build a **real zip** through the sink at a 64-byte chunk size and re-read it with `ZipReader`, one of them feeding an entry from a `ReadableStream` of unknown length — which is what proves zip.js's data descriptor makes a forward-only sink legal at all.
- **`export-data/stream_section.test.ts`** — 16 tests over the page-by-page section streamer + the wall-clock budget. An empty section opens no archive entry and still claims completeness; a sub-page, an exact-page and a 2400-row section each stream valid JSON with the right page-call count; **120,000 rows** stream through what used to be a 50,000-row `EXPORT_ROW_CEILING`. Completeness honesty is pinned from four directions: a mid-stream page failure keeps the rows read, closes the array so the file is still parseable, and refuses to claim completeness; a first-page failure opens nothing and is incomplete; a server total above the rows read forces incomplete; and a short page with no server count still proves completeness. The budget cases cover a walk cut short mid-section (named in `deadlineSkipped`) and a section opened past the deadline being **shed without even spending its `count=exact` query**. `shape` / `keep` are pinned in order, and `walkPages` (the reduce-without-an-entry form behind the jobs summary) repeats the failure + budget cases.
- **`export-data/wiring.test.ts`** — 12 source-grep guards on the streaming invariants, which are structural and would all regress green: no `BlobWriter` and no single-shot `.upload(` anywhere in `index.ts` (either one puts the whole archive back in memory — the allocation both caps existed to protect); no `MAX_RUNS`, `EXPORT_ROW_CEILING` or `fetchAllPages`; all five blob sweeps budgeted by name; `upload.abort()` before the signing path and the signed URL minted only after the build returns; the response's `complete` folding in the deadline shortfall and the manifest merging it into `incomplete`; `manifest.json` still the last entry written (anything after it is uncounted); the full personal-data entry set still wired (audit/data-export-completeness); the three path-shape assertions still gating the service-role downloader; and — parsing migration `20270602_001` — that the artifact goes to the `exports` bucket, that the bucket's object limit is above the `runs` bucket's 25 MB, that it carries **no** `storage.objects` policy (signed-URL-only per `20260816_001`), and that the 7-day retention sweep was widened to it.
- **`export-data/paging.test.ts`** — 4 tests. The `EXPORT_PAGE_SIZE`/db-max-rows match, `parseContentRangeTotal` (reads the total, refuses `0-999/*` and anything unparseable — an unknown total must never read as a small one), a source guard that every multi-row read in `index.ts` either pages with `.range(` or is an explicit `.limit(1)`, and a guard that `paging.ts` no longer exports a row ceiling while still explaining why it was removed.
- **`strava-import/backfill.test.ts`** — 22 tests over the page walk, which could not be exercised at all until `backfill` was lifted out of `index.ts` (a module-level `Deno.serve` meant importing it bound a port). A stubbed `globalThis.fetch` and a hand-rolled client drive **all seven exits**: the two that reach the end of the window (an empty page, a short page) and the five that truncate (429/503, a non-2xx, a **thrown `fetch`**, a **body that is not JSON at all**, the 20-page cap) — the last two used to escape the function entirely and be answered as 500 `internal_error` with every count discarded (decisions § 768). Then the resume cursor: `parseSyncCursor` failing closed on eleven malformed shapes including an inverted window and a frontier below its own job floor, the serialise round-trip, `nextWalkWindow` narrowing from the correct end for an oldest-first and a newest-first page and **refusing** a cursor that would not narrow, the cap exit recording its frontier, a stored cursor narrowing the next walk, a finished walk clearing it and stamping `last_sync_at`, a request reaching further back ignoring it, a throttle on page 1 recording nothing, a throttle after a resume keeping the cursor it could not advance, and — against a simulated 1,250-activity window — a **second sync getting past the cap**, which is the whole point of the column.
- **`strava-import/wiring.test.ts`** — 7 source-grep guards. Each handler runs on the validated local rather than a second read of the untyped body (`lookbackDays`, then `code` / `scope` / `redirect_uri`); the `code` check lives at the top level and `handleConnect` does not re-check it (its `if (!code)` was unreachable, decisions § 768); exactly two exits may set `complete = true` and the return carries `resumable`; the page fetch and its JSON parse sit inside a try/catch that breaks rather than rethrows; `last_sync_at` is stamped and `sync_cursor` cleared only inside the `if (complete)`, and a resume point written only on a truncation; and both `.env.development` and `.env.example` allow-list the mobile callback, pinned against `kStravaCallbackUri` in the Dart client rather than a literal.
- **`strava-webhook/wiring.test.ts`** — 3 source-grep guards. (1) Every `return` before `readJsonWithLimit` goes through the `refuseUnread` helper, so no refusal branch (503 unconfigured, 429 throttled, 403 wrong secret, 405 wrong method) leaves the request body unread — Deno holds the connection open for an unread stream, which is a slow-loris against the one function reachable by URL alone. (2) The shared secret is read from `X-Webhook-Secret` BEFORE the `?secret=` query param, and the two collapse to one value with `??` so a wrong header gets no second try. (3) That merged value is compared with `timingSafeEqual`, never `===` (decisions §567).
- **`_shared/stripe_boundary.test.ts`** — 4 source guards over the one thing the `deno check` lane cannot see for itself. The Stripe SDK's declarations bind only through `_shared/stripe.ts`: esm.sh rewrites stripe's ambient `declare module 'stripe'` to name its own declaration file's URL, TypeScript matches ambient declarations by LITERAL specifier text, and an import straight from the runtime URL therefore resolves to `any` — it does not fail, it stops checking (decisions § 765). So this pins that no module outside the boundary imports an `esm.sh/stripe` URL; that something still imports the boundary (or the guard above it passes vacuously the day the Stripe functions are renamed); that the runtime specifier and the declaration specifier name the same stripe version, since two strings name one package and a half-done bump types the tier against a version it does not run; and that both halves of the compile-time guard inside `stripe.ts` are still present. The COLLAPSE half is not here and cannot be — no source grep can see it, because the import text does not change — it is a `@ts-expect-error` inside `stripe.ts` that the typecheck lane runs, negative because every positive assertion is satisfied by `any` itself. Every assertion was proved to fail against a deliberately broken tree.
- **`_shared/body_limit.test.ts`** — 12 tests for `readJsonWithLimit` and `readTextWithLimit` covering small / at-limit / over-limit bodies, chunked-transfer bypass, and the `tooLarge` response shape.
- **`revenuecat-webhook/lib.test.ts`** — 25 tests, two functions. `mapEventToTier(eventType, productId, currentTier)`: every activating event → `pro`, lifetime-product detection (substring match), null product id → `pro` default, EXPIRATION + CANCELLATION → `free` for non-lifetime, → `null` for lifetime (parallel-sub cancel can't downgrade), null `currentTier` → `free` (conservative default), unknown event types → `null`, **BILLING_ISSUE → null tier (no downgrade during grace period)**, **SUBSCRIPTION_PAUSED / TRANSFER → null tier (no-op events)**, plus the disjoint-taxonomy sanity test. `mapEventToBillingIssue(eventType, now?)`: BILLING_ISSUE → ISO timestamp string (set the flag); RENEWAL / UNCANCELLATION / EXPIRATION / CANCELLATION → `null` (clear the flag — payment recovered or subscription ended); other events → `undefined` (no write). One combined test pins the independence: BILLING_ISSUE moves the flag but NOT the tier, so a future refactor that re-couples them fails here.
- **`auth-email/lib.test.ts`** — 33 tests over the pure hook surface: Standard Webhooks verification (valid signature passes; tampered body / wrong secret / stale + future timestamps / missing headers / undecodable secret all reject fail-closed; multi-signature headers and `|`-rotated + bare-`whsec_` secret forms accepted), locale normalization + the settings → metadata → `en` fallback chain, catalogue parity (every one of the six locales carries every action key non-empty, CTA required on link actions), `planSends` per action (signup / email-OTP-reuses-magiclink / the secure email-change double-send with the documented reversed `token_hash`/`token_hash_new` pairing / single-confirm change / code-only reauthentication / unknown-action informational default / no-recipient skip), GoTrue-byte-compatible verify URLs (unencoded plain `redirect_to`, encoded on `&=#`), rendering (verify link is the FIRST URL in the HTML — the e2e `extractLink` contract — OTP alternative shown, `<html lang>` stamped, unknown locale → English), RFC 2047 subject encoding, MIME assembly, `extractAddr`.
- **`auth-email/handler.test.ts`** — 14 tests driving the FULL request path with a synthetic signed `Request` + injected deps (no stack): 405 non-POST, 503 hook_not_configured without the secret, 401 on a tampered body, 503 smtp_not_configured after a valid signature, the localized happy path (settings locale beats metadata locale; verify link lands in the MIME), settings-lookup failure falling back to the metadata locale, the email-change double send, SMTP failure → 500 (GoTrue must never think it sent), no-recipient 200 skip, invalid-JSON 400, oversized-body rejection.
- **`_shared/handler_envelope.test.ts`** — HTTP-level tests over the five webhook / cron / hook handlers that bypass the platform `verify_jwt` gate. **Auth-rejection branches:** refresh-tokens (403 on missing / wrong / non-Bearer Authorization), strava-webhook (403 on POST with no `?secret=`, on GET with no `?secret=` but a CORRECT `hub.verify_token` — the bare GET was answered by the verify-token gate whatever the secret gate did, § 815 — on POST with a wrong `?secret=`, and on a GET with a valid `?secret=` but a wrong `hub.verify_token`, a gate that had no case at all before § 815), revenuecat-webhook (405 on GET, 401 missing_signature, 401 bad_signature), auth-email (405 on GET; 401 missing_headers without the Standard Webhooks headers; 401 bad_signature on a fresh-timestamped wrong signature — proves an unsigned caller can't make GoTrue's send-email hook render + send auth mail). **Positive / gate branches:** refresh-tokens 200 on the correct cron bearer, which the three 403 cases cannot see because a gate refusing everything passes all three — the fixture is an integration inside the sweep's one-hour window holding no vault secret, so the loop `continue`s before Strava, and `disconnected_at` is read back afterwards as the negative observation that the upstream was not reached ([decisions § 1101](../architecture/decisions.md)); auth-email delivers a correctly signed signup hook into Mailpit, asserting the FRENCH catalogue subject (from `user_metadata.locale`, since a payload with no `user.id` has no settings row) and this run's unique `token_hash` in the body ([§ 1100](../architecture/decisions.md)); revenuecat-webhook 200 on a valid-HMAC anonymous event, 400 event_outside_freshness_window on a stale event, 400 missing_event_timestamp_ms; strava-webhook GET handshake echoes hub.challenge, 200 "OK" on a non-create event whose `event_time` is deliberately 30 days stale (a fresh one is answered identically by the not-connected-athlete branch further down, so the stale timestamp is what makes the 200 a claim about the early return), 400 on a create-shaped event with no ids. **Side-effect (the write, not just the envelope):** revenuecat-webhook drives an ephemeral user INITIAL_PURCHASE → dedupe-replay → EXPIRATION → lifetime → lifetime-protected PRODUCT_CHANGE and reads `user_profiles.subscription_tier` back at each step (proves the decided tier reaches the column, that a replay is deduped not re-applied, and that PRODUCT_CHANGE reads the written current tier); stripe-events-webhook `account.updated` mirrors charges/payouts/details + onboarded_at into `instructor_payout_accounts` and dedupes a replay. The two side-effect tests are gated on `SUPABASE_SERVICE_ROLE_KEY` (in addition to `SUPABASE_TEST_URL`) to plant + read the row; without it they skip. The CI job replaces the auto-started edge runtime with `supabase functions serve --env-file` because the auto-started runtime ignores `.env.local` and 503's every secret-gated call — the gated branches are only reachable when the secret is configured. All 25 cases are mutation-checked against the SERVED tree by `check_served_envelope_mutations.mjs` in the same job ([decisions § 815](../architecture/decisions.md)): 22 single-gate mutations, 26 declared kills, 0 survivors, 0 unmeasured, and a case no mutation claims fails the build. The two 2026-09-03 mutations are `cron-sweep-count-fabricated` (the hourly job records a count the sweep never produced; it probes with the real cron bearer and deliberately does NOT close the gate, because the refusal branch spends an `ipBucketKey` rate-limit token per call and twenty polls of it would put a 429 the three refusal cases cannot distinguish from a 403 into a later round) and `auth-email-metadata-locale-ignored` (a brand-new signup has no `user_settings` row, so dropping the metadata locale sends every confirmation in English; beaconed, because the response is `{}` either way). Configuring SMTP for the positive case also re-anchored `auth-email-missing-headers-accepted`, whose mutant used to stop at the `smtp_not_configured` 503 and now reaches the send plan — the SMTP guard had been standing in for the signature check that mutation removes.
- **`export-data/render.test.ts`** — 20 tests over the two text renderers the Art 20 archive is made of, split out of `index.ts` into `render.ts` so a test can call them at all ([decisions § 834](../architecture/decisions.md)). `csvRow` emits exactly one value per `CSV_COLS` entry (an added header with no matching value shifts every later field for the whole export, silently) and each value lands under the header its name promises; a title carrying comma / quote / CR / LF survives a round trip through a real RFC 4180 splitter; `track_url` stays absent from the CSV. `buildGpx` escapes `startedAt` and each point's `ts` as well as the title (the Go twin escapes all three and this one escaped only the title, [§ 832](../architecture/decisions.md)); a non-numeric or non-finite `lat`/`lng` drops the point rather than closing the quoted attribute with it, while the placeable points around it are kept; a non-numeric `ele`/`bpm` omits its tag; `bpm` is truncated to the integer the element requires; and an empty track still frames a document that opens and closes every tag exactly once. `canonicalTrackUrl` / `canonicalHrUrl` refuse seven near-misses each — including each other's suffix, or the hr sweep downloads the track and files it under `hr/`.
- **`_shared/sentry.test.ts`** — 6 tests over `withSentry`, the envelope all sixteen functions return through, which had none ([decisions § 835](../architecture/decisions.md)). A handler's own `Response` passes through with its status, headers and body intact; nine deliberate refusal statuses stay themselves rather than collapsing into one 500; a thrown error yields exactly `500 {"error":"internal_error"}` with neither the message nor the function name in the body, while the operator log still gets both (the silent-500 failure is the control for the leak test and vice versa); a thrown non-`Error` — string, object, `null`, `undefined`, number — takes the same path rather than throwing inside the catch; a rejected promise AND a synchronous throw are both caught, which is what forces the `await` to sit inside the `try`; and the original request reaches the handler with its method, headers and RAW body unconsumed, since every HMAC path verifies over the bytes.
- **`_shared/strava_upstream.test.ts`** — 11 tests over three exported helpers that had no direct coverage. `fetchStravaActivity`'s three-state answer decides whether the webhook returns 500 (Strava REDELIVERS) or 200 (Strava drops the activity forever), so 429 / 503 are pinned as `rate_limited` and seven other statuses as `not_found` — collapsing either direction loses runs or retries a delivery that can never succeed; the success case pins the activity id into the path and the token into the bearer. `isAlreadyImported` is pinned as a head-only exact count over all three predicates (`user_id`, `source`, `metadata->>strava_id`), with the id compared as TEXT because the jsonb extraction yields text, and an unknown count read as not-imported rather than imported. `gzipBytes` is measured as a real gunzip round trip (an implementation returning its input, or dropping every chunk after the first, satisfies any length assertion but not this) plus the empty-input member. `uploadTrack` pins the `{user_id}/{run_id}.json.gz` path both readers re-derive, and that a failed upload throws rather than stamping `track_url` for an object that does not exist. Round 31 added the asymmetric half nothing had asked ([decisions § 916](../architecture/decisions.md)): a failed POINTER write must throw too, or the trace sits in Storage with no row naming it and `isAlreadyImported` makes sure no later sync ever retries.
- **`_shared/ingest_activity.test.ts`** — 12 tests over `ingestActivity`, the one writer both Strava paths share (`strava-import` reaches it through `backfill`, `strava-webhook` calls it directly, so its defensive arms belong to neither suite). A non-run-family payload is refused even though both callers pre-filter, the legacy `type` field is honoured when `sport_type` is absent, an imported run is private unless the caller says so, a refused insert throws so the caller can count it, duration falls back to elapsed time, elevation reaches BOTH the column and the metadata bag, and walk / hike survive the trip to the column. Round 31 added the two the swallow made unaskable ([decisions § 916](../architecture/decisions.md)): a track that cannot be stored is **logged** rather than swallowed silently — with the failure supplied in the shape supabase-js actually rejects in (a plain `{ message, details, hint, code }`, not an `Error`), which is what makes both halves of the assertion bite, the message reaching the line at all and `details` / `hint` being kept out of the shared log aggregator — and the positive control beside it, that an activity with no stream logs **nothing**, because a line on every treadmill run is the same as no line. Five of the six mutations were verified killing them; the sixth exposed that an `instanceof Error` test alone reported every fault as `'unknown'`, which is the defect the ADR records.
- **`refresh-tokens/sweep_invariants.test.ts`** — 7 tests over the QUERY the cron sweep sends, which the sibling suite's mock recorded none of. The provider predicate (without it every Garmin and parkrun row goes through Strava's OAuth endpoint), the `token_expiry` horizon bracketed against the test's own clock (without it the whole table refreshes hourly), and the `order` + `limit(500)` pair as ONE invariant — a cap with no order spends the budget on an arbitrary slice and can leave the soonest-to-expire untouched run after run. The select is pinned to the two columns it uses and to carrying no token material. The disconnect write is pinned to BOTH predicates, or a dead Strava grant disconnects the runner's Garmin. An unreadable vault row skips that integration and the sweep carries on; a row with no refresh token never reaches Strava; and each integration is refreshed with its OWN token, stated as a per-row pairing rather than a count.
- **`clip-public-track/wiring.test.ts`** — 6 source-grep guards on the only anon-reachable path to another runner's GPS trace, which had no test file of its own. The clip is taken against `ownerId` and never the viewer (one identifier's difference, no error, publishes the owner's home); a row whose owner cannot be resolved is refused before the Storage path is derived; the owner bypass demands a non-null caller; the anon bucket is IP-derived, spent through the service role (the user-context guard rejects a synthetic key on any other client) and fails closed; the decode sits inside a try that answers 502 rather than throwing into a 500 ([§ 832](../architecture/decisions.md)); and both amplification bounds still guard their own quantity, with the compressed cap ahead of inflation.
- **`race-listings-sync/wiring.test.ts`** — 10 source-grep guards on a function that had none. An unrecognised provider answers 400 `unknown_provider` rather than being coerced to RunSignUp ([§ 832](../architecture/decisions.md)), with the sibling `race-results-import` read in the same test so the two legs of one feature cannot drift apart again unnoticed; an omitted provider still defaults; each leg is gated on its own key AND secret, fail-closed, ahead of the success answer; and the caller is identified then throttled at the documented 2 / 8 per hour before any provider work.
- **`revenuecat-webhook/wiring.test.ts`** — 4 tests on what the handler HANDS the tier mapper. `lib.test.ts` supplies `currentTier` itself and so could not see that the handler supplied `null` for four of the five activating types, leaving the lifetime guard unreachable exactly where a lifetime owner is billed monthly for a parallel entitlement ([§ 832](../architecture/decisions.md)). The gate is pinned to name both event lists and not to single out `PRODUCT_CHANGE`; the profile read must precede the decision and its result must be what reaches the mapper; the behavioural half walks the exported `ACTIVATING_EVENTS` list (with a membership pin beside it, so an emptied list runs zero iterations and still fails) asserting each type declines to downgrade a lifetime holder while still granting `pro` to everyone else; and a signed body carrying no event object answers 400 rather than 500, which RevenueCat would retry for three days.

The happy-path 200s with valid HMAC / freshness / dedupe still need real secrets to drive and are exercised manually only — see [apps/backend/CLAUDE.md § Testing without real credentials](../../apps/backend/CLAUDE.md#testing-without-real-credentials).

### `apps/web/tests-e2e/**/*.spec.ts` — 1,791 declared tests across 474 spec files (Playwright suite)

End-to-end browser tests that drive the real SvelteKit app against a real local Supabase. Unit tests pin pure helpers and SQL pins RLS at the database; this suite catches the next failure mode — **a UI fetch path that bypasses or misuses an otherwise-correct policy** (a wrong join, a dropped filter, a client-side lookup that trusts the URL, an optimistic update that never round-trips). Browser-only on purpose — mobile / watch don't have an equivalent harness (Flutter `integration_test` is too slow + flaky on CI to be worth the cycles right now).

**Stack:** `@playwright/test` 1.59.1, Chromium-only, run via `pnpm test:e2e` from `apps/web`. Webkit + Firefox would 3× the runtime; cross-browser bug yield on a SvelteKit static site is low. Single worker (`fullyParallel: false`, `workers: 1`) — concurrent tests against shared Supabase data race. The dev server (vite, port 7777) is auto-started by Playwright's `webServer` block; spec files attach pre-saved auth state so the only place the `/login` form runs is `globalSetup`. Total wall-clock for the full suite: ~110 s.

**One thing to know about sign-out:** the `globalSetup` fixture signs each user in once and saves cookies + the refresh token to `.auth/<user>.json`. Every test that uses `test.use({ storageState: USER_X.storageStatePath })` loads that file fresh. **Any test that triggers `auth.logout()` (which calls `supabase.auth.signOut()`) will revoke the current session's refresh token server-side — and that's the same token sitting in the saved file** (yes, even with `scope: 'local'` — supabase-js still hits the server logout endpoint). Subsequent tests for that user load the file, get the now-revoked token, and fail to authenticate. The rule the suite uses today: any sign-out test starts with an EMPTY storage state and signs in via the form first to mint an ephemeral session — that session's refresh token is what gets revoked, and the saved file's token is never touched. See `cross-cutting/sign-in-out.spec.ts` for the pattern.

**Why `vite dev` and not `vite preview`:** `adapter-static` + `fallback: 'index.html'` returns the SPA shell for any unmatched route (e.g. `/runs/<id>`). The fallback HTML computes its asset base via `new URL("..", location).pathname` — for `/runs/<id>` that resolves to `/runs`, breaking `_app/` asset URLs. Production fixes this with a CloudFront viewer-request rewrite; `vite preview` doesn't have that, so dev mode is the right server for headless e2e.

**Auth fixture (`fixtures/auth.ts`)** — Playwright `globalSetup` signs each seeded user in once via the real form and saves their storage state to `.auth/<user>.json`. Specs then `test.use({ storageState: USER_X.storageStatePath })` instead of re-running the login flow per test. Three users from `seed.sql` (`runner@test.com` free, `alex@test.com` free, `morgan@test.com` pro) cover owner / cross-user-viewer / paywall-pro cases.

**Browser-zone dates (`fixtures/dates.ts`)** — every day-relative seed (`browserDate` / `browserDateOf` / `browserDayStart` / `browserDayAt` / `noonOnBrowserDay` / `waterStorageKey`) is built in the zone `playwright.config.ts` pins the browser to, never in the runner's. `fixtures/dates.test.ts` unit-tests those helpers and additionally scans the whole `tests-e2e` tree for local-zone date getters, with a reasoned allowlist; it runs in the web unit suite, not under Playwright, because the defect is invisible to any run whose two zones happen to agree that hour ([decisions § 728](../architecture/decisions.md)).

**Backend cross-check reads (`fixtures/db-read.ts`)** — a spec's service-role assertion stacks two claims, that the read reached the database and that what came back is what the feature wrote; `const { data } = await admin.from(...)` collapses them, and the absence becomes a value the `expect` judges the feature on. `readRow` / `readMaybeRow` / `readRows` / `readCount` keep them apart. `fixtures/db-read.test.ts` unit-tests the helpers (a failed read throws naming itself; zero rows survives as a real answer; an absent `.single()` row is reported as absent rather than as a broken read) and scans the whole `tests-e2e` tree for a binding from a read whose `error` is never consulted appearing inside an `expect(...)`. The scan bans the shape rather than a list of absorbers: its first version enumerated them and a bare `?.`, a `!`, a cast and the read's own `null` all passed straight through, leaving 62 assertions — 30 RLS negatives plus the Art 17 cascade checks — passing on reads that never reached the table ([decisions § 777](../architecture/decisions.md)).

**Playwright-tree typecheck (`fixtures/tsconfig-coverage.test.ts`)** — the tree is compiled by esbuild (Playwright) and `tsx` (the fixture guards), neither of which type-checks, and `.svelte-kit/tsconfig.json` includes `src/` / `test/` / `tests/` only, so nothing checked `tests-e2e/` until [decisions § 749](../architecture/decisions.md). `apps/web/tsconfig.tests-e2e.json` is a second `tsc` root over the tree, run as `npm run check:e2e-types --workspace=apps/web` and as the `Playwright tree typecheck` step of `parity-types`. This guard (2 tests, web unit suite) fails if a compilable file appears under `tests-e2e/` that no include pattern reaches, if the config stops extending the strict app config, or if CI stops running the script.

**`apps/web` typecheck coverage (`scripts/tsconfig_coverage.test.mjs`)** — the sibling of the guard above, one level up: `scripts/`, `lambda/` (eight production AWS handlers), `svelte.config.js` and `static/sw.js` were outside every `tsc` root too ([decisions § 752](../architecture/decisions.md)). `tsconfig.node.json` and `tsconfig.service-worker.json` cover them, run as `check:node-types` / `check:sw-types` in the `Node + service-worker tree typecheck` step of `parity-types`. This guard (3 tests, run by `npm run test:tsconfig-coverage --workspace=apps/web` in that same step, not by the web unit suite — it needs `svelte-kit sync` first) names no tree: it reads every `tsconfig*.json` at the top of `apps/web`, resolves each one's effective `include` / `exclude` through its `extends` chain, and fails when any compilable file git reports under `apps/web` is matched by none, when a root is named by no npm script, or when `ci.yml` runs none of the scripts that name a root.

**Pinned UUIDs (`fixtures/seeded-data.ts`)** — `RUNNER_PUBLIC_RUN_ID`, `ALEX_PRIVATE_RUN_ID`, `RUNNER_PUBLIC_ROUTE_ID` are deterministic UUIDs hardcoded into `seed.sql` so cross-user, share-page, and privacy-clipping tests can address known rows without first listing-and-picking. The pinned public run is also exempted from the cross-user kudos / comment seeds (`id != '...'` filter on the engagement inserts) so the kudos toggle test starts at zero kudos.

#### Layout

The suite mirrors `apps/web/src/routes/`, with two flat concern folders for things that don't fit a single page. The convention: any test that needs a second browser context goes under `cross-user/`; any test that touches >1 route or storage-state file goes under `cross-cutting/`; everything else lives at `<route>.spec.ts` (or `<route>/<sub>.spec.ts` for routes with detail pages).

```
tests-e2e/
  fixtures/                    — globalSetup, helpers, browser-zone dates, seeded constants, users
  landing.spec.ts              — /
  explore.spec.ts              — /explore (redirects to /routes?tab=explore)
  learn/                       — public Learn/guides surface (anon storageState; learn.md, decisions §161)
    hub.spec.ts                — /learn renders the hub heading + ≥1 guide card; a card link resolves to /learn/[slug] (no 404)
    article.spec.ts            — /learn/road-running-101 renders the prose body, breadcrumb, CTA block; feature CTA href = /plans/new + sign-up href = /login?signup=1
    seo.spec.ts                — article <head>: <title> contains the guide title + "Threkir", absolute canonical, og:title/description/type=article/image, Article JSON-LD in the DOM
    category.spec.ts           — /learn/category/getting-started lists that category's guides; unknown category → error UI
    cta-links-resolve.spec.ts  — anon clicks the feature CTA → lands on /login (auth funnel), not a hard 404
  dashboard-period.spec.ts     — /dashboard/period/[type]/[date] (week + month deep links + invalid-date fallback)
  login.spec.ts                — /login (failed sign-in; sign-up: ?signup=1; forgot-password full round-trip via Mailpit; happy sign-in path in cross-cutting/sign-in-out)
  dashboard.spec.ts            — /dashboard
  feed.spec.ts                 — /feed
  coach.spec.ts                — /coach (mount, dropdowns, send → mocked SSE assistant bubble)
  live/
    spectator.spec.ts          — /live/[id] (anon: shell mount + planted-pings backlog hydrate → LIVE + named runner via public_profiles + stat strip; finished-state for a run whose duration places it >2 min in the past; private + bogus-id not-broadcasting). Exercises the Supabase Realtime FALLBACK path (PUBLIC_LIVE_HUB_URL unset) — seeds live_run_pings directly.
    spectator_websocket.spec.ts — /live/[id] on the REAL Go live-hub WebSocket path. NOT run by the sharded suite (testIgnore'd) — only by the dedicated `playwright.livehub.config.ts`, which boots the actual job_worker live-hub binary on :8099 + a second dev server with PUBLIC_LIVE_HUB_URL set, so the page takes `openLiveWebSocket()`. Two cases: (1) push backlog before connect → on-connect WS replay flips badge to LIVE + lands last-ping stats + anon handle, then a post-connect push streams over the live subscribe; (2) single pre-load push → snapshot late-join hydrates. Pings POST to the hub via `fixtures/livehub.ts` (`pushLivePing`, throws on privacy-zone clip). Needs the Go toolchain; CI job `e2e-web-livehub` (unsharded). Run locally: `pnpm test:e2e:livehub`.
    settings/export_job.spec.ts — the QUEUED Art 20 export rail on /settings/account, against a real Go worker and a real Storage stack. NOT run by the sharded suite (testIgnore'd) — only by the dedicated `playwright.exporthub.config.ts`, which boots the job_worker on :8098 with auth ON (an export is the caller's own data, so unlike the live-hub lane the verifier is NOT disabled) and a dev server with PUBLIC_EXPORT_HUB_URL set. The same worker process drains the `data_export` queue, so there is one thing to boot. Two cases: (1) one journey — the archive is enqueued, a reload mid-flight finds it again with nothing stored locally (the property the queued rail exists for), and it lands as a real zip whose signed URL is fetched and magic bytes checked; (2) `POST /v1/export` answers 404 against the running binary, because a deleted route is worth checking where it was mounted. The journey is one test rather than three because each enqueue spends a `check_rate_limit_tiered` token, and it signs in as the PRO seed user for the same reason — free allows 2/h and the lane retries once on CI, so a free user would sit exactly on the ceiling with no headroom and a 429 would read as a broken rail. `scripts/start-exporthub.sh` verifies the JWT signing secret against the stack's own anon key before booting, so a wrong secret fails at boot instead of as a 401 mid-spec. Needs the Go toolchain; CI job `e2e-web-exporthub` (unsharded). Run locally: `pnpm test:e2e:exporthub`.
    event.spec.ts              — /live/event/[id]/[instance] (pre-race empty state; running race + 3 runners → status pill, leaderboard sorted distance-desc with per-user avatar tint)
  runs/
    list.spec.ts               — /history (filter, sort, search, multi-select, create, delete; bulk-delete actually-deletes round-trip)
    new.spec.ts                — /runs/new standalone create form (RunEditor → land on /runs/[new])
    detail.spec.ts             — /runs/[id] (edit, cancel, single-run delete via the trash icon)
    cascade.spec.ts            — backend boundary: deleting a run sweeps every cascading child (kudos, comments, photos, segment_efforts, live_run_pings, run_matched_tracks, notifications) + the Storage object; run_photos cascade
    photos.spec.ts             — /runs/[id] RunPhotos: owner upload + caption edit + delete (with DB + Storage assertions)
    save-as-route.spec.ts      — /runs/[id] Save-as-route CRUD (prompt → /routes/[new])
    track-missing.spec.ts      — row + Storage divergence resilience: plant a row with `track_url` pointing at a non-existent Storage object (mirrors a mid-sync crash where the row insert succeeded but the gzipped track upload failed); /runs/[id] must render the run header + distance/duration without crashing on the failed track download. Pins the data-layer's try/catch around fetchTrack
    social.spec.ts             — /runs/[id] owner sees kudos count + comment list (RunSocial mounts for own runs); owner posts comment on own run
    load-failure.spec.ts       — /runs read failures stay distinguishable from "you have no runs". First page: a 500 renders the retryable error card, never the `runs-empty-no-data` onboarding card, and the retry recovers. Second page: the Load-more affordance only exists in paginated mode (All time + both filters at "all"), which the runner's seeded back-history (225 rows, mostly the `generate_series` bulk block in `seed.sql` § 4b) fills past one 50-run page — a failed page-two shows `runs-load-more-error`, keeps the button (the error lives *inside* the `hasMore` block, so it can only render if the failure left `hasMore` alone), relabels it Retry, and recovers on click. The page-two intercept matches `offset=50` rather than "the next runs GET" so it cannot fire on an unrelated read
  gym/
    gym.spec.ts                — /gym lightweight loop: log a free-form workout (title + exercise + sets) → PR badge on the list → detail per-exercise PR chip + set rows → delete (DB assertions throughout)
    multimodal_home_history.spec.ts — Phase 4 multi-modal Home + History (data-gated, no flag — seeds a lift): sidebar always shows Gym + Nutrition; /dashboard shows the Recent-lifts card; /history shows the All/Runs/Lifts/Meals chips + a lift row in the unified timeline linking to /gym/[id]; the All-view modality-aware Log menu (run/workout/meal, keyboard-navigable) + the single-modality Log action; the Runs chip renders run rows as a timeline (no run toolbar) with a "View all" → /runs, and Lifts/Meals "View all" → /gym // /nutrition; back-nav restores the feed from the snapshot without a refetch; the timeline grid flows multi-column on a wide canvas
    class-instructor.spec.ts   — gym/strength-class instructor seam gaps (instructor_business.md): a `class` event with NO gym_template self-hides the "Log this as a workout" affordance (the null-template negative the class_gym_seam spec leaves untested); the routine-detail Start button (`routine-start`) routes to /gym/session/[id] and mounts the guided runner with the authored exercise prefilled
    activity-loader.spec.ts    — ActivityLoader in a live loading state: stalls the /gym/routines GET (a never-resolving `page.route` gate) so the page holds its loading branch, then asserts the shared animated-athlete loader's accessible surface — a `[role="status"]` region carrying the localized "Loading…" text with an `<svg>` figure inside — then releases the request so the page settles clean
  nutrition/
    nutrition.spec.ts          — /nutrition manual-log loop: open /nutrition/log → pick a meal slot → manual entry (name + macros) → save → land on /nutrition with the item under its slot + calories → water tracker increments by a 250 ml unit (DB assertion + cleanup). The Open Food Facts search path is unit-tested in food_search.test.ts (no network in e2e)
                                 Also the undo contract on the food-entry delete (U8): one click removes the row and shows the undo bar, Undo restores it AND the backend row is still there (proving the delete was deferred, never performed — asserted after the undo so it cannot race the window), dismiss commits it, and an untouched 8 s window expires so the held mutation lands on its own. The same undo behaviour is pinned on route-conditions.spec.ts (survives a reload after Undo), runs/social.spec.ts + cross-user/comments.spec.ts (incl. the reply cascade), comment-tap-targets.spec.ts (the bar's own dismiss clears the 44 px floor), and round 12's four adopters: u/notifications.spec.ts (single row, a collapsed GROUP restored by ONE undo, and an expiring window), routes/review.spec.ts (Undo hands back the SAME row id, not a re-insert), routes/markers.spec.ts (undo then dismiss-to-commit), and settings/gear.spec.ts — whose keyboard-only leg Tabs from inside the edit Modal to the undo bar and activates it with Enter, the exact regression that made round 11 revert this adoption
  sessions/                    — yoga/pilates session-planner + follow-along player (not yet exhaustively catalogued; session_runner / session-plan / club-template / movement-autocomplete specs also live here)
    runner-skip-pause.spec.ts  — follow-along player control gaps (instructor_business.md M5): SKIP a step mid-session → the logged gym_workout carries session_adherence = 'partial' with the skipped step recorded 'skipped' and the rest 'completed'; PAUSE a timed hold → the countdown freezes + the control flips to Resume, and resuming carries the session to a clean save
    plan-edit-start.spec.ts    — session-plan lifecycle gaps: EDIT a saved plan (SessionPlanEditor `existing` path) to append a movement → the new step round-trips on the detail view + persists; a `class` event's attached-sequence link routes through to /sessions/[id] where the follow-along runner starts
  coaching/                    — coach↔athlete roster + review surface (not yet exhaustively catalogued; invite / assign-plan / load-error specs also live here)
    link-lifecycle.spec.ts     — link-lifecycle boundaries the happy-path specs miss: coach revokes an athlete → /coaching/athletes/[id] becomes RLS-inaccessible ("Not on your roster") + the link row is 'ended'; an athlete leaves their coach from their own /coaching (the whole athlete side, untested before); an anon visitor to a valid invite URL gets the sign-in CTA (not an error/redirect); an already-redeemed token shows the "Invite problem" card; an assigned plan with mixed done/missed workouts renders the right compliance counts + status pills
  routes/
    list.spec.ts               — /routes (search, filter, tab switch)
    detail.spec.ts             — /routes/[id] (star, public toggle, tag add+remove, review submit + DB upsert)
    detail-load-failure.spec.ts — /routes/[id] a failed read is not a deleted route: a 500 on the route read renders the retryable load error, never the not-found line, and Retry recovers
    import.spec.ts             — /routes Import-route modal: drop a GPX → preview → Save → land on /routes/[new]
  challenges/
    detail-load-failure.spec.ts — /challenges/[id] a failed read is not a missing challenge: the load error with Retry renders ahead of the not-found line, and a failed leaderboard read reports itself rather than reading as an absent challenge
  fundraising/
    detail-load-failure.spec.ts — /fundraisers/[id] read failures seen as an ANONYMOUS donor (the only spec that visits the page logged out, which is what caught the layout auth guard never listing `/fundraisers/`): a failed campaign read shows the retryable error instead of "isn't available", and a failed totals or feed read reports that panel without blanking the page
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
    backup-completeness.spec.ts — /settings/account, the archive's own honesty. A run pointing at a Storage blob that was never uploaded makes the track download genuinely fail, and both the page and `manifest.json` must say so; restoring an archive that declares `complete: false` still lands its rows but surfaces the verdict. Third case (§ 845): a shortfall the track counter CANNOT describe — a 500 on `get_my_profile`, routed only after the page has loaded so the boot read is not what is being tested — must reach the page as the sections sentence naming `profile`. It deliberately does not assert the track sentence is absent: the seeded runs' blobs do not survive a `supabase db reset`, so every track read fails in this environment and the archive is honestly short of both. Which sentence a given shortfall earns is decided in `backupShortfall` and measured exhaustively by `src/lib/backup/shortfall.test.ts`
    integrations-connected.spec.ts — connected-state UI on planted `integrations` rows (badges, Sync now, the disconnect ConfirmDialog + its DB delete), plus the Strava truncation disclosure in all three shapes: a resumable partial says it picks up where it stopped, a throttle that advanced nothing says it has no restart point, and a completed walk keeps the success toast rather than being downgraded. Since § 846 also the FIRST-CONNECT leg — the OAuth callback is a separate code path from Sync now, and it graded its result then dropped everything but the toast; the spec drives `?code=&scope=&state=` with the CSRF state stashed in `sessionStorage` and asserts the note renders off the `action: 'connect'` exchange. **If "Disconnect Strava" is red locally and green on CI, it is the shared edge-runtime container, not this spec and not Strava env.** The filing that raised it blamed missing Strava credentials; measured 2026-09-02, that is wrong in both directions. The disconnect path needs no Strava credentials at all — `plantIntegration` writes no tokens, so `handleDisconnect` resolves an empty access token and skips the deauthorize call — and CI's `e2e-web` job has none either: it runs `supabase start` and never `functions serve --env-file`, and no `apps/backend/supabase/.env` is committed, so an env-keyed auto-skip would have skipped on CI too and deleted the coverage instead of explaining the red. The real local failure is that the ONE edge-runtime container shared across every worktree is bind-mounted at the tree it was started from; once that directory has been replaced under it, every invoke answers `{"code":"BOOT_ERROR"}` / 503 and its log reads `failed to determine entrypoint` for strava-import, race-listings-sync and race-results-import alike. Every spec that invokes any Edge Function is red in that state, so no per-spec skip is the right instrument — recreate the local stack
    export.spec.ts             — /settings/account Data Export: CSV + JSON button downloads (filename + body shape — header row, seeded data rows, no user_id leak in JSON) + Backup ZIP magic-bytes wrapper check + Backup ZIP interior shape (manifest.json + profile.json + runs.json + routes.json all present, manifest carries a version key) + truncated-export disclosure (a `complete: false` response swaps "Export ready" for "Export ready, but partial — N runs of M" and leaves a persistent shortfall notice on the page; a complete one renders no notice)
    preferences.spec.ts        — theme, units, pace format, map style (each save round-trip)
    privacy-zones.spec.ts      — /settings/preferences privacy-zones CRUD: service-role plant a zone via user_settings.prefs.privacy_zones, reload, verify the zone-row renders with seeded coords + radius, click Remove + Save → reload → zone gone from UI AND prefs blob; empty-state copy when prefs has no zones. The MapLibre tap-to-add picker isn't drivable in Playwright, so the seed path is via service-role; the share-time guardrail is covered separately in cross-cutting/privacy-zones.spec.ts
    integrations.spec.ts       — Strava, parkrun, Garmin (list render + parkrun connect/disconnect round-trip + Strava OAuth-redirect path)
    devices.spec.ts            — current-browser row + "This device" badge + inline label edit round-trip
    licenses.spec.ts           — open-source license list
    upgrade.spec.ts            — Pro pricing, RevenueCat checkout
  share/
    run.spec.ts                — /share/run/[id] anon + authed-non-owner view; private-run not-found for anon; sign-up CTA click-through; run-meta render
    route.spec.ts              — /share/route/[id] anon view
    badge.spec.ts              — /share/badge/[id] share-page chrome: header logo + footer home/sign-in links on both the found and not-available states
  u/
    profile.spec.ts            — /u/[id] (self vs cross-user view, Followers + Following tab list rendering + click-through)
    notifications.spec.ts      — /u/[me]?tab=notifications inbox: list renders, Mark all read empties Unread filter
  cross-user/                  — multi-context (two browsers, two users)
    kudos.spec.ts              — alex kudos runner, reload persists, rescind
    comments.spec.ts           — top-level + nested-reply round-trips
    run-detail-non-owner.spec.ts — /runs/[id]'s NON-OWNER branch (issue #666): alex opens runner's PUBLIC run on the canonical signed-in surface, the run renders with owner attribution, kudos + the comment composer work (DB row asserted, author = alex), the branch POSTs to clip-public-track with the run id (the observable that proves the track is not taken from the owner's direct Storage path), and no visibility chip / Edit / Delete-run control renders. A PRIVATE run by the same owner still lands on not-found — entitlement is a `public_runs` row, not "not mine"
    follows.spec.ts            — morgan follows runner, counter increments, unfollow
    notifications.spec.ts      — kudos → bell badge update + popover entry
    event-register-refusal.spec.ts (clubs/) — what a BUYER reads when `events-checkout` refuses after the click, which had no spec: `event-paid-register.spec.ts` covers only the states the page works out for itself before it (sold out / sales closed from the pure `registrationOpen` helper). Stubs the function at the network layer and drives `event_full` / `sales_closed` / `host_cannot_take_payment` / an unrecognised 500, asserting each reads as its own sentence, that the host-capability refusal is NOT the retryable copy, and that nothing renders the string supabase-js actually throws. Found the live defect: `functions.invoke` reports every non-2xx as a FunctionsHttpError whose message is the fixed "Edge Function returned a non-2xx status code" (the `{error: '<code>'}` envelope rides on `context`), and the page toasted `e.message` — so every refusal read as that internal sentence
    strava-sync-refusal.spec.ts (settings/) — the third site of the same defect: /settings/integrations interpolates a failed sync or connect into "Strava sync failed: {error}", a slot written to carry a reason, and every non-2xx filled it with supabase-js's fixed invoke sentence. `integrations-connected.spec.ts` presses Sync only over the success path. Stubs the function at 503 `strava_not_configured` (its own sentence now), 502 `refresh_failed` (the revoked-token case, reported as itself), and a 500 with an UNREADABLE body — the fail-closed leg, which pins that a missing envelope falls back to the caller's own wording rather than putting the internal sentence back. A fifth case covers DISCONNECT, which rides the same function on purpose (it revokes at Strava's end and wipes the vault rows rather than doing a bare DELETE) into the same reason-shaped slot — found by the `src/lib/edge_function_error_guard.test.ts` source guard rather than by reading, which is the argument for the guard
    payouts-not-configured.spec.ts (settings/) — /settings/payouts Connect-onboarding refusals. The page intends an INFO toast on a keyless build and a red error otherwise, choosing by pattern-matching the thrown message; `event-paid-register.spec.ts` walks the button but only asserts no navigation, so which answer appeared was never checked — and it was the wrong one, because the pattern was applied to the same fixed invoke string. Asserts the info branch on `stripe_not_configured`, the error branch carrying a machine code on a real failure, and that neither leaks the invoke internals
  cross-cutting/               — span >1 page or >1 session
    ai-consent-lifecycle.spec.ts — the versioned AI-processing consent record end to end, against a saga user who genuinely has none (every other AI spec either mocks the endpoint or runs as a seed user `seed.sql` already stamps): /coach RENDER-gates the chat behind the first-use disclosure and no `/api/coach**` request fires before the click; accepting records the CURRENT version server-side, not the Coach's own minimum; withdrawing on /settings/account clears both consent columns (Art 7(3)) and the /coach gate re-engages on the next visit; and with the record withdrawn the UNMOCKED `/api/coach/route-describe` really 403s, so /routes/[id] shows the consent-gap copy pointing at Settings rather than the retryable "try again", with the L1 templated sentence still rendered beside it. Each test sets its own precondition through the service role, so no test depends on the one before it
    health-consent-withdrawal.spec.ts — the Art 7(3) withdrawal of the health-data consent driven through the real Save on /settings/account, which no other spec performs: `settings/account.spec.ts` and `settings/preferences.spec.ts` both restore the box and leave the write unmade, because a real withdrawal against the shared seed user would erase USER_A's demographics for the whole shard. A saga user makes the destructive half safe. Asserts both directions at once — the Art 9 set goes (stamp, gender, height, the whole `body_metrics` weight series, and the `user_settings.prefs.date_of_birth` MIRROR the health-use surfaces actually read), while `user_profiles.date_of_birth` STAYS, because the age record backs the under-18 discoverability floor and carries no consent term (§ 718 / § 721). Second test reads the withheld state back off a real page: with a date on record and the stamp gone, /nutrition/targets says "Needs health-data consent" rather than printing the age or claiming "Not set" about a date the runner did set
    architecture-guards.spec.ts — Node-side static guards: every authed +page.svelte that fetches in onMount waits for `auth.user` (catches the auth-race pattern that bit 9+ pages); login snapshots `return_to` at mount; /live/[id] data path runs independently of map.on(load); pushPing guards every map.* call with `if (!map)`
    billing-issue-banner.spec.ts — global "Update your card to keep Pro" banner end-to-end: service-role plant `user_profiles.billing_issue_at`, banner visible on /dashboard with relative-days copy ("3 days ago"); no flag → no banner; "today" copy for a flag set within 24h; non-service-role UPDATE of billing_issue_at raises 42501 (lock_subscription_columns defence in depth — prevents client-side suppression of the banner)
    job-tier-priority.spec.ts  — tier-aware job-queue scheduling. Plant runner (free) + morgan (pro) runs back-to-back; assert morgan's map_match `scheduled_at` is at least 25 s earlier than runner's (the helper offsets free by +30 s). Direct unit test of the `job_scheduled_at_for_user(uuid)` helper (pro → ≈ now, free → now+30s, unknown user → free fallback). Manual rematch via `enqueue_run_rematch` RPC also honours the same tier offset (pinned because rematch is a separate enqueue site)
    jobs-stuck-alert.spec.ts   — read-only operator surface for stuck jobs (decisions.md § 58 contract). Idle queue → stuck_count=0; a planted job with locked_at 6 min ago surfaces via both `find_stuck_jobs()` and `jobs_stuck_summary()`; custom threshold arg honoured (2-min-old job is stuck under `interval '1 minute'` but not under the 5-min default); the pg_cron `jobs-stuck-alert` schedule is registered + active with cadence `*/10 * * * *`
    auth-walls.spec.ts         — RLS leak checks (cross-user run + private-club isolation), anon-redirect walks (/dashboard, /history, /coach, /plans, /clubs, /settings/account), ?return_to round-trip
    behaviors.spec.ts          — small focused checks: kudos+rescind UNIQUE round-trip, display-name UI edit verified at the DB layer, club post round-trip shape pinned via DB read, public_runs view contract (anon visibility limited to is_public=true rows)
    cross-user-mutations.spec.ts — User B cannot UPDATE / DELETE User A's runs / routes / kudos / comments via supabase-js, and a non-member cannot INSERT a club_post into a private club (RLS UPDATE/DELETE/INSERT pinned end-to-end at the wire, not just SELECT)
    db-constraints.spec.ts     — UNIQUE / CHECK / partial-index / FK walks (training_plans_one_active, run_kudos PK, user_follows PK, club_members PK, clubs.slug, runs.source enum, routes.surface enum, club_members.role enum, subscription_tier narrow union, plan date-range CHECKs, route_reviews.rating range, event_results.finisher_status / duration_s, training_plans.status, notifications.kind, device_tokens.platform, plan_workouts.week_id FK, club_members.user_id FK to auth.users) + lock_subscription_columns paywall-bypass guard
    kudos-concurrency.spec.ts  — fire 5 simultaneous run_kudos inserts for the same (user, run) pair via supabase-js; assert exactly one row lands and every non-winner is either silent (supabase-js swallowed the dedupe) or 23505. A regression that surfaced 4xx-other-than-23505 here would crash the optimistic toggleKudos UI handler
    paywall-wire.spec.ts       — `/api/coach` daily-limit gate via real user JWTs: free user planted at message_count=2 → 3rd request 429s with `error: 'daily_limit'`, `tier: 'free'`, `limit: 2`; pro user at the free cap (2) doesn't 429 (Pro has a higher 10/day cap); pro user planted at message_count=10 → 11th request 429s with `tier: 'pro'`, `limit: 10`; anon POST → 401. Auto-skips when `BYPASS_PAYWALL=true` in `apps/web/.env.local`
    tier-cache-resilience.spec.ts — companion to paywall-wire: where that pins the static states (free vs pro), this pins the *dynamic* property — flip morgan free → pro mid-session via service-role write and watch the very next /api/coach request observe the new state using the SAME JWT (no re-sign-in). Catches a regression that would cache subscription_tier at sign-in or in a module-level memo
    public-runs-view.spec.ts   — `public_runs` view privacy-strip contract end-to-end: plant a public run with every strip-listed metadata key (24 keys: strava_id, garmin_id, plan_workout_id, race_name, perceived_effort, …), read as anon via supabase-js, assert each strip-listed key is absent and the retained keys (activity_type, avg_bpm) survive; anon CANNOT read is_public=false rows
    runs-external-id-dedupe.spec.ts — `runs.external_id` UNIQUE constraint resilience: 5 simultaneous service-role inserts with the same external_id must produce exactly one row, every loser raising 23505 (not a different error code); a second post-success replay also gets a clean 23505. Pins the import-pipeline backstop for Strava manual-sync + strava-webhook racing the same activity
    storage-boundaries.spec.ts — `runs` Storage bucket RLS via supabase-js: anon cannot download a private run's track via the bucket directly; cross-user authed download is denied; cross-user upload to another user's `{user_id}/` prefix is rejected. Defence-in-depth on top of the row-level RLS
    strava-import-guards.spec.ts — `strava-import` Edge Function pre-side-effect input validation (10 tests): missing Authorization → 401; missing/invalid action → 400; connect-action shape errors (code, scope, redirect_uri) → 400 with per-branch error code; **fail-closed-when-misconfigured**: with STRAVA_ALLOWED_REDIRECTS unset the EF returns 503 strava_not_configured rather than falling through to "allow any redirect"; sync lookbackDays out-of-range → 400. This lane can pin only that one allowlist branch — its edge runtime carries no `STRAVA_ALLOWED_REDIRECTS`, so every `connect` posted here short-circuits at the 503 whatever `redirect_uri` it claims. The accept and the not-in-the-list branches are pinned pure in `_shared/redirect_allowlist.test.ts`
    realtime.spec.ts           — service-role INSERT into club_posts pushes through Realtime to a subscribed /clubs/[slug] page (postgres_changes filter + debounced reload)
    smoke.spec.ts              — surface smoke: every key page mounts past its loading shell with one stable selector visible (dashboard / feed / runs / routes / plans / clubs / coach / all settings tabs / detail pages / anon landing+login variants)
    surfaces.spec.ts           — detail-surface checks (back-link nav, owner-only affordances, tab switches, sidebar nav round-trips)
    triggers.spec.ts           — enroll_club_owner, notify_run_kudos, notify_run_comment, notify_user_follow, notify_run_comment_reply — all five fan-out triggers verified via service-role DB read after either a UI action or a service-role plant
    sign-in-out.spec.ts        — form sign-in + popover sign-out (uses ephemeral session, see preamble)
    navigation.spec.ts         — sidebar collapse persistence
    reflow-narrow-viewport.spec.ts — WCAG 1.4.10 guard: 16 routes (15 signed-in + the anon cookie notice) at 300, 320 and 360 CSS px, asserting `documentElement.scrollWidth <= clientWidth` — the derivation, never a pixel (§ 500), which is also the only form that tolerates a legitimate inner scroller. The 300 px row is renderer headroom, added after CI's Linux fonts measured three routes 12-20 px wider than macOS and failed a guard that passed locally (§ 535 amendment); every guarded route's narrowest fit is at or under 280 px, so it leaves room rather than pinning the layout. Population-asserted twice per § 534 (a visible control or heading inside `#main-content`, plus a node-count floor), because a redirect stub or a spinner fits any viewport; a heading alone does not work — `/routes` and `/plans` carry their title in the surface-tab strip and have no `h1`. Proved to fire: reverting `.main-content { min-width: 0 }` fails 13 of 15, the page-gutter token override alone fails 4, and each of nine later per-route fixes alone pushes its own route's narrowest fit back above 300 px. **Measure against a freshly seeded stack** — the e2e globalSetup only signs users in, so a long-lived local database renders different content (the fresh seed mounts TrendDeltasCard on /dashboard, 591 nodes vs 509) and hid three failures
    reflow-seeded-routes.spec.ts — the same WCAG 1.4.10 derivation over the five families that render from NO seed and so could not be measured by the sweep above: `/live/[id]`, `/live/event/[id]/[instance]`, `/fundraisers/[id]`, `/segments/[id]` and a POPULATED `/messages/[[id]]`. Shares the measurement contract via `fixtures/reflow.ts` so the two specs cannot drift into two definitions of "conforms". Fixtures are built at RUNTIME through the service-role client and torn down in `finally` — not by growing `seed.sql`, which would need a `db reset` (destructive on a shared local stack) and whose live/stale/finished rows decay against the wall clock. Each route asserts a populated locator per § 534 (`course-progress`, `li.runner` ×3, `button.thread`, `a.athlete`, `.donation-feed .row` ×3), because a spinner or not-found card fits any viewport and would pass falsely. Fixture gotchas are documented at each call site: the live run needs a projected end in the FUTURE or `isFinishedStale` short-circuits before the backlog loads; ping coordinates must clear the seeded Melbourne privacy zone or the triggers coarsen them away; a `fundraisers` insert needs an `instructor_payout_accounts` row first (the `host_can_take_payment` BEFORE-INSERT trigger); and the global segment is READ from the curator-owned catalogue, never created. **NOT YET EXECUTED** — authored while Docker on the workstation was wedged after a disk-exhaustion event, so the local stack never started; quote no figure from these five routes until it has passed CI (decisions § 543)
    privacy-zones.spec.ts      — owner Share guardrail when track crosses a zone (cancel + confirm paths) + cross-user clipping via the clip-public-track EF
    cross-feature.spec.ts      — runs↔goals (goal-card 100%) + runs↔plans (day-cell + progress ring) + cross-user kudos→owner /runs/[id]
    privacy-zone-clipping-journey.spec.ts — the same zone-straddling run across all FIVE render surfaces: owner-full via the owner JWT + owner /runs/[id] DOM, clipped on /share/run/[id], clipped identically in the /u/[id] run modal, coarsened-not-precise in live_run_pings, and (SURFACE 5, issue #666) clipped identically on the NON-OWNER branch of /runs/[id]
    run-visibility-propagation-journey.spec.ts — private → public → private across feed / profile / share / the follower's /runs/[id]; the /runs/[id] leg is asserted both ways (not-found while private, the run once public, not-found again after re-privatising) so revocation is pinned as well as grant
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
- **`simulate.insertRun(...)`** — service-role helper for actions only mobile/watch can do on the canonical web stack ([decisions § 24](../architecture/decisions.md)). Currently: `insertRun` (with optional gzipped track upload to the `runs` Storage bucket — mirrors the recorder's sync path), `deleteRun` (with track cleanup), `insertEvent` / `deleteEvent` (used by the `clubs/event-rsvp.spec.ts` round-trip and any future saga that needs an event row without driving the create-event modal — `insertEvent` accepts `recurrence_freq` / `recurrence_byday` / `recurrence_until` for planting recurring events in one call), `insertKudos` / `insertComment` (engagement on a planted run — used by `runs/social.spec.ts` and `u/notifications.spec.ts` to fan out via the notify_* triggers without driving the UI), `insertLivePings` (plant a sequence of `live_run_pings` rows so the /live/[id] spectator page hydrates from a backlog without spinning up a real broadcaster — used by `live/spectator.spec.ts`; the real-hub `live/spectator_websocket.spec.ts` uses `fixtures/livehub.ts pushLivePing` instead), `setUserSetting` / `clearUserSettingKey` (user_settings.prefs upsert when the canonical UI requires a hard-to-drive interaction like the privacy-zone MapLibre picker), `setClubMemberStatus` (flip a club_members row's status — used by `clubs/approval.spec.ts` to restore alex to pending after the runner-approves test), `clearNotifications` / `setNotificationsUnread` (the notifications table has no automatic cleanup, accumulates across runs, and the bell badge caps at "9+" — tests that assert exact unread counts must clear or normalise first). Each helper bypasses RLS via the service-role client; keep the surface narrow — anything a real user could do via the web UI through a non-canvas interaction should go through the UI in the saga, not here.
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

### `apps/web/src/lib/segments/catalogue_browse.test.ts` — 41 tests (13 added)

The catalogue browse shaping, plus a new `fold` block. Every vector in that block is one the Dart twin's hand-written fold table answered differently: Vietnamese tone marks over a barred D that must NOT fold, Greek breathings, the two sigmas, the pinyin tone letters, Cyrillic, a spacing diacritic deleted outright, a combining mark outside the five blocks the old table knew, a Georgian Mtavruli capital, a CJK compatibility ideograph, a Hangul syllable decomposing to jamo, the stroke and ligature letters that stay unfolded, and the widening property the whole helper rests on. The Dart suite carries the same 14, so the pair's agreement is visible rather than asserted ([decisions § 852](../architecture/decisions.md)).

### `apps/web/src/lib/segments/catalogue_fold_table.test.ts` — 5 tests

The rail between the SHIPPED web `fold` and the generated table the phone reads. `scripts/check_catalogue_fold_table.mjs` compares the committed table with what the generator renders, which cannot see the generator and web's `fold` drifting apart — both spell the fold out, only one reaches a browser. So this parses the committed Dart table, replays the algorithm `catalogue_browse.dart` implements over it, and asserts `fold` answers identically per entry and end to end over a corpus of real names. Deliberately one-directional: it does not sweep the code space for MISSING entries, because that is what a Node whose ICU has moved produces and the drift guard is the one that knows to say "regenerate" ([decisions § 855](../architecture/decisions.md)). Opens by asserting the table parsed into thousands of ascending, parallel entries, so a file it stops being able to read fails rather than passing over nothing.

### `apps/mobile_android/test/catalogue_browse_test.dart` — 41 tests (14 added)

Mirror of the web suite above, vector for vector. Twelve of the fourteen fail against the table this replaced — measured by running the old fold over the same inputs — and the two that pass are the invariants it got right: a combining mark inside the ranges it knew, and the letters with no canonical decomposition, which must stay unfolded on both platforms. One extra case has no web analogue: the generated table's own shape, since the Dart side binary-searches it and an unsorted table would not fail loudly, it would quietly stop folding some letters.

### `scripts/check_catalogue_fold_table.test.mjs` — 13 tests

The accent-fold drift guard, and the generator under it. Pins that the two causes of a mismatch are reported as different sentences — a hand-edit or a stale commit against a Node whose Unicode tables have moved — because the second reaches a PR that touched none of it, and sending that reader hunting for an edit they did not make wastes the run. Plus: a render that lost its version stamp is itself a finding (without it the guard cannot tell the causes apart), the committed table is what the generator renders, its keys are strictly ascending and parallel to its values, the Hangul arithmetic reproduces NFD across all 11,172 syllables independently of the generator's own assertion, the fold answers the divergence classes and leaves the undecomposable letters alone, and `dartLiteral` emits ASCII only.


### `scripts/check_infra_iam.test.mjs` — 77 tests

The IAM rails under `infra/`, which no test had reached. `infra/github-oidc/`
mints the only two identities anything outside the AWS account can assume, and
the guard it now has ([decisions § 889](../architecture/decisions.md)) is
measured the way that file's failure modes actually occur: a fixture faithful
enough to carry the interpolated ARNs, the prose comment above an `Action` list
and the two-role shape, asserted to pass first, so every case below is the
mutation and not the fixture. `StringLike` for `StringEquals`; a `*` in the sub;
a `:ref:`-shaped and a `:pull_request`-shaped sub; an unpinned `:aud`; a second
provider audience; a role name disagreeing with its `Environment` tag; a
`github_repo` variable given a default. Then the lockstep: renaming the GitHub
environment on the workflow side alone — verbatim the `web@1.0.3` failure —
reported from BOTH directions, and the two environments crossed over each other.
Then scope: `s3:*`; a new action on `Resource "*"`; an exemption nothing uses; a
preview role reaching a prod bucket; an ARN wildcarding its account field; a
Lambda the module declares that the deploy policy omits, and a grant naming a
function that does not exist. Then reachability: a Function URL left at `NONE`,
the plain `lambda:InvokeFunction` grant dropped (issue #590), a grant open to any
distribution. Two closing cases run the whole comparison against the COMMITTED
tree and assert the parsers reached it — a passing run that checked almost
nothing is not a pass.

### `scripts/check_infra_coverage.test.mjs` — 81 tests

What in `infra/` is watched by nothing ([decisions § 890](../architecture/decisions.md)).
Two halves, each mutated on its own. Stack coverage: a new directory missing from
the terraform workflow's `stack:` matrix, one missing from `dependabot.yml`, a
matrix entry and a dependabot entry naming directories that are gone, an
exemption that is no longer needed and one for a directory that no longer exists,
and a matrix the parser can no longer read — which must fail rather than certify
nothing. Alarm coverage: a Lambda with no p95 alarm (the real `osrm-proxy` gap),
one with no error-rate alarm, a new Lambda with neither, either distribution
alarm removed, a classifier that stopped matching, and an empty function list —
the last two because a guard that resolves nothing reports every subject as fine.
The parsers are exercised separately, including the `for_each`-through-a-locals-map
resolution that makes the five share Lambdas read as five. One case runs the real
script end to end through `execFileSync` against a copy of `alarms.tf` with the
`osrm-proxy` p95 alarm stripped, asserting the process exits non-zero: the guard
is shown to fail on the exact regression it was written for, exit code and all.

### `infra/modules/web-stack/functions/www_redirect.test.mjs` — 14 tests (new)

The first tests over `infra/modules/web-stack/functions/`. The CloudFront Function there is associated with every cache behaviour on the distribution, so it is the first code any visitor, crawler or API client touches, and nothing had ever executed it — [§ 757](../architecture/decisions.md) put it in a tsc program, which proves it compiles and cannot tell a redirect that fires from one that silently does not. There is no module system at the edge, so the harness evaluates the source and pulls `handler` out of the resulting scope, which also pins that the file declares a top-level `function handler` rather than something the runtime could not call. Fourteen cases against real viewer-request events: the apex redirect with path and query preserved, a non-www passthrough returning the request object itself, a missing Host header, repeated and valueless query parameters, an already-encoded path forwarded verbatim, a traversal-shaped and a protocol-relative-looking path both staying on the apex, a host that merely contains `www.`, and the two that failed before the fix — a mixed-case `WWW.` host escaping the redirect entirely, and a POST/PUT/PATCH/DELETE answered with a 301 that clients rewrite to a bodiless GET. See [decisions § 894](../architecture/decisions.md). Runs as its own step in `parity-types` with its own `::error::`.

### `apps/web/src/lib/share/share_head_origin.test.ts` — 2 tests

Which origin the five share Lambdas resolve `PUBLIC_SITE_URL` to, and what the wrong fold emits. A source register requires every `PUBLIC_SITE_URL` read under `apps/web/lambda/` to go through `siteOrigin`, with a population floor so an empty walk fails rather than reporting a clean tree; reverting one Lambda to `?? DEFAULT_SITE_URL` fails it by name. Two behavioural cases drive the head builders the Lambdas actually call — the first asserts what a blank origin produces (a root-relative `og:url` and `og:image`, the same shape `share_url_source_guard.test.ts` bans in the sources), the second that `undefined`, `null`, `''`, `'   '` and a trailing-slash origin all come out absolute and single-slashed. See [decisions § 895](../architecture/decisions.md).

### `apps/web/src/lib/coach/coach_lambda_handler.test.ts` — 17 tests (new)

The production coach Lambda's own wrapper layer, which `handler.test.ts` structurally cannot reach: which sub-path a request dispatches to, which of the three byte caps that sub-path gets, the base64 decode, the custom auth header, the hardcoded `bypassPaywallEnabled: false`, and the outer fail-closed envelope. The module reads a runtime-provided `awslambda` global at import time, so the stub is installed before a dynamic import; every case stops before a network call. Two cases fail without the fixes they pin — a non-POST reaching the core, and a sub-dispatcher re-deriving its response from a parsed copy of the core's body. The rest pin what was right but unproven: each cap measured in bytes rather than `String.length`, the decode firing on the base64 flag and only on it, the JWT read from `x-supabase-authorization` and never `Authorization`, the provider check not gating the route sub-paths, and a missing env var answering a generic 503 that does not name itself. A fourteenth pins the [§ 898](../architecture/decisions.md) gate: `COACH_PROVIDER=openai` with no `OPENAI_BASE_URL` refuses before the daily-quota increment, and hands over to the core once one is configured — so the case shows a gate rather than a blanket refusal of the provider. See [decisions § 896](../architecture/decisions.md).

### `apps/web/src/lib/routes/generate_lambda_handler.test.ts` — 6 tests (new)

The generate-route Lambda's wrapper, measured the same way. The method gate (which fails without the fix), the 4 KB cap against decoded bytes including the multi-byte case, the base64 decode shown to be flag-driven in both directions, that a well-formed POST reaches the CORE (the 501 is the core's, so the wrapper handed over rather than answering for it), and that every refusal is parseable JSON with a JSON content-type. See [decisions § 896](../architecture/decisions.md).

### `apps/web/src/lib/lambda_log_hygiene.test.ts` — 5 tests (new)

What the eight production Lambdas may put in a CloudWatch line. A per-handler table declares which `event.<field>` its log lines may name — the five share Lambdas declare `rawPath` (a share path is a public URL naming a public entity), the other three declare nothing, and a handler absent from the table fails rather than defaulting to permissive. The second rule requires every log line to be a literal message plus object literals, so no caught value is spread whole. Both walk the sources with a top-level argument splitter that tracks bracket depth and string state, both carry a population floor, and both were checked to discriminate: `path: event.rawPath` added to osrm-proxy's catch fails the first by name (that path *is* the runner's waypoint coordinates), and `console.error('…', e)` restored in the coach's stream pump fails the second. See [decisions § 897](../architecture/decisions.md).

---

## Suite totals after the #789 coverage round (2026-08-31)

Measured on the merged branch, not transcribed from the six slice reports. Each
lane's own runner produced these numbers; the pgtap and Flutter figures are the
whole suite, not the added files.

| Lane | Command | Before | After |
|---|---|---|---|
| Web unit | `npm run test:unit --workspace=apps/web` | 4413 | 4508 |
| Edge Functions (Deno) | `deno test --no-check supabase/functions/` | 618 | 785 |
| Edge Functions (Deno), round 31 | `deno test --no-check supabase/functions/` | 861 | 879 |
| pgTAP | `supabase test db --local` | 2242 in 265 files | 2406 in 272 files |
| Repo guards | `node --test 'scripts/*.test.mjs'` | 556 | 613 |
| Backend guards | `node --test 'apps/backend/scripts/*.test.mjs'` | 124 | 128 |
| Watch sim (python) | `python3 -m unittest discover -s apps/custom_watch/sim` | 25 | 50 |
| Go worker | `go test ./...` | — | +117 test funcs / 235 cases |
| Flutter (android) | `flutter test` | — | 6750 |

Three mutation guards back these rather than the counts alone.
`check_edge_function_test_vacuity.mjs` reports 785 killed, 0 survived, 0
unmeasured — it caught three of the round's own new cases as vacuous
([decisions § 788](../architecture/decisions.md)'s second costume, an equality
between two of the subject's own outputs) and 15 more as unmeasured, where a
top-level dereference made the file throw during load and score as "not
measured" rather than "not killed". `check_pgtap_refusal_assertions.mjs`
reports 179 refusal assertions mutation-checked across 272 files, 5 survivors,
all 5 expected. `check_served_envelope_mutations.mjs` covers the tier neither
of those can reach — the handler-envelope cases, whose subject is a separately
booted `functions serve` host rather than an imported module — and reports 23
cases against 20 single-gate mutations of the SERVED tree, 0 survivors, 0
unmeasured ([decisions § 815](../architecture/decisions.md)).

The one pgtap failure on this branch, `donations_status_lock_test`, is
environmental and pre-existing: it fails identically on the untouched base
commit (265 files / 2242 tests, same file, same `planned 19 tests but ran 0`).
The workstation CLI is 2.109.1 against CI's pinned 2.84.2, and the two disagree
about `service_role` EXECUTE on `fundraiser_totals`.

## Round 31 — the guard tier's own coverage (2026-09-02)

Nothing guards the guards. This round's subject was the ~30 `scripts/*.test.mjs`
suites themselves: for each of the highest-blast-radius ones, the exact
violation it exists to catch was introduced into its REAL subject — the
committed `ci.yml`, `CLAUDE.md`, the syncer table, `.tool-versions`,
`package.json`, `deno.lock`, the fold table, the ligature vocabulary — and the
guard required to fail. Repo guards: **830** tests (up from 788); the two composite-action suites: **19** (up from 6).

Guards mutation-checked against their own subject and confirmed capable of
failing, with no defect found: `check_parity_pair_registry` (all four
properties — a pair dropped from either registry, a dead path, a path the two
registries disagree about), `check_shared_constants` (a bent rail on the web,
Dart and SQL sides of three different constants), `check_workflow_binaries` (an
`npx` of an undeclared binary), `check_root_scripts` (a script `cd`-ing into a
missing directory), `check_pnpm_overrides` (a CVE pin deleted), `sync_deno_lock
--check` (a drifted workspace section), `check_dead_dependencies` (an unread
dependency), `check_catalogue_fold_table` (one code point bent, and the Unicode
version claim bent), `web_icon_font` (a shipped ligature removed from the
vocabulary), `tsconfig_coverage` (a compilable `.mjs` outside every root).

Three that could not fail, each fixed with the case that pins it:

### `scripts/check_ci_diagnostics.test.mjs` — 36 tests (10 added)

Rule 3 asserts every job is named in the `CI gate` aggregator's `needs:` list,
on the premise that the aggregator passes only when every needed job passed or
was skipped. That premise lives in a shell block inside the gate job and nothing
read it. Three edits to that block leave rule 3 green while the single required
status check reports success over a red repository — all three applied to the
committed `ci.yml` and confirmed to pass the guard: removing the job-level
`if: always()` (GitHub then SKIPS the gate on exactly the runs it exists to
block, and a skipped required check holds nothing), replacing the `run:` with an
`echo` (the exit status stops depending on the 31 jobs), and deleting the
`exit 1` (the failure prints under a green check). Rule 4 now reads the gate
itself; the eight branches it added are each mutation-checked, including the two
block-boundary cases the first cut of the tests could not reach.
[decisions § 909](../architecture/decisions.md).

### `scripts/check_twin_claims.test.mjs` — 15 tests (new)

`check_parity_pair_registry` cross-checks CLAUDE.md against the syncer table in
both directions, and both can agree perfectly about a pair that is in NEITHER —
the `turn_cues` (§ 641) and accent-fold (§ 760) failure, which CLAUDE.md names
outright. The new guard takes the SOURCE as its subject: a header declaring a
cross-platform twin must name a file that exists and a pair some syncer row
carries. Over the tree that is **105 declarations, 13 violating** — nine pairs
declared in both headers and registered nowhere, five headers naming a path the
counterpart moved out of. They sit in `KNOWN_GAPS`, which fails when an entry
stops being a violation, so the register can only shrink; the two open sets are
in `followups.md`. Run as a fifth step of `parity-matrix`.
[decisions § 910](../architecture/decisions.md).

### `scripts/check_toolchain_pins.test.mjs` — 74 tests (7 added)

`.tool-versions` pinned `nodejs 22` while all 21 `actions/setup-node` steps say
24, and nothing in the repo read the file. Its commented lines carried the
template's rust / flutter / golang / terraform versions against the repo's real
ones. Two rails added — every setup-node step names a `node-version` and all
agree, and every `.tool-versions` line (commented included) matches the pin the
repo enforces — and writing the first surfaced a blind spot in the Flutter rail
it was copied from: both anchored on the `- uses:` marker form, and `audit.yml`'s
step is written `- name:` then `uses:`, so the first cut found 20 of 21 sites and
missed the one whose comment claims it matches the rest. 54 steps in the
committed workflows use that form. [decisions § 911](../architecture/decisions.md).

A third rail added 2026-09-02: every `denoland/setup-deno` step names an EXACT
`MAJOR.MINOR.PATCH` and they all agree, with `.tool-versions`' `deno` line held
against it. Both steps took `v2.x`. Unlike Node, a major is not enough — a Deno
MINOR carries new `deno check` diagnostics, which is the failure this rule is
about — so the seven cases include the five channel spellings (`v2.x`, `2.x`,
`2`, `v2`, `canary`) refused one by one, the exact form accepted with and
without its `v` and quoted, a step naming no version, two workflows disagreeing,
the vacuity case, a version read off a neighbouring step, and the
`.tool-versions` half in all three states. [decisions § 965](../architecture/decisions.md).

### `.github/actions/install-playwright/verify_chromium.test.mjs` — 9 tests (new)

The other composite action's shell, which had never been executed by anything.
Its verification + apt fallback lived inline in `action.yml`, where nothing
could drive it, and its apt branch runs only after a launch has already failed —
so the whole repair path shipped unrun. Extracted to `verify_chromium.sh` on the
sibling's pattern and driven with stub `node` / `pnpm` / `sudo` / `timeout` on
PATH. Two cases assert the property the code's own comment states and nothing
checked: `install-deps` failing all three attempts still PASSES when the browser
then launches, and `install-deps` succeeding still FAILS when it does not. One
covers a hazard the extraction created rather than found — the apt.conf heredoc
terminator was anchored only by YAML's dedent, and in a `.sh` an indented `CONF`
would swallow the retry loop and the verdict as heredoc content.
[decisions § 912](../architecture/decisions.md).

Two of the nine could not fail when first written, found by mutating the script
they cover: an ordering assertion built on a bare `indexOf` (which answers -1 for
"not found", ordering before everything, so an apt.conf never written read as
"written first"), and a match on the browser's error anywhere in the log, where
the first failed launch has already printed the same text.

### `scripts/check_ci_diagnostics.test.mjs` census — 2 more tests

The census walks three `scripts/` directories, and `.github/actions/` is not one
of them, so nothing asserted either composite-action suite is run at all —
deleting a `workflow-lint` step would have been silent. Every `.sh` under that
directory now needs a same-named `.test.mjs`, and every such suite must be run by
a `ci.yml` job. Both count their subjects first, so an empty walk fails rather
than passing. [decisions § 913](../architecture/decisions.md).

### `.github/actions/start-supabase/wait_for_sidecars.test.mjs` — 10 tests (4 added)

The script exists because the loop it replaced accepted kong's own answer as the
upstream's, and its header names the answer each of its three probes requires.
Only the edge-runtime one was ever driven: the stub answered a fixed 200 to
storage and auth, so neither pattern was asked anything, and a stub that always
says 200 would also have passed with the URLs swapped. Added: kong's own 503 on
the storage path is not storage answering (and short-circuits, so no ready line
can print under a failure); storage's own 4xx IS; a password grant GoTrue refuses
is not auth being ready, which is why that probe is a grant rather than
`/health`; and each probe addresses its own sidecar's path.
---

## Added by the #789 coverage round 31 — web unit lane (2026-09-02)

Five defects, each pinned by the cases that found it. Every assertion below was
mutation-checked: the fix reverted, the case observed failing with the message
it claims, the fix restored, the case observed green.

### `apps/web/src/lib/runs/event_results_csv.test.ts` — 25 tests (3 added)

A chip-timing cell holding only separators. `Number('')` is `0`, so `':'`,
`'::'`, `'  :  '`, `'1:'`, `':30'` and `'1::30'` all parsed as real times and a
finished row carried a 0 s finish that sorts first and stands as the event
record. The suite already pinned the wholly blank cell as an error row, which is
what makes the gap a gap. A second case pins the accepted class as plain decimal
counts — `'0x10'` read as 16 s, `'1e3'` as 1000 and `'+5'` as 5 — while keeping
per-component whitespace tolerated (`'1 : 00 : 30'`), and a third drives the
whole parser so the organiser sees `Row 2 … unparseable`. All three fail against
the pre-fix source. See [decisions § 923](../architecture/decisions.md).

### `apps/web/src/lib/lambda_log_hygiene.test.ts` — 3 tests (1 added)

The two rules, applied one frame down. The Lambda handlers are wrappers whose
job is to call a transport-agnostic core under `src/lib`, and the core is what
catches the provider error and logs it — into the wrapper's own log group. The
new case derives its population by following relative imports from each Lambda
entry point (69 modules, 58 console calls) and fails when an argument is a bare
identifier or member chain, which is the caught value itself. Both offenders it
named on the pre-fix tree — `route_request` and `route_describe`, each doing
`console.error('…', e)` on an Anthropic error whose 400 body quotes the runner's
own typed request — are fixed in the same commit. Carries two population floors
so a broken import walk fails rather than reporting a clean tree. See
[decisions § 919](../architecture/decisions.md).

### `apps/web/src/lib/paged_read_guards.test.ts` — 1 test (new)

Every `.range()` read in the web tree, and whether its ordering is a total
order. PostgREST turns `.range()` into `LIMIT`/`OFFSET`, so a non-unique (or
absent) `ORDER BY` lets a row on a page boundary be returned twice or not at
all. The walker reads each chain backwards over balanced brackets — a naive
slice at the nearest delimiter is cut by the `{ ascending: false }` inside every
`.order()` — blanks comments so prose about a paged read is not read as one, and
follows a closure builder, which is where `fetchRuns` keeps its ordering. On the
pre-fix tree it names six reads: `createBackup`'s runs page (ordered on
`started_at` alone) and its routes page (no order at all, under a manifest
claiming `complete`), both `fetchRuns` branches, and both ZIP importers' dedupe
reads. Population floor of eight `.range()` reads. See
[decisions § 922](../architecture/decisions.md).

### `apps/web/scripts/env_isolation.test.mjs` — 22 tests (3 added)

Two behavioural cases for the route-generation engines the guard had never
watched — a remote `GRAPHHOPPER_URL` / `GRAPH_CYCLE_URL` refused, a loopback
pair accepted — and one coverage case that stops the list being the thing that
has to remember: it walks `apps/web/src` and `apps/web/lambda` for URL-shaped
env reads and fails when one is neither guarded nor declared in
`NOT_ISOLATED_URL_VARS` with a reason. The same case fails an exemption naming a
var nothing reads any more, and one that is both guarded and exempt. Deleting
the two engine entries fails two of the three by name. See
[decisions § 920](../architecture/decisions.md).

### `apps/web/scripts/check_production_env.test.mjs` — 27 tests (6 added)

The release-side mirror. `PUBLIC_SITE_URL`, `PUBLIC_LIVE_HUB_URL` and
`PUBLIC_EXPORT_HUB_URL` are optional — one case pins that a release with none of
them set still passes — but a value that IS set now takes the same
production-URL test the Supabase URL takes: a loopback site origin (which bakes
localhost into the canonical and `og:url` of every prerendered share page), a
loopback live or export hub, and a `TODO-set-me` that is not a URL at all. A
sixth case reads the dev guard's own `KNOWN_ENV_VARS` and fails when a `PUBLIC_`
origin is watched in one direction and not the other. Removing the sweep fails
four of the six. See [decisions § 921](../architecture/decisions.md).

### Lane totals

| Lane | Command | Before | After |
|---|---|---|---|
| Web unit | `npm run test:unit --workspace=apps/web` | 4625 | 4630 |
| apps/web guards | `node --test apps/web/scripts/*.test.mjs` | 86 | 95 |

`npm run check` (svelte-check) reports 0 errors over 2489 files, with the five
pre-existing `state_referenced_locally` warnings in `PlanEditor.svelte` — a file
this lane did not touch. `npm run check:node-types` is clean; it caught an
untyped recursive helper in the new coverage walker that the suite itself ran
green over, `apps/web/scripts` being inside that root under `checkJs`.

## Added by the #789 coverage round 31 — mobile lane (2026-09-02)

Every entry below is a matched web/Dart pair unless it says otherwise: this
lane's subject was the TS-Dart parity surface, so a test added to one side is
a test added to both. Each was mutation-checked — the code it covers was
broken, the failure confirmed to be the one expected, and the change reverted
and re-run green — inside a single script invocation so a timeout could not
strand a mutation.

### `off_route_alert` — the sustained-off-route escalation

Five mirror cases each (`apps/web/src/lib/safety/off_route_alert.test.ts`,
`apps/mobile_android/test/off_route_alert_test.dart`, mirrored to the iOS twin):
a non-finite distance never arms the clock and never spends the once-per-run
latch, over `NaN` / `Infinity` / `-Infinity`; it resets the window the way a
null does; a whole run of unusable readings leaves a later genuine departure
still able to fire; a backwards clock step re-anchors instead of wedging; and a
backwards step shorter than the window does not shorten it either. Four
mutations pinned across the two sides. Web 10 → 15, Dart 12 → 17. See
[decisions §§ 929-930](../architecture/decisions.md).

### Non-finite coordinates at the parser and recorder rungs

`packages/gpx_parser/test/route_parser_test.dart` gains six cases — one per text
format plus the elevation-only degradation — pinning that `double.tryParse`'s
acceptance of the `NaN` / `Infinity` literals no longer reaches a `Waypoint`,
and that one bad point no longer poisons the route's own distance. 38 → 44.
`packages/run_recorder/test/route_helpers_test.dart` gains four, pinning that
the three route-projection helpers answer null rather than `+Infinity` when
every segment projects to NaN, and that a non-finite runner position is refused
on a good route. 29 → 33. Two mutations each, both sides.

### Parity pairs registered after being measured

Nine pairs whose own headers claimed lockstep while no syncer row carried them.
Each was measured with a throwaway differential harness — both halves run over
the same input grid, outputs diffed — before any registration. The harnesses
are not committed (they are one-shot, and the committed mirror tests are what a
future change is graded against); the grids are recorded in
[decisions § 931](../architecture/decisions.md).

| Pair | Measured over | Outcome | Tests before → after |
|---|---|---|---|
| `route_loop` | 5,543 inputs | identical | web 71, Dart 20 → 52 |
| `streaks` | 16,449 inputs | identical | unchanged (22 each) |
| `text_limits` | data pair, third rail already guarded | identical | unchanged (web 3, Dart 6) |
| `column_limits` | data pair, third rail already guarded | identical | unchanged (web 7, Dart 11) |
| `fundraiser_progress` | 225 inputs | identical (one unreachable shape difference) | unchanged (11 each) |
| `calories` | 13,500 inputs | **diverged** | 12 → 18 each |
| `tile_pack` | non-finite bbox corners | **diverged** | 8 → 10 each |
| `readiness` | tie behaviour under both sorts | **diverged** | 11 → 14 each |
| `cycle_plan` | malformed date anchors | **diverged** | 22 → 26 each |

`route_loop`'s two suites still differ in raw count after the Dart one gained
the web battery, and legitimately: web runs nine cases per field coordinate
where the Dart mirror runs five, because three of web's nine (the waypoint
count, the exact start pin and the closing-equals-start check) are one case on
the Dart side and the other two — the radial-seed rotation and the anchor
collapse — are already covered by that suite's own non-parameterised cases. The
differential harness, not the count, is what establishes the two agree.

The four divergent pairs' new cases are the interesting half. `calories` pins
that every input is graded for finiteness and that the result is always a
finite non-negative integer, over a cross-product sweep of eight values of
distance against eight of weight; `tile_pack` that a non-finite bbox corner is
refused rather than yielding an empty pack on one platform and an exception on
the other; `readiness` that a tie in absolute delta resolves to the first
contributor added, including an all-zero three-way tie, and that the tiebreak
does not override a genuinely larger contributor; `cycle_plan` that an
unreadable date anchor makes all four entry points decline rather than one
guessing and the other throwing. Fourteen mutations across the four.

### `e164` — the trusted-contact phone repair

Four mirror cases each: every one of the eleven hyphen-family code points is
folded (the class carried three); the invisible characters a paste carries
(soft hyphen, the zero-width trio, BOM, ideographic and medium-mathematical
space) are folded; a FULLWIDTH parenthesised trunk zero is deleted whole like
the ASCII one, which is the pinning of the structural rule that the two bracket
sets must match; and an unknown separator is still refused rather than dropped.
16 → 20 each, six mutations pinned, and the two halves measured identical over
3,478 inputs. See [decisions § 933](../architecture/decisions.md).

### `csv_run_importer` — mobile only, no web twin

Twelve new cases in `apps/mobile_android/test/csv_run_importer_test.dart`
(mirrored to the iOS twin): negative distance, negative duration and the three
non-finite literals are refused with a message naming the cell, zero stays
legal, every value the registered `ActivityType` rail carries is accepted, case
is normalised rather than refused, and a value `runs_activity_type_check`
cannot hold is refused at import instead of syncing forever on a 23514. 22 →
34. Two existing cases were CORRECTED rather than deleted: both asserted the
old pass-through behaviour on the stated grounds that `public.runs` carries
`distance_m >= 0` and `duration_s >= 0` CHECKs, which it does not — the missing
constraints are filed in `followups.md`. Five mutations pinned; the first pass
left one alive, because the assertion matched the accidental `.round()` throw's
message as well as the deliberate refusal's, and was tightened. See
[decisions § 934](../architecture/decisions.md).

### `strava_importer` and the run-screen layering contract — mobile only

`stravaCsvDistanceMetres`' doc names web's `stravaDistanceMetres` as its
mirror, and that one has guarded on `Number.isFinite` since it was written
while this one used `?? 0` — which catches an unparseable cell, not an unusable
one. Five cases in `apps/mobile_android/test/strava_importer_zip_test.dart`
pin that the three non-finite literals read as 0 in both the raw-metres and the
two-column paths, and that an unparseable cell still reads as 0 so the existing
behaviour is not what changed. 26 → 31, one mutation.

`architecture_guards_test.dart` gains two cases on the L0-L4 contract, both in
the gap between the two guards already there. The existing pair proves the
L0/L1 publish precedes the first effect and that each effect has its own
try/catch; neither can see what a catch DOES, so a `catch (e) { rethrow; }` or
an empty `catch (e) {}` kept the pair count intact while defeating the rule.
All fourteen catches in `_onSnapshot` are clean today and nothing said so. The
first new case reads each catch body brace-matched and requires it non-empty,
reporting, and not rethrowing; the second requires everything after the publish
to sit inside a try/catch, with the publish expression and the debug-only
mirror assert as the two stated allowances — a bare statement dropped between
two try-blocks throws straight out and skips every effect below it. 232 → 234,
three mutations (a rethrowing catch, an empty catch, a bare statement).

### Lane totals

| Suite | Command | Before | After |
|---|---|---|---|
| `off_route_alert` (Dart) | `flutter test test/off_route_alert_test.dart` | 12 | 17 |
| `route_parser` | `dart test` in `packages/gpx_parser` | 38 | 44 |
| `route_helpers` | `flutter test test/route_helpers_test.dart` | 29 | 33 |
| `route_loop` (Dart) | `flutter test test/route_loop_test.dart` | 20 | 52 |
| `calories` (Dart) | `flutter test test/calories_test.dart` | 12 | 18 |
| `tile_pack` (Dart) | `flutter test test/tile_pack_test.dart` | 8 | 10 |
| `readiness` (Dart) | `flutter test test/readiness_test.dart` | 11 | 14 |
| `cycle_plan` (Dart) | `flutter test test/cycle_plan_test.dart` | 22 | 26 |
| `e164` (Dart) | `flutter test test/e164_test.dart` | 16 | 20 |
| `csv_run_importer` | `flutter test test/csv_run_importer_test.dart` | 22 | 34 |
| `strava_importer_zip` | `flutter test test/strava_importer_zip_test.dart` | 26 | 31 |
| `architecture_guards` | `flutter test test/architecture_guards_test.dart` | 232 | 234 |

The web halves of the six shared pairs move by the same counts and are run with
`npx tsx --test` from `apps/web`. The full Flutter suite was NOT run — the box
is 14 GB and the standing rule is targeted files only, so what is claimed here
is what was executed: the twelve suites above, plus the three `import_screen`
suites the CSV change could reach (36 pass) and `packages/gpx_parser`'s and
`packages/run_recorder`'s own. `flutter analyze` reports zero `warning` and
zero `error` on both `mobile_android` and `mobile_ios` (the ~3,455 remaining
issues are all `info`, the acknowledged tech debt). On the web side the FULL
unit suite was run rather than a subset, because six of this lane's changes
touch a web half: `npm run test:unit --workspace=apps/web` is 4657 pass / 0
fail. `check_parity_pair_registry` reports 109 pairs registered identically in
both registries, `check_twin_claims` reports 105 declarations with an EMPTY
`KNOWN_GAPS`, and `check_shared_constants` 40 checks.

## Round 32 — the database tier (2026-09-02)

The sql lane's own runner produced these. `supabase db reset` and
`supabase test db` were both run from this branch's own `apps/backend`, so the
schema under test is this branch's migrations.

### `apps/backend/supabase/tests/runs_physical_quantity_bounds_test.sql` — 16 tests (new)

`runs_distance_m_check` / `runs_duration_s_check` / `runs_elevation_gain_m_check`
(migration `20270704000001`), asserted from the ordinary `authenticated` seat
because the self-owned INSERT policy is the only privilege the exploit needs.
Two of the sixteen pin the Postgres facts the constraint is shaped around —
`'NaN'::numeric >= 0` is true and NaN outranks every real value — so the reason
each bound names NaN cannot be simplified away later. One pins that an infinite
`distance_m` is refused with a 22003 by the `numeric(10, 2)` scale rather than a
23514, which is why that bound carries no infinity term while
`elevation_gain_m`'s bare `numeric` does. The last is the consequence rather
than the constraint: the 5k personal record is the honest run, which is what
goes red when the duration floor is removed. Three mutations killed — the
distance bound reduced to a bare `>= 0` (tests 6, 7, 16), the duration bound
dropped (9, 16), the elevation bound losing its Infinity term (14) — each
restored and re-run green. See [decisions § 939](../architecture/decisions.md).

### `apps/backend/supabase/tests/numeric_bounds_reject_nan_test.sql` — 6 tests (new)

The catch-all behind [decisions § 940](../architecture/decisions.md). It pulls
every single-column numeric CHECK in `public` out of the catalogue, substitutes
the column for `'NaN'` (and for `'Infinity'` where the column's typmod can hold
one), and EXECUTES the expression — so a bound added later in the one-sided
shape fails here rather than joining the list. Two rules: rule 1 grades the
evaluable set; rule 2 requires every numeric column appearing only in a
multi-column CHECK to also carry a single-column one, which is what made
`segments.end_distance_m`'s absence a failure rather than a silence.
`challenges.goal_value` is the one exemption (its bound is window-relative and
cannot be written one column at a time) and is pinned by value in
`challenge_goal_check_test.sql` instead — that suite grew from 9 to 13.

The sweep carries an **operator validation**: before it asks the real schema
anything it creates `public.nan_bound_probe (v numeric check (v >= 0))` inside
its own transaction and requires the sweep to name that column as admitting
both literals. A substitution that had quietly become a no-op would satisfy
every emptiness assertion for free, and the two population floors alone would
not catch it. Four mutations killed: `gym_sets.weight_kg` reduced to a bare
`>= 0` (rule 1 NaN), `segment_efforts.time_seconds` losing only its Infinity
term (rule 1 Infinity), `segments_end_distance_m_check` dropped entirely
(rule 2), and `challenges_goal_ck` losing its NaN term (the by-value pins).

### `apps/backend/supabase/tests/frozen_managed_columns_test.sql` — 16 tests (new)

The eleven managed columns of [decisions § 941](../architecture/decisions.md),
each asserted against the write that reached it, all from an ordinary
`authenticated` session under the row owner's own JWT. Value comparisons rather
than `throws_ok`, because the guard discards rather than refuses — a 42501 on
`shadow_hidden` would tell a hidden account that it is hidden.

Three of the sixteen exist to catch over-reach rather than under-reach, and they
are the ones that make the design falsifiable: the route still has its derived
geometry after the freeze (a guard ordered after the derivation would leave the
route with no line at all), an admin can still unhide through
`admin_unhide_target`, and the club really is unhidden afterwards. Five
mutations killed — the routes trigger dropped, the `user_profiles` trigger
dropped, the clubs trigger reduced to BEFORE UPDATE (the original bug's shape),
the routes guard made SECURITY DEFINER (which masks `current_user` and lets
every caller through), and the clubs guard re-keyed on the JWT role, which fails
the "an admin can still unhide" assertion precisely because every legitimate
writer is a definer function called by an ordinary user's session.

### `apps/backend/supabase/tests/definer_mutator_authorization_test.sql` — 6 tests (new)

The catch-all behind [decisions § 942](../architecture/decisions.md): every
SECURITY DEFINER function `anon` or `authenticated` may EXECUTE and that writes
must name its caller somewhere in its body, because RLS is not consulted for
anything such a function touches. 45 functions in scope, all 45 gate, one
registered exemption (`confirm_safety_contact_by_token`, which authenticates by
an emailed single-use token). No defect found — the value is that the rule is
now enforced rather than followed by habit.

Two of the six assertions are the operator validation, and they point in
opposite directions: the sweep must NAME a planted client-executable definer
mutator that mentions no caller, and must NOT flag `set_run_expected_return`,
which authorizes only inside its own `WHERE` clause. Five mutations killed — a
real function stripped of its `auth.uid()`, the exemption registry emptied, the
vocabulary stripped of `auth.uid` (which fails the do-not-over-flag assertion
too), an exemption whose reason is too short, and a stale exemption naming a
function that does gate.

### Round 32 sql-lane suite totals

| Suite | Command | Before | After |
|---|---|---|---|
| pgTAP | `supabase test db` from `apps/backend` | 2526 in 281 files | 2548 in 283 files |
| Backend guards | `node --test apps/backend/scripts/*.test.mjs` | 147 | 147 |
| pgtap refusal mutation guard | `node apps/backend/scripts/check_pgtap_refusal_assertions.mjs` | 179 assertions / 5 expected survivors | 179 / 5 |

The four new files add 44 assertions between them and none is a refusal in the
guard's vocabulary — every one is a value comparison or a catalogue read, which
is why its total is unchanged.

The one pgtap failure on this branch is `donations_status_lock_test`, which is
the known workstation-vs-CI Supabase CLI image split (2.109.1 against CI's
2.84.2 disagreeing about `service_role` EXECUTE on `fundraiser_totals`) and
fails identically on the untouched base commit.
---

## Added by the #789 coverage round 32 — infra + Lambda tier (2026-09-02)

### `scripts/check_infra_coverage.test.mjs` — 40 tests (15 added)

A third half beside stack coverage and Lambda alarm coverage: the eighteen cache
behaviours on the CloudFront distribution, each of which re-states by hand the
three properties CloudFront inherits between behaviours for none of. Twelve
fixture mutations, each the omission a nineteenth behaviour is copy-pasted into
existence with — no `response_headers_policy_id`, no viewer-request
`function_association`, two behaviours associating different functions, an
`allow-all` viewer policy, a `target_origin_id` naming no declared origin, no
`cache_policy_id`, two different response-headers policies, that shared policy
losing its CSP and losing its `Permissions-Policy`, an origin with no OAC, and an
origin CloudFront may reach over plaintext http. Two more require the guard to
fail rather than pass vacuously when the behaviour list or the whole distribution
comes back unreadable. `parseDistribution` is then run against the COMMITTED
module and required to resolve all four fields on every behaviour, and one case
drives the real script end to end through `execFileSync` against a copy of
`main.tf` with the `/og/run/*` behaviour's headers policy struck off, asserting a
non-zero exit. Mutation-checked a second time against the real Terraform outside
the suite: six edits, six reds, each naming the behaviour or origin. See
[decisions § 949](../architecture/decisions.md).

### `scripts/check_infra_iam.test.mjs` — 41 tests (12 added)

The alias half of origin reachability, plus what the parser was silently
skipping. The fixture module gains the `aws_lambda_alias` and the `qualifier`
lines the real one carries, so it is faithful and every case below it is a real
mutation: a grant that drops the alias qualifier while the Function URL keeps it
(the resource policy then covers the unqualified ARN, not the one CloudFront
invokes — issue #590 one field over), a Function URL qualified by another
function's alias (every alias here is named `live`, so this applies cleanly and
serves the wrong function), and a qualifier naming an alias the module does not
declare. Two more require a block the parser could not attribute to be REPORTED
rather than dropped — a Function URL whose `function_name` is written another way
was `continue`d, and one fewer loop iteration is indistinguishable from one fewer
Lambda. Then the secret-scope rule: a `*_lambda_env` local merging the decrypted
sops map whole, a comprehension carrying no predicate (which looks filtered and
is not), and no sops reference at all, which must fail rather than certify a tree
the reader stopped reading. Two closing cases assert the committed module's
aliases, qualifiers and filters. Mutation-checked against the real Terraform as
well: three edits, three reds. See [decisions §§ 950-951](../architecture/decisions.md).

### `scripts/hcl_lex.test.mjs` — 14 tests (5 added)

`nestedBlocks`, the repeated-block reader the lexer was missing — `nestedBlock`
returns the first match and a CloudFront distribution declares eighteen cache
behaviours and nine origins. The cases pin source order, that a global regex does
not skip the first match, that a block which never closes stops the scan rather
than looping, that an absent header returns nothing, and — the one that matters —
that the scan resumes past a block's CLOSING brace, so a header nested inside a
block it already returned is not counted twice.

### `apps/web/src/lib/routes/osrm_proxy_lambda_handler.test.ts` — 11 tests (new)

The third of the three API Lambda wrappers, and the last one nothing had ever
executed. Eleven cases over what the wrapper owns and the core cannot see: the
GET-only gate (which fails without the `Allow` header this round added), the
`/api/routes/osrm` prefix strip shown by the status it produces (a 501 is the
CORE's answer to an unconfigured engine, which it only reaches once the path has
parsed, where a 400 would prove the strip did not happen), a path outside the
prefix and a missing `rawPath` both refused by the wrapper, a malformed sub-path
refused by the core, the hardcoded `allowDemoFallback: false` for both an unset
and an empty `OSRM_URL` — an unconfigured deploy must refuse rather than relay
the runner's waypoint coordinates, routinely their home, to
`router.project-osrm.org` (issue #198) — an absent `queryStringParameters`
substituted rather than thrown on, and the outer 503 envelope. The
header-source case requires SILENCE as well as a 401: reading `authorization`
instead of `x-supabase-authorization` still yields a token and GoTrue still
answers 401, so the status alone could not tell the two apart, measured. Every
case stops before a network call. Mutation-checked: five edits, five reds. See
[decisions § 953](../architecture/decisions.md).

### `apps/web/src/lib/share/share_lambda_handlers.test.ts` — 5 tests (new)

The four share Lambda wrappers — share-run, share-route, share-recap,
share-badge — none of which any test had ever called, and the routing contract
between them and CloudFront. `share_run_cache_control.test.ts` says driving them
"would require a Supabase fake"; it does not, and that sentence is why four
request-time production handlers were only ever grepped. With the Supabase env
absent every lookup misses, the HTML path takes its not-found branch and the PNG
path renders its generic branded card, and nothing touches the network.

The routing case reads every share `path_pattern` out of
`infra/modules/web-stack/main.tf` rather than listing it, and requires each to be
a path its own Lambda actually routes: a behaviour's pattern and the Lambda's
regex are two independent spellings of one route, and a mismatch answers the
Lambda's JSON 404, which the distribution's 404-to-`/index.html` fallback then
renders as the SPA shell (at 200 until [decisions § 1022](../architecture/decisions.md)
made it answer 404 — the body is still the shell, so the mismatch is still
invisible to a reader and this is still the only thing that catches it). The remaining four pin what the siblings must
agree on and no single file can show — the same five-minute plus
stale-while-revalidate `Cache-Control` on both paths, the asymmetric not-found
contract (a `noindex` HTML 404 for the page, a 200 PNG for the image so a social
unfurl never renders a broken card) with the body checked for a real PNG
signature and the `isBase64Encoded` flag a Function URL binary body needs, the
JSON 404 for a path outside a Lambda's own two routes, and the outer 503
envelope. Mutation-checked: five edits across four different Lambdas, five reds.
See [decisions § 953](../architecture/decisions.md).

### `apps/web/src/lib/lambda_log_hygiene.test.ts` — 5 tests (2 added)

A third rule and a hole in the walk that feeds all of them. The rule: the
identifier holding a credential may not appear in a log line's arguments, in any
spelling. Five Lambda-reachable auth gates logged
`tokenPrefix: accessToken.slice(0, 20) + '...'`, which for a Supabase JWT is the
base64url header — identical for every token the project issues, so it
identified nothing while writing bytes of a live credential into a log group
retained for thirty days.

The hole: the reachability walk followed only relative import specifiers, so a
core reached through `$lib/x` was outside the set these rules are applied to
(69 modules reached, three `$lib` imports naming a seventieth that was not). The
new closure case states the property rather than naming a module — every module
in the set resolves every import it makes into another module in the set — and
resolves specifiers with its OWN resolver, not the walker's: the first draft
asked the walker how to resolve an import, which agrees with the walker by
construction, and reverting the walker to relative-only left it green.
Mutation-checked: reverting the walker, restoring a token slice in a core, and
adding an `event.rawPath` to osrm-proxy's log line each go red on the right case.
See [decisions § 952](../architecture/decisions.md).

### `apps/web/src/lib/security_guards.test.ts` — 89 tests (1 added, 1 rewritten)

The added one is a three-script agreement over the estate secrets file, which
nothing had ever read together: `sops-init.sh` writes the not-yet-wired
placeholder token into the estate `.sops.yaml`, `secret-set.sh` writes into the
encrypted file, and `key-rotate.sh` reads the rule back to decide which key the
file should be under. All three must declare the same `PROJECT_SLUG`, build the
estate path from it rather than spelling the subdirectory out, and name the same
placeholder token — which `key-rotate.sh` must DERIVE from the slug and the env
rather than spell, so a third env cannot be added to one script alone. It fails
on the pre-fix source: `key-rotate.sh` anchored on `<env>/secrets` and
`REPLACE_<ENV>_KMS_ARN`, neither of which occurs in the estate config, so both
envs matched no rule. Mutation-checked: reverting the anchor, reverting the
placeholder to a literal, renaming a token in `sops-init.sh` alone, one script
disagreeing about the slug, and one spelling the subdirectory out — five edits,
five reds.

The rewritten one: `Coach Lambda Function URL is AWS_IAM-auth + CloudFront-only` was four
`/aws_lambda_function_url[\s\S]*?authorization_type = "AWS_IAM"/`-shaped matches
against the whole module. A lazy match across a file holding eight Function URLs,
eight OACs and sixteen permissions says only that SOME resource somewhere has the
property; measured, appending a ninth Function URL with
`authorization_type = "NONE"` and a ninth permission with `principal = "*"` left
it green. Renamed to `EVERY Lambda Function URL …` and read per resource, with a
population floor and two properties the whole-file form could not express: every
OAC signs `always`, and only the `InvokeFunctionUrl` grants are required to
declare `function_url_auth_type`. Mutation-checked: five edits, five reds. The
other ten infra assertions in this file were mutation-checked in place and all
ten already discriminated. See [decisions § 953](../architecture/decisions.md).
## Round 32 — shared Dart packages (2026-09-02)

Five defects fixed with their pinning tests
([decisions §§ 954-958](../architecture/decisions.md)). Counts before → after,
each suite run under `systemd-run --user --scope -p MemoryMax=4G
-p MemorySwapMax=0 -- flutter test --concurrency=2` from the package
directory:

| suite | command | before | after |
|---|---|---|---|
| `route_parser` (gpx_parser) | `flutter test test/route_parser_test.dart` | 44 | 60 |
| `run_recorder` | `flutter test test/run_recorder_test.dart` | 62 | 73 |
| `atomic_io` (core_models) | `flutter test test/atomic_io_test.dart` | 14 | 17 |
| `ui_kit` (whole package) | `flutter test` | 278 | 282 |

What the new cases ask that nothing asked before: that a FINITE coordinate is
still refused when it is not a coordinate (the NaN guard's sibling — `1e308`
overflows the haversine to a NaN `distanceMetres` that `jsonEncode` then
refuses, so the import parses and cannot be saved); that a GeoJSON
`FeatureCollection`, bare geometry and `MultiLineString` import at all; that a
malformed GeoJSON container is an empty import rather than a `TypeError`; that
the recorder's two unconditional append paths — the first fix after `begin()`
and the post-gap re-anchor — refuse an unusable fix; that the accuracy gate
fails CLOSED on a NaN and on the negative value CoreLocation uses to disown a
fix; that a throwing snapshot consumer stops neither distance nor the elapsed
timer (asserted as a property, with the throw itself asserted so the test
cannot pass vacuously); that a 112-hour resumed session survives lap
serialisation and `stop()`; that an atomic write claims its temp sibling rather
than naming it; and that `StatGrid` lays out under an unbounded width instead
of throwing `UnsupportedError` out of `build()`.

Every new assertion was mutation-checked: 22 mutations across the four
packages, each confirmed to turn the intended test red and each restored to
green (the scripts are the round's `reviews/mutate*.sh`, gitignored).
`flutter analyze` reports zero `warning` and zero `error` in all five packages;
the remaining issues are `info`. `npx tsx --test
src/lib/decisions_numbering_guard.test.ts` from `apps/web` passes 3/3 over the
appended ADRs.

NOT run by this lane, and not claimed: the full Flutter workspace suite, the
`api_client` suite (unchanged by this lane), Gradle, Playwright, and anything
needing the local Supabase stack.

## #789 round 33 — the Lambda lane (2026-09-02)

Five followups closed with their pinning tests ([decisions §§ 967-971](../architecture/decisions.md)). Every test below EXECUTES the code it names; none of them is a source-text assertion except the four registers, which say so.

### `apps/web/src/lib/coach/coach_lambda_handler.test.ts` — 17 tests (3 added)

Two behavioural cases drive the wrapper's newly anchored dispatch. The first sends the six paths measured to be mis-routed by the old `rawPath.includes(...)` — `/api/coach/route-describe-v2`, `…/route-describeZZ`, `/api/coach/x/route-describe`, `…/route-describe/extra`, `…/route-requestX`, `…/route-request/extra` — and requires a 404 where each previously reached a sub-handler and answered its own `400`. The second pins the half the followup missed: an unknown path under the `/api/coach*` prefix no longer falls through to the coach turn, and a body past the 256 KB coach cap on such a path is refused as a missing route rather than sized against it; the three canonical paths still route, trailing slash included. The third is a **register**, not a behavioural test: it derives the expected sub-path set from the `src/routes/api/coach/` directory and compares it with the Lambda's `SUB_PATHS` table, so a fourth dev route fails the PR until the Lambda routes it. Planting `route-describe-v2` fails it by name; reverting the dispatch to `includes` fails all three.

### `apps/web/src/lib/coach/coach_body.test.ts` — 13 tests (2 added)

Both drive `decodeLambdaBody`. The first measures that no STRING reaches its `400 invalid body encoding` branch — six malformed base64 inputs all decode — which is the half of the followup that was right. The second measures that a non-string body does reach it and is refused 400 rather than throwing, which is why the branch was not deleted; removing the catch makes the case throw `ERR_INVALID_ARG_TYPE`. An array is pinned as the one non-string that still decodes, because `Buffer.from` reads it as a byte array.

### `apps/web/src/lib/security_guards.test.ts` — 90 tests (1 added, 1 rewritten)

The rewritten one is the body-cap guard, which named only `/api/coach` and now walks every `src/routes/api/**/+server.ts` and `lambda/*/src/index.ts`: a wrapper that mentions a cap must import it, must not declare it, must call `decodeLambdaBody` or `checkBodyByteLimit`, and must not spell a `… * 1024` inline. Inlining the cap in `generate-route` fails it on two counts; hand-rolling its size check fails it on the third. The added one is a guard over the guards: it walks every `.test.ts`, selects those stripping BOTH comment forms, and fails when the block strip precedes the line blank. Reverting `paged_read_guards.test.ts` to the old order fails it. Both carry population floors.

### `apps/web/src/lib/share/share_lambda_handlers.test.ts` — 6 tests (1 added)

Drives all five share Lambdas for the two JSON responses that declared no `cache-control`. The 404 must carry the same five-minute window as every sibling response; the 503 must be `no-store`, because caching a transient failure at the edge turns a blip into a five-minute outage. Fails in both directions — dropping the window from the 404, and giving the 503 the window.

### `apps/web/src/lib/share/share_lambda_handlers.test.ts` — 8 tests (2 more added)

A second pair covers what makes the five share Lambdas safe without a method gate. The first parses every `ordered_cache_behavior` block in `infra/modules/web-stack/main.tf` targeting a `lambda-share-*` origin (14 of them) and fails when one allows POST, PUT, PATCH or DELETE — the value their whole method safety rests on, which nothing had asserted. Because this lane must not edit `infra/`, that check could not be falsified by mutating its input: the check is a pure function over parsed blocks, and the second case runs it against a synthetic behaviour shaped exactly like `/api/coach*` and requires it to name that behaviour. The guard carries its own proof that it fires. See [decisions § 972](../architecture/decisions.md).

### `apps/web/src/lib/core/site_url.test.ts` — 3 tests (1 added)

The added one is the **register** that moved here from `lambda_site_origin.test.ts`: every `PUBLIC_SITE_URL` read under `src` and `lambda` must fold through `siteOrigin`, in either runtime's spelling. It reuses the walker the sibling default-is-spelled-once scan already had, and has a population floor of 27 reads. Reverting any one of the 22 in-app folds to `env.PUBLIC_SITE_URL || DEFAULT_SITE_URL` fails it by name — but only since the comment-stripper fix in [§ 971](../architecture/decisions.md); with the old order, reverting the fold in `runs/[id]/+page.svelte` left this file green, which is how that false pass was found.

### `apps/web/src/lib/share/lambda_site_origin.test.ts` — 2 tests (1 removed)

Its Lambda-only register is superseded by the wider one above; the two behavioural cases over the share head builders stay. **Renamed `share_head_origin.test.ts` in round 34** ([decisions § 1002](../architecture/decisions.md)) — with the register gone the file reads no Lambda source, and the `lambda_` prefix named a scope it no longer had.

Run by this lane and passing: the full `apps/web` unit suite via `npm run test:unit` (4684/4684), `svelte-check --tsconfig ./tsconfig.json` (0 errors), `npm run check:tsconfig-coverage`, `npm run check:script-types`, and `decisions_numbering_guard` 3/3 over the appended ADRs.

NOT run by this lane, and not claimed: Playwright, any Flutter suite, and anything needing the local Supabase stack.

## #789 round 34 — web lane (2026-09-02)

### `apps/web/src/lib/core/strip_comments.test.ts` — 16 tests (new file)

Drives the single-sourced comment stripper directly ([decisions § 1000](../architecture/decisions.md)). Fifteen unit cases cover what the thirteen hand-rolled copies could not: a `//` carrying `/*` opening nothing, the same inside a single-quoted string and inside a template literal, a `://` in a string surviving, a regex literal spelling both delimiters surviving byte for byte, division not read as a regex, a regex after `return` read as one, a comment inside a `${}` expression, a nested template not closing the outer one early, an unterminated quote bounded to its own line, an unterminated block blanked to EOF, and offsets plus line count preserved. The sixteenth runs the scanner over every `.ts`/`.svelte` under `apps/web/src` (2,500+ files) and requires the output to be the same length as the input and idempotent — a shape check that catches a mis-synchronisation anywhere in the real corpus. Falsified twice: deleting the string branch fails the string case and the URL case; disabling the regex branch fails both regex cases.

### `apps/web/src/lib/security_guards.test.ts` — 90 tests (1 rewritten)

The § 971 ordering guard is replaced by a single-source one. It walks `src`, `tests-e2e` and `lambda`, counts block-comment strips per file, and requires every file spelling one to appear in a register with the exact count and a reason; it also fails when a registered file stops spelling one, and carries a floor of 11 importers of the shared stripper. The register holds the three CSS scanners (where `//` is not a comment) and the one JS copy under `src/lib/integrations`, which this lane did not own. Falsified twice: appending a hand-rolled stripper to `format/avatar.test.ts` fails it as `(1, registered not at all)`; doubling `rtl_css_guards.test.ts`'s own strip fails it as `(2, registered 1)`.

Also converted to import the shared stripper, so the rule has one home: `core/site_url.test.ts`, `core/gear_undo_scope.test.ts`, `lambda_log_hygiene.test.ts`, `paged_read_guards.test.ts`, `backup/cloud_export_transport.test.ts`, `coach/coach_lambda_handler.test.ts` (two copies), `tests-e2e/fixtures/dates.test.ts`, `tests-e2e/fixtures/db-read.test.ts`, `tests-e2e/fixtures/base-url.test.ts` and `tests-e2e/cross-cutting/architecture-guards.spec.ts`. Their assertions are unchanged and all still pass. The last of those is a Playwright spec this lane could not execute: its five banned patterns were run against `src/lib/core/data.ts` through the old chain and the new scanner outside Playwright and answer identically (all five `false`).

### `apps/web/src/lib/share/share_lambda_handlers.test.ts` — 10 tests (2 added, 1 comment rewritten)

Both added cases drive all five share Lambdas for real. The first sends `OPTIONS`, `POST`, `DELETE` and an event carrying no method at all at `/og/run/<id>.png` and requires a `405` with `Allow: GET, HEAD`, `content-type: application/json` and `cache-control: no-store` from each — the refusal returns in 0.4 ms against ~200 ms for the render tests beside it, which is the short-circuit being visible rather than asserted. The second pins that `HEAD` still renders on both paths of all four siblings with the shared five-minute window, since HEAD is in the behaviours' `cached_methods` and refusing it would break a path the edge actively caches. Falsified three ways: deleting the gate from `share-recap`, adding `OPTIONS` to the allowed set, and dropping `HEAD` from it. The § 972 Terraform guard is unchanged; only its premise comment is, because the five now do carry a gate. See [decisions § 1005](../architecture/decisions.md).

### `apps/web/src/lib/core/edge_function_contract.test.ts` — 7 tests (2 added, 2 generalised)

The § 982 refusal-vocabulary pair now runs off a register covering BOTH checkout pairs rather than the donations one alone. Every code `clubs/[slug]/events/[id]/+page.svelte` compares must be one `events-checkout` can send, and `event_full` / `sales_closed` / `host_cannot_take_payment` must each map to copy of their own rather than the generic line. Two data are per-pair because the halves differ: `events-checkout` templates none of its codes, and the event page groups four codes into one ternary branch so its code-to-copy window is wider. Falsified by spelling the event page's `host_cannot_take_payment` as `owner_cannot_take_payment` — the exact confusion the original filing made — and by collapsing `event_full` onto the generic line; the reverse swap on the fundraiser page still fails the donations half. See [decisions § 1003](../architecture/decisions.md).

### `apps/web/src/lib/security_guards.test.ts` — 91 tests (1 more added)

A population guard over the eight production Lambdas: each must gate its own HTTP method, by comparing `event.requestContext.http.method` and answering a 405, or by calling the shared `shareMethodRefusal`. Every one of the eight gates was already driven behaviourally, but by five different suites, none of which walks the directory — so a ninth Lambda would have arrived ungated with everything green, which is how the five share handlers went without a gate at all. Falsified twice: deleting `osrm-proxy`'s gate names it, and adding an empty ninth handler directory names that. See [decisions § 1006](../architecture/decisions.md).

## #789 round 34 — the firmware lane (2026-09-02)

Every case below is *host-tested* per [`docs/custom_watch/quality_standards.md`](../custom_watch/quality_standards.md) — the `cargo test` host lane, no silicon and no simulator. The Monkey C rail is weaker still and is labelled where it appears: there is no Connect IQ SDK on this machine, so its tests were **edited and read, never executed**.

### `apps/custom_watch/core/src/grade_adjusted_pace.rs` — 32 tests (2 added, 2 rewritten)

`MIN_SEGMENT_M` was 5 m, which is below `ELEVATION_GAIN_MIN_DELTA_M / MAX_GRADE` — so the smallest altitude change the codebase calls climb was, over the shortest run it measures a grade across, a 0.60 grade that clamped to a factor of 5.396 ([decisions § 992](../architecture/decisions.md)). `the_window_is_longer_than_the_noise_floor_the_gain_path_discards` states that relationship rather than the number and fails at 5 m naming the grade; `a_track_shorter_than_one_window_yields_no_grade_adjusted_pace` proves the walk reads the constant rather than a literal. The two rewritten estimator cases state their distances as fractions of the window, so widening it again cannot leave a stale sub-gate sample reading as an above-gate one — which is what both were.

### `apps/web/src/lib/runs/grade_adjusted_pace.test.ts` — 12 tests (2 added), `apps/mobile_android/test/grade_adjusted_pace_test.dart` — 12 (2 added), `apps/watch_garmin/source-test/GradeAdjustedPaceTest.mc` — 1 added, 6 rewritten (**not executed**)

The same two cases on the other three rails. **Nothing pinned this constant's value on any rail before**: measured, every suite on every rail passed at 5, 20, 30 and 50 m. The Monkey C rewrites are the six `GradeTracker` cases whose literal distances were sized for a 5 m gate; they now read `$.MIN_SEGMENT_M`, including the flat-ground loop, which stepped 7 m and would otherwise have passed by never measuring anything at all.

### `apps/custom_watch/core/src/run_stats.rs` — 23 tests (2 added)

The watch carried both elevation-gain rules after web collapsed its two into one ([§ 993](../architecture/decisions.md)). `elevation_gain_is_the_route_summarys_own_gated_rule_and_not_a_second_one` drives a +/-1 m sawtooth over 30 samples of dead-flat road: **15 m** of phantom climb under the rule this replaced, 0 under the gated one, and it asserts the two entry points agree over the same altitudes. The second case is the control — a 300 m staircase reads 300 m either way, so the gate is shown to cost nothing where there is signal.

### `apps/custom_watch/core/src/record_cadence.rs` — 32 tests (2 added, 1 rewritten)

`ele_dm_from_m` accepted -3276.8 m and returned `Some(i16::MIN)`, which IS `ELE_NONE`, so the reading encoded to the sentinel and decoded back as `None` ([§ 994](../architecture/decisions.md)). The rewritten edge case pinned the wrong claim; `every_altitude_this_stores_survives_the_round_trip` states the invariant as a property over encode/decode instead. `the_altitude_ceiling_is_far_below_what_the_device_believes` is **characterisation, not approval**: it pins that `plausible_alt` admits five summits the field cannot store and that 69 % of a Silverton-Handies-Silverton profile carries no elevation, so the day the field widens to `CRS1`'s `i16` metres the test goes red rather than the limit going quiet.

### `apps/custom_watch/core/src/recap.rs` — 34 tests (3 added)

`build_year_in_running_recap` reported the **all-time** best streak on a card titled with one year, and fed it to the badge grid ([§ 995](../architecture/decisions.md)). Measured: twelve consecutive days in March 2024 gave a 2026 card a 12-day best and a `streak-7` badge. `a_month_recap_bounds_its_best_streak_at_the_first` is the same rule one window down (8 against 2). The third case is the guard against over-correcting: a streak crossing New Year counts at its **full** seven days, and it passes with and without the bound, which is why it is there.

### `apps/custom_watch/core/src/fitness.rs` — 61 tests (2 added, 1 widened)

`RunSource` could name neither `parkrun` nor `race`, and the only variant left — `Other` — does not qualify ([§ 996](../architecture/decisions.md)). The widened case walks a `WEB_SOURCES` register of all eight web values rather than a hand-listed six; the register is the half `is_qualifying`'s new exhaustive match cannot enforce, since the compiler makes a new variant answer the match but cannot make anyone test it.

Run by this lane and passing: `cargo test --target x86_64-unknown-linux-gnu --workspace --exclude app --exclude nrf52840_dk` (2840/2840), `cargo build --release --target thumbv7em-none-eabihf`, all three CI `cargo clippy … -D warnings` invocations, `cargo fmt --check`, `check_watch_wire_vectors.mjs` (and its 31 unit tests), `check_shared_constants.mjs`, `check_parity_pair_registry.mjs`, `check_watch_doc_counts.mjs`, `check_watch_page_ring.mjs`, `check_watch_ble_uuids.mjs`, `check_watch_ios_source.mjs`, `check_doc_checkboxes.mjs`, `check_garmin_source.sh` (and its 22 unit tests), the `apps/web` `runs` + `routes` + `training` suites (1456/1456), `svelte-check` (0 errors), `dart analyze` on the two changed Dart files (3 infos, 0 warnings), and the Flutter files `grade_adjusted_pace_test.dart`, `roadbook_test.dart`, `pace_analysis_test.dart`, `run_detail_screen_test.dart`, `fuel_plan_test.dart`, `architecture_guards_test.dart`.

NOT run by this lane, and not claimed: any Monkey C compilation or execution, the Renode sim, Playwright, the full Flutter suite, and anything needing the local Supabase stack. Nothing here is sim-verified or bench-verified.

## Round 34 — the #789 mobile lane (2026-09-02)

### `apps/mobile_android/test/race_providers_test.dart` — 11 tests (6 added)

Five pin `raceProbeUnavailable`, the port of web's fail-closed probe grading ([§ 1007](../architecture/decisions.md)): the 503 gate whatever the body says, a 429 / 5xx confirming nothing, a readable non-429 4xx meaning the function ran PAST the gate, no readable status at all, and a `RaceService` with no Supabase behind it answering unconfigured rather than configured. The sixth derives its own premise before asserting ([§ 1008](../architecture/decisions.md)): it reads `race-results-import`'s probe branch, requires that branch still to refuse UltraSignup independently of its credential, and only then requires the client to name that function. Lifting § 975 makes the guard say to re-decide rather than to delete an assertion.

### `apps/mobile_android/test/track_blob_size_test.dart` — 4 tests (new)

The reachability arithmetic behind [§ 1009](../architecture/decisions.md), re-derivable rather than asserted: a realistic 1 Hz trace through the uploader's own `debugTrackBlobJson` gzips to ~27 bytes per waypoint, so the `runs` bucket's 25 MiB limit is ~960k points — 266 h of recording (unreachable) against a 94 MiB GPX (ordinary). Plus: a `TrackTooLargeException` must classify as `tooLarge` through `classifyImportFailure`, which is a property of its SENTENCE and not of its type; and the size check must sit before `uploadBinary` in `_uploadTrack`, or it saves nothing over the 413 it exists to pre-empt.

### `apps/mobile_android/test/finite_parse_guard_test.dart` — 3 tests (new)

The source-level guard of [§ 1011](../architecture/decisions.md): every `double.tryParse` / `num.tryParse` under `lib/` must have a finiteness test in its enclosing FUNCTION body, or call a predicate that does, or carry an `// unchecked-parse:` marker. Allowlist is empty — no site legitimately wants an unchecked double. `int.tryParse` is not scanned: it answers null to both "NaN" and "Infinity". The two support tests are § 510's self-check (the matcher still fires) and a pin that the body finder stops at the function — not at the innermost block, which would miss a sibling guard outside an `if`, and not at the class body, which would let one method's `isFinite` vouch for another's.

### `apps/mobile_android/test/in_progress_settled_test.dart` — 4 tests (new)

[§ 1012](../architecture/decisions.md)'s completion signal for the one store write path deliberately off the serialised chain. Two behavioural: an append the caller discarded, and a clear the caller discarded, are both settled by `debugInProgressSettled()`. Two structural: the recording path must still not reach `_serialised`, and `clearInProgress` must publish its future. The clear-tracking half is structural on purpose — a behavioural version PASSED under the mutation that removes the tracking, because the delete lands within a turn or two on a fast disk either way, and a test that passes under its own mutation is worse than no test.

### `apps/mobile_android/test/settings_integrations_parkrun_partial_test.dart` — 4 tests (new)

The parkrun half of [§ 1014](../architecture/decisions.md): a capped history names the gap (`n of total`), a shortfall with no total still says a shortfall happened with no fabricated denominator, and the two complete shapes still read as a plain success and as "nothing new". Mirrors `settings_integrations_strava_partial_test.dart`, one importer over.

### `apps/mobile_android/test/races_screen_test.dart` — 22 tests (2 added)

The race-results half of § 1014: a 502 truncation is said in its own words and leaves the sheet open so the manual paste form stays reachable, and a `complete: false` success is not presented as a whole import. The screen's fake now carries `complete` and `throwTruncated` so both shapes are drivable.

### `apps/mobile_android/test/shared_file_import_test.dart` — 27 tests (6 added, 1 inverted)

[§ 1025](../architecture/decisions.md)'s KMZ support. A KMZ unwraps to the KML inside it; it is recognised by the zip magic number rather than by an extension an OS share drops; `doc.kml` wins when present and any `.kml` is taken when it is not; a zip with no KML is not a route; bytes that are neither a zip nor UTF-8 are refused; and every other format still decodes as text. The end-to-end `importPath` case writes a real `.kmz` — the file `readAsString` used to throw on. The fixture archive is BUILT in the test rather than committed as a binary, so the test says what is inside it. The pre-existing "KMZ is absent from every catalogue" assertion is inverted rather than deleted: same guard, still pinning that the promise and the picker cannot drift.

### `apps/mobile_android/test/geocoding_test.dart` — 26 tests (2 added)

A geocoder answer that is not a coordinate is dropped on BOTH providers — Nominatim's strings (`"NaN"`, `"1e400"`) and MapTiler's JSON numbers (`1e400` decodes to `Infinity`) — and out-of-range with them. The second pins the bound as INCLUSIVE: the poles and the antimeridian are places. The MapTiler fixture is a literal wire body rather than `jsonEncode` output, because `jsonEncode` refuses the very value under test.

### `apps/mobile_android/test/activity_type_vocabulary_test.dart` — 8 tests (2 added)

[§ 1013](../architecture/decisions.md): the enum lives in `core_models`, which takes no Flutter dependency (asserted on the IMPORT, not on a mention — the file's own header names `package:flutter/material.dart` to explain why the icon getter could not travel), and the CSV importer reaches the vocabulary without a widget toolkit.

### `packages/core_models/test/run_row_shape_test.dart` — 24 tests (7 added)

[§ 1010](../architecture/decisions.md): `runRowFromRun` is total. A non-finite distance resolves to zero and agrees with `Run.toJson` over the same inputs (one shared rule, not two copies); a non-finite embedded best is dropped rather than thrown on (`toInt()` raises out of the row BUILDER); a non-finite anywhere in the bag is dropped, including inside nested lists and maps; a finite bag survives untouched; and an explicit `null` is preserved rather than read as a dropped non-finite.

### `packages/core_models/test/import_completeness_test.dart` — 7 tests ↔ `apps/web/src/lib/integrations/import_completeness.test.ts` — 7 tests

`parseImportCompleteness`, mirrored case for case over six of the seven: an unreadable body is partial, only an explicit `true` claims whole, an embedded error forces partial beside a `complete` flag (a blank one is not an error), counts are non-negative integers or zero, `total` is carried only when sent, and a `total` below `imported + skipped` is no total at all. The seventh is per-platform and is not a mirror — a source guard that `strava_sync_result` still IMPORTS this module's `importResponseCount` / `importResponseText` rather than having grown a private copy, which nothing else on either platform would catch ([§ 1039](../architecture/decisions.md)).

These six cases lived in `strava_sync_result_test.dart` / `.test.ts` until the pair was split out on 2026-09-03; both of those files now hold **16 Dart / 17 web**, which is what their registry rows had claimed all along.

### `packages/core_models/test/metadata_keys_test.dart` — 4 tests (1 added)

`StorageBuckets.runsBucketMaxBytes` is read against the migration that sets the `runs` bucket's `file_size_limit` — a client rail on a server bound, in the shape `text_limits` and `column_limits` already use.

Run by this lane and passing: every Dart file named above, individually, under a 4 GB cgroup; `packages/core_models` in full (143); `packages/run_recorder` architecture + geolocator-fake suites; `apps/mobile_android` `architecture_guards_test` (272), `l10n_parity_test`, `routes_screen_test`, `csv_run_importer_test`, `preferences*`; `apps/web` `strava_sync_result.test.ts`, `race_import_providers.test.ts`, `catalogues.test.ts`, `messages_parity.test.ts`, `svelte-check` (0 errors), and `check_constraint_unions.mjs`.

NOT run by this lane, and not claimed: Playwright, the full `apps/mobile_android` suite (the box cannot finish it), pgTAP, and anything needing a working local edge runtime.

## #789 round 36 — the web guard split (2026-09-03)

### `apps/web/src/lib/security_guards.test.ts` — 91 tests, split into twelve files

[§ 1065](../architecture/decisions.md): the file reached 3,728 lines and 91 tests, and two unrelated lanes landed in it in one round. Every assertion moved verbatim into a concern-scoped file, checked both ways by script — each of the 91 test bodies appears byte-identical in exactly one destination, and the sorted name sets match. The four `security_guards.test.ts` headings above are per-round historical records of a file that no longer exists; they are left as written.

`privacy_guards.test.ts` 21, `infra_guards.test.ts` 12, `consent_guards.test.ts` 11, `lambda_guards.test.ts` 9, `a11y_guards.test.ts` 8, `credential_guards.test.ts` 6, `rate_limit_guards.test.ts` 6, `edge_function_guards.test.ts` 5, `paywall_guards.test.ts` 5, `ci_workflow_guards.test.ts` 4, `xss_guards.test.ts` 3, `source_scanner_guards.test.ts` 1 — 91 total, recounted on the merged tree.

The one-test file is deliberate: the comment-delimiter REGISTER is the single thing every lane adding a source scanner must edit, so it is the one file a scanner author needs to find.
