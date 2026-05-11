---
name: Gap-closure follow-ups
description: Outstanding work after the 2026-05-10 gap-closure session. Mirrors `roadmap.md` in spirit — checkboxes, brief context, no doc-rot. Prune entries as they land.
---

# Gap-closure follow-ups

Session of 2026-05-10 ran through the four highest-priority test-coverage gaps from `docs/testing.md` "What's not covered" and closed three of them plus a CI gap and four production bugs (see "What landed" below). The pending work below is what remains.

Pick up cold by reading this file + `docs/testing.md` "What's *not* covered" — both should reflect current state.

## What landed this session

**Tests + CI infrastructure (8 commits):**
- `pgtap-rls` CI job — gates the full 279-test pgTAP RLS suite on every PR
- 7 new pgtap suites (route_reviews, segments, clubs, club_members, club_posts, events, event_attendees) — closes the original "still uncovered tables" list
- `api-client-integration` CI job — boots local Supabase + runs `flutter test` against the seed user; covers the five priority `ApiClient` wire-level methods (signIn / getRuns / saveRun + _uploadTrack / fetchTrack)
- `SocialService.withClient` + `TrainingService.withClient` DI seams + 5 wire-level integration tests on the same CI job
- `edge-functions` CI job — boots `supabase functions serve --env-file`, runs 9 HTTP-level handler-envelope tests for refresh-tokens / strava-webhook / revenuecat-webhook + the pre-existing pure-helper deno tests that had no CI coverage

**Production bugs fixed:**
1. `is_route_visible_to` revoke from anon (migration 20260711_001) broke anon SELECT on `route_reviews` + `segments` — PG 17.6 manifested it as a backend SIGSEGV instead of clean 42501. Fixed by moving the function to the `private` schema and granting anon EXECUTE (migration 20260819_001, mirrors the parallel for `is_run_visible_to`).
2. `club_posts` had three INSERT policies stacking; the older two (`admins can post top-level` + `active members can reply`) had been dead code since 20260428_001's `members can post` catch-all landed. Cleanup migration 20260820_001.
3. `ApiClient._uploadTrack` + `uploadTrackBytes` set `contentType: application/json` for gzipped JSON bytes — every live-recording save on mobile was 415'ing silently against the runs-bucket MIME allowlist (migration 20260815_001). Fixed.
4. `seed.sql` "restored canonical" `track_url` after the path-shape CHECK exercise, leaving an orphaned URL pointing at a non-existent Storage file. Any dev using the seed user got fetchTrack 404s. Fixed.
5. `hmacHex` RFC 4868 reference-vector test had been silently wrong since written — the body construction UTF-8-expanded each 0xcd byte into `c3 8d`. Refactored hmacHex to accept `Uint8Array` so byte-exact tests actually represent the bytes they claim.

## Carry-over from "completed" tasks

These tasks are marked completed at the high-leverage surface but have known sub-gaps left for follow-up.

### Mobile testing gaps (from session task #3)

- [ ] **RunScreen Finish + save UI test.** Tried during the session; reverted. The existing widget-test scaffold doesn't fully initialise `RunRecorder` from `run_recorder` so `_stop()` doesn't produce a row in `LocalRunStore`. Needs additional platform-channel mocks for whatever the recorder depends on at start time. Data-pipeline equivalent (`recording_integration_test.dart`) IS covered — only the UI Finish-tap surface remains uncovered.
- [ ] **Device-instrumented `integration_test` harness.** None exist today. Would close real-device coverage for tile-cache, foreground-service, and background-sync paths that need actual Android primitives. New infrastructure.
- [ ] **Widen the `SocialService` / `TrainingService` wire-level suite.** The seam + 5-test scaffold is in place (`services_integration_test.dart`); adding new tests is one block per method. ~25 untested Supabase-touching methods across both services. Bug-discovery yield: probably moderate — the 5 existing tests passed first try, so this surface is more correct than the ApiClient one was.

### Edge Function tests (from session task #4)

- [ ] **OSRM smoke test in CI.** Genuinely blocked on free-runner capacity — the OSM PBF extract + osrm-extract memory pressure don't fit. Real options: self-hosted runner, or a pre-built OSRM cache in S3 the workflow downloads. Both are infra decisions outside the code.
- [ ] **Positive-path Edge Function tests.** Current handler-envelope suite only covers auth-rejection branches. Adding 200-on-valid-HMAC / replay-protection-dedupe / freshness-window tests needs real secret values in the test config — straightforward to add once we decide on a CI-side secret config strategy.

## Pending tasks (session-order)

### #5 Phase 1+2b ops

- [x] **MapTiler API usage monitoring** (Phase 1, roadmap.md) — runbook landed in `apps/web/deployment.md` § Other alerts. No CloudFront proxy on the tile path (clients hit `api.maptiler.com` directly) so the alert lives MapTiler-side: 80% threshold against the monthly quota, daily-usage email to the SNS oncall address. Operator follow-up: actually click through the MapTiler dashboard once for prod + preview; the runbook covers each step.
- [x] **Verify dashboard queries are under 2 s for users with 200+ runs** (Phase 2b, roadmap.md). Measured locally at 2074 runs — all three queries (`fetchRuns(limit:50)`, `fetchWeeklyMileage`, `fetchPersonalRecords`) ran in 0.1–1 ms, ~1000× under the 2 s budget. No index changes needed; the existing composites carry it. Roadmap Phase 2b checkbox ticked.

### #6 Android residuals (parity.md follow-ups)

- [ ] Ultra-length recording (mobile_android backlog #117 — long-runs >6 h crash-resume guarantee)
- [x] Club-template publish action — AppBar publish button on `plan_detail_screen.dart` opens a picker of the viewer's owner/admin clubs (via `adminClubsForPublish` filter), then commits via `TrainingService.publishPlanAsTemplate`. Found + fixed two latent bugs while wiring: (1) Dart was calling a non-existent `publish_plan_as_template` RPC — replaced with the canonical multi-INSERT path that mirrors web `data.ts`; (2) `clonePlanTemplate` was passing `p_template_id` / `p_start_date` (with stray `p_` prefix) — corrected to `template_id` / `new_start_date` matching the actual `clone_plan_template` SQL signature. Test coverage: 3 unit tests on `adminClubsForPublish`, 3 widget tests on `PublishClubPicker`, 1 wire-level integration test for `publishPlanAsTemplate` against real Supabase. Twin-mirrored.
- [ ] Club-owned-route admin transfer / detach UI on `route_detail_screen`
- [x] Device-override "+ Add override" sheet in Settings → Devices — registry of 10 D/UD keys in `devices_screen.dart` drives a key-picker → type-aware value-editor flow (bool / enum / int / double). Excludes purely-universal keys that have no device-scope semantics. 5 new unit tests pin the registry shape. Mirrored to iOS.
- [ ] Pro native RevenueCat purchase sheet + native donate (`purchases_flutter` mobile Pro flow)
- [ ] Full-screen route builder (mobile click-to-place + OSRM snap + elevation-preview-while-drawing — see `mobile_android_backlog.md` Route-management section)
- [ ] Auto-link unmatched run to saved route on save
- [ ] Map-matched track display (gated on Map-matching deploy under #14)
- [x] Per-point BPM HR-zone view from the phone recorder — `RunRecorder.setHeartRate(bpm)` stamps each `BleHeartRate` sample onto the next constructed waypoint. Out-of-range guard at the recorder (< 30 or > 230 BPM). 2 new unit tests in `run_recorder_test.dart`. The breakdown panel on `run_detail_screen.dart` was already wired against `track[].bpm`; now phone-recorded runs feed it too.

### #7 Workout execution v2

Per `docs/workout_execution.md` deferred section:
- [x] `rewindStep` UI control — `WorkoutRunner.rewindStep()` + leftmost band button (disabled on step 0). 4 new runner tests + 2 new band tests.
- [ ] Ghost-pacer marker on the map
- [ ] Duration-based steps (v2)
- [ ] Crash-checkpoint resume

### #8 In-app route builder (mobile)

Phase 3 "In-app route builder (free)" — 4 unchecked items in `roadmap.md`. Web has it at `/routes/new`; mobile needs the equivalent. Largely subsumed by Android residuals "full-screen route builder."

### #9 Push notifications + Monetisation

- [ ] **FCM (Android) + APNs (iOS) push notifications.** Phase 4b. Blocked on Firebase / APNs credentials being set up — both the platform creds AND `VAPID_PRIVATE_KEY` for the web Push API.
- [ ] **Mobile Pro purchase flow.** `purchases_flutter` RevenueCat native sheet on Android + iOS, plus the donate hand-off via in-app browser. Phase 3 monetisation.

### #10 External integrations

Phase 3 "External platform sync" — entire table is `[ ]` in roadmap.md:
- [ ] HealthKit (iOS)
- [ ] Health Connect (Android)
- [ ] Strava OAuth + sync (Edge Function `strava-import` exists, not wired into client)
- [ ] Garmin (multi-day Developer Program application + OAuth)
- [x] parkrun athlete-number import — already shipped on Android/iOS. Settings → Integrations → "parkrun" tile in `settings_screen.dart` (line 1274) calls `_importParkrun`, pre-fills from `user_profiles.parkrun_number` via `fetchMyProfile`, then drives `ApiClient.setParkrunAthleteNumber` + `ApiClient.importParkrunResults` (invokes the existing Edge Function). Parity.md already lists it as ✓. The followups entry was stale.
- [ ] RunSignUp

### #11 Platform parity (multi-platform)

- [ ] **iOS** — the byte-identical Dart codebase is there; almost every parity.md row still `✗` or `Partial` pending Mac-build runtime verification. High-leverage gaps: GPX/KML/TCX import, recording verification, run history surface, social, settings, Strava/parkrun wiring, BLE HR pairing, share-as-image, public/private toggle, Apple Sign-In Services-ID.
- [ ] **Apple Watch** — route nav visuals, ultra-length stress, live race participant, complication target wiring (Xcode Widget Extension), activity types, lap markers, hold-to-stop, TTS cues, pedometer, GPS self-heal, indoor mode, route picker UI, BLE pairing UI.
- [ ] **Wear OS** — settings surfaces mostly unmirrored from universal-prefs keys.

### #12 Backend Go service (Phase 2/3)

Whole Go service on Fly.io. Live spectator WS hub, job queue, Strava webhook migration off Edge Function, token-refresh worker, export worker, Upstash Redis for ephemeral position store. Then premium Go endpoints: `/training-plan`, `/vo2max`, `/race-predictor`, `/recovery`.

### #13 Live spectator WebSocket (blocked by #12)

Replace the current simulated WS with a real connection to the Go service. Wire the spectator UI to subscribe to ephemeral position updates from Redis. Single PR once #12 lands.

### #14 Map matching + Protomaps + parity audit (Future)

- [ ] **Map matching deploy:** OSRM alongside Supabase, OSM extract refresh pipeline, auth endpoint, return matched geom to mobile, raw-vs-matched toggle, offline fallback. Engine choice + trigger wiring already shipped; deploy is what remains.
- [ ] **Protomaps self-hosted tiles** — all 4 items from roadmap.md "Future" section.
- [x] **Cross-platform parity periodic audit in CI** — new `parity-matrix` CI job runs `scripts/check_parity_matrix.dart` on every PR. Validates row column count, legal cell values (`✓ / ✗ / Partial / N/A` only), the iOS-ahead-of-Android impossibility (decisions §39), and Partial-without-Notes. Caught 3 real drift bugs on first run (Garmin row with stray `|`, `"✓ (read-only)"` non-standard cell, empty-Notes Partial); all fixed. Cross-client integration test in CI is still open.

### #15 Competitor backlog + SEO route pages

From `roadmap.md` "Competitor-parity backlog (unphased)" — open items only (about half the table already shipped):
- [ ] Heatmap / popular-route discovery (#4)
- [ ] Trail / offline navigation (#5)
- [ ] Gear tracking (#7)
- [ ] Audio-coached runs (#9)
- [ ] Race calendar + results import (#10)
- [ ] Advanced analytics polish (#11)
- [ ] Premium billing extensions (#12)
- [ ] Treadmill BLE FTMS (#13)
- [ ] SEO-indexed public route pages (Phase 3 "Community route library")
