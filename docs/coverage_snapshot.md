# Coverage snapshot — 2026-05-19

**Snapshot, not source of truth.** This is the baseline from which the "push every area to 90%" work starts. Estimates answer: "would CI catch a regression in this feature before merge?" — not measured line coverage. Roll-up at the bottom.

## Session-end update — 2026-05-19

This session hardened the **anti-spam + dev/prod-isolation surface** end-to-end and added cross-cutting arch guards that would have caught the bugs the session opened with. Three real misconfiguration vectors closed in code (each previously silent in CI):

| Surface | Was | Now | What changed |
|---|---|---|---|
| Rate-limit error parsing (TS↔Dart parity) | — | ~95% | NEW helper pair — `apps/web/src/lib/rate_limit_errors.{ts,test.ts}` (19) + `apps/mobile_android/lib/rate_limit_errors.dart` + `test/rate_limit_errors_test.dart` (19). Translates P0001 from `rate limit exceeded for <bucket>, retry in Ns` into friendly per-bucket strings ("creating clubs", "creating routes", "filing reports"). 3 call-sites wired (`saveRoute` + `createClub` + `submitReport`); previously each carried its own ad-hoc translation. |
| pgtap rate-limit suite (`create_rate_limits_test.sql`) | 4 tests, `%rate limit exceeded%` LIKE | 6 tests, `^rate limit exceeded for create_X, retry in [0-9]+s$` anchored regex via `throws_matching` | Tightened the format-pin so a future migration that swaps the comma, drops "retry in", or removes the integer-seconds suffix fails at the SQL layer instead of silently breaking the client parser. Added `create_report` (10/hr) coverage targeting 10 of the 30 already-planted routes — duplicate-pending check is per (reporter, kind, id), so distinct targets give 10 slots; 11th raises. 315 → 317 pgtap tests. |
| Production env guard (`check_production_env.mjs`) | 7 tests, SUPABASE_URL + ANON_KEY only | 14 tests, all 4 required PUBLIC_* | Added `PUBLIC_MAPTILER_KEY` + `PUBLIC_REVENUECAT_WEB_API_KEY` to the required set (previously a missing release secret silently baked broken maplibre tile URLs + a no-op Pro purchase flow into the static artifact). Explicit "SENTRY is deliberately not enforced" test pins error-reporting as optional. Workflow-step `env:` block in `release-web.yml` updated in lockstep — without it, the next `web@*` tag would have failed the guard. |
| Dev/prod isolation guard (`env_isolation.mjs`) | 13 tests, 7 URLs guarded | 19 tests, 9 URLs guarded | Added `PUBLIC_LIVE_HUB_URL` (web client's live-broadcast URL, distinct from Dart twin's un-prefixed `LIVE_HUB_URL`) + `PUBLIC_EXPORT_HUB_URL` (Cloud-export Go endpoint). A dev `.env.local` aimed at either prod URL was previously not flagged — test pings would have hit prod live-broadcast; test exports would have queued real export jobs. Plus a meta-guard test that pins `docs/dev_prod_isolation.md` in lockstep with `KNOWN_ENV_VARS` so a future URL-shaped env var can't slip past either side. |
| Web architecture guards (`security_guards.test.ts`) | 28 tests | 32 tests | Two new source-text guards: (1) `release-web.yml` invokes `check_production_env.mjs` before `npm run build` AND threads every required secret into the guard step's `env:` block. (2) `saveRoute` + `createClub` + `submitReport` in `data.ts` all route P0001 through `rateLimitErrorMessage` (centralises the "friendly wait-N-minutes" line so a refactor can't slip a callsite back to the raw exception). |
| Dart architecture guards (`architecture_guards_test.dart`) | 79 tests | 84 tests | 5 new source-text guards: `club_form_sheet` + `route_builder_screen` import + call `rateLimitErrorMessage`, plus three timeout pins on the routing/elevation/geocoding helpers' `kOsrmSnapTimeout` / `kOsrmRouteTimeout` / `kElevationFetchTimeout` / `kGeocodingTimeout` constants. |

### Bugs caught (not coded around) this session

| Symptom | Root cause | Fix |
|---|---|---|
| Helper was extended to require 4 PUBLIC_* keys but the release workflow only threaded 2 into the guard step — next `web@*` tag would have hard-failed CI | Missed wiring during the `check_production_env.mjs` extension | Added `PUBLIC_MAPTILER_KEY` + `PUBLIC_REVENUECAT_WEB_API_KEY` to `release-web.yml` guard-step env, pinned by an arch test |
| Web client reads `PUBLIC_LIVE_HUB_URL` + `PUBLIC_EXPORT_HUB_URL` but env-isolation guard only listed the un-prefixed Dart-side form — silent dev → prod misconfig vector | Helper's `KNOWN_ENV_VARS` drifted from the actual code's env reads | Added both to `KNOWN_ENV_VARS`, plus a doc-lockstep meta-guard so it can't happen again |
| pgtap rate-limit suite's `%rate limit exceeded%` LIKE pattern was loose enough to survive a comma-to-colon migration — client parsers (web + Dart) depend on the exact comma + "retry in" + integer-seconds shape | `throws_like` with too-permissive pattern | `throws_matching` with anchored POSIX regex pinning the exact format |
| `submit_report` carried its own ad-hoc "Too many reports — please wait a few minutes" translation while `create_club` + `create_route` went through the shared `rateLimitErrorMessage` helper | Three independent translations for the same P0001 source | Refactored `submitReport` (web) to route through the shared helper; added `create_report → 'filing reports'` to the helper's verb map (TS + Dart twin) |

### Stale entries from prior sessions — corrected this pass

| Entry | Was listed as | Actual state | Updated where |
|---|---|---|---|
| Routes Heatmap tab + RPC plumbing | 40% (in two tables) | 92% — Round C (2026-05-15) shipped `routes/heatmap.spec.ts` (6 tests) + `routes/heatmap-interaction.spec.ts` | Fixed in the Routes per-area table + "What's still below 90%" list |
| pgtap rate-limit count in backend table | "80%" (collective) | Same %, but test count is now 317 not 315 | Reflected in Backend section |

## Wear OS unit-test pass — 2026-05-19 (post-mobile continuation)

After the mobile pure-logic additions, three more Wear OS source
files got dedicated unit-test files. One small refactor (extracting
HeartRateMonitor's BPM validity gate to a testable companion-level
function) + two existing-as-pure-logic surfaces.

| Surface | Tests | What's pinned |
|---|---|---|
| `HeartRateMonitor` BPM validity gate | 9 (NEW `HeartRateMonitorTest.kt`) | Hoisted `isValidBpm(bpm: Double): Boolean` + named constants `MIN_VALID_BPM=30` / `MAX_VALID_BPM=230`. Pinned: inclusive bounds (30 and 230 pass), typical resting+active rates (45-200) pass, just-below + just-above bounds reject, zero/negative/NaN/Infinity all reject — explicit doc on why `bpm >= 30 && bpm <= 230` drops NaN while the logically-equivalent `!(bpm < 30 \|\| bpm > 230)` would NOT. |
| `TrackWriter` file format + lifecycle | 9 (NEW `TrackWriterTest.kt`) | The streamer that backs the recording loop's track file. Format: empty close → "[]", single point → 1-element array, multiple → comma-separated NO trailing comma, null elevation → JSON null literal (NOT quoted "null"), ISO 8601 UTC timestamps. Lifecycle: pointCount tracks each append, re-open clears the file, close is idempotent, path is absolute (CheckpointStore's trackFilePath resolves across process restarts). |
| `RecordingRepository` state + isActive | 10 (NEW `RecordingRepositoryTest.kt`) | The process-wide singleton that decouples recording state from UI lifecycle. isActive contract — all 4 Stage values pinned separately (Recording + Paused → true so the UI stays mounted on pause; Idle + Finished → false). Default-state assertions on every field of `Metrics`. update() composes through (not reset on each write). reset() clears regardless of prior state. Stage enum value set pinned (forces deliberate isActive review on additions). |

### Pieces of work + commits

| Piece | Commit | Tests |
|---|---|---|
| HeartRateMonitor BPM validity gate (extract + tests) | `38d0ce3` | 9 |
| TrackWriter file format + lifecycle | `e095711` | 9 |
| RecordingRepository state + isActive | `a8ad4d0` | 10 |

Total this pass: **28 new Wear OS tests**.

### Lessons baked into the new specs

- **JUnit 4 `assertEquals(message, expected, actual)`** — message is the FIRST arg, not last. Kotlin lets you pass strings in any order so the wrong order compiles fine but produces a confusing "expected:<[test-run]> but was:<[your-message]>" failure. RecordingRepository test initially failed for this exact reason; comment in the spec walks through it.
- **The `bpm >= 30 && bpm <= 230` vs `!(bpm < 30 || bpm > 230)` distinction matters for NaN.** The former drops NaN (both comparisons false → false). The latter accepts it (`!(false || false)` → true). HeartRateMonitor test pins the right form so a future refactor to the inverted shape would fail loud.
- **Wear OS test naming Windows-safety.** Kotlin backtick names containing `"` (double quotes) emit a Windows compile-warning. Pure cosmetic but trivial to avoid by paraphrasing.

## Mobile + watch unit-test gaps pass — 2026-05-19 (post-EF continuation)

After the backend EF guards pass, three mobile lib/ files + one
watch_wear source file had no unit tests despite carrying load-
bearing logic. All four now have dedicated pure-logic test files:

| Surface | Tests | What's pinned |
|---|---|---|
| `preferences.dart` ActivityType enum | 17 (NEW `preferences_test.dart`) | per-activity getters that drive the entire recording stack: `label`, `icon`, `usesSpeed` (pace vs speed), `kcalPerKgPerKm` (range + relative ordering), `splitIntervalMetres`, `gpsDistanceFilter`, `minMovementMetres` (jitter floor), `strideMetres` (cycle=0 + relative ordering), `maxSpeedMps` (cycle > run sanity ranking), `fromName` (round-trip + null + unknown fallback), `DistanceUnit` set |
| `watch_ingest_queue.dart` pure decoders | 16 (NEW `watch_ingest_queue_test.dart`) | `runFromWatchPayload` (the watch-run JSON wire format from Wear OS + watchOS senders): minimum-valid shape, missing/empty fields, mixed-detail waypoints, decimal-bpm flooring, malformed-input safety on track + laps, num coercion (int distance_m + double duration_s both tolerated); `parseRunSource` (every enum round-trip + watch fallback) |
| `strava_importer.dart` parseStravaDate | 16 (NEW `strava_importer_test.dart`) | ISO 8601 path (UTC, ms precision, TZ offset); US-locale path (PM-shift, noon edge `hour < 12` guard, midnight AM edge, 24-hour no-marker, full month name "April", all 12 month abbreviations, single + upper-half-double-digit day); failure paths (garbage, unknown month, partial match → null fallback) |
| `SavedRoute.kt` (watch_wear) | 9 (NEW `SavedRouteTest.kt`) | `toLatLngs` (preserve order — RouteMath walks sequentially; empty + duplicate handling); `waypointsAsJson` (the ACTION_START Intent wire format — array shape, "[]" on empty, doubles-not-strings, insertion order); data-class equality on SavedRoute + Waypoint (LocalRouteStore dedupes by equality) |

### Pieces of work + commits

| Piece | Commit | Tests |
|---|---|---|
| preferences ActivityType enum | `4973f36` | 17 |
| watch_ingest_queue pure decoders | `5b26f35` | 16 |
| strava_importer parseStravaDate | `923bd15` | 16 |
| SavedRoute (watch_wear) | `01deabc` | 9 |

Total this pass: **58 new tests** across 3 mobile lib/ files (mirrored to iOS twin) + 1 watch_wear source file. All run in <1s combined.

### Lessons baked into the new specs

- **Mobile twin discipline.** Every test file mirrored to `apps/mobile_ios/test/` byte-identically; `diff -rq apps/mobile_android/test apps/mobile_ios/test` returns empty. The pure-logic helpers don't have `Platform.isIOS` dispatch so they're true byte-identical files.
- **JUnit + kotlinx-serialization gotchas on Wear OS.** Test names can't contain raw `[` / `]` (Kotlin identifier rule). The `jsonPrimitive.double` extension needs explicit `import kotlinx.serialization.json.double` — JsonPrimitive's `.double` doesn't come in automatically.
- **The Gradle task path.** Wear OS unit tests run via `./gradlew :app:testDebugUnitTest --tests 'com.runapp.watchwear.Foo'` from `apps/watch_wear/android`. The top-level `:app:test` aggregator doesn't accept `--tests`; per-variant `testDebugUnitTest` does.

## Backend EF guards pass — 2026-05-19 (post-survey continuation)

All 5 JWT-gated Edge Functions now have dedicated pre-side-effect
guard specs in the strava-import-guards mould. Before this pass
only `strava-import` had one (10 tests); now all 5 do:

| EF | Tests added | What's pinned |
|---|---|---|
| `clip-public-track` | 7 (NEW spec) | GET/PUT/POST method gates; 401 platform gate; missing/non-string/empty run_id; unknown-uuid 404 |
| `delete-account` | 4 (NEW spec) | GET/PUT method gates; 401 platform gate; 256-byte body cap (closes chunked-transfer-encoding bypass on the most destructive EF) |
| `export-data` | 6 (NEW spec) | GET/PUT method gates; 401 platform gate; 1KB body cap; 'fit'/non-string format → 400 with csv/gpx hint copy |
| `parkrun-import` | 7 (NEW spec) | 401 platform gate; 1KB body cap; the `/^A\d{1,12}$/` athleteNumber regex's THREE load-bearing pieces (anchor, length cap, case sensitivity) — the regex IS the outbound-fetch attack-surface guard |
| `strava-import` | (already 10) | Already covered by `strava-import-guards.spec.ts` |

### Pieces of work + commits

| Piece | Commit | Tests |
|---|---|---|
| clip-public-track guards | `18ee7d9` | 7 |
| delete-account guards | `d546138` | 4 |
| export-data guards | `2f7be35` | 6 |
| parkrun-import guards | `ff1b189` | 7 |

### Lessons baked into the new specs (so the next writer doesn't re-derive)

- **Platform `verify_jwt = true` 401s requests without `Authorization` BEFORE the handler runs.** Tests for handler-local 405 / 4xx branches must include a valid Authorization to clear the platform gate. The handler's own missing-auth branch is unreachable on the wire — pin status only, not body.
- **Rate-limit checks fire BEFORE body-shape validation on `export-data` + `parkrun-import`.** Each 400-branch test consumes one of the seed user's free-tier slots. The specs install a `beforeEach` that service-role-deletes the user's rate-limit row to keep tests deterministic across reruns.
- **Body-size caps (`readJsonWithLimit`) fire BEFORE `auth.getUser`.** This means 413 tests don't consume rate-limit slots — exercise the cap freely without needing a reset.
- **`delete-account` is destructive on the seed user.** Stop at the gates that fire BEFORE `auth.getUser` (method, body cap, platform 401). The destructive paths (rate-limit, Storage walk, admin delete) need either a throwaway user or a refactor to inject the admin client; deferred.

## Marginal-lift pass — 2026-05-19 (final continuation)

Three 75–80% surfaces lifted to ~90+%:

| Surface | Was | Now | What changed |
|---|---|---|---|
| Profile `/u/[id]` (`tests-e2e/u/profile.spec.ts`) | 80% (4 tests) | ~92% (9 tests) | Added: default tab is Runs (no `?tab=`); `?tab=notifications` from non-self viewer falls through + tab strip button absent (privacy gate); count-button click activates matching tab; invalid uuid renders Profile-not-found empty card; anon visitor auth-walled with `?return_to` preserved. Documents inline the `setTab` URL-asymmetry surfaced while writing (reads `?tab=` on mount but doesn't write on click). |
| Activity feed `/social?tab=feed` (`tests-e2e/social/feed.spec.ts`) | 80% (2 tests) | ~92% (6 tests) | Added: Run-filter happy path (counterpart to existing Cycle empty state); window-hint advertises "Last 14 days" (lockstep with `FEED_WINDOW_DAYS`); 15-days-ago run does NOT surface (14-day cutoff is the privacy contract); private run from followed user does NOT surface (`is_public` gate). Each uses a signature distance (12345m / 23456m) so absence assertions are unambiguous. |
| Coach handler (`apps/web/src/lib/coach/handler.test.ts`) | 75% surface (no server-side unit tests) | ~92% pre-Supabase | NEW unit-test file — handleCoach's four early-return branches (503 missing API key, 401 missing/bad Authorization, 400 invalid JSON body, 400 invalid messages) all reachable without DI. 10 tests, <100ms. Server-side mirror to the e2e mocked-route tests that already pinned the client side of these envelopes. |

### Pieces of work + commits (this continuation)

| Piece | Commit | Result |
|---|---|---|
| Profile deepening | `697e607` | 4 → 9 tests; anon + invalid-uuid + non-self notifications gate pinned |
| Feed deepening | `37b2a1e` | 2 → 6 tests; 14-day window + private-run boundary pinned with signature-distance absence assertions |
| Coach handler unit tests | `f857cf5` | NEW file; 10 tests on the 503/401/400 pre-Supabase paths |

## Coverage-deepening pass — 2026-05-19 (continuation)

Following the hardening pass earlier in the session, six addressable
sub-90% rows from the snapshot lifted to ~90+%:

| Surface | Was | Now | What changed |
|---|---|---|---|
| Mobile spectator screen (`live_spectator_screen_test.dart`) | 55% (1 test) | ~92% (18 tests) | Hoisted two private formatters (`_fmtDuration` / `_fmtPace`) to top-level `@visibleForTesting` (`formatLiveDuration` / `formatLivePace`); added 6 unit tests pinning boundary cases (sub-minute, exact-hour M:SS→H:MM:SS flip, half-second rounding, 5:59→5:60 rollover); added 6 widget tests for loading + error states (CircularProgressIndicator → ErrorState → Retry button), plus initial-render Status badge "Connecting" check. Mirrored to iOS twin. |
| Multi-client realtime delivery (`cross-cutting/realtime.spec.ts`) | 55% (2 tests) | ~92% (4 tests) | Added: (a) single-page realtime push on `/live/[id]` — service-role INSERT into `live_run_pings` flips the distance text via `supabase.channel` without reload; (b) N=3 fan-out — runner+follower+anon contexts all observe the same ping. Both use `expect.poll` on `textContent` so they're unit-agnostic (a regression where `browser.newContext` drops `playwright.config.use.locale` and falls into mi-mode would otherwise mask). |
| Race control (clubs) (`clubs/event-race-control.spec.ts`) | 65% (no multi-context) | ~92% (2 tests) | New file — admin (USER_A) drives Arm → GO → End in one context; member (USER_B) observes armed → running → cleared banner via realtime in the parallel context. Second test pins Arm → Cancel separately (different status path; member-side banner-clear must accept both `cancelled` and `finished`). ConfirmDialog scoped via `getByRole('dialog')`. |
| AI Coach SSE streaming (`coach/page.spec.ts`) | 70% | ~92% (4 new tests, 49 total) | Added: multi-token append-in-order; special characters preserved (`\``, em-dash, curly quotes, emoji, accent); mid-stream `event: error` retains partial + surfaces banner; empty stream (meta + done, no tokens) keeps composer reusable. Inline doc on the non-obvious SSE-parser quirk: blocks need explicit `\n\n` tails — existing happy-path tests work incidentally because their assertions only depend on token-event flush, not the final block. |
| Live run screen idle state (`run_screen_test.dart`) | 65% (5 idle tests) | ~85% (11 idle tests) | Default-activity-is-Run pinned; each of 4 enum values (Run/Walk/Cycle/Hike) gets its own selectable-chip test (the existing Walk-only test couldn't catch a per-enum-value typo); idle-state surfaces Choose-route + Share-live + Training-plans buttons pinned; first-run empty-state prompt renders with no signals planted. Recording/countdown/post-state widget testing still gated on geolocator mocking (separate effort). |
| pgtap rate-limit format pin | (covered separately above) | 6 tests | Tightened `throws_like '%rate limit exceeded%'` (would survive a comma-to-colon migration) to `throws_matching '^rate limit exceeded for create_X, retry in [0-9]+s$'` for all 3 buckets (clubs, routes, reports). |

### Pieces of work + commits

| Piece | Commit | What |
|---|---|---|
| Rate-limit unification + prod-env guard extension | `80c56eb` | submit_report routed through shared `rateLimitErrorMessage` (TS+Dart); `check_production_env` now requires 4 PUBLIC_* keys; release-web.yml secret wiring fixed (real bug: next tag would have failed) |
| pgtap rate-limit anchored format + create_report | `4683791` | `throws_matching` regex pins client-parser-compatible format; 10/hr create_report cap added |
| Env-isolation guard expansion + doc lockstep | `bcd8527` | `PUBLIC_LIVE_HUB_URL` + `PUBLIC_EXPORT_HUB_URL` added; meta-guard pins `docs/dev_prod_isolation.md` ↔ `KNOWN_ENV_VARS` |
| Coverage snapshot refresh (initial) | `026e55c` | Today's hardening reflected; stale Heatmap entries fixed |
| Mobile spectator deepening | `cc5ac3e` | 1 → 18 tests; formatters hoisted to `@visibleForTesting` |
| Realtime fan-out on `/live/[id]` | `79533f8` | 2 new tests including 3-context fan-out |
| Race-control multi-context | `9071480` | New spec, 2 tests, admin + member realtime handoff |
| Coach SSE edge cases | `bbf8e93` | 4 new tests; non-obvious SSE-parser quirk documented |
| Run screen idle deepening | `b535744` | 5 → 11 tests; enum coverage + empty-state + secondary affordances |

### Real bugs caught (not coded around) this round

| Symptom | Root cause | Fix |
|---|---|---|
| `release-web.yml` guard step passed only 2 of the 4 PUBLIC_* secrets it now requires — next `web@*` tag would have hard-failed CI on missing MAPTILER/REVENUECAT secrets | Missed wiring when `check_production_env.mjs` was extended | Added both secrets to the workflow's env block; arch test pins lockstep |
| `env_isolation.mjs` missed `PUBLIC_LIVE_HUB_URL` + `PUBLIC_EXPORT_HUB_URL` — a dev `.env.local` aimed at prod live-hub / cloud-exporter would not be flagged | Helper's `KNOWN_ENV_VARS` drifted from actual code env reads | Added both; meta-guard test pins doc ↔ helper |
| pgtap suite's `%rate limit exceeded%` LIKE pattern was loose enough to survive a comma-to-colon migration that would silently break both web + Dart client parsers | Permissive `throws_like` pattern | Switched to `throws_matching` with anchored POSIX regex |
| `submit_report` carried its own ad-hoc translation; three independent verb maps for the same P0001 source | History drift | Unified through `rateLimitErrorMessage`, mirrored to Dart twin |

### Lessons baked into specs (so future writers don't re-discover)

- `browser.newContext({ storageState: ... })` drops `playwright.config.use.locale` / `timezoneId` defaults. Set them explicitly on each manually-created context. Without `locale: 'en-GB'`, an anon context falls into mi-mode and renders distance as `1094 yd` instead of `1.0 km`. (Documented in `cross-cutting/realtime.spec.ts` + `clubs/event-race-control.spec.ts`.)
- The `/live/[id]` page's `formatDistance` reads from a reactive `unit` signal whose value depends on auth-store profile-load timing. Asserting a specific format-text (`'4.5'`) is brittle; asserting `textContent` changed via `expect.poll` is what actually proves realtime delivery.
- CoachChat's SSE parser splits on `\n\n` — event blocks need explicit `\n\n` tails, not `array.join('\n')` with a trailing `''`. Existing happy-path tests work incidentally because they only assert on token-event flush, not the final block. (Documented inline in `coach/page.spec.ts:SSE: mid-stream error`.)

## Session-end update — 2026-05-16

This session moved 13 web surfaces above 75%, added the People tab to fill the find-other-runners gap, restructured `tests-e2e/` to mirror app routes, and fixed 6 real app bugs surfaced by the new tests. `/recap/[year]` and `/explore` were the last two web rows lifted in the session; both now pin invalid-input and anon paths in addition to the happy-path render.

| Surface | Was | Now | What changed |
|---|---|---|---|
| `/social` | — | 90% | NEW top-level hub (didn't exist) — ARIA tab strip (Feed / People / Clubs) with `?tab=` URL state; replaces the `/u/[me]?tab=feed` self-only feed and the old `/clubs` browse landing |
| `/social?tab=people` | — | 90% | NEW — search saga + suggestion empty state covered; only top-level surface for finding other runners (fills the gap left when feed moved off `/u/[me]`) |
| `/social?tab=feed` | 75% (under `/u/[me]`) | 75% | NEW location — feed migrated from `/u/[me]?tab=feed`; legacy `?tab=feed` deep links bounce through |
| `/auth/reset` | 0% | 75% | Full Mailpit round-trip (request → email → token → new password → re-login). **Fix**: `/auth/reset` was missing from `shellLessExact` in `+layout.svelte`, so the reset link silently rendered through the signed-in shell |
| `/plans/new` | 50% | 90% | Full wizard, replace-active path, week-edit persistence (clicking a week to expand the day-by-day editor — edits now persist on submit) |
| `/routes/new` | 50% | 75% | Save modal round-trip + description persisted. **Fix**: route description was silently dropped on Save Route — migration `20260902_001_routes_description.sql` + `saveRoute` + render |
| `/settings/integrations` | 50% | 90% | Connected-state UI + disconnect ConfirmDialog. **Fix**: Disconnect had no confirm dialog — added a `ConfirmDialog` so destructive disconnect goes through a confirm modal (matches the rest of the app) |
| `/live/[id]` | 50% | 75% | Finished state + named-runner + planted pings. **Fix**: dead `'finished'` status path + Anonymous-runner anon read + invalid `hsl()` avatar alpha (avatar fell through to white) |
| `/live/event/[id]/[instance]` | 50% | 75% | 3-runner leaderboard with planted positions; mutex on leader badge |
| `/runs/new` | 50% | 90% | 15 tests: page chrome, save round-trip → /runs/[id], distance/duration validation (zero/negative blocked), decimal km, activity-chip persistence (run/walk/hike/cycle), source pinned to `app` with `metadata.manual_entry=true` (the CHECK constraint rejects `'manual'`), no-prefill contract on `?distance=...&activity=...`, started_at near-now defaulting, discard-mid-form plants no row. **Fix**: RunEditor activity chips were rendered inside a `<label class="field">` wrapping a `<span class="field-label">Activity</span>` — the wrapping label leaked into the accessible name of the active chip (it appeared as `button "Activity Walk Hike Cycle": Run`). Switched to `<fieldset>/<legend>` with `role="radiogroup"` + `role="radio"` + `aria-checked` so each chip has a clean name. |
| `/clubs/new` | 50% | 90% | 9 tests: page chrome (kicker + h1 + tagline + back-link to `/social?tab=clubs`), visibility × join-policy matrix (public+open, public+request, private→invite with token generated, public→private→public coercion back to open), slug derivation + `/clubs/[slug]` resolves, viewer auto-enrolled as owner (`enroll_club_owner_trigger`), Create-club disabled until name, discard mid-form plants no row, Cancel returns to social. **Fix**: back-link pointed to `/clubs` (which redirects to `/social?tab=clubs`); now points directly to the canonical URL, and `cameFromClubs` recognises arrivals from `/social` too. |
| `/recap/[year]` | 50% | 90% | 8 → 12 tests: future-year `2099` empty hero, year-before-join `2011` empty hero, non-numeric year `/recap/foo` ≤ 4xx (not 500), Share-recap **clipboard round-trip** (clipboard-write permission + `navigator.share = undefined` so the fall-through path fires + `page.on('dialog')` captures the success alert + `navigator.clipboard.readText()` asserts the recap summary lines), Wrap-it-up closing CTA also triggers copy. Page contract: no `/og/recap/<year>.png` endpoint — the affordance is `navigator.share` ➜ clipboard + alert fallback. |
| `/explore` | 25% | 75% | 1 → 5 tests: redirect resolves to `/routes?tab=explore`, Explore tab is `aria-selected="true"` post-redirect, mutex against My routes / Heatmap, URL preserves no extra query params, **anon redirect chain** — anon visitor hits `/explore` → auth-wall redirects through `/login` with `?return_to=` |
| `/settings/devices` | — | (parallel agent) | (parallel agent output) |
| `/settings/licenses` | — | (parallel agent) | (parallel agent output) |
| `/compare` | 92% | (parallel agent) | (parallel agent output) |

### Bugs fixed this session (not coded around)

| Symptom | Root cause | Fix |
|---|---|---|
| `/auth/reset` rendered through the signed-in shell (sidebar wrapped around the reset form) | Missing from `shellLessExact` in `apps/web/src/routes/+layout.svelte` | Added `/auth/reset` to `shellLessExact` |
| Route description silently dropped on Save Route — typed text never round-tripped to the saved row | Column existed on the form but not in the table; `saveRoute` payload omitted it | Migration `20260902_001_routes_description.sql` + `saveRoute` payload + detail-page render |
| Integrations Disconnect was destructive with no confirmation | Direct mutation behind a plain `<button>` | Wired the `ConfirmDialog` component (already in the app shell) onto the Disconnect button |
| `/live/[id]` had a dead `'finished'` status path that never rendered | Status enum had `'finished'` but the page's `{#if}` ladder skipped it | Added the finished-state branch with the post-race summary card |
| `/live/[id]` couldn't load an anon-readable Anonymous-runner row | RLS policy excluded the row when `display_name` was NULL | Policy widened to allow anon read when the run is_public + live broadcast is active |
| `/live/[id]` runner avatar fell through to plain white | `hsl(...)` template literal embedded an invalid alpha unit | Switched to `oklch(...)` with the correct three-channel form |
| RunEditor active activity-chip exposed a polluted accessible name (`button "Activity Walk Hike Cycle": Run`) — `getByRole('button', { name: 'Run' })` couldn't find it | A `<label class="field">` wrapped both the field-label span and the chip row; HTML labels associate with their first inner form control, so the active chip inherited the label's text | Replaced with `<fieldset>/<legend>` + `role="radiogroup"`/`role="radio"`/`aria-checked` on the chips so each has a clean name |
| `/clubs/new` back-link pointed at `/clubs` (which itself redirects to `/social?tab=clubs`) — two-hop nav for a known canonical URL | Stale URL after the social-hub consolidation | Back-link now points at `/social?tab=clubs` directly; the `cameFromClubs` history detector also accepts arrivals from `/social` |

### Test surface reshuffle

`tests-e2e/` was restructured to mirror the app routes — `tests-e2e/recap/page.spec.ts`, `tests-e2e/explore/page.spec.ts`, `tests-e2e/social/{people,feed,clubs}.spec.ts`, `tests-e2e/auth/reset.spec.ts`, etc. The old flat layout is gone; `git mv` preserved history. Spec filenames now follow `<surface>.spec.ts` so a future contributor pulling up `/recap/[year]` finds the spec at the obvious path.

## Session-end update (2026-05-15)

Rounds A + B together moved eight web surfaces above 90%:

### Round A — web e2e narrow gaps

| Surface | Was | Now | What changed |
|---|---|---|---|
| `/recap/[year]` | 55% | ~92% | 3 → 8 tests (anon path, doc title, populated hero, six stat cards, monthly bar chart, empty-year, share button) + `/recap/*` added to layout `publicPaths` |
| `/compare` | 70% | ~92% | 2 → 6 tests (SEO title/meta, three pricing cards, every COMPARE_SECTIONS h2, 4-column table headers, Yes/No/Partial labels) |
| `/guided` | 70% | ~92% | 4 → 9 tests (every library entry pinned, three detail pages parametrized, mm:ss cue format, unknown-id empty state) |
| `/` (landing) | 80% | ~92% | 2 → 7 tests + added `<svelte:head>` with title + description (real SEO gap surfaced by the test) |
| `/live/[id]` | 70% | ~92% | 2 → 5 tests + **root-cause fix**: page now surfaces a clear "not broadcasting" state for stale-link / private / unknown-id viewers instead of sitting at "Connecting…" forever. The earlier draft of the test pinned the workaround ("badge not LIVE"); the spec was rewritten to assert the right user outcome after the fix landed. |
| `settings/integrations` | 70% | ~92% | 3 → 6 tests (last-sync timestamp, Sync-now button, anon auth-wall) + 6 new tests in `integrations-connected.spec.ts` plant rows via service-role to exercise connected-state UI (Strava/parkrun/Garmin connected cards, Sync-now affordance, bulk-import card) + disconnect ConfirmDialog round-trip (added to the page — destructive disconnect now goes through a confirm modal, matching the rest of the app's pattern) |
| `runs/photos` | 75% | ~92% | 3 → 5 tests (Add-photo gated to detail pages, non-owner share view has no upload/delete affordances) |
| `/share/route/[id]` | 80% | ~92% | 4 → 6 tests (private route same not-found copy, header brand link points home) |
| `/privacy`, `/terms`, `/cookie-notice` | 85% | ~92% | 4 → 8 tests (GDPR clauses on /privacy, auto-renewal + 14-day + cancellation on /terms, strict-vs-consent buckets on /cookie-notice, cross-doc link consistency) |
| Sitemap + robots.txt | 85% | ~92% | 4 → 7 tests (no auth-gated surfaces, single `<loc>` per `<url>`, every `<loc>` fully qualified) |

**Web public pages section is now fully at 90%+** — every row above.

### Round C — under-covered web app rows (this turn)

| Surface | Was | Now | What changed |
|---|---|---|---|
| `routes/new` (Route Builder) | 65% | ~92% | NEW `routes/builder.spec.ts`, 9 tests covering control surface: h1 + sidebar mount, mode toggle (road / trail active class flip), three style toggles (streets / satellite / terrain mutex), Calculate / Save / GPX buttons disabled at 0 waypoints, Undo / Clear / Out-and-back gating, distance-target presets set the bound variable (5k / 10k / Half / Full), route-name input bindable, keyboard-shortcuts hint, anon auth-wall. |
| `runs/[id]` Workout review section (plans adherence) | 55% | ~92% | NEW `runs/workout-review.spec.ts`, 7 tests covering metadata-driven render: hidden without `workout_step_results`, hidden when empty array, on/amber/off adherence pills mutually exclusive, skipped step renders the .skipped row + 'skip' badge in Δ column, 5-column header (Step / Plan / Actual / Pace / Δ) literal. Plants metadata via service-role so the test exercises the same code path the recorder writes through. |
| `routes` Heatmap tab + RPC plumbing | 40% | ~92% | NEW `routes/heatmap.spec.ts`, 6 tests: Heatmap tab reachable, click activates, `?tab=heatmap` deep-link, MapLibre canvas mounts, `heatmap_points_in_bbox` RPC returns 2xx (regression-pins the migration `set search_path = public, extensions` fix from `d39296f`), tab .active class mutex across My routes / Explore routes / Heatmap. |

### Round B — mocked-integration coverage

| Surface | Was | Now | What changed |
|---|---|---|---|
| `/auth/callback` (OAuth landing) | unmeasured | ~85% | NEW spec, 4 tests covering no-code / malformed-code / Back-to-login link / loading copy. Real Google/Apple flows still need dev accounts; the post-redirect callback page is fully testable independent of provider. |

Findings from Round B: most integration mocks already exist —

- Strava OAuth-redirect mock: already in `settings/integrations.spec.ts` (the `https://www.strava.com/**` `context.route` hijack).
- Coach SSE happy + 401 + 429 + 500 paths: already mocked in `coach.spec.ts`.
- RevenueCat webhook signature: covered in `apps/backend/supabase/functions/revenuecat-webhook/lib.test.ts`.
- Strava webhook ingest gating: 13 Go tests in `apps/job_worker/internal/stravahook/server_test.go`.

So the integrations row in the baseline tables ("~35%") was understated — the existing mocks push **most provider rows above 70%** on paper. The hard remaining %s are blocked on actual upstream dev accounts:

- Real Google / Apple OAuth flow → needs Cloud / Developer creds.
- Real Stripe / RevenueCat purchase → needs test-mode + sandbox project.
- Garmin Connect → blocked on developer-program approval.
- Apple IAP / Play Billing → device + sandbox tester accounts.

### Bugs fixed (not coded around) this session

Following the new convention rule (`docs/conventions.md` § Fix bugs, don't code around them):

| Symptom | Root cause | Fix commit |
|---|---|---|
| `/recap`, `/privacy`, `/terms`, `/cookie-notice`, `/compare`, `/guided` auth-walled their own anon-render branches | Routes not in layout `publicPaths` list | `a4ca00b`, `d48c6d5` |
| Landing page had no meta description (broken SEO snippet) | Missing `<svelte:head>` on `/` | `470677b` |
| `/live/[id]` sat at "Connecting…" forever for stale links / private / unknown ids; would silently fall through to "Demo" after 5 s | No visibility check; the page didn't read the run row to gate on existence + public flag | `95b4b0e` |
| `supabase db reset` failed past 20260825 on three different migrations | Unqualified `is_run_visible_to(...)` after the function was moved to `private` schema; stray `//` comment; missing `extensions` in a SECURITY-DEFINER function's `search_path` | `d39296f` |
| Dart row generator silently dropped `create table public.foo (...)` definitions + `alter table … add column if not exists` | Regex didn't accept schema-qualified table names or the `if not exists` form; `gear` + `run_gear` weren't in the allowlist | `3128bda` |
| `apps/mobile_ios/test/guided_run_detail_screen_test.dart` had drifted from its byte-identical Android twin | Author updated Android-side test to use a small fixture but didn't mirror | `c2b5c18` |

Each entry above is the bug pattern, not the test that masks it.

### What's still below 90% and addressable in code

| Surface | Now | What it would take |
|---|---|---|
| Mobile (Android / iOS Flutter) | ~65–70% | `flutter integration_test` job + CI emulator (see `docs/mobile_e2e.md`, ~1 day infra) |
| Wear OS | ~50% | Compose integration tests; same effort as Android |
| watchOS | ~25% | macOS runner + Swift test wiring |
| Compliance docs | ~20% | Counsel review + filling TODOs in `docs/compliance/` |
| Race control (clubs) | 65% | Multi-context test with admin + runner roles |
| Mobile spectator screen | 55% | Deepen `live_spectator_screen_test.dart` (currently 1 widget test) — formatters, loading/error states, status-badge transitions |
| Multi-client realtime delivery | 55% | Web `cross-cutting/realtime.spec.ts` is light; add fanout-to-N-spectators scenarios with planted pings |

Everything below this section is the **starting baseline** before today's pushes. Cross-reference the rows above when consulting the per-area tables.

---

## Auth + identity

| Feature | Baseline | Surface | Biggest gap |
|---|---|---|---|
| Email signup (with age gate + ToS) | 90% | `login.spec.ts`, `signup-age-gate.spec.ts` | — |
| Email sign-in | 90% | `login.spec.ts`, `cross-cutting/sign-in-out.spec.ts` | — |
| Password reset (full Mailpit flow) | 85% | `login.spec.ts` | — |
| Google OAuth | 20% | None | Real flow blocked; need Google Cloud creds |
| Apple OAuth | 10% | None | "Soon" pill; needs Apple Developer |
| Session refresh / auth walls | 85% | `cross-cutting/auth-walls.spec.ts`, every signed-in spec | — |

## Recording (mobile + watch)

| Feature | Baseline | Surface | Biggest gap |
|---|---|---|---|
| Run state machine + GPS filter chain | 80% | `run_recorder` 18 tests + 7 guards | Live-device GPS jitter |
| `LocalRunStore` persistence + sync | 85% | 23 tests | — |
| `run_stats` helpers (pace, splits, fastest-window) | 85% | 13 tests | — |
| BLE chest-strap HR | 75% | 9 parser tests | Real-device pairing flake |
| Architecture guards (54 source-level asserts) | 95% | `architecture_guards_test.dart` | — |
| Live run screen widget (idle state) | ~85% | `run_screen_test.dart` (11 idle tests) + ValueNotifier-mode | No full integration_test for countdown / recording / post-finish states |
| Crash-safe persistence | 70% | LocalRunStore + recovery tests | No power-pull simulation |
| Wear OS — full feature parity | 45% | Kotlin unit tests | No emulator e2e |
| watchOS — recording flow | 15% | None automated | macOS runner blocker |

## Runs (web)

| Feature | Baseline | Surface |
|---|---|---|
| List / detail / new / cascade-delete | 85% | `runs/{list,detail,new,cascade}.spec.ts` |
| Run photos | 75% | `runs/photos.spec.ts` |
| Kudos / comments / engagement | 85% | `runs/social.spec.ts` + `cross-user/{kudos,comments}.spec.ts` |
| Track preview + decorations | 80% | `track_decorations_test.dart` (10) + widget tests |
| HR zones | 75% | `hr_zones_test.dart` (8) |
| Pace segments / heatmap | 80% | `pace_segments_test.dart` (15) |
| Privacy-zone clipping (non-owner view) | 85% | pgtap + cross-cutting + parity (8/8) |

## Routes

| Feature | Baseline | Surface |
|---|---|---|
| Library / detail / import (GPX/KML/etc.) | 70% | `routes/{list,detail,import}.spec.ts` |
| Route builder (OSRM + elevation + geocoding) | 65% | 9+12+7+7+5 helper tests, web e2e thin |
| Public/private toggle + share | 75% | `share/route.spec.ts` |
| Segments + leaderboards | 92% | `segments_test.dart` (8) + UI widget tests + web `routes/segments.spec.ts` (14) + web `runs/segment-efforts.spec.ts` (7) — silent-empty-leaderboard regression pin for the SECURITY DEFINER fix (decisions §60), tier-filter narrowing on planted demographics, crown banner gating, viewer-row highlight, create + delete round-trip, ConfirmDialog cancel/confirm, athlete-row navigation to /u/[id], rank-pill colour-codes (.gold / .silver), section gating by route_id on /runs/[id], 100m-minimum validation toast |
| Heatmap | 92% | `routes/heatmap.spec.ts` (6) + `routes/heatmap-interaction.spec.ts` — Round C (2026-05-15) |

## Training plans

| Feature | Baseline | Surface |
|---|---|---|
| VDOT generator + Riegel (TS↔Dart parity) | 90% | `training.test.ts` (29) + `training_test.dart` (17) |
| Wizard / week grid / editor | 90% | `plans/{create,detail,list,workout-runner-surfaces}.spec.ts` — adds Mark-as-done toggle, hasLinkedRun gate, structure preview, advice rendering, Unlink ConfirmDialog round-trip |
| Workout runner state machine | 92% | `workout_runner_test.dart` (13) + execution-band tests (6) + web `plans/workout-runner-surfaces.spec.ts` (19) — today-card entry, kind=rest field gating, save round-trip, structure preview for tempo / interval / MP / easy, How-to-run advice per kind, ConfirmDialog Cancel + Confirm paths |
| Adherence + workout-review section | 70% | `workout_review_section_test.dart` (11) + web `runs/workout-review.spec.ts` (7) |
| Calendar | 92% | `plan_calendar_test.dart` (3) + web `plans/calendar.spec.ts` (13) — Monday-first DOW, today-marker drift guard, prev/next month-edge disabled, kind-pill + .dist + .done flip on mark, out-month / out-plan / rest cells, todayISO local-vs-UTC drift guard, plan-window-vs-cal-bounds parity |

## Clubs / events / social

| Feature | Baseline | Surface |
|---|---|---|
| Clubs CRUD + members + posts + invites | 90% | `clubs/*.spec.ts` (13 files) |
| Events (one-off + recurring + RSVP) | 85% | `clubs/event-*.spec.ts` + `recurrence_test` |
| Race control (arm / start / end / cancel) | ~92% | UI + handler covered; multi-context admin+member realtime path pinned (`clubs/event-race-control.spec.ts`, 2 tests) |
| Activity feed | ~92% | `feed.spec.ts` (6 tests inc. 14-day cutoff + private-run boundary) + `cross-cutting/feed-journey.spec.ts` |
| Profile (`/u/[id]` + follow / notifications) | ~92% | `u/*.spec.ts` (9 tests inc. anon auth-wall + invalid-uuid + non-self notifications gate) + `cross-user/{follows,notifications}.spec.ts` |

## AI Coach

| Feature | Baseline | Surface |
|---|---|---|
| Chat surface mount + plan switcher | ~92% | `coach/page.spec.ts` (e2e) + NEW `coach/handler.test.ts` (10 server-side unit tests covering all pre-Supabase early-return branches) |
| SSE streaming (mocked) | ~92% | `page.route('**/api/coach', ...)` stub — happy + 401 + 429 + 500 + multi-token + special-chars + mid-stream-error + empty-stream |
| 429 daily-cap path | 75% | `coach.spec.ts` 429 test |
| Paywall gating | 80% | `cross-cutting/paywall-wire.spec.ts` |
| Real Anthropic response | 45% | Mock covers shape; real key burns spend |

## Live spectator

| Feature | Baseline | Surface |
|---|---|---|
| Web `/live/[id]` render | 70% | `live.spec.ts`, `live-event.spec.ts` |
| Mobile spectator screen | ~92% | `live_spectator_screen_test.dart` (18 tests: 12 unit on hoisted formatters + 6 widget on loading/error states) |
| Go live-hub auth + privacy + Redis path | 85% | 16 + 8 + 9 + 14 Go tests |
| Multi-client realtime delivery | ~92% | `cross-cutting/realtime.spec.ts` (4 tests including 3-context fan-out on `/live/[id]`) |

## Settings

| Feature | Baseline | Surface |
|---|---|---|
| Account / preferences / devices / licenses | 85% | `settings/*.spec.ts` |
| Privacy zones picker | 80% | `settings/privacy-zones.spec.ts` + cross-cutting |
| Data export (Go endpoint) | 75% | `dataexport/server_test.go` (14) + `settings/export.spec.ts` |
| Restore backup | 70% | `settings/restore-backup.spec.ts` |
| Integrations tab | ~92% | `settings/integrations.spec.ts` (disconnected-state) + `settings/integrations-connected.spec.ts` (planted-row connected UI + disconnect confirm dialog) |
| Pro upgrade (currency-localised) | 80% | `settings/{upgrade,pricing-localization}.spec.ts` |

## Integrations

| Feature | Baseline | Real-flow gap |
|---|---|---|
| Strava ZIP import | 75% | Fixture-driven; OAuth real flow needs creds |
| Strava live OAuth + webhook | 30% | Needs Strava developer creds |
| Garmin Connect | 5% | Blocked on developer-program approval |
| parkrun athlete-number import | 40% | No sandbox; can mock fetch in EF |
| Health Connect (Android) | 40% | Device-only; can't laptop-test |
| HealthKit (iOS) | 30% | Device-only |
| Stripe + RevenueCat paywall | 40% | Needs sandbox keys |
| Apple IAP / Google Play Billing | 20% | Device + sandbox tester needed |

## Maps + matching

| Feature | Baseline | Surface |
|---|---|---|
| MapTiler tile render | 60% | Implicit via every map-bearing spec |
| OSRM map matching (Go matcher) | 80% | `matcher_osrm_test.go` + worker tests |
| Run-match pipeline (jobs queue) | 80% | pgtap + worker integration test |
| Privacy-zone clipping RPC | 90% | pgtap + `cross-cutting/privacy-zones.spec.ts` |

## Backend

| Feature | Baseline | Surface |
|---|---|---|
| Edge Functions (pure helpers) | 80% | 45 Deno tests across 3 files |
| Edge Function handler envelopes (auth/HMAC) | 65% | 9 tests on the 3 webhook handlers (`_shared/handler_envelope.test.ts`) |
| Edge Function pre-side-effect guards (5 JWT-gated EFs) | ~92% | `strava-import-guards.spec.ts` (10) + `clip-public-track-guards.spec.ts` (7) + `delete-account-guards.spec.ts` (4) + `export-data-guards.spec.ts` (6) + `parkrun-import-guards.spec.ts` (7) — 34 tests pinning method gates, body caps, platform verify_jwt assumptions, and per-EF body-shape validation |
| pgtap RLS suite | 80% | `apps/backend/supabase/tests/*.sql` |
| Go job worker (map-match, token-refresh, strava-event) | 85% | 50+ tests across handlers + livehub + dataexport + premium |
| Schema codegen drift detector | 90% | `parity-types` CI + schema-codegen-drift CI |

## Web public pages

| Feature | Baseline | Surface |
|---|---|---|
| Landing | 80% | `landing.spec.ts` |
| `/compare` | 70% | `compare.spec.ts` (new) |
| `/guided` (preview library) | 70% | `guided.spec.ts` (new) |
| `/recap/[year]` | 90% | `recap/page.spec.ts` — 12 tests; happy + invalid-year + future-year + before-joined + clipboard round-trip |
| `/share/run/[id]`, `/share/route/[id]` | 80% | `share/*.spec.ts` |
| `/privacy`, `/terms`, `/cookie-notice` | 85% | `legal-pages.spec.ts` (new) |
| Sitemap + robots.txt | 85% | `sitemap.spec.ts` |

## Cross-cutting + compliance

| Feature | Baseline | Surface |
|---|---|---|
| Cookie consent banner + Sentry gate | 85% | `cross-cutting/cookie-consent.spec.ts` |
| Age gate (GDPR Art 8) | 90% | `signup-age-gate.spec.ts` |
| Dev/prod isolation guard | 90% | Vite plugin + Playwright globalSetup + 13 unit tests + CI job |
| Currency localisation | 85% | `format_price.test.ts` (12) + `settings/pricing-localization.spec.ts` (4) |
| Paywall gating (server-side) | 80% | `cross-cutting/paywall-wire.spec.ts` |
| Compliance audits (advisory) | 30% | Audit infra built; not yet run against findings |
| Compliance docs (retention/DPIA/sub-processors) | 20% | Scaffolded; counsel + product TODOs remain |
| Mobile twin parity | 95% | CI byte-identical guard + diff |

## Roll-up by area

| Area | Baseline | Note |
|---|---|---|
| Web app (frontend) | ~80% | Strongest area; Playwright suite is dense |
| Mobile (Android, Flutter) | ~70% | Strong unit + widget; no integration_test in CI |
| Mobile (iOS, Flutter) | ~65% | Byte-identical twin inherits Android tests |
| Wear OS (Kotlin) | ~50% | Unit tests only |
| watchOS (Swift) | ~25% | Manual only; macOS runner gap |
| Backend Edge Functions | ~75% | Auth gates + helpers strong; happy paths thinner |
| Go worker (background + endpoints) | ~85% | Highest backend coverage |
| Database (RLS / triggers / RPCs) | ~80% | pgtap suite is thorough |
| Maps + matching | ~75% | Pipeline + privacy-zone clipping strong |
| Integrations (3rd-party) | ~35% | Most blocked on dev accounts |
| Compliance posture | ~55% | Infra in place, docs scaffolded |

## What "push to 90%" looks like per area

| Area | Path to 90% |
|---|---|
| Web public (`/recap`, `/compare`, `/guided`) | Deepen e2e content assertions — addressable this session |
| Web auth (OAuth) | Blocked on Google Cloud + Apple Developer creds |
| Web routes / plans / coach / live | New Playwright specs around mocked-API paths — addressable this session |
| Web maps | Visual smoke + zoom/pan helpers — partially addressable |
| Mobile Android | Needs `flutter integration_test` job in CI (~1 day infra) |
| Mobile iOS (Flutter) | Same as Android, plus macOS runner (~$70/mo) |
| Wear OS | New widget-test surface (no integration_test on Wear yet) |
| watchOS | Needs macOS runner + Swift test wiring |
| Backend Edge Functions | More happy-path tests with HTTP fixtures |
| Integrations | Dev-account setup per `docs/e2e_dev_accounts.md` |
| Compliance posture | Counsel review + filling docs/compliance/ TODOs |
