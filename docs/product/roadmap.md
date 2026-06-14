# Run app — product roadmap

## Status at a glance

*Snapshot 2026-06-03. The per-item checkboxes below remain the source of truth — this section is just the orientation layer on top of them.*

- **Shipped (built + tested in-repo): Phases 1, 2, 2b, 3.** Phone recording (Android + iOS), Apple Watch + Wear OS standalone recording, the SvelteKit web app, the full social layer (following + feed, kudos / comments, clubs + events, segments + leaderboards, run photos, notifications inbox, gear), AI Coach, training plans + generator + training-load / VO₂ analysis, monetisation infra (RevenueCat Pro tier), and six-locale i18n across every client.
- **In flight — Go-service production cutover.** The live-spectator WebSocket hub (+ Redis fan-out), Strava webhook, token refresh, data export, and premium endpoints are all code-complete and tested under `apps/job_worker/`. What's left is operator-only: deploy to Fly.io, point `live.threkir.com` at it, set the secrets, then flip `PUBLIC_LIVE_HUB_URL` (web) + `LIVE_HUB_URL` (mobile). No client code changes.
- **Blocked on external credentials / approval.** Garmin Connect (developer-program application), native push FCM / APNs (Firebase + APNs keys + client token registration), RunSignUp race results (API key), live in-app-purchase sheets (RevenueCat dashboard config), watchOS complication (Xcode Widget Extension target).
- **In progress: Phase 4 — multi-modal gym + nutrition.** Data foundation (migration `20261204_001`) + the web **gym** module are shipped; the web cross-modality Tier-1 layer has landed — lift→load wired into the dashboard fitness curve, bounded recent-lifts + 7-day nutrition in the Coach context, self-hiding gym cards on Home, and the unified `/history` activities timeline with kind chips. The web **nutrition** module has now landed too: `/nutrition` (Mifflin-St Jeor macro rings, meal-slot log, water, weekly trend) + `/nutrition/log` (Open Food Facts search → confirm portion, manual fallback) + Settings body-metrics entry + the `body_metrics` migration. The **mobile nutrition** screens have now landed too (Android + byte-identical iOS twin: `nutrition_screen.dart` + `nutrition_log_sheet.dart` + `food_search.dart`). The **mobile shell reshape has landed (G5):** the bottom nav is `Home / History / Log / Social / Settings` with a centre Log action sheet, the Home dashboard composes self-hiding today's-lift + nutrition rings + recent-lifts cards, and a Settings → Body metrics entry (Art 9 consent-gated) feeds real nutrition targets. The **mobile cross-modality layer has now landed too:** lift→load wired into the mobile dashboard fitness curve (`lift_load.dart`), the recent-lifts trend card, and the unified mobile **History** timeline (`runs_screen.dart` + `activity_timeline_list.dart`, assembled from the local stores via `lib/local_activities.dart` — offline-first). Web's gym/nutrition surfaces were then **ungated to match mobile** (2026-06-04, [decisions §63 amendment](../architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db)): the Gym + Nutrition sidebar items are always present and the dashboard cards + history chips self-hide on data presence; the `multi_modal_nav` flag is retired. The **social-feed lift cards + gym sharing have now landed too** (2026-06-12, web + mobile): a public/private toggle + copy-share-link on `/gym/[id]` (+ mobile `gym_detail_screen`), a read-only public `/share/workout/[id]` page, and lift cards in the feed via `fetchFollowingActivityFeed` (runs through `public_runs`, public lifts through `gym_workouts` RLS, merged) with a `Lift` filter chip. The web admin moderation page (`/admin/reports`) has now landed too (DB-enforced admin allow-list + triage queue; [decisions §142](../architecture/decisions.md#142-admin-authorization-is-db-enforced-via-app_admins--a-privateis_admin-oracle-never-client-side-route-gating)). Remaining: (operator) the iOS/Play privacy-form updates for body metrics + Open Food Facts. Also queued but unscheduled: an RTL locale, Protomaps self-hosted tiles, and map-matching deploy.

---

**Contents:** [Status at a glance](#status-at-a-glance) · [Vision](#vision) · [Strategic pillars](#strategic-pillars) · [Architecture evolution](#architecture-evolution) · [Phase 1 — MVP: prove the core loop](#phase-1--mvp-prove-the-core-loop) · [Phase 2 — watch parity: wrist-first experience](#phase-2--watch-parity-wrist-first-experience) · [Phase 2b — web app: plan big, review deep](#phase-2b--web-app-plan-big-review-deep) · [Phase 3 — growth and monetisation](#phase-3--growth-and-monetisation) · [Phase 4 — multi-modal: gym + nutrition](#phase-4--multi-modal-gym--nutrition) · [Multi-language (i18n)](#multi-language-i18n-across-all-clients--landed) · [Future — Protomaps self-hosted tiles](#future--protomaps-self-hosted-tiles) · [Future — Map matching (Strava / Nike Run Club quality)](#future--map-matching-strava--nike-run-club-quality) · [Future — Cross-platform parity enforcement](#future--cross-platform-parity-enforcement) · [Future — Hardware: ultra-marathon-optimized watch](#future--hardware-ultra-marathon-optimized-watch) · [Competitive positioning](#competitive-positioning) · [Tech stack summary](#tech-stack-summary) · [Cost projection](#cost-projection) · [Deferred from Phase 1 (Android-specific)](#deferred-from-phase-1-android-specific) · [Known issues — runs storage + bulk import](#known-issues--runs-storage--bulk-import) · [Open risks](#open-risks) · [Anti-spam / moderation — what's shipped, what's deferred](#anti-spam--moderation--whats-shipped-whats-deferred) · [Competitor-parity backlog (unphased)](#competitor-parity-backlog-unphased)

## Vision

A cross-platform running app that covers every device and surface a runner might use — iPhone, Android phone, Apple Watch, Wear OS, and a full desktop web app — with seamless route planning, live spectator tracking, ML-powered training plans, and free access to the features every other app puts behind a paywall.

---

## Strategic pillars

1. **MapLibre GL JS** — open-source vector maps with smooth rendering, 3D terrain, and zero vendor lock-in
2. **Watch parity** — Apple Watch and Wear OS treated as first-class platforms, not companions
3. **Free core** — route building, GPX import, and run history stay permanently free
4. **Open ecosystem** — sync with Strava, HealthKit, Health Connect, parkrun, and race results
5. **Web as a power tool** — the web app is where you plan, analyse, and manage; the phone and watch are where you run
6. **Scale-ready backend** — two-service architecture that grows from a single Supabase project to include a Go service for real-time and background processing

---

## Architecture evolution

```
Phase 1:    Supabase only (CRUD, auth, storage)
Phase 2:  + Go service    (WebSockets, background jobs)
Phase 3:    Go service handles premium features (training plans, VO2 max — rule-based)
Future:   + Python service if/when ML model training requires it
```

Full technical details in `backend_scaling.md`.

---

## Phase 1 — MVP: prove the core loop

**Target:** ~8 weeks
**Goal:** A working, testable app that covers plan → run → review
**Backend:** Supabase only

### GPX / KML import

The primary differentiator. Users export a KML from Google My Maps or any other source and open it directly in the app. The route loads instantly on a map, ready to run. No account required. Free forever.

- [x] Parse GPX, KML, KMZ, and GeoJSON formats (web)
- [x] Display route with distance and elevation summary on import
- [x] Save imported route to Supabase
- [x] Parse GPX, KML, GeoJSON, and TCX on Android (file picker + LocalRouteStore)
- [x] Parse on iOS — `apps/mobile_ios/lib/screens/import_screen.dart` is byte-identical to mobile_android per [decisions.md § 39](../architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase) and uses the same `packages/gpx_parser` engine; iOS widget suite (`import_screen_test.dart`, `importer_external_id_test.dart`, `strava_importer_helpers_test.dart`) exercises the path. Real-device file-picker validation still TBD.

### Live GPS run recording (phone)

Track position, pace, distance, and elapsed time using device GPS. Runs saved to local storage first — no backend required at this stage.

- [x] Background location tracking (Android — geolocator foreground service)
- [x] Background location tracking (iOS — CLLocationManager background mode via run_recorder; Info.plist UIBackgroundModes:location + NSLocationAlwaysAndWhenInUseUsageDescription; verified on simulator)
- [x] Real-time pace and distance display (Android)
- [x] ~~Auto-pause on stop detection~~ (Android) — *removed*: replaced by moving time derived from the GPS track at summary time. See [decisions.md § 4](../architecture/decisions.md).
- [x] Manual pause/resume (Android)
- [x] Lap markers (Android)
- [x] Wakelock during run (Android)
- [x] Activity types — run, walk, cycle, hike — with per-type pace/speed display, calorie multipliers, split intervals, and GPS filters (Android)
- [x] Audio cues for splits and pace alerts via TTS (Android) — pace alerts also fire `HapticFeedback.heavyImpact()` (double pulse for "speed up", single for "slow down") so the cue lands with headphones paused
- [x] Step count and cadence via pedometer (Android)
- [x] Live HTTP tile cache so revisited tiles work without network (Android)
- [x] GPS self-heal retry loop — recorder re-subscribes automatically when location services / permission come back mid-run (Android)
- [x] Indoor / no-GPS mode — run proceeds as time-only when GPS is unavailable; stopwatch keeps ticking, `RunSnapshot.currentPosition` is nullable, and the live map falls back to "Waiting for GPS..." (Android)
- [x] Live lock-screen notification — `RunNotificationBridge` replaces the static "Run in progress" with live time / distance / pace on the same geolocator foreground-service channel (Android)

### Route overlay during run

Show the imported route on the map while running. Current position tracks against the planned line. Off-route haptic alerts when drifting more than 50m from the path.

- [x] Live position marker on route (Android)
- [x] Off-route detection and alert (Android — banner + TTS at >40m)
- [x] Distance remaining to end of route (Android — projects current position
      onto the closest route segment, sums remaining segment lengths)

### Run history + basic stats

Persist completed runs locally with distance, duration, average pace, and a map trace of the actual path taken.

- [x] Run list sorted by date
- [x] Individual run detail view (map + stats)
- [x] Weekly mileage summary on home screen
- [x] Elevation chart on run detail (Android)
- [x] Lap splits on run detail (Android)
- [x] Edit run title and notes (Android); manual-entry runs also let the user correct distance + duration in the same dialog
- [x] Share run as GPX (Android)
- [x] Share run as image card — map + headline stats (Android)
- [x] Save a history run as a reusable route (Douglas–Peucker simplified track) (Android)
- [x] Add a run manually — date/time, duration, distance, optional saved route (Android)
- [x] Delete runs (Android)
- [x] Multi-select runs in history and bulk delete (Android)
- [x] History sort by newest, oldest, longest, fastest (Android)
- [x] History date filter — today, this week (default), last 30 days, this year, all time (Android)
- [x] Personal Bests on dashboard — longest run, fastest pace, fastest 5k (Android)
- [x] Weekly distance goal with progress bar (Android)
- [x] Multi-goal dashboard — distance / time / avg-pace / run-count, weekly or monthly, with per-goal progress feedback (Android, web)
- [x] Browsable weekly/monthly summary — navigate to previous periods from dashboard, share as text or screenshot (Android)

### Cloud sync + auth

- [x] Supabase Auth with email/password sign-in and sign-up
- [x] Google and Apple OAuth scaffolded (needs provider credentials to enable); iOS: Apple Sign-In scaffolded behind _kAppleSignInEnabled = false pending Services ID setup
- [x] Auth callback route for OAuth redirect
- [x] Onboarding flow on first launch with location permission request (Android)
- [x] Pre-run background-location nudge (Android 11+) — the initial dialog only grants "while in use", so before a run starts `run_screen` checks for `ACCESS_BACKGROUND_LOCATION` and, when missing, deep-links to app settings ("Allow all the time"). Non-blocking. Pure `background_location_nudge.dart` (persona #57); iOS twin returns false (its own Always escalation).
- [x] Offline-only mode — runs work without backend or auth (Android)
- [x] UUID run IDs to avoid sync collisions across devices
- [x] Pull remote runs from Supabase, merge with local store (Android)
- [x] Bulk sync button for unsynced runs (Android)
- [x] Backup all runs as JSON via system share sheet (Android, web)
- [x] Auto-sync on connectivity change and app foreground (Android — via
      `connectivity_plus` + lifecycle observer)
- [x] Conflict resolution: newer-wins by `last_modified_at` timestamp (Android)
- [x] Strava data export ZIP import (Android — `activities.csv` + per-run
      GPX/TCX/FIT track files)
- [x] Health Connect import — pulls workouts from Google Fit, Samsung Health,
      Garmin Connect, Fitbit, Runna, etc. (Android, summary only — no GPS routes)
- [x] WorkManager-based periodic background sync (Android, when app is closed)

### Backend work (Phase 1)

- [x] Database schema: runs, routes, integrations, user_profiles tables
- [x] Row-level security policies on all tables
- [x] Database functions (weekly_mileage, personal_records)
- [x] Seed script with test user and mock data
- [x] Edge Functions: parkrun-import, strava-import, strava-webhook, refresh-tokens, export-data, revenuecat-webhook, delete-account
- [x] Move GPS tracks from JSONB `track` column to Supabase Storage. Tracks
      are now gzipped JSON files at `runs/{user_id}/{run_id}.json.gz` and the
      row stores a `track_url` pointer. Cuts per-row size by ~99%, eliminates
      jsonb column bloat on the dashboard query path, and lets bulk imports
      (Strava, Health Connect) scale to 100K users on a $25/month Supabase
      plan instead of needing the Team tier.
- [x] Encrypt OAuth tokens in `integrations` — migration `20260603_001_integrations_vault.sql` drops the plaintext `access_token` / `refresh_token` columns and replaces them with `access_token_secret_id` / `refresh_token_secret_id` UUID references into `vault.secrets` (Supabase Vault, libsodium, project-managed master key). SECURITY DEFINER helpers `get_integration_tokens` / `set_integration_tokens` encapsulate the admin-only `vault.decrypted_secrets` view so EFs don't need extra grants. See decisions.md § 41.
- [x] Add rate limiting to Edge Function endpoints — migration `20260604_001_rate_limits.sql` adds a `rate_limits (user_id, bucket, window_start, count)` table + a SECURITY DEFINER `check_rate_limit(user, bucket, max, window)` function that does an atomic upsert-and-check with fixed-window bucketing. Shared `_shared/rate_limit.ts` helper turns denials into a 429 with `Retry-After`. Wired into `parkrun-import` (4/h), `strava-import` (10/h connect, 4/h sync), `delete-account` (3/h), and `export-data` (2/h). Hourly pg_cron sweep cleans rows >24 h old.
- [x] Validate Strava webhook receivers — Strava doesn't sign POST payloads (their model is "the callback URL is secret"). The function requires `STRAVA_WEBHOOK_SECRET` in the URL query string, validates it with a `timingSafeEqual` constant-time compare, and additionally checks `hub.verify_token` on the GET handshake. Fails closed when the env var is missing. See `apps/backend/supabase/functions/strava-webhook/index.ts`.
- [x] Set up MapTiler API usage monitoring — runbook in `apps/web/deployment.md` § Other alerts. Clients hit `api.maptiler.com` directly (no CloudFront proxy → no CloudWatch metric path), so the alert lives MapTiler-side: enable **Account → Notifications → Daily usage email** with an 80% threshold against the monthly quota (free tier = 100k tile requests/month → trigger at 80k). When the alert fires the response options are documented inline (raise mobile tile-cache TTL or kick off the Protomaps migration).

### Milestone: internal TestFlight / Play Store internal track release

---

## Phase 2 — watch parity: wrist-first experience

**Target:** ~6 weeks after Phase 1
**Goal:** Both watch platforms feel like first-class running computers, not companion screens
**Backend:** Supabase + Go service

### Apple Watch standalone GPS recording

- [x] Standalone workout session (no phone required)
- [x] Heart rate via HealthKit sensor (live BPM in `RunningView`, `avg_bpm` forwarded in run metadata)
- [x] Haptic pace alerts (above / below target)
- [x] Syncs run data via Watch Connectivity framework — `WatchConnectivityManager.swift` posts gzipped track + metadata via `WCSession.transferFile(_:metadata:)`; the iOS Flutter `WatchIngestBridge` decodes and persists. WatchIngestQueue on the phone side persists pre-auth payloads to disk so a restart between watch transfer and sign-in doesn't lose the run.

### Wear OS standalone GPS recording

- [x] Compose-for-Wear UI (pure Kotlin rewrite — see [decisions.md § 15](../architecture/decisions.md))
- [x] GPS recording independent of phone (`FusedLocationProviderClient` in `GpsRecorder.kt`)
- [x] HR recording via Health Services (`MeasureClient` in `HeartRateMonitor.kt`, average pushed to `run.metadata.avg_bpm`)
- [x] Ultra-length (10h+) recording: streaming on-disk track writer, rolling-HR aggregation, checkpoint-by-reference, throttled notification refresh, streamed gzip upload, low-battery pre-run warning
- [x] Battery-optimisation whitelist nudge — "Fix battery saver" pre-run chip + instruction card. Samsung One UI Watch (persona #35) is steered to the Galaxy Wearable manual path because the system whitelist intent is a no-op there; strategy in `system/BatteryGuidance.kt` (unit-tested)
- [x] Live race mode: server-authoritative Arm/GO/End + per-runner pings feeding a spectator leaderboard, auto-submitted `event_results` rows, optional organiser approval gating
- [x] Recording UX parity with Android — pre-run activity picker (run / walk / hike / cycle cycles via a CompactChip), 3-second start countdown (`CountdownOverlay`), pause / resume, lap button + splits table on PostRun, 800 ms hold-to-stop with circular progress ring, haptic confirmations on lap / pause / resume (`LocalHapticFeedback`)
- [x] TTS audio cues (`recording/TtsAnnouncer.kt`) — "Run started", per-km splits, pace-drift nudges, "Run complete". Gated on `BuildConfig.ENABLE_TTS`; phrasing mirrors `apps/mobile_android/lib/audio_cues.dart`.
- [x] Target-pace picker + haptic pace alerts — pre-run **Pace** chip cycles off / 4:00 / 4:30 / 5:00 / 5:30 / 6:00 / 6:30 / 7:00 per km; `RunRecordingService.firePaceAlert` vibrates (double pulse for "speed up", single for "slow down") + TTS nudge when live pace drifts >30 s, rate-limited to 1/30 s.
- [x] Pedometer + `metadata.steps` — `Pedometer.kt` via `Sensor.TYPE_STEP_COUNTER` with per-run baseline; live "N steps" readout on RunningScreen; writes `run.metadata.steps` when the sensor produced samples. Requires `ACTIVITY_RECOGNITION` (added to `permissionLauncher`).
- [x] GPS self-heal — 10 s watchdog in `RunRecordingService` re-subscribes to the Fused provider when the stream stalls for 30 s despite `locationAvailable=true`
- [x] Indoor / no-GPS mode — clock + `TrackWriter` handle zero-fix runs; RunningScreen banner distinguishes "No GPS — time only" (never had a fix) from "GPS lost" (lost mid-run)
- [x] Auto-sync on reconnect — `system/NetworkWatcher.kt` exposes a `ConnectivityManager.NetworkCallback` flow; `RunViewModel.observeConnectivity()` fires `drainQueue()` on every offline→online transition (seeds first emission to skip the cold-start case).
- [x] Manual sync chip on `PreRunScreen` — the "N runs to sync" caption at the top of the home screen is now a tappable `CompactChip` that calls `vm.sync()` (which wraps `drainQueue()` with a `syncing` UI flag). Disabled when offline or already syncing; spinner replaces the label while a drain is in flight. Complements the auto-drain triggers (connectivity edge, app cold-start, post-run) for the "I just got home and want my run synced now" case.

### Route navigation on watch

Pure route-geometry helpers (`offRouteDistanceM`, `routeRemainingM`) are ported to Kotlin as `watch_wear:recording/RouteMath.kt` with a 17-test mirror suite against the Dart twin. Route data syncs to the watch via `SupabaseClient.fetchRoutes` + `LocalRouteStore`. The pre-run Route chip + picker wire a selection into the recording loop, and `RunningScreen` renders the off-route banner (with hysteresis + haptic) and the "X to go" badge. What's left: rendering the route *visually* during a run, which requires a live map on the watch.

- [x] Route sync to the watch (`SupabaseClient.fetchRoutes` + `LocalRouteStore` DataStore cache; drains on picker open)
- [x] Pre-run Route chip + picker screen (`Stage.RoutePicker` with "None" + per-route chips)
- [x] Off-route haptic + banner on `RunningScreen` (threshold 40 m on / 20 m off, double `HapticFeedback.LongPress` on entry)
- [x] "X.XX km to go" badge on `RunningScreen` under the distance readout
- [x] Route preview on watch face before starting — `PreRunScreen` mounts `RouteMiniMap` (80 dp) under the Route chip when a route is selected. Reuses the same projection helper as the in-run mini-map; `current = null` because GPS hasn't started, so the viewport just frames the polyline. Tap the preview to re-open the picker.
- [x] Live position on mini-map during run — `ui/RouteMiniMap.kt` renders the planned-route polyline + a position-dot on `RunningScreen` whenever a route is loaded. Pure projection helper `recording/MapProjection.kt` (10 unit tests) handles the lat/lng → unit-square math with auto-fit bounds + padding. Tile background deferred to v2 — at 56 dp on a 46 mm screen raster tiles aren't legible anyway, and skipping them keeps power + storage costs at zero.
- [x] Track-so-far overlay on the mini-map — the polyline of where the runner has actually been is drawn behind the planned route (faded indigo, alpha 0.55) so they can see drift at a glance. Service appends one point per GPS sample to a rolling buffer capped at 256 points; `recording/TrackOverlayBuffer.halveIfOverflowing` does geometric (every-other) downsampling in place when the cap is exceeded — preserves the run start and the latest fix, converges in `ceil(log2(n/cap))` iterations. 7 unit tests on the buffer, 3 source-level wiring guards on the propagation chain.
- [x] Mini-map for free-form runs — the in-run mini-map used to require a planned route to render. Now mounts whenever there's *anything* to show (route OR ≥2 track points OR a current GPS fix), so a free-form run shows the runner's track-so-far + position dot as a "shape of my run" view. Pre-run preview shrunk 80 → 56 dp; the pre-run screen is a region-anchored `Box` (status captions top, action pills centred, battery/sign-out icons on the chord) so content overflow in one region can't shove the Start button into the system `TimeText` — no full-column scroll. The genuinely scrollable Wear screens (battery-instructions, route picker) are driven by the physical bezel / crown via `Modifier.rotaryScrollable` (persona samsung #32).
- [x] Raster tile background on the in-run mini-map — `ui/RouteMiniMap.kt` now draws MapTiler `streets-v2-dark` tiles under the polyline when `PUBLIC_MAPTILER_KEY` is set in `apps/watch_wear/android/.env.local`. Same env-var name as the web app for a shared key. Pure Web Mercator math in `recording/MercatorTiles.kt` (13 unit tests) handles fitBounds → integer-zoom selection + lat/lng → pixel projection that aligns with tile corners. `ui/TileSource.kt` fetches via OkHttp with a 50 MB disk cache; `ui/TileLayer.kt` is the Compose composable that draws bitmaps as they arrive (silent failure path keeps the polyline + midnight background as a graceful fallback).
- [x] Tile pre-fetch on route selection for cellular-drop robustness — when the runner picks a route in the picker, `RunViewModel.selectRoute` fans out `tileSource.prefetch(latlngs, viewportPx = 400f)` in `viewModelScope`. Tiles for the bounding box land in OkHttp's disk cache while connectivity is good (paired phone or wifi); if the watch goes off-grid mid-run, the running screen still renders the route on actual streets instead of falling back to midnight + polyline. Best-effort path — failures don't block the picker and the running screen still has on-demand fetching as a secondary fallback.
- [x] Running-mode UX — the pause / lap / stop button cluster now auto-hides 5 s after the last interaction so the runner gets an unobstructed view of the route map. Tap anywhere on the watch face to bring the buttons back; they fade out again 5 s later. While paused, controls stay pinned visible so the runner can resume without hunting for a hidden tap zone. Translucent button backgrounds (`Color.Black.copy(alpha = 0.55f)`) + edge-anchored `BottomCenter` placement so the route stays visible *through* the controls when they're shown. Time + distance + status captions wear a soft `Shadow` so they remain legible against busy `streets-v2-dark` tiles.
- [x] Owner-curated route picker via `routes.is_starred` — the watch fetches `is_starred=eq.true&order=updated_at.desc&limit=30` so a power user with 200 saved routes doesn't scroll through every one on a 1.4-inch screen. First-launch fallback: when no routes are starred yet, the watch pulls the 10 most-recently-updated owned routes so the picker isn't empty before the runner has had a chance to curate. Star toggles live on web (`/routes` cards + `/routes/[id]` header) and mobile (`routes_screen.dart` trailing star, `route_detail_screen.dart` AppBar star). Backed by partial index `idx_routes_user_starred (user_id, updated_at desc) WHERE is_starred` so the starred fetch is index-only. Migration `20260606_001_routes_is_starred.sql`. Watch is read-only — no star UI on the wrist (see `decisions.md § 44`).

### Glanceable tiles and complications

- [ ] watchOS complication: pace + distance — Swift source + provider + four `widgetFamily` views (Circular / Corner / Inline / Rectangular) ship in `apps/watch_ios/Complications/`. `WorkoutManager` writes an active-run snapshot to an App-Group `UserDefaults` on every state transition (`publishComplicationSnapshot`) and nudges `WidgetCenter.reloadTimelines`. **Checkbox stays unticked until the Widget Extension target is added in Xcode** — see [`apps/watch_ios/Complications/README.md`](../../apps/watch_ios/Complications/README.md) for the one-time wiring step.
- [x] Wear OS tile: active run summary — `apps/watch_wear/.../tiles/ActiveRunTileService.kt` renders idle ("Tap to start") and active (elapsed time + distance + pace) layouts via ProtoLayout. `RunRecordingService` calls `requestUpdate` on every stage transition (start / pause / resume / stop) so the tile content always matches the live recording state. Manifest entry guards the service with `BIND_TILE_PROVIDER`; preview drawable shown in the watch face's tile picker. Pure formatter unit tests + a source-level wiring guard pin the contract.

### Live spectator tracking

- [x] `/live/{run_id}` spectator page with MapLibre map (simulated runner)
- [x] Live position dot, trace line, pace/distance/elapsed stats
- [x] Runner shares a live tracking link before starting — pre-start "Share live link" button on `run_screen.dart` pre-mints the run id so the URL is stable across the "share now → tap GO later" gap; URL points at `/live/{run_id}` on the configured web host (`WEB_BASE_URL`).
- [x] Mobile recorder writes per-ping rows to `live_run_pings` while a run is in flight — `LiveBroadcaster` (Android + iOS twin) attached on Share-live-link tap, throttled 5 s, swallows network failures (L4); `ApiClient.beginLiveBroadcast` pre-creates the parent `runs` row with `is_public=true` so anon spectators on the share URL can read; `endLiveBroadcast` wipes pings on stop and `cleanup_stale_live_run_pings` (cron, 4 h) handles the crash path.
- [x] WebSocket connection to Go service (replace simulation) — both ends shipped. Mobile recorder routes pings through `apps/mobile_android/lib/live_hub_client.dart` when `LIVE_HUB_URL` is in `dotenv.env`; web spectator opens a WS to `${PUBLIC_LIVE_HUB_URL}/v1/live/{run_id}/subscribe` when set (with auto-reconnect + late-joiner snapshot via `fetchLiveSnapshot`). Both gracefully fall back to the Supabase Realtime path when unset. The Go-side hub lives in `apps/job_worker/internal/livehub/` (see #12). Env-flip lands once the Fly.io app is provisioned.
- [x] Positions stored ephemerally in Redis (TTL 24h) for late joiners — **code shipped** as `apps/job_worker/internal/livehub/redis_hub.go` (pub/sub on `live:{runID}:ch`, last-known `live:{runID}:last` + history ring, all 24h-TTL'd; 14 miniredis tests). `main.go` picks the backend at boot from `REDIS_URL` (else the in-process map, which is the single-replica dev default). See the "Set up Upstash Redis" item under Backend work (Phase 2) below — only the operator env-flip remains.

### Backend work (Phase 2)

- [ ] Deploy Go service to Fly.io (~$5/month)
  - [x] **WebSocket hub code shipped + deploy config ready** — `apps/job_worker/internal/livehub/` (Hub + HTTP routes + WS streaming via `coder/websocket` + per-room privacy-zone clip via `SupabaseZoneFetcher`); 34 tests race-clean. Wired into `main.go`'s health listener alongside `/health`. `apps/job_worker/fly.toml` exposes `:443` (TLS + http handler for WS) with `LIVEHUB_ALLOWED_ORIGINS` env + `/health` HTTP probe; env examples (`apps/web/.env.example` → `PUBLIC_LIVE_HUB_URL`, `apps/mobile_android/.env.example` → `LIVE_HUB_URL`) and `apps/job_worker/deployment.md § Live spectator hub` document the cutover. Remaining steps are operator-only: `flyctl deploy --remote-only`, `flyctl certs add live.threkir.com`, Route 53 record, then flip the two env vars in the prod sops blob + next mobile release.
  - [x] Background job queue (Postgres-backed via River-style `claim_next_job` / `defer_job` / `finish_job` RPCs)
  - [x] **Strava webhook handler (moved from Edge Function)** — HTTP endpoint at `apps/job_worker/internal/stravahook/server.go` (POST `/v1/strava/webhook`) validates URL secret + verify-token + freshness + dedupes via `webhook_events`, then enqueues a `kind='strava_event'` job; the worker handler (`internal/handler_strava_event.go`) does the activity fetch + Storage upload + runs insert async. Matches Strava's "ack within 2s" recommendation. The CHECK allowlist on `jobs.kind` (migration `20260823_001`) admits the new kind. 23 new tests across the dispatch + endpoint (race-clean). Cutover is operator-mediated via `POST /api/v3/push_subscriptions`; the EF stays deployed for rollback. See `apps/job_worker/deployment.md § Cutover recipe for the Strava webhook`.
  - [x] **Token refresh worker (moved from Edge Function)** — `kind='token_refresh'` in `apps/job_worker/internal/handler_token_refresh.go`. Sweeps `integrations` rows where `provider='strava'` and `token_expiry < now()+1h`, rotates via Strava `/oauth/token` (`grant_type=refresh_token`), persists through `set_integration_tokens` RPC. Per-row error isolation — a single user's 4xx/5xx skips that row and the sweep finishes `done`. Pluggable `StravaRefresher` seam for tests. 12 new tests (8 handler + 4 Strava client), race-clean. The `refresh-tokens` Edge Function stays deployed during cutover; the pg_cron schedule that enqueues the hourly token_refresh job lives in migration `20260821_001_token_refresh_cron.sql` (dedupe-safe — multi-tick ticks while the worker is behind coalesce onto one backlog row). `apps/backend/CLAUDE.md`'s Edge Functions table marks `refresh-tokens` Deprecated (rollback path). See `apps/job_worker/deployment.md § Job kinds + cutover`.
  - [x] **Data export worker (moved from Edge Function)** — actually shipped as an HTTP endpoint (`POST /v1/export`) rather than a job kind, since the user is waiting on a signed URL. New package `apps/job_worker/internal/dataexport/` with JWT auth (same `SUPABASE_JWT_SECRET` the live hub uses), tiered rate limit (`check_rate_limit_tiered`, free 2/h + pro 8/h, fail-closed), CSV / GPX-zip builders, Storage upload, 10-min signed URL. 14 tests, race-clean. `apps/backend/CLAUDE.md` marks the `export-data` Edge Function Deprecated (rollback path). Cutover is operator-mediated via a client-side URL flip. See `apps/job_worker/deployment.md`.
- [x] **Set up Upstash Redis for live position streams** — Go code shipped (`apps/job_worker/internal/livehub/redis_hub.go`). `LivePubSub` interface lets `main.go` pick at boot via `REDIS_URL`. Redis pub/sub on `live:{runID}:ch` for fan-out; `live:{runID}:last` for snapshot survives across process restarts with a 24h TTL. 14 miniredis-backed tests pin every contract (TTL expiry, late-joiner pre-load, subscriber drop semantics, per-room zone + run-meta caches, URL parser). Operator just needs to set the Fly secret to flip from in-process to Redis-backed.
- [x] Add `personal_records` summary table with insert trigger (migration `20260508_001_personal_records_cache.sql` — table, `refresh_personal_records_for_user(uid)` helper, insert / update / delete triggers, backfill; `security definer` writes, reads scoped to owner)
- [x] Add `jobs` table for Go worker queue (migration `20260609_001_run_match_pipeline.sql` — generic `(id, kind, payload jsonb, status, attempts, scheduled_at, locked_at, locked_by)` queue with River-style `claim_next_job` / `finish_job` / `defer_job` SECURITY DEFINER API. `for update skip locked` for safe concurrent drain; partial indexes on `(scheduled_at, kind) where status='queued'` keep the worker scan O(active set); RLS deny-by-default + revoke EXECUTE from public + grant to service_role for the worker functions. First tenant is `kind='map_match'`; strava-webhook / token-refresh / data-export now follow the same shape — see the three bullets above.)
- [x] Migrate Strava webhook, token refresh, data export from Edge Functions to Go service — code complete + tested for all three (see the sub-bullets under "Deploy Go service to Fly.io"). The Edge Functions stay deployed as rollback paths; the only remaining step is the operator-mediated cutover (provision the Fly.io worker, repoint Strava's `push_subscriptions` URL, apply the token-refresh cron migration, flip the client export URL), tracked under the unchecked "Deploy Go service to Fly.io" item above.

### Milestone: App Store + Play Store public beta

---

## Phase 2b — web app: plan big, review deep

**Target:** ~5 weeks (runs in parallel with or immediately after Phase 2)
**Goal:** A SvelteKit web app at `threkir.com` that handles everything better done on a big screen
**Backend:** No new services — database optimisations only

### Full-screen route builder

- [x] MapLibre GL JS map with click-to-place waypoints
- [x] Draggable markers to reshape route
- [x] Road snap (OSRM car profile) and trail mode (OSRM foot profile)
- [x] Auto-calculated distance and elevation profile as you draw
- [x] Direction arrows on route line
- [x] Overlap detection (purple for out-and-back sections)
- [x] Preview line from last waypoint to cursor
- [x] Snap-to-start with pulsing marker to close loops
- [x] Numbered waypoint markers (green start, red end)
- [x] Place search via MapTiler geocoding
- [x] Geolocate button + auto-center on user location
- [x] Export as GPX with elevation data
- [x] Export as KML
- [x] Save route to Supabase
- [x] Shareable link generation (makes route public + copies link)

### Run history dashboard

- [x] Stat cards (this week distance/runs, total runs, longest run, weekly pace)
- [x] Weekly mileage bar chart (12 weeks)
- [x] Calendar heatmap of runs (GitHub-style, 20 weeks)
- [x] Personal records table (5k, 10k, half, marathon)
- [x] Recent runs list with source badges
- [x] All data fetched from Supabase (mock fallback for empty tables)
- [x] Monthly and yearly mileage toggle (week/month/year view)
- [x] Filter by source (All, Recorded, Strava, parkrun, HealthKit)
- [x] Filter by activity type (All, Run, Walk, Cycle, Hike)

### Deep run analysis

- [x] MapLibre GPS trace with direction arrows, start/finish markers
- [x] Elevation profile (SVG chart)
- [x] Splits table (per-km pace + elevation)
- [x] Heart rate zone breakdown (stacked bar + legend)
- [x] Key stats (distance, duration, pace, HR, elevation)
- [x] Back link to run list
- [x] Trace animation (replay run as moving dot with animated trace)
- [x] Comparison against previous runs on same route — `lib/routes/route_history.ts` ports the mobile filter (same `route_id` + same `metadata.activity_type` + > 100 m, sorted by duration); `RouteHistory.svelte` mounts on `/runs/[id]` and renders the PB / "+Δs behind PB" / "Attempt N of M — PB: H:MM:SS" card. 10 unit tests in `lib/routes/route_history.test.ts`.

### Live tracking spectator view (web)

- [x] Public page at `/live/{run_id}` (no auth required)
- [x] MapLibre map with runner dot and trace line
- [x] Live distance, elapsed time, pace stats
- [x] Pulsing "LIVE" badge
- [x] Map auto-follows runner position
- [x] Open Graph and SEO meta tags
- [x] Connect to Go service WebSocket — the spectator page takes the real `openLiveWebSocket()` path whenever `PUBLIC_LIVE_HUB_URL` is set (`lib/runs/live_hub.ts`); the Supabase Realtime channel is the fallback when it isn't, and the demo animation is only the no-signal filler. End-to-end proven against the real Go hub binary by `tests-e2e/live/spectator_websocket.spec.ts` (dedicated `playwright.livehub.config.ts`, CI job `e2e-web-livehub`): snapshot late-join + on-connect replay + live ping streaming.
- [ ] **Operator deploy only** — provision the Go live-hub (Fly.io), point `live.threkir.com` at it, set `LIVEHUB_REQUIRE_AUTH=1` + `SUPABASE_JWT_SECRET` + `LIVEHUB_ALLOWED_ORIGINS`, then flip `PUBLIC_LIVE_HUB_URL` (web) + `LIVE_HUB_URL` (mobile). No client code changes needed — the path lights up from env alone. See `apps/job_worker/deployment.md`.

### Account and integrations management

- [x] Connect / disconnect Strava, Garmin, parkrun, HealthKit (persisted to Supabase)
- [x] Account settings page (display name, preferred units)
- [x] Enter parkrun athlete number
- [x] Download all data as CSV (GDPR compliance)
- [x] Manage premium subscription — `/settings/upgrade` shows tier-aware copy and a Manage subscription button that redirects to the RevenueCat-supplied `managementURL` for web purchases (mobile users are routed to App Store / Play Store with explanatory toast).

### Public route and run pages

- [x] `/share/route/{id}` — public route with map, distance, elevation, sign-up CTA
- [x] `/share/run/{id}` — public run with GPS trace, stats, sign-up CTA
- [x] Open Graph meta tags (title, description, type)
- [x] SEO metadata (title, description)

### Auth and data layer

- [x] Supabase Auth store with `onAuthStateChange` listener
- [x] Email/password sign-in and sign-up
- [x] Google and Apple OAuth scaffolded
- [x] Auth callback route (`/auth/callback`)
- [x] Auth guard on protected routes (loading state while checking)
- [x] Data access layer (`data.ts`) with Supabase queries + mock fallback
- [x] Layout with sidebar nav, user info, logout

### Backend work (Phase 2b)

- [x] Supabase config: auth redirect URLs, email confirmations disabled for dev
- [x] Seed script with test user, runs, routes, integrations
- [x] `mv_weekly_mileage` materialized view
- [x] Full-text search index on `routes.name`
- [x] Composite indexes for dashboard queries (runs by source, distance range)
- [x] `pg_cron` job to refresh materialized view (every 15 min) — migration `20260602_001_pg_cron_schedules.sql` schedules `refresh materialized view concurrently mv_weekly_mileage` (later bumped from `*/5` to `*/15` in `20260706_001_pg_cron_mv_refresh_15min.sql` after the cost-controls audit flagged the cadence as the dominant Supabase background-compute draw) plus a 15-minute `cleanup_stale_live_run_pings()` sweep that the `20260509_001` follow-up note had pending.
- [x] Verify dashboard queries perform under 2 seconds for users with 200+ runs — measured locally at 2074 runs for the seed user (10× the target). `fetchRuns(limit:50)` 0.11 ms via `runs_user_started_at` index scan; `fetchWeeklyMileage` 0.99 ms (seq scan + sort — planner correctly picks seq when the user owns ~all rows); `fetchPersonalRecords` 0.31 ms via the trigger-maintained PR cache. All three queries land ~1000× under the 2 s budget. Indexes already in place from `20260405_001_initial_schema.sql` carry it.

### Milestone: web app live at `threkir.com`

---

## Phase 3 — growth and monetisation

**Target:** ~8 weeks after Phase 2
**Goal:** Build the features that drive acquisition, retention, and revenue
**Backend:** Supabase + Go service (premium features added to Go service)

### In-app route builder (free)

- [x] Click-to-place waypoints on MapLibre (mobile) — `route_builder_screen.dart`, tap-to-place + numbered pins, long-press to drag-reshape
- [x] Auto-snap to roads or trail mode — `routing.dart` (foot/car profiles via public OSRM), plus a Straight bypass for off-road
- [x] Elevation preview before running — `elevation.dart` against Open-Meteo (sample ≤100 points), status pill renders `N m ↑` as the polyline updates
- [x] Save to route library + shareable link — Save dialog hands off to `ApiClient.saveRoute`, public toggle exposes it via the existing share path

### Community route library

- [x] Public / private toggle per route
- [x] Explore Routes screen — search public routes by name (full-text), filter by distance range and surface type, save to library, paginated results (Android)
- [x] "Popular near me" discovery feed — PostGIS `ST_DWithin` queries via `nearby_routes` RPC, `start_point geography(Point)` column with auto-populate trigger, "Near Me" tab on Android explore screen (geolocator) and web explore page (browser Geolocation API)
- [x] Route ratings and comments — `route_reviews` table (1-5 stars + optional comment, one per user per route), reviews section on route detail screen, avg rating in stats row, submit/edit review dialog
- [x] **Club-owned routes** — `routes.club_id` (nullable FK) shipped in migration `20260520_001_club_owned_routes.sql`; data layer (`getClubRoutes`, `transferRouteToClub`), EventEditor optgroups, and the `/clubs/[slug]` Routes tab with admin transfer/create are wired. See decisions.md § 30.
- [x] **Save-to-library is a reference, not a clone** — `saved_routes (user_id, route_id)` join table shipped in the same migration; `getMyRoutes` UNIONs personal + saved, `bookmarkRoute` / `unbookmarkRoute` insert into the join table instead of cloning, and the canonical row accumulates `run_count`. See decisions.md § 30.
- [x] Share to social (image card with map + stats) — `widgets/route_share_card.dart` mirrors the existing `run_share_card` pattern: portrait `RepaintBoundary` with the route polyline + name + distance + climb + surface, captured via `boundary.toImage(pixelRatio: 3.0)` and handed to `share_plus`. Wired into `route_detail_screen` Share popup as "Share as image" alongside the existing GPX / KML options. Mirrored byte-identically to mobile_ios.
- [x] SEO-indexed public route pages — `/share/route/[id]` carries a per-route `<title>` + Open Graph + `<link rel="canonical">` + `og:url` + schema.org JSON-LD (`WebPage` + `BreadcrumbList`, via `buildRouteJsonLd` in `share/share_meta.ts`), is listed in `/sitemap.xml`, and renders a per-route og:image at `/og/route/[id].png`. The in-app `/routes/[id]` canonicals to the public page so the two URLs for one route don't split ranking signals. JSON-LD omits `geo` (track is privacy-clipped server-side). **Request-time freshness shipped (2026-06-04):** both surfaces moved off build-time prerender to the `share-route` Lambda (`apps/web/lambda/share-route/`, mirror of `share-run`), so a route made public after a build — or beyond the old 5k cap — unfurls with the right head + a rendered image regardless of build cadence; the PNG returns a generic branded card at 200 for private/deleted ids. See decisions.md § 104 + `apps/web/lambda/share-route/README.md`.

### Clubs and events — social layer

Phased rollout so the schema doesn't sprawl. MVP is club-owned events only, enum-based recurrence (Phase 2), and open-join clubs with invite-link sharing (Phase 2). See `docs/features/clubs.md` for surfaces and `apps/backend/supabase/migrations/20260416_001_clubs_and_events.sql` for schema.

- [x] **Phase 1 — MVP (web only):** `clubs` / `club_members` / `events` / `event_attendees` / `club_posts` tables with RLS; browse/create/view clubs, create one-off events, RSVP, owner/admin text updates. No recurrence, no invites, no notifications. Web routes: `/clubs`, `/clubs/new`, `/clubs/[slug]`, `/clubs/[slug]/events/new`, `/clubs/[slug]/events/[id]`.
- [x] **Phase 2 — recurrence + invites:** Enum recurrence (`weekly` / `biweekly` / `monthly` + `byday[]` + `until_date`) with instance expansion on the client; per-instance RSVPs (`event_attendees` pkey extended with `instance_start`); join policies (`open` / `request` / `invite`) with a pending-requests admin panel; shareable invite tokens on clubs + `/clubs/join/[token]` landing route; one-level threaded replies on posts. Migration: `20260417_001_phase2_social.sql`.
- [x] **Phase 3 — Android mirror:** `clubs_screen.dart` (Browse + My clubs), `club_detail_screen.dart` (feed / events / members tabs with threaded post replies and member post composer), `event_detail_screen.dart` (per-instance RSVP + admin update composer), `upcoming_event_card.dart` replaces the Last-Run card on the Run tab when the user has RSVP'd `going` to an event within 48h. Clubs added as a 6th bottom-nav tab. Recurrence is ported to Dart (`recurrence.dart`) so instance expansion stays consistent with web. Club/event creation is deliberately not on Android — admins still use the web app for those.
- [x] **Phase 4a — realtime (web + Android):** Supabase Realtime is enabled on `club_posts`, `event_attendees`, `club_members`, and `race_sessions` (migrations `20260418_001_social_realtime.sql` + `20260425_001_race_sessions.sql`). Web club / event detail pages and Android `ClubDetailScreen` / `EventDetailScreen` subscribe via `postgres_changes` and debounce reloads at 250ms. Payloads are ignored in favour of a fresh enriched fetch so RLS stays authoritative.
- [x] **Race organiser controls on Android (Arm / Fire Go / End).** `SocialService.armRace` / `startRace` / `endRace` mirror `apps/web/src/lib/core/data.ts`. `event_detail_screen.dart` renders a race-control card — visible to owners / admins / race directors (`ClubView.isRaceDirector`) — with the state machine `idle/finished/cancelled → Arm (+ auto-approve toggle) → armed → Fire Go / Cancel → running → End / Cancel race`. Realtime updates flow through the existing `subscribeToEvent` channel extended to include `race_sessions` filtered by `event_id`.
- [x] **Phase 4b — email delivery + event-day reminders:** The *in-app* inbox fan-out for club posts + completed runs ships (migration `20261101_001`, persona #38 — `decisions.md § 96`); the **email leg of the device-delivery layer now ships too** (migration `20261130_001`, `decisions.md § 117`). A new `event_reminder` kind + `enqueue_event_reminders()` (hourly pg_cron) creates a reminder for every `going` RSVP whose occurrence is inside the next 24 h (skips cancelled occurrences; deduped per occurrence). An AFTER-INSERT trigger on `notifications` enqueues a `notification_email` job per recipient; the Go worker's `handler_notification_email.go` drains it, honours the `user_settings.prefs.email_notifications` preference (`all | important | off`, default `important` — `docs/backend/settings.md`), resolves the address via the GoTrue admin API, and sends over SMTP (local Mailpit `:54325`; Resend/SES SMTP in prod). Credential-free and end-to-end testable against the local Docker stack — email needed no Firebase/APNs key. Admin-update fan-out rides the same `notification_email` path once an admin-update notification kind is added.
- [ ] **Phase 4b — native push (FCM / APNs):** The remaining device-delivery leg: native push to iOS (APNs) + Android (FCM). The `notifications` row is already the source of truth, so a sibling consumer of the same rows is all that's needed — but this leg is genuinely blocked on user-supplied Firebase / APNs credentials + mobile client-side token registration. `device_tokens` table is shipped (migration `20260506_001_device_tokens.sql` — platform-checked `token` rows, `is_notifications_enabled` per-device toggle, partial index on active tokens, self-scoped RLS, trigger on `updated_at`); mobile has no `firebase_messaging` wiring yet. Provision a Firebase project + APNs auth key, drop `google-services.json` / `GoogleService-Info.plist`, register tokens on sign-in, then add an FCM/APNs sender as a second consumer alongside the email handler. (Web push is a separate not-blocked slice — the VAPID client path already ships; see `parity.md`.)
- [x] **Lifecycle + transactional email** — beyond the notification channel, the Go worker sends template-keyed `lifecycle_email`: a **welcome** on signup (`decisions.md § 119`), a **Pro-purchase receipt** + **payment-failed dunning** on subscription transitions (`decisions.md § 121`). All email is **branded HTML + plain-text** with inbox preview text, and **localized across all six locales** (`decisions.md § 120`). **Full subsystem reference: [docs/features/email.md](../features/email.md).**
- [ ] **Email — engagement + remaining transactional:** weekly digest + lifecycle drip (needs a per-category preference center + RFC 8058 one-click unsubscribe + bounce suppression first); account-deletion receipt (needs inline send from `delete-account`). NOT planned: data-export-ready (export is synchronous), password-changed / new-device (no auth hooks / device tracking). Reasons in [docs/features/email.md](../features/email.md#planned--not-built).
- [ ] **Email — production ops:** provision SMTP (Resend/SES) + `APP_BASE_URL` on the worker, confirm the pg_cron schedules in prod Supabase, set SPF/DKIM/DMARC on `threkir.com`. Nothing sends in prod until these land — see [docs/features/email.md § Production ops](../features/email.md#production-ops-required-before-any-email-actually-sends).
- [x] **Typed events (run / cycle / class / social) — Slice E:** events carry a behaviour-driving `category` + free-text `discipline`; athletic affordances (route/distance/pace/race/results) self-hide for `class`/`social` in the UI **and** are blocked at the data layer. Web type-first editor + category-gated detail shipped; mobile read-only category-gated detail shipped. Migrations `20261227_001` + `20261228_001`. See [club_events.md](../features/club_events.md).
- [x] **Paid events (marketplace) — Slice P1 (web):** Stripe Connect destination charges — a host (`events.host_user_id`) charges for an **in-person** event, the platform takes an application fee, and a completed Checkout grants the RSVP. User-level `/settings/payouts` Connect onboarding, an EventEditor "Charge" toggle gated on `charges_enabled`, and a "Register · $X" flow on the event-detail page with a `?paid=1` success poll. The `stripe-events-webhook` is the sole, idempotent, service-role-only writer of order status. **Web checkout only; manual refunds via the Stripe dashboard in P1.** Schema migration `20261229_001` (`instructor_payout_accounts` / `event_pricing` / `event_orders` + `event_attendees.order_id`). **Live charge path is UNVERIFIED** — needs operator Stripe test-mode keys (`sk_test_` / `ca_` / `whsec_`); the rail, RLS, pure helpers, and non-charge UI are built + tested. **Planned:** P2 automated refund/cancel coupling + buyer self-cancel + waitlist notify-to-pay; P3 mobile register (web-checkout handoff) + receipt/refund email + the class→gym seam; P4 class-pass / recurring memberships / virtual paid events / club-level pooled payouts. Gated on owner + CISO + counsel sign-off (SOC 2 / GovRAMP, PCI SAQ A, sub-processor footprint). See [club_events.md § Slice P](../features/club_events.md#slice-p--paid-registration).
- [x] **Session planner (yoga/pilates content) — P1 (web canonical + mobile read):** a reusable `session_plans` engine (blocks → timed/per-side/cue items) mirroring the gym routine engine's shape — build/save/reuse, **no execution/logging yet**. Web `SessionPlanEditor` + `/sessions` list + `/sessions/[id]` read view + a read-only sequence on the class-event detail (organiser attach). Mobile gets the `expandSessionSteps` TS↔Dart parity pair + a read/list (`SessionsScreen`/`SessionDetailScreen`; editor stays web-first). Schema migration `20270103_001` (`session_plans`/`_blocks`/`_items` + `events.session_plan_id` + the `SessionItemKind` CHECK), pgtap RLS coverage. No compliance gate (no payments). **P2 pure-logic + runner landing (2026-06-11, in progress):** `computeSessionAdherence` (on the `session_steps` pair), the `workoutDraftFromSession` seam helper, and the `gym_workouts.metadata` session trio (`session_plan_id` / `session_step_results` / `session_adherence`) are merged; the follow-along **UI** (web player + mobile runner) + `LocalSessionStore` land as follow-on commits. **P3 sharing slice shipped (2026-06-12, web + mobile):** a logged-out public share page `/share/session/[id]` (`lookupSharedSession`) + an `is_public` toggle + copy-share-link on `/sessions/[id]` (mirrored as an owner-gated toggle on mobile `session_detail_screen` via `ApiClient.setSessionPlanPublic`); movement-name autocomplete in the web `SessionPlanEditor` (`fetchSessionMovementNames`, web-first); club-published session templates — `publishSessionAsTemplate` + a club-detail Templates surface (web + mobile) with per-row Adopt → the `clone_session_template` SECURITY DEFINER RPC (migration `20270104_001`, author/member-gated + rate-limited; pgtap `clone_session_template_test.sql`). Public read gated on `is_public` + the existing RLS (no schema change beyond the new RPC). **Planned:** the P3 curated pose catalog; P4 progression / multi-week / watch / AI sequencing. See [session_planner.md](../features/session_planner.md) + [decisions.md § 140](../architecture/decisions.md).
- [x] **Gym routine engine — P1 (web + mobile):** reusable gym routines (`gym_routines` → `gym_routine_exercises` → `gym_routine_sets` + a `gym_workouts.metadata` jsonb bag), "Save as routine" from a logged session, and "Repeat last" that prefills a new log — **prefill-only, no execution loop**. Web `/gym/routines` library (self-hiding) + builder + `[id]` detail; the `gym_routine` (`routineFromWorkout` + `prefillFromRoutine`) TS↔Dart parity pair; mobile twin (`LocalRoutineStore` + routine library/detail/builder, byte-identical iOS). DSAR export extended (Deno twin **and** the production Go worker). Four narrow-union ↔ CHECK pairs (periodisation / modality / progression / set_type). Migration `20270101_001`; Playwright + pgtap. No compliance gate. **P2/P3 execution shipped (2026-06-12, web + mobile):** `expandRoutineSteps` + the `gym_adherence` (`computeRoutineAdherence`, per-axis 80% cutoff) + `gym_progression` (`nextPrescription`) parity pairs, the `GymWorkoutRunner` (`packages/run_recorder`), the `gym_workouts.metadata` execution trio (`routine_id` / `gym_step_results` / `gym_adherence`), and the on-screen runners (web `GymSessionRunner` + `GymExecutionBand`; mobile `gym_session_screen.dart`). **P2 authoring + P4 progression UI shipped (2026-06-12, web + mobile):** the routine editor now authors supersets, per-set set-types + rest, per-exercise modality (weight×reps / time / distance / bodyweight) and a progression scheme + params (the `routine_editor_build`/`assignSupersetGroups` parity pair maps the per-row "superset with next" flag to the relational columns); session start prefills the planned targets from `nextPrescription` over logged history (the `progression_prefill`/`lastSessionSets` parity pair) and the workout review shows a neutral next-target chip — the prescriber algorithm itself is only called, never changed. **Planned:** P4 progression *engine* wiring (Coach-authored reads) stays gated on the validation-gate sign-off. See [gym_programming.md](../features/gym_programming.md).
- [x] **Timed gym work — `gym_sets.duration_s`:** a nullable `duration_s` (seconds) on `gym_sets` so planks / holds / timed intervals are first-class (no longer forced into reps/load). Threaded through `GymEditor` / `gym_compose_sheet` + the `gym_exercise_set_history` RPC; web + mobile twin; migration `20261231_001`; pgtap + Playwright + Flutter tests. Foundation for clean session-plan logging (closed `session_planner.md` open Q1). See [instructor_business.md § M2](../features/instructor_business.md).
- [x] **Attendance / check-in (host-only, distinct from RSVP):** a `class`-event organiser marks who actually showed up — a nullable `event_attendees.attendance` (`attended`/`no_show`, NULL until marked) orthogonal to RSVP `status` (paid ≠ attended), written only via the organiser-gated `mark_attendance` SECURITY DEFINER RPC (table column UPDATE on `attendance` revoked, so the RPC is the sole write path; the self-only RSVP update stays intact). Host UI web + mobile twin, read-only for non-hosts. Migration `20270102_001`; pgtap + Playwright + Flutter tests. No compliance gate. See [instructor_business.md § M6](../features/instructor_business.md).

### External platform sync

| Source | Method | Status |
|---|---|---|
| Apple HealthKit | `health` Flutter package | [x] Shipped via the `health` package's HealthKit backend; iOS import card + button now platform-labelled. No GPS traces — Apple Health doesn't expose third-party-app routes. |
| Android Health Connect | `health` Flutter package | [x] Shipped on Android via the same `health` package's Health Connect backend; pulls Google Fit / Samsung Health / Garmin / Fitbit workout summaries. No GPS traces. |
| Strava | Official OAuth 2.0 API + webhook | [x] Connect button + sync wired (`ApiClient.syncStrava` invokes the `strava-import` Edge Function with `action: 'sync'`). Native in-app OAuth on mobile via `flutter_web_auth_2` — Chrome Custom Tabs on Android, ASWebAuthenticationSession on iOS. `_connectStrava` in `settings_screen.dart` drives the auth session, parses `threkir://strava-callback?code=…&scope=…` via `parseStravaCallback`, and exchanges through `ApiClient.completeStravaOAuth` (POST `action: 'connect'`). Falls back to the old browser flow on unconfigured builds. Operational: callback URI must be allow-listed in the Strava developer console AND in `STRAVA_ALLOWED_REDIRECTS` on the EF. Webhook handler is live. |
| Garmin Connect | Official developer program (apply) | [ ] Hard-blocked on the multi-day Garmin Developer Program application. Once approved, follow the Strava pattern. |
| parkrun | Athlete number scrape | [x] Shipped on Android/iOS — Settings → Integrations → "parkrun" tile calls `ApiClient.setParkrunAthleteNumber` + `importParkrunResults` (Edge Function). |
| Race results | RunSignUp API + bib scrape | [ ] Needs a RunSignUp API key. Once provisioned, follow the parkrun pattern. |

### AI Coach (free, usage-capped)

Claude-powered training advisor embedded in the web app. Reviews the runner's plan and recent runs; does not generate plans or prescribe medical/nutrition advice (see `decisions.md #12`).

- [x] Server endpoint (`/api/coach/+server.ts`) with prompt-cached system prompt + context dump
- [x] `CoachChat.svelte` UI with suggestion chips and cache-hit stats
- [x] Daily usage limit per user (free: 2, pro: 10 — `user_coach_usage` table, `increment_coach_usage` / `get_coach_usage` RPCs)
- [x] Personality tones — `coach_personality` user setting (`supportive` / `drill_sergeant` / `analytical`) fed into the system prompt
- [x] User preferences (date of birth, HR zones, resting/max HR, weekly mileage goal) fed into context for personalised advice
- [x] Top-level `/coach` page with plan switcher (`?plan=<id>`), graceful plan-less fallback, and dashboard "Ask the coach" deep-link card
- [x] "Grounded in:" context strip showing the plan, run count, HR-zone status, and weekly goal that the model has loaded — sourced from the same data as `buildContext()` so it reflects what's actually sent
- [x] Configurable runs window — UI selector (10 / 20 / 50 / 100) → `recent_runs_limit` request param, server-clamped to `[1, 100]`
- [x] OpenAI-compatible provider option (`COACH_PROVIDER=openai`) for local-Ollama / llama.cpp / vLLM dev iteration without burning Anthropic tokens
- [x] Cross-device chat history — `coach_messages` table, RLS owner-only, scoped per (user × plan); replaces the prior localStorage persistence with one-time client migration on first read
- [x] Server-Sent Events streaming so tokens render as they arrive; placeholder bouncing-dot indicator until the first token; persists across reload mid-stream via realtime subscription
- [x] Markdown rendering for assistant replies (`marked` + `DOMPurify`) — paragraphs, lists, **bold**, code blocks, inline links to specific runs (`[Apr 25 long run](../../../../../../runs/<id>)`)
- [x] Conversation archive + sidebar history list with auto-derived titles (first user message, truncated). "Start new" flips `archived_at` rather than deleting; per-archive view (read-only) and delete
- [x] Inline bubble actions on hover — copy, regenerate (assistant), edit-and-resend (user), thumbs-up / thumbs-down (assistant). Reactions persisted via column-level UPDATE on `coach_messages.reaction`
- [x] Server `mode` (`send` / `regenerate` / `edit`) + `anchor_message_id` truncate-and-rerun support so regenerate / edit don't duplicate user messages
- [x] **AI route descriptions** (web) — `/routes/[id]` "Describe this route" renders a templated description for everyone (offline, `localisedTemplate` over the `route_description` twin), and enhances it with `claude-opus-4-8` for Pro users via `/api/coach/route-describe` (server `is_pro()` gate, fail-closed, templated fallback on every failure — `decisions.md § 151`). Mobile UI wiring deferred; the Dart twin helper exists for parity.

### Monetisation — Pro tier + one-off donations

The original free-with-donations pivot (`decisions.md #18`) was superseded by the Pro-tier revival (`decisions.md #23`). Infrastructure from the donations era is kept: no features are hidden behind the paywall today; Pro changes behaviour inside two features (higher coach cap, processing priority) rather than gating screens.

- [x] Core gate infrastructure — `isLocked()` still returns `false` for every registered key (see `decisions.md #18` for why we retained the scaffolding)
- [x] `/settings/upgrade` page rewritten as a two-card layout: Pro plan ($9.99 / mo) + one-off Donate button (see `decisions.md #23`)
- [x] `/api/coach/+server.ts` enforces per-tier daily caps via shared `increment_coach_usage` + `usedToday > TIER_LIMITS[tier].dailyLimit` gate (free: 2/day, pro: 10/day — see `decisions.md #23` May 2026 update)
- [x] `features.ts` — `isPro()` helper + `priority_processing` feature-registry entry
- [x] `monthly_funding` table retained but no longer read by the UI
- [x] Custom `ConfirmDialog.svelte` replacing all browser `confirm()`/`alert()`/`prompt()` calls (see `decisions.md #19`)
- [x] `ToastContainer.svelte` + `toast.svelte.ts` for transient success/error/info feedback
- [x] RevenueCat web SDK wired behind the "Get Pro" button — `lib/revenuecat.ts` calls `Purchases.configure(PUBLIC_REVENUECAT_WEB_API_KEY, userId)` and `/settings/upgrade` invokes `startProCheckout(userId)`. Falls back to a "Pro checkout is not configured on this build" toast when the env key is missing so dev/preview builds stay usable.
- [x] `purchases_flutter` wired on mobile — `apps/mobile_android/lib/revenuecat.dart` is the wrapper (`isRevenueCatConfigured` / `configureRevenueCat` / `startProCheckout` / `managementUrl`). Settings → "Subscribe to Pro" tile presents the native RC sheet when `REVENUECAT_API_KEY_ANDROID` / `_IOS` is in `dotenv.env`, falls back to the existing web `/settings/upgrade` URL otherwise. Webhook still flips `subscription_tier`; profile refetch picks up the new tier. Twin-mirrored to iOS. Live sheet still needs an RC dashboard + product configuration on the operator side.
- [x] Tier-aware rate-limiting on Edge Functions — migration `20260605_001_rate_limits_tiered.sql` adds `check_rate_limit_tiered(user, bucket, free_max, pro_max, window)` which resolves `user_profiles.subscription_tier` and the window check in one round trip. Wired into the heavy paths: `parkrun-import` 4/h → 16/h, `strava-import:sync` 4/h → 16/h, `export-data` 2/h → 8/h. `delete-account` stays at 3/h regardless of tier (destructive action, tier shouldn't loosen it). Lifetime treated as pro. Free-tier fallback is conservative — missing-profile rows get the lower ceiling.

### Premium tier — training and coaching (deferred, see decisions.md #18 and #23)

This section predates the Pro-tier revival and tracks features that were *originally* premium-gated (structured workout runner, plan generator, VO2 max, race predictor, recovery advisor). Under the current model (`decisions.md #23`) Pro unlocks **a higher coach daily cap (10/day vs 2/day) + priority processing** rather than gating whole features — so the items below are roadmap work, not paywall work, until product direction says otherwise.

**Structured training plan runner (workout execution):**

The foundation under both the generator and any hand-built plan: a data model for a *plan* (goal race + weeks + per-day planned workouts), the surfaces that render "today's workout" to the runner, and the execution loop that drives live pace targets from the planned workout and auto-matches recorded runs back to it. This unlocks the use case where the runner pastes a plan from a coach or a book (e.g. a 32-week marathon plan with phase-banded paces) and the app walks them through it day by day. Own feature because it's valuable with or without plan *generation* — a generated plan is just one of several inputs to the runner.

**Status: v1 shipped on Android** ([workout_execution.md](../features/workout_execution.md)) — data model, web plan editor, generator, today's-workout card, the live execution loop, and post-run auto-match all ship. The unticked items below are the genuine remaining gaps.

- [x] Data model:
  - [x] `training_plans` table: `id`, `user_id`, `name`, `goal_event_id` (nullable FK to `events`), `goal_time_seconds`, `start_date`, `end_date`, `status` (`active` / `completed` / `abandoned`), `notes`
  - [x] `plan_weeks`: `id`, `plan_id`, `week_index`, `phase_label` (`base` / `build` / `race_specific` / `taper` — free-form string), `target_volume_metres`, `notes`
  - [x] `plan_workouts`: `id`, `week_id`, `scheduled_date`, `kind` (enum: `easy` / `long` / `recovery` / `tempo` / `interval` / `marathon_pace` / `race` / `rest`), `target_distance_metres`, `target_duration_seconds`, `target_pace_sec_per_km` (nullable), `target_pace_tolerance_sec` (nullable), `structure` jsonb (for structured workouts like `4×1 mi @ 7:00 w/ 1 mi easy`), `notes`, `completed_run_id` (nullable FK to `runs` once matched). Migration `20260419_001_training_plans.sql` (+ hardening `20260421_001`).
  - [x] Dart + TS type regeneration via the existing `gen:types` flow — see `docs/architecture/schema_codegen.md`
- [x] Plan editor (web-first, mobile read-only in v1) — *create + inline per-day edit + bulk-ops + the built-in starter library all ship*
  - [x] Create a plan from scratch: set goal race, date, target time, number of weeks
  - [x] Import from templates: paste markdown table, parse into weeks/workouts — `lib/training/plan_serialize.ts#parsePlanMarkdown` / `parsePlanJson` parse a pasted Markdown table (or JSON export) into the editable preview on `/plans/new` (PlanEditor import disclosure); round-trips with the export path below. *Built-in starter library shipped (`starter_plans.ts` ↔ `starter_plans.dart` — C25K / 12-week half / 16-week marathon presets instantiated through `generatePlan` via the `/plans/new` + `plan_new_screen.dart` picker, unit-tested both sides); plus club-template cloning (`clone_plan_template`) + the generator's C25K walk-run variant*
  - [x] Edit per-day workouts inline: kind, distance, target pace, notes (`WorkoutEditor.svelte`)
  - [x] Bulk operations: shift the plan forward/back by N days + mark a week as recovery (`lib/training/plan_bulk_ops.ts` — pure date-shift + recovery-scaling helpers; `/plans/[id]` owner controls orchestrate the per-row updates), plus **duplicate-a-week** via the atomic `duplicate_plan_week` RPC (migration `20261205_001`; `duplicatePlanWeek` in `data.ts`, per-week Duplicate button on `/plans/[id]`) — the insert + week-index re-index can't be done safely client-side because of the `plan_weeks (plan_id, week_index)` unique constraint, so it lives in its own SECURITY DEFINER transaction. **Mobile parity (2026-06-12):** duplicate-a-week shipped on `plan_detail_screen.dart` (`TrainingService.duplicatePlanWeek`); shift-plan / mark-recovery stay web-only
- [ ] Dashboard + run-tab surfaces — *today's-workout card + progress + the longest-long-run / overall-phase markers ship; the focused current-week strip doesn't*
  - [x] "Today's workout" card on the dashboard: type, distance, target pace, quick "Start workout" button (web dashboard + plan detail; mobile dashboard + Run tab)
  - [ ] This-week view: 7-day strip with planned vs completed state per day — *partial: the plan-detail per-week day-grids + the month `PlanCalendar` show planned-vs-completed per day, but there's no focused current-week strip*
  - [x] Plan progress: weeks completed, adherence % (planned miles vs actual), long-run longest, phase marker — `lib/training/plan_progress.ts` (`orderedPlanPhases` + `longestCompletedLongRunMetres`) drives an overall base→build→peak→taper marker (current phase highlighted) + a longest-long-run stat (actual distance when the linked run is in window, else planned target) in the `/plans/[id]` header. Mobile mirror shipped — `plan_progress.dart` drives the same header markers on `plan_detail_screen.dart`
- [x] Execution loop (mobile — web isn't a GPS-recording surface):
  - [x] "Start workout" opens the run screen pre-configured: activity type from workout kind, target pace locked in, audio cues tuned to the workout's tolerance (e.g. tight band for intervals, loose band for easy runs)
  - [x] Live "workout progress" overlay during structured workouts — shows the current rep / recovery, upcoming target, reps remaining (`workout_execution_band.dart` + `packages/run_recorder/.../workout_runner.dart`)
  - [x] Post-run: the completed `run_id` auto-links to the planned workout (same day, same activity) and the workout card flips to "done" with a side-by-side comparison of planned vs actual (`autoMatchRunToPlanWorkout`)
  - [ ] Manual override: runner can un-link, re-link to a different planned workout, or mark a workout as skipped without deleting it — *partial: un-link + a workout-detail **Re-link picker** ship (2026-06-12, web + mobile twin — re-points a completed workout at a different owner-scoped run within ±7 days, excluding runs already linked to another workout so `plan_progress` can't double-count); a plan-level "skipped" status still doesn't*
- [x] Adherence feedback — web + mobile shipped (`plan_adherence.ts` ↔ `plan_adherence.dart` parity pair; the over/under-running drift banner + missed-long make-up/skip callout render on web `/plans/[id]` + Android `plan_detail_screen.dart`, 2026-06-12)
  - [x] "N of M workouts completed this week" summary
  - [x] Flag when weekly mileage drifts >20% under or over plan (both directions matter — over-running the easy weeks is a real failure mode) — `weeklyDrift` compares the current week's actual run mileage (runs dated in the week window) to its planned volume; a flagged over/under drift renders as a coloured banner on `/plans/[id]` (owner-only)
  - [x] Missed-workout recovery: suggest whether to make up a missed long run or skip it, driven by simple rules (phase + proximity to recovery week) — `missedWorkoutAdvice`: a past-and-uncompleted long run in the current week prompts make-up (base/build), or skip (taper, or a step-back week imminent — detected via a >15% next-week volume drop). Quality sessions aren't worth a dedicated make-up
- [ ] Sharing and handoff:
  - [x] Export a plan as markdown or JSON (round-trip with the paste-import path) — `planToMarkdown` / `planToJson` (`lib/training/plan_serialize.ts`); the `/plans/[id]` header Export menu copies Markdown to the clipboard or downloads `.md` / `.json`. Re-importing an export reproduces the same workouts (round-trip unit-tested)
  - [x] Public plan library — users can publish a plan they followed and others can clone it into their own account. `training_plans.is_public_template` (orthogonal to the club-scoped `is_template + club_id`; migration `20270126_001`) + `clone_public_plan(template_id, start_date)` SECURITY DEFINER RPC (authorises on public visibility, not club membership; strips publisher fitness data + auto-completes the caller's active plan, same as the club path). Web `/plans/library` (search + author handle + preview) + `/plans/library/[id]` clone; owner-only Publish-to-library / Unpublish toggle on `/plans/[id]`. **Mobile parity:** `PlanLibraryScreen` + `PlanLibraryPreviewScreen` reached from the plans-list Browse-library action, plus the publish/unpublish AppBar action on plan detail. Additive RLS lets any authenticated user read a public template's weeks/workouts; non-public plans stay private.

**Scope note:** this is the single largest feature on the Phase 3 list. Budget weeks, not days. Build in this order: data model + web plan editor first (read-heavy), then dashboard "today's workout" card, then the run-tab execution loop. Structured-workout execution (intervals with live rep tracking) is the final layer and can be skipped in v1 if it blocks ship.

**Training plan generator:** shipped — `generatePlan` in `apps/web/src/lib/training/training.ts` (+ byte-twin `apps/mobile_android/lib/training.dart`), wired into `/plans/new` (web) and `plan_new_screen.dart` (mobile).
- [x] Adaptive weekly plans for 5k, 10k, half marathon, full marathon
- [x] VDOT calculation using Daniels' Running Formula
- [x] Training phase determination (base → build → peak → taper)
- [x] Workout generation: easy, tempo, interval, long run with target paces
- [x] **Adjustment based on missed sessions and recovery patterns** — *shipped: a rule-based "Re-plan remaining weeks" engine + surface (web + mobile twin), plus a trend-gated adaptive re-plan (`plan_adaptive_replan.ts` ↔ `.dart`, wired into `/plans/[id]` + `plan_detail_screen.dart`). The generator still emits a static plan; re-planning is a separate post-hoc action on the plan detail rather than a generator change.* Delivered:
  - [x] **Engine (pure):** `lib/training/plan_replan.ts#replanRemaining` ships — deterministic, rule-based, returns a future-only change diff. Honours `missedWorkoutAdvice` (a missed long run in base/build bumps the next future long run, capped at +15% so it can't spike; skipped in the taper or before a step-back), eases the next non-taper week when the last complete week over-ran (`weeklyDrift`), **never mutates the frozen past, the goal date, or the taper/race weeks**. Reuses `plan_adherence.ts`; 6 unit tests. **Dart twin shipped (2026-06-12):** `plan_replan.dart` (+ `plan_adherence.dart`) with mirror suites, wired into the mobile plan-detail re-plan flow. `plan_progress.dart` also shipped.
  - [x] **Surface:** owner-only "Re-plan remaining weeks" on `/plans/[id]` — computes the diff, shows a preview panel (each change with from → to + reason), applies on confirm via per-row `updatePlanWorkout`, or toasts "on track" when nothing needs changing. Localized into all six catalogues; e2e seeds a missed long run and asserts the make-up is proposed + written. **Mobile parity (2026-06-12):** the same flow shipped on `plan_detail_screen.dart` (preview modal → apply via `TrainingService.updateWorkout`), widget-tested.
  - **Trigger hook:** offer the action contextually when the adherence layer already flags drift or a missed long run (the banners shipped in `plan_adherence.ts`).
  - **Tests:** unit on the re-plan rules (deficit redistribution, taper-preservation, make-up insertion); e2e that seeds a plan with a missed week and asserts the future weeks change while past weeks + the race date hold.
  - **Sizing:** ~3–5 dev-days. Pure engine first, then the preview/apply UI.
- [x] **Duplicate-a-week bulk op** (split out of "Bulk operations" above) — shipped via the atomic `duplicate_plan_week(p_week_id)` SECURITY DEFINER RPC (migration `20261205_001`): INSERTs the week + its workouts, re-indexes the following weeks, and shifts dates in one transaction (the `plan_weeks (plan_id, week_index)` unique constraint rules out client orchestration). Wired into `/plans/[id]` (web) + `plan_detail_screen.dart` (mobile) via `duplicatePlanWeek`. Shift-by-N-days + mark-week-recovery also ship (`plan_bulk_ops.ts`).
- [x] Output plugs into the plan-runner data model above — the generator produces `training_plans` + `plan_weeks` + `plan_workouts` rows, same as a hand-built plan

**VO2 max estimation:** shipped — `lib/training/fitness.ts`, surfaced on the dashboard.
- [x] Estimate from pace + heart-rate data — implemented as Daniels VDOT from the best qualifying run (the original Cooper-formula note is superseded)
- [x] Track VO2 max trend over time — dashboard SVG sparkline over `fitness_snapshots`
- [x] Update after each qualifying run

**Race pace predictor:** shipped — `RaceDayPanel.svelte` (Riegel projection), mounts on plan detail within 21 days of the goal race.
- [x] Predict finish times (Riegel formula with VO2 max adjustment)
- [x] Confidence levels based on data quality — `predictionConfidence` (training.ts/.dart parity pair) grades the Riegel projection high/moderate/low from the anchoring effort's distance gap (factor vs target), recency, and qualifying-run count; surfaced as a confidence chip with a localized reason tooltip on `RaceDayPanel` (only for the data-derived path, not a user-set goal time)

**Recovery advisor:** shipped — `lib/training/training_load.ts` + `readiness.ts`; `TrainingLoadChart` (90-day fitness / fatigue / form trio) + a readiness card on the dashboard.
- [x] Acute training load (ATL) — 7-day EWMA
- [x] Chronic training load (CTL) — 42-day EWMA
- [x] Training stress balance (TSB = CTL - ATL)
- [x] Rest/easy/hard session recommendation
- [x] Days until next recommended hard session — `daysUntilNextHardSession` (fitness.ts/.dart parity pair) projects the ATL/CTL EWMAs forward at rest until TSB recovers to the hard-session threshold (−10); surfaced under the recovery-advice line on the dashboard (web `fitness-next-hard` line + mobile `FitnessCard`), shown only when ≥1 day out and not framed as a comeback

### Competitor-parity — shipped social + engagement

Surfaces that other running apps ship as table stakes; these have now shipped. Each one is "the canonical answer is well-known, copy it." Order is rough leverage-per-effort, not strict dependency. See `docs/architecture/decisions.md § 30` for the precedent (club-owned routes) and individual decision entries for the specs as they're written.

- [x] **Following graph + activity feed** — `user_follows (follower_id, followee_id, followed_at)` join table; activity feed hosted as the **Feed** tab under `/social` (the top-level Social hub — see below) showing recent public runs from people you follow, server-side time-windowed to the last `FEED_WINDOW_DAYS` (14) days so the feed reads as "what's new" rather than a backlog dump. Full-width responsive card grid (`repeat(auto-fill, minmax(22rem, 1fr))` matching `/runs`); per-entry track-preview map; activity-segmented filter + "Last 14 days" hint pill. Cards link to `/runs/[id]`. The legacy `/feed` URL and the old `/u/[me]?tab=feed` deep link both redirect to `/social?tab=feed`. Public-by-default user profile pages at `/u/[id]` showing display_name, avatar, recent public runs, follow button. Strava's core engagement loop. Spec: `decisions.md § 31` + `decisions.md § 61`.
- [x] **Social hub IA — find other runners** — Sidebar item "Clubs" renamed to "Social" with three tabs at `/social`: **Feed** (default), **People**, **Clubs**. The new **People** tab is the first top-level surface for discovery — name-search (debounced 300ms, `user_profiles.display_name ILIKE`, self-excluded) plus a Suggested-for-you list (members of viewer's clubs they don't follow yet, ranked by shared-club count). Inline Follow toggle with optimistic flip + rollback. `data.ts#searchPeople` + `fetchSuggestedPeople` (no SECURITY DEFINER RPC — existing RLS on `user_profiles` + `club_members` + `user_follows` covers it). `/clubs` and `/feed` top-level routes stay alive as redirects so deep links keep resolving; club sub-routes are unchanged. Spec: `decisions.md § 61`. 11 e2e tests in `tests-e2e/runs/social.spec.ts`. **Mobile (Android + iOS twin):** `screens/people_screen.dart` mirrors `SocialPeople.svelte` (same 300 ms debounce, same suggested-from-clubs ranking, same optimistic-flip Follow). Mobile has no top-level Social tab — the People surface hangs off the AppBar of `feed_screen.dart` and `clubs_screen.dart` via a `person_search` icon.
- [x] **Kudos + comments on runs** — `run_kudos (user_id, run_id)` join + `run_comments (id, run_id, author_id, body, parent_comment_id, …)` with one-level threading. RLS gates visibility through an EXISTS subquery on `runs` so engagement on a private run is invisible to anyone but the owner. RunSocial component mounts on `/share/run/[id]`, `/runs/[id]`, and as compact kudos/comment chips on each `/feed` entry. Spec: `decisions.md § 32`.
- [x] **Privacy zones** — `user_settings.prefs.privacy_zones: [{lat, lng, radius_m}]` plus a `clip_track_for_user` SECURITY DEFINER RPC that reads zones server-side and returns only the clipped middle (so zones never reach the client). Settings UI on `/settings/preferences` with a MapLibre map picker. `/share/run/[id]` and `/share/route/[id]` both call the RPC; owner views are unclipped. v2 follow-up: snap `routes.start_point` to first non-zone waypoint via the existing `routes_set_start_point` trigger so nearby-routes search doesn't leak. Spec: `decisions.md § 33`.
- [x] **Training load curves (Fitness / Fatigue / Form)** — `lib/training_load.ts` (TRIMP when HR data is available, distance proxy fallback) + `TrainingLoadChart` three-line SVG over 90 days of daily-aggregated stress. Mounts on `/dashboard` below the existing fitness numeric card. Server-side recompute job is still pending (parity.md), but the live client computation matches what the job will eventually produce. Spec: `decisions.md § 34`.
- [x] **Plan templates (coach-managed plans)** — `training_plans.is_template + parent_template_id + club_id` (decisions §35). `clone_plan_template(template_id, start_date)` SECURITY DEFINER RPC duplicates template + weeks + workouts into a user-owned active plan, anchored at the chosen start date. `/clubs/[slug]` gains a Templates tab; `/plans/new` shows a "Start from a club template" picker; `/plans/[id]` exposes Publish-as-template (owner-only when they admin a club) plus a parent-template chip on cloned instances. Clone-not-subscribe — template edits don't propagate to existing instances. **Mobile parity (2026-06-12):** the new-plan template picker shipped on `plan_new_screen.dart` (bottom-sheet picker across the viewer's clubs → `clonePlanTemplate`), alongside the existing club-detail Templates tab + Publish-as-template flow.
- [x] **Photos on runs** — `run_photos (id, run_id, owner_id, storage_path, caption, position_idx)` table backed by a public-read `run-photos` Storage bucket; bytes live at `{owner_id}/{photo_id}.{ext}` with per-user-folder INSERT/DELETE policies. Visibility tracks the parent run via EXISTS-on-runs (same shape as kudos/comments). RunPhotos.svelte gallery mounts on `/runs/[id]` (full owner UI: upload + caption + delete) and `/share/run/[id]` (read-only). **Server-side EXIF strip**: an AFTER INSERT trigger on `run_photos` enqueues a `kind='photo_process'` job; the Go worker downloads the photo, walks the JPEG marker stream, removes every APPn (0xE0–0xEF) + COM segment (EXIF / XMP / ICC / vendor tags), and re-uploads in place — no re-encoding, lossless, idempotent. JPEG-only for v1; PNG/WebP/HEIC pass through unchanged (see `apps/job_worker/internal/exif/` + `handler_photo_process.go`). Migration `20260525_001_run_photos.sql` (+ `20260825_001_jobs_kind_allowlist_photo_process.sql` for the trigger); spec: `decisions.md § 36`. Deferred: server-side thumbnail generation, club-photo features.
- [x] **Segments + leaderboards (route-anchored, v1)** — `segments (route_id, name, start_distance_m, end_distance_m, length_m generated, author_id)` + `segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)` with `unique(segment_id, run_id)` so reimports don't double-count. RLS visibility on both tables tracks the parent route via EXISTS. Auto-effort generation is **client-side** (decisions §37): `lib/segments.ts#computeEffortFromTrack` walks the track once, accumulates haversine distance, and interpolates timestamps at the start/end crossings. SegmentsPanel on `/routes/[id]` (create-from-distance-range + expandable leaderboard); RunSegmentEfforts on `/runs/[id]` (rank pills with gold/silver/bronze for top-10).
- [x] **Segments v2 — tiered leaderboards + KOM/QOM crowns** — `user_profiles.gender` + `user_profiles.date_of_birth` (both nullable, opt-in via Settings → Demographics on web; mobile twin pending). `segment_leaderboard_tiered(segment_id, gender, age_band, limit)` SECURITY INVOKER RPC joins profiles server-side and applies the filters there using Strava's 5-year age bins (`SEGMENT_AGE_BANDS` constant — `18-19`, `20-24`, …, `75+`). SegmentsPanel on `/routes/[id]` (web) + `widgets/segments_panel.dart` (mobile twin) gain gender + age-band dropdowns above the leaderboard that re-fire the RPC on change. **Crowns**: a gold trophy renders on the rank-1 row of whichever filtered view is open; the crown's tooltip / aria-label is composed from `crownLabel(gender, age)` ("Fastest woman 30-34", "Fastest overall", etc.) so it's always honest about the tier; a "You hold this crown" banner appears above the list when the viewer is rank 1 under the active filter. Migration `20260829_001_segments_v2_tiered_leaderboards.sql`. Still deferred: arbitrary-geometry segments (Hidden Markov / Hausdorff matching) and real-time effort during a run.
- [x] **Notifications inbox** — `notifications (user_id, actor_id, kind, run_id, comment_id, event_id, plan_id, club_id, read_at, …)` populated by SECURITY DEFINER triggers on `run_kudos`, `run_comments`, `user_follows`, `event_attendees`, `event_exceptions`, `plan_workouts`, `direct_messages`, `club_posts`, and `runs` so every social side-effect is written in the same transaction as the source. Kinds: kudos / comment / comment_reply / follow / event_rsvp / event_cancel / plan_update / message / club_post / run_completed. The two community fan-outs (migration `20261101_001`, persona #38): a new club post notifies every active member except the author; a public run started in the last 24 h notifies the runner's followers (recency gate stops a bulk import from exploding inboxes — `decisions.md § 96`). Sidebar bell with unread badge + popover; the full inbox lives under the Notifications tab on `/u/[me]` (own profile only) with all / unread sub-filters; mirrored on the mobile `ProfileScreen`. Refresh on auth-ready and on window focus (no polling). v2: batch / collapse ("Alice and 4 others gave kudos…"), realtime push, device-push fan-out (FCM/APNs, Phase 4b). Spec: `decisions.md § 38`.
- [x] **Run streaks** — daily consecutive-day counter (current + best). Strava-style grace rule: a missing today doesn't break the streak as long as yesterday is intact, so the streak survives the morning-after-a-late-run UX. Pure compute via `lib/streaks.ts` (web) / `lib/streaks.dart` (mobile twin) / `recording/Streaks.kt` (Wear OS) — bucketise run `started_at` by local day, walk the sorted set for `best`, walk back from today for `current`. Mounts as a 5th dashboard stat card on web (flame-coloured when active) and as a "Streak" section between All Time + Last 20 Weeks on mobile; Wear OS port is pure-math-only today (no UI yet, following the RouteMath / MercatorTiles "tests first, UI in a follow-up" pattern). No new tables — derived live from the existing `runs` rows. 13 web + 14 Dart + 13 Kotlin unit tests cover Strava grace, gaps, month/year boundaries, future-clock-skew clamping, and order-independence on all three surfaces.

### Elevation and pace analysis (post-run)

- [x] Elevation profile with chart
- [x] Split table (pace, elevation per km)
- [x] Interactive elevation chart with pace overlay — tap/drag crosshair shows elevation, distance, and local pace; fill colored by pace zones (green fast, amber avg, red slow)
- [x] Best effort tracking — auto-detect fastest 1k, 1mi, 5k, 10k, half marathon, marathon within a single run
- [x] Compare against personal best on same route — Route History section shows PB, time delta, and attempt ranking when run has a routeId

### Backend work (Phase 3)

- [x] Add premium endpoints to Go service — shipped under `apps/job_worker/internal/premium/`. All four endpoints mounted on the existing `/health` listener as POSTs (consistent verb regardless of whether the endpoint reads or computes): `/v1/premium/training-plan` (Riegel-derived paces + phased weekly mileage), `/v1/premium/vo2max` (Daniels VDOT from the best qualifying run in the last 90 days), `/v1/premium/race-predictor` (Riegel from best effort), `/v1/premium/recovery` (90-day EWMA CTL/ATL/TSB + advice). Gated via `user_profiles.subscription_tier` (`pro` + `lifetime` count; anything else → 402) after a shared HS256 JWT extract that mirrors the live hub's auth path. Pure-compute helpers mirror `apps/web/src/lib/training/fitness.ts` + `apps/web/src/lib/training/training.ts`. 36 tests (16 pure-compute + 20 httptest), race-clean. See `docs/product/followups.md § #12` for the full surface, test list, and cutover recipe.
- [x] Enable PostGIS extension in Supabase — shipped in migration `20260415_001_postgis_nearby_routes.sql` (extension + `routes.start_point` + GiST index + `nearby_routes` RPC + sync trigger).
- [x] Add `geom geography(LineString, 4326)` column to `routes` with spatial index — shipped in migration `20260607_001_routes_geom_linestring.sql`. Column + `routes_geom_gist` GiST index + `routes_set_geom` trigger keep the full polyline in sync with `waypoints`. Backfill rebuilds existing rows with ≥2 valid waypoints. Both client codegens treat the column as opaque; queries against it live server-side.
- [x] Add `training_plans` table for generated plans — shipped in migration `20260419_001_training_plans.sql` along with `plan_weeks` and `plan_workouts`. Hardening pass in `20260421_001_plan_hardening.sql`; editor / template surfaces in `20260420_001` and `20260524_001`.
- [x] Add `fitness_snapshots` table for VO2 max and training load history (migration `20260507_001_fitness_snapshots.sql` — `vdot`, `vo2_max`, ATL / CTL / TSB columns, `qualifying_run_count`, `source` check, `latest_fitness_snapshot()` RPC. Server-side recompute job + advisor UI still pending.)
- [x] Connect RevenueCat webhook to update `subscription_tier` in `user_profiles` — Edge Function `revenuecat-webhook` (HMAC-verified via `REVENUECAT_WEBHOOK_SECRET`) handles INITIAL_PURCHASE / RENEWAL / CANCELLATION / EXPIRATION, maps lifetime SKUs to the `lifetime` tier, and updates `user_profiles.subscription_tier` with a guard that lifetime never gets downgraded.
- [ ] Apply for Garmin Connect developer program

### Milestone: App Store + Play Store general availability

---

## Phase 4 — multi-modal: gym + nutrition

**Target:** TBD (post-Phase-3 monetisation milestone)
**Goal:** Expand from running-only to a running + gym + nutrition product inside one app per platform. The differentiator vs Strava (running silo) and MyFitnessPal (nutrition silo) is **cross-modality intelligence** — lifts in the recovery curve + a Coach that reasons across all three — surfaced through one Home and one History. (Co-located cards alone are not the wedge.)
**Architecture:** [decisions.md § 63](../architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db) is the foundational ADR. **Layout & IA + hardened plan:** [docs/features/multi_modal.md](../features/multi_modal.md) (mobile-first anti-clutter IA, the inform-vs-command integration model, lift-load spec, sequencing/validation gates, sensitive-data/DSAR). **Data foundation shipped:** migration `20261204_001` (`gym_workouts`/`gym_sets`/`food_log` + `activities` view) + the `api_client` gym/food methods. (The original `runs.kind` discriminator was dropped by `20261206_001` per F1/D1 — the view projects a per-branch literal instead.)

**Sequencing (hardened — NOT parallel):** finish the Phase 3 training moat (missed-session re-planning — counters Runna, closer to revenue) → ship the nav foundation + **gym** (strong runner fit, low friction, trustworthy lift→load) → **validation gate** (measure gym engagement before committing to nutrition) → ship **nutrition, food-DB-backed** (never manual-only) → promote cross-modality intelligence first-class as each lands. Depth tiers are future work, not committed here. The §63 standalone-escape-hatch is the formal fallback if nutrition's user shape diverges.

### Navigation foundation (mobile + web)

Without this, every new modality competes for the 5-slot bottom nav.

- [x] **Mobile bottom nav** — **shipped (G5)**: `home_screen.dart` is `Home / History / Log / Social / Settings`. The `Run` tab leaves the nav; the centre `Log` slot is a raised FAB (`widgets/log_sheet.dart`) presenting Log run / Log lift / Log food, most-recently-used floats to top, long-press repeats the last modality (one-tap "start run" muscle memory preserved), ≥48 dp + a Semantics label. Picking a modality navigates to its **dwell-in capture page** (run → recorder, lift → Gym, food → Nutrition) — all three are in-shell keep-alive PageView pages, so a session (a recording, a half-built workout, the day's food log) survives navigating away. Shipped **ungated** with a `prefsKeepRunPrimary` "Run as primary action" toggle (protect-the-core-runner) rather than behind `multi_modal_nav`. Twin-mirrored to iOS.
- [~] **Home redesign (mobile + web)** — cards from every modality: today's run, today's lift, daily nutrition rings, plus the existing dashboard cards (mileage chart, training load, fitness, intensity, weekly goal). Cards self-hide when the modality has no data. **Web shipped** (gym slice): a Today's-lift card + a Recent-lifts trend card + a first-run "log a lift" footer on `/dashboard`, all flag- + data-gated. The nutrition macro rings shipped on their own `/nutrition` page; folding a daily-nutrition-rings card into the `/dashboard` Home stack is the remaining piece of this redesign. **Mobile Home card composition shipped (G5):** `dashboard_screen.dart` composes a self-hiding today's-lift card (`widgets/gym_summary_card.dart`) + today's nutrition rings card (`widgets/nutrition_rings_card.dart`) + a recent-lifts trend card (`widgets/recent_lifts_card.dart`), each omitted when that modality has no data, 2-up on phones ≥360 dp. Remaining: the web Home nutrition card (web's rings live on `/nutrition`).
- [x] **History unification (mobile + web)** — single timeline of activities (runs + lifts + meals) with filter chips. Run-detail / lift-detail / meal-detail are separate routes. **Web shipped**: `/history` is the pure unified timeline (the run-list management moved to its own dedicated `/runs` page, un-redirected — §63 amendment); All/Runs/Lifts/Meals chips over the `activities` view once a second modality has data (data-gated, no flag; every chip incl. Runs is the timeline; each single-modality tab has a `View all` → `/runs` / `/gym` / `/nutrition`; rows link to `/runs/[id]` + `/gym/[id]`; meal rows in the timeline stay read-only — the per-meal detail is the dedicated `/nutrition/[date]/[slot]` route off the day view). **Mobile shipped** (byte-identical twin): `runs_screen.dart` hosts the same chips + a day-grouped timeline (`widgets/activity_timeline_list.dart`), assembled from the **local stores** via `lib/local_activities.dart` (offline-first, not `fetchActivities`; History hydrates the gym + food stores on mount); same per-tab `View all` push; run rows open run-detail (local lookup, else `fetchRunById`), lift rows open `GymDetailScreen`, meals read-only. **Per-meal detail shipped (2026-06-12):** web `/nutrition/[date]/[slot]` + mobile `nutrition_meal_detail_screen.dart` (slot items + macro breakdown + 7-day trend), reached from the nutrition day-view meal headers.
- [x] **Web sidebar** — `Run` / `Gym` / `Nutrition` as explicit siblings. Web isn't constrained by the bottom-nav ceiling so the modalities surface directly. **Gym + Nutrition sidebar items ship, always present** (web `+layout.svelte`) — ungated to match mobile (§63 amendment); the dashboard cards + history chips self-hide on data presence.
- [x] **Feature flag** — `multi_modal_nav` per user (universal `user_settings.prefs`, `docs/backend/settings.md`). **Retired / dormant** (2026-06-04, §63 amendment): no surface reads it any more — web was ungated to rely on data presence like mobile (which never had the flag; pure-runner protection is the `prefsKeepRunPrimary` toggle). The key is kept registered as a possible future kill-switch, not deleted.

### Activity-kind data model

The DB grows a shared abstraction so cross-modality views stay sane.

- [x] Migration: broader modality discriminator. The original `runs.kind` column (`'run' | 'lift' | 'meal'`, `20261204_001`) was **dropped** by `20261206_001` (F1 / decision D1): `runs` only ever held `'run'`, so the column was vestigial. The `activities` view now projects the literal `'run'`/`'lift'`/`'meal'` per UNION branch instead. The finer-grained `activity_type` (`run | walk | cycle | hike | stroller`) is now a real `runs` column (`20261207_001`, F3), no longer a metadata key.
- [x] New tables: a `gym_workouts` parent + `gym_sets` child (one row per set within a workout), and a `food_log` table (one row per logged item). Schema kept deliberately thin for the lightweight tier; food / exercise DB tables are deferred to depth tiers. **Shipped** in `20261204_001`.
- [x] `activities` view — UNION of `runs` + `gym_workouts` + `food_log` projecting `(id, user_id, kind, started_at, summary_jsonb)`. Drives the unified History list without three round trips. **Shipped** (`security_invoker`); consumed by web History via `fetchActivities`.
- [x] RLS — owner-scoped writes, public-toggle aligned with how `runs.is_public` works today so the social layer reuses the existing follower / feed plumbing. **Shipped** in `20261204_001`.
- [ ] Codegen — `npm run gen:types` + `dart run scripts/gen_dart_models.dart` after each migration (per [schema_codegen.md](../architecture/schema_codegen.md)). Update the narrow-union pair list in `apps/web/scripts/check_constraint_unions.mjs` for the new `kind` CHECK.

### Gym — lightweight tier

Strong app's free-form log, not its programmed-routine engine.

- [x] Web: **shipped** — `/gym` (list, PR badges) + `/gym/[id]` (detail, per-exercise PR chips, edit/delete) + the composer as a modal (`GymEditor.svelte`, exercise name as free text with history autocomplete, sets[] with reps + weight + optional RPE). Data layer in `core/data.ts`; e2e in `tests-e2e/gym/gym.spec.ts`. Followed the create-flow modal pattern rather than a standalone `/gym/new` route.
- [x] Mobile: **shipped** — `gym_screen.dart` (list + PR badges + log composer), `gym_compose_sheet.dart` (free-text exercise with history autocomplete + inline reps/weight/RPE sets), `gym_detail_screen.dart` (per-exercise PR chips + edit/delete). All offline-first through the already-shipped `LocalGymStore` (decisions §122); list stats + PR badges compute from the store's inline sets, hydrated by `api_client.fetchGymWorkoutsWithSets`. Twin-mirrored byte-for-byte to iOS ([decisions.md § 39](../architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)). **Nav entry landed (G5):** `GymScreen` is reachable via the centre Log sheet ("Log lift") + the Home today's-lift card.
- [x] Personal-records per `(user, exercise_name)` — heaviest set, most volume, best rep PR (Epley e1RM). **Shipped** as the pure parity pair `gym_prs.ts` ↔ `gym_prs.dart` (17 tests each); web History rows show a "PR" badge and detail shows per-exercise chips. Home PR card pending (Home redesign).
- [x] Sharing — **shipped web + mobile (2026-06-12)**: same `is_public` pattern as runs. Web `/gym/[id]` gets a public/private toggle + copy-share-link (`setGymWorkoutPublic`) + a read-only public `/share/workout/[id]` page; mobile mirrors the toggle on `gym_detail_screen.dart`. Lift summary cards (title + set count + volume) appear in the social feed (next item).
- [ ] **Not in scope:** exercise database, workout templates, programmes, RPE-driven progression (all in the gym depth tier below).

### Nutrition — food-DB-backed (NOT manual-only)

**Hardened:** manual macro entry is dead on arrival (nobody knows the macros of "chicken bowl"); a food database is pulled forward from the depth tier — **nutrition does not ship without it.** Gated behind the gym validation gate (below). Full rationale + IA: [docs/features/multi_modal.md](../features/multi_modal.md).

- [x] Web: **shipped** — `/nutrition` (daily log + rings + weekly trends) + `/nutrition/log` (composer — **search Open Food Facts → tap → confirm portion**; manual entry only as the no-match fallback). Nutrition sidebar item always present (§63 amendment ungated web).
- [x] Mobile: **shipped** — `nutrition_screen.dart`, `nutrition_log_sheet.dart`, `food_search.dart` (Open Food Facts client, pluggable-fetcher seam), twin-mirrored. **Nav entry landed (G5):** reachable via the Log sheet ("Log food") + the Home nutrition rings card. Barcode scan (camera) is a v1.1 fast-path on the same lookup (deferred).
- [x] Daily targets — Mifflin-St Jeor BMR × activity-level (`nutrition_targets` parity pair), overridable in Settings. **Shipped both sides:** web demographics card + mobile `settings_body_metrics_screen.dart` (G5) behind the Art 9 health-consent gate; **body metrics** stored as height on `user_profiles` + a `body_metrics` weight time-series (migration `20261216_001`). Mobile resolves targets via the shared `loadNutritionTargets`. **Operator carry-over:** privacy disclosures (iOS label / Play Data Safety / sub-processor list — Open Food Facts) still to update before real-user launch.
- [x] Water tracker — separate from food log, simple count of 250 ml units. Shipped web + mobile.
- [x] Weekly trends — mirrors the existing `mileage_trend_card` pattern. Shipped web + mobile (7-day calorie trend on `nutrition_screen.dart`).

### Cross-modality integration — the headline, not the afterthought

**This is the wedge** (Coach reasoning across all three + lifts in the recovery curve), not the card layout. Built first-class as each module lands, on the **inform vs command** two-tier model (see [multi_modal.md](../features/multi_modal.md)).

- [x] **Lift training-load (Tier 1):** lift sessions contribute `source='lift'`-tagged stress to the same CTL/ATL/TSB series (`liftStress` in the `training_load` parity pair), calibrated so a hard lift ≈ an easy run's TSS and capped against typos. **Run-load stays separable** so a lift bug can't corrupt run-only readiness; a calibration test pins the target. **Wired on both platforms:** web `/dashboard` feeds logged gym sessions into `computeTrainingLoadSeries` (data-gated, no flag — §63 amendment) via the pure `liftsFromSetHistory` helper, and mobile `dashboard_screen.dart` does the same via the Dart twin `lift_load.dart`, so the fitness/fatigue/form trio, recovery advice, and readiness ring all reflect lifts; the chart shows a "gym sessions included" hint.
- [x] **Coach context (Tier 1):** `coach/context.ts` reads a **bounded** recent-lifts cap (`COACH_LIFTS_CAP`) + a 7-day nutrition *summary* (daily averages, not raw rows) so prompt size + cost stay flat. Nutrition is gated on the same Art 9 health-consent as DOB/HR; lifts are ungated activity data. Daily cap unchanged.
- [x] Home composes all three modalities (self-hiding); History timeline + filter chips over the `activities` view (windowed/paginated). **Web shipped** for runs + lifts (see Home/History rows above). **Mobile shipped:** self-hiding today's-lift + nutrition rings + recent-lifts cards on `dashboard_screen.dart`, and the unified mobile **History** timeline on `runs_screen.dart` (`widgets/activity_timeline_list.dart`, assembled from the local stores via `lib/local_activities.dart` — offline-first).
- [x] Social feed extends to **lift** cards (`is_public`) — **shipped web + mobile (2026-06-12)**: `fetchFollowingActivityFeed` merges public runs (`public_runs`) + public gym workouts (`gym_workouts` owner-or-public RLS) into one window; a distinct lift card + `Lift` filter chip render on web `SocialFeed` + mobile `feed_screen`. Only headline columns surface (no notes/RPE); engagement stays run-only. **meals are not feed-shareable in v1** (privacy footgun, little upside).
- [x] **DSAR (must-fix):** `gym_workouts` / `gym_sets` (nested embed) / `food_log` / `body_metrics` / `safety_contacts` (both directions — `owner_id` + `contact_user_id`, `confirm_token` redacted) all in the data-export path (Go `dataexport` + `export-data` EF; Go completeness guard + Deno 39-spec tests); deletion already FK-cascades from `auth.users`.
- [ ] **Tier 2 (deferred, gated on data trust):** recommendation engine ("under-fuelling for tomorrow's long run", "skip the lift, CTL too high"), plan re-planning that factors fuelling + lift load, Coach-authored meal/lift plans, unified Whoop-style recovery score. Off until logging is reliable.

### Depth tiers (deferred, documented for sequencing decisions)

Not Phase 4 work — documented so future-us doesn't re-litigate scope when the lightweight modules ship.

**Gym — mid (Strong-app territory):**

- Exercise database (FK from `gym_sets.exercise_id` instead of free text), with a starter set of common compounds + isolations + cardio.
- Workout templates — saved routines users adopt from a library or build themselves (mirror of training-plan templates).
- RPE / set-type metadata (warmup / working / dropset / failure).

**Gym — heavy (full programming):**

- Periodised programs (linear, conjugate, block) with progressive-overload prescriptions.
- AI Coach extension: writes the program from goals + history.
- Equipment / gym-availability constraints in plan generation.

**Nutrition — mid (MyFitnessPal territory):**

- Food database (USDA + Open Food Facts), barcode scan (mobile-only, camera permission).
- Meal templates — saved meals users log with one tap.
- Recipe builder — N ingredients → one logged meal.

**Nutrition — heavy (AI-driven):**

- Photo-of-plate recognition (vision-model-based — heavy lift, expensive at scale).
- AI Coach writes the meal plan from training plan + goals + dietary preferences.
- Restaurant menu suggestions, grocery list export.

**Cross-modality depth:**

- Unified recovery score factoring lift + sleep + nutrition + run load (the "Whoop" view).
- Recommendation engine — "you're under-fuelling for tomorrow's long run" / "skip the lift, your CTL is too high".

### Standalone-product test escape hatch

If during early Phase 4 development it becomes obvious that nutrition has a very different user / market shape than running + gym, ship it as a separate app with its own Supabase project and converge later if/when the data justifies it. This is a deliberate branch, not a default — see [decisions.md § 63](../architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db) for why "one app vs three apps that sync" is a binary choice with no defensible middle ground.

---

## Multi-language (i18n) across all clients — landed

Web already shipped six locales (`en/de/fr/es/ja/pt-BR`) — see [decisions.md § 108](../architecture/decisions.md#108-web-i18n-is-detected-client-side-with-a-lazy-loaded-message-catalogue--not-an-accept-language-ssr-framework). This epic brought the same six to mobile + the two watches, each via its platform-standard mechanism, with a per-device locale that defaults to the device locale (never DB-synced). Tracked in [parity.md § App-level settings](parity.md#app-level-settings-not-in-the-registry). Mobile design: [decisions.md § 113](../architecture/decisions.md#113-mobile-i18n-uses-flutter-gen-l10n--arb-with-committed-non-synthetic-output-and-a-per-device-locale).

- [x] Mobile (Flutter): gen-l10n + ARB framework, `localeNotifier` + per-device `Preferences.locale`, language picker in Settings → Preferences, parity + negotiation + picker tests
- [x] Mobile: pilot strings migrated (nav + settings section headers) proving the path
- [x] Mobile: bulk migration of all UI strings to ARB (9 surface groups, ~1900 keys/locale)
- [x] Mobile: `intl` `DateFormat`/`NumberFormat` replacing the hand-rolled English month-name + `.` -decimal formatters
- [x] Mobile: TTS announcement locale + spoken phrases + guided-run scripts follow the active app locale (was hard-coded `en-US`)
- [x] Wear OS (Kotlin): `values-<locale>/strings.xml` resources, `stringResource` migration, locale-aware number formatting + `TtsAnnouncer` locale (device-locale-follow)
- [x] watchOS (SwiftUI): `Localizable.xcstrings` catalogue + project regions + `Measurement`/`NumberFormatter` locale formatting (catalog parity-checked; Mac `xcodebuild` + per-locale simulator spot-check is the one remaining verification)
- [ ] RTL (`EdgeInsetsDirectional` sweep) — deferred until an RTL catalogue (Arabic/Hebrew) is added; infra (CSS logical props on web, dirForLocale on mobile) is ready

---

## Future — Protomaps self-hosted tiles

Migrate from MapTiler to self-hosted map tiles using Protomaps (PMTiles format on S3 or Cloudflare R2). Eliminates per-request tile costs entirely — pay only for storage and bandwidth. Evaluate once tile API usage exceeds MapTiler free tier.

- [ ] Generate PMTiles from OpenStreetMap planet extract
- [ ] Host on Cloudflare R2 (or S3)
- [ ] Point MapLibre style URL to self-hosted tiles
- [ ] Remove MapTiler dependency

---

## Future — Map matching (Strava / Nike Run Club quality)

Snap recorded tracks to the road/path network so the rendered line sits on the actual route rather than drifting with GPS noise. This is what Strava, Nike Run Club, and Google Fit do server-side to produce their clean, road-aligned traces. Consumer phone GPS is 3–8 m accurate on open sky and worse in urban areas — no amount of client-side smoothing can correct that bias, only map matching can.

The target is **professional-grade Hidden Markov Model map matching**, the same family of algorithms used by Strava et al. Open-source reference implementations: [Valhalla Meili](https://github.com/valhalla/valhalla/tree/master/src/meili), [OSRM `/match`](https://project-osrm.org/docs/v5.24.0/api/#match-service), [GraphHopper map matching](https://github.com/graphhopper/graphhopper/tree/master/map-matching). All three take a raw GPS trace + OSM road data and return a snapped polyline.

- [ ] Stand up a backend map-matching service:
  - [x] Pick one of Valhalla Meili, OSRM, or GraphHopper — evaluate on running-specific tracks (trails, parks, urban grid). Picked **OSRM** for the first cut: lightweight (single binary, no JVM), `/match/v1/foot` is a single-call HMM snap, foot profile (`/opt/foot.lua`) keeps parks + trails in the graph. Local dev stack lives at `apps/job_worker/osrm/` (Geofabrik PBF + `osrm-extract` / `partition` / `customize` Makefile + `docker compose up`). `OSRMMatcher` in `apps/job_worker/internal/matcher_osrm.go` is wired in `main.go` whenever `OSRM_URL` is set; otherwise the worker stays on the passthrough so the rest of the pipeline can be exercised without an engine.
  - [ ] Deploy alongside Supabase (Docker image + OSM extract for target region, start country-level then global)
  - [ ] OSM extract refresh pipeline (monthly diffs from Geofabrik)
  - [ ] Expose as an authenticated endpoint (`POST /runs/:id/match`)
- [ ] Wire up sync path:
  - [x] `ApiClient.saveRun` triggers matching on the backend after upload — implicit via the `runs_enqueue_match_job_trigger` (migration `20260609_001_run_match_pipeline.sql`), so every successful track upload auto-creates a `pending` `run_matched_tracks` row + a `kind='map_match'` job. Re-uploads (UPDATE OF track_url) reset state and re-enqueue idempotently.
  - [x] Store both the raw and matched tracks (so future re-matching with better data/algorithms is possible) — `run_matched_tracks (run_id PK, status, matched_track_url, attempts, matched_at, algorithm, algorithm_version, error_message)` carries the matched-side state in a side table; `runs.track_url` stays the canonical raw track. Side-table shape leaves the rarely-read state out of the hot list-query path and lets the worker write under service-role without widening RLS on `runs`.
  - [x] Return the matched geometry to the client for display — Go worker (`apps/job_worker/`) computes + uploads a `.matched.json.gz` blob and PATCHes `run_matched_tracks.status='matched'`. Default matcher is `PassthroughMatcher` (visually identical to raw); set `OSRM_URL` to switch the worker over to `OSRMMatcher` against the local OSRM stack at `apps/job_worker/osrm/`. **Web read path** (`apps/web/src/lib/core/data.ts:fetchRunMatchedTrack` + `/runs/[id]` swaps `RunMap.track` to the matched line when present, surfaces `pending` / `failed` / `skipped` via a corner pill) **and mobile read path** (`ApiClient.fetchRunMatchedTrack` + `run_detail_screen.dart` swaps `LiveRunMap.track` via `_matchInfo?.hasRenderableTrack` + `_MatchStatusPill` for non-matched states) are both wired.
- [ ] Client display:
  - [x] `run_detail_screen` prefers the matched track when available, falls back to raw — `run_detail_screen.dart:522-524` `mapTrack = _matchInfo?.hasRenderableTrack == true ? _matchInfo!.track! : run.track`. Stats (splits, HR zones, elevation) keep deriving from `run.track` because those are properties of what the runner did, not how the line is drawn.
  - [x] `live_run_map` during recording still shows the raw track (live matching is out of scope — it's too slow and too expensive per fix) — implicit: `_maybeFetchMatchedTrack` only fires from `run_detail_screen`'s `initState`; the recording surface (`run_screen.dart`) never calls into it.
  - [ ] Toggle in settings to show raw vs matched (for debugging / verification)
- [ ] Privacy & reliability:
  - [ ] Graceful offline fallback — if the backend is unreachable, show the raw track and retry matching on next sync
  - [ ] Self-hosted from day one to avoid sending user tracks to a third party
- [ ] Stretch: on-device map matching for fully-offline users. Port or FFI-wrap one of the engines above — multi-week effort, revisit once the backend version is proven.

Interim mitigation (shipped): polyline smoothing at render time in `LiveRunMap._smoothTrack`. Reduces GPS zig-zag but cannot correct systematic offset from the road — only map matching can.

---

## Future — Cross-platform parity enforcement

A structural fix for the ongoing problem of Android, iOS, web, and watch clients silently drifting out of sync. We've already paid the cost several times — `activity_type` stored on mobile but not displayed on web, `surface` stored by web but dropped by mobile, `moving_time` computed on one platform but not the others, Google Sign-In on web but not Android. Each one was a manual hunt to find and patch. The goal of this initiative is to make drift **impossible to merge without noticing**.

Three layers, in priority order — each is self-contained, you can ship one without the others.

### 1. Auto-generate DTO types from the Supabase schema

The database schema is the single source of truth. Today, each client hand-writes its own row-to-model mapping (`ApiClient._runFromRow` in Dart, `Run` interface + `fetchRunById` in TypeScript) and they silently diverge when the schema changes. Replace hand-written types with generated ones.

- [x] **Web**: `npm run gen:types` (in `apps/backend`) runs `supabase gen types typescript --local` and writes `apps/web/src/lib/database.types.ts`. `apps/web/src/lib/types.ts` derives `Run` / `Route` / `Integration` / `UserProfile` from `Database['public']['Tables'][...]['Row']`, overriding only the client-side augmentations (narrow unions for `source`/`surface`/`provider`, lazy `track` field, looser `metadata`).
- [x] **CI check**: new `parity-types` job in `.github/workflows/ci.yml` starts local Supabase, runs `npm run gen:types:check`, and fails the build when the committed `database.types.ts` diverges from the schema.
- [x] **Mobile (Dart)**: shipped a local generator (`scripts/gen_dart_models.dart`) that parses `apps/backend/supabase/migrations/*.sql` and emits `packages/core_models/lib/src/generated/db_rows.dart` with `RunRow` / `RouteRow` / `IntegrationRow` / `UserProfileRow` classes plus column-name constants. Chose the custom script over `supadart` / `supabase_codegen` to avoid a dependency-evaluation rabbit-hole on a 4-table schema.
- [x] `ApiClient.saveRun` / `saveRoute` / `_runFromRow` / `_routeFromRow` now route through the generated row classes and column constants, so a column rename in a migration surfaces as a compile error in Dart after regeneration. The hand-written domain `Run` / `Route` / `Waypoint` classes stay for their richer ergonomics (`Duration`, `RunSource` enum, camelCase), but are constructed from / serialized through the generated rows.

**Expected effect**: adding `metadata.steps` on mobile last week would have caused an immediate TypeScript compile error on the web until it was consumed there. Schema-level drift becomes structurally impossible.

### 2. Living feature parity matrix

A single markdown table that lists every user-visible feature with a checkmark per platform. Reviewed during every PR that adds or changes a feature.

- [x] New section in `docs/product/features.md` (or a new `docs/product/parity.md`) with a table: **Feature × [Android, iOS, Web, Wear OS, Apple Watch]**, each cell `✓` / `✗` / `Partial` / `N/A`. Shipped as [`docs/product/parity.md`](parity.md).
- [x] Link from each feature's "Phase X" entry in `docs/product/features.md` to its row in the matrix. Each feature's spec now has a `**Parity:** [see matrix](parity.md#...)` line immediately under its header.
- [x] PR template checkbox: "Updated the feature parity matrix if this PR adds or changes a user-visible feature." Lives in [`.github/pull_request_template.md`](../../.github/pull_request_template.md) under *Docs checklist*.
- [ ] Periodically audit: grep the matrix for rows with mismatched ticks, confirm each asymmetry is intentional (e.g. Android has a pedometer, web can't have one — that's a permanent `✗`), and open follow-up tickets for unintentional gaps.

**Expected effect**: the `activity_type` / `surface` / `moving_time` drift we spent hours hunting becomes visible on page load. Asymmetries are either documented-as-intentional or immediately visible as bugs.

### 3. Cross-client integration test in CI

Single automated test that writes a run via one client and reads it via another, asserting round-trip equality on every field.

- [ ] Start local Supabase (`supabase start`) in CI.
- [ ] Dart integration test: `api_client.saveRun(<fixture>)` against the local instance.
- [ ] Node script: fetch the same run via the web's `fetchRunById` and `parseInt(run.metadata?.steps)` etc., assert deep equality with the fixture.
- [ ] Run on every PR. Red if any field round-trips incorrectly.
- [ ] Extend to `routes`, in-progress runs, auth flows, and sync paths over time.

**Expected effect**: the last line of defence — catches drift that slips past type generation (e.g. metadata fields that are untyped `Json` on both sides) and past the human parity matrix check.

### Non-goal: full backend rewrite

A proper backend API (Go / Node / Rust) where all business logic lives server-side would structurally prevent most of this drift by giving clients nothing to drift *from*. But it's a 2–4 week refactor and only pays off with 3+ actively-developed clients. Revisit if the app ever has a paying user base large enough to justify the engineering spend.

### Recommended order

Do **#1 first** — it's a 15-minute setup per client and removes a whole class of bugs permanently.
Then **#2** — 30-minute doc edit, self-correcting via reviews.
Then **#3** when the first two catch enough to prove their value but leave residual drift worth automating away.

---

## Shipped — Windowed / paged local stores for very large activity history

The offline-first mobile stores (`LocalRunStore`, `LocalGymStore`, `LocalFoodStore`) used to load **every** row into memory on init. They now keep a compact on-disk **summary index** (`index.json`, one lightweight `RunSummary`/summary per row) and hydrate only a **resident window** of full rows — so cold-load reads ONE index file instead of N per-row files, and full `Run` objects (with their GPS tracks + bulky metadata) are capped while the lightweight index still covers the whole history. See [decisions.md § 135](../architecture/decisions.md#135-durable-per-store-summary-index--windowed-hydration-for-the-offline-first-local-stores).

- [x] **Windowed read API** — `LocalRunStore` exposes `summaries` / `summaryRuns` (full-history, track-less), `runs` (resident window ∪ all unsynced), `runById` (resident → disk hydrate), `recentWindow(N)`, `hydrateOlder(N)`, `iterateAllRuns`; `OfflineSyncStore` (gym/food) adds `summaryOf` + `loadInWindow` / `estimateRowsInWindow`.
- [x] **`buildLocalActivities` + run-list pagination against the windowed API** — the History timeline reads `recentWindow()`; `runs_screen` filters / sorts / summarises over the full-history index and resolves only the visible page to resident full runs (hydrating older rows + detail-nav via `runById`).
- [x] **Index-first cold-load + self-heal** — a valid index whose id-set matches the on-disk run files is reused (fast path); a missing / corrupt / drifted index falls back to the full parallel walk and rebuilds (post-crash self-heal + first-launch migration). All-history consumers (dashboard, fitness, mileage, goals, recap, gear backfill, period summary, import dedup) read the index; dashboard PBs read the authoritative server `personal_records` cache.
- [x] **Sync never holds the full set** — the drain works the always-resident unsynced subset (`unsyncedRuns`), and the index is maintained as a batched, atomic, crash-safe sidecar (never a per-row write).

The profiling-to-find-a-threshold step was made moot by the design: cold-load is now bounded by the window + a single index decode regardless of total history, so there's no scale at which it degrades to the old O(n) behaviour.

---

## Future — Hardware: ultra-marathon-optimized watch

**Status: research only. Tier 2+ not committed.** See [decisions.md § 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) for the original deferral and its 2026-05-28 amendment (which permits tier-1 owner-personal bench-prototype work but binds tier 2+ to the original gates).

**Full dedicated roadmap** — per-tier status, the three strategic vectors, the per-step bring-up checklist, and unresolved planning questions — lives at [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md). This section is just a parking-lot stub so the watch shows up in the main roadmap; the detail belongs with the other watch research.

A purpose-built wrist device for ultra-marathon use — 100+ hour GPS battery life, dual-band GNSS for foliage / canyon accuracy, Sharp MIP always-on display, 5-button layout, offline vector maps, IPX7. Targets the niche Garmin Fenix / COROS Vertix / Suunto Vertical own today. Full research lives at [`docs/custom_watch/`](../custom_watch/README.md):

- [Vision](../custom_watch/vision.md) — why ultra (not road or general-purpose smartwatch), the product requirements that fall out of that niche, the competitive set
- [Competitive landscape](../custom_watch/competitive_landscape.md) — frank read on what's unbeatable (chip-level hardware, GNSS algorithm IP, brand trust, retail), what's exploitable (Garmin's hostile UI, weak community, glacial updates), and the three asymmetric strategic vectors that beat building your own watch
- [BOM](../custom_watch/bom.md) — component picks per subsystem (Ambiq Apollo510B MCU, Sony CXD5610 dual-band GNSS, Maxim MAX86177 HR, Sharp Memory LCD, Bosch BMP581), ~$114 production BOM at 10k units (post-[§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified) refresh)
- [Prototyping](../custom_watch/prototyping.md) — three honest cost tiers: $1–2k bench prototype, $15–250k wearable prototype, $300–600k VC-demo / production-intent unit
- [Performance path](../custom_watch/performance_path.md) — where battery life actually comes from: big levers (display, MCU, GNSS chip, sensor coprocessor) vs medium (DMA, tickless RTOS, partial display, multi-rail PMIC) vs the small ones that don't move the needle (RTOS / language / compiler / UI library)
- [Firmware](../custom_watch/firmware.md) — original Zephyr proposal + Supabase-integration design. Superseded by [§ 80](../architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) which picked Embassy + Rust for tier 1; reads as the fallback spec
- [Parts](../custom_watch/parts.md) — active tier-1 shopping list (~$300 silicon + $200-900 bench tools) with order checkboxes

The unticked items below are the gates that would have to flip before *tier 2+* becomes real work. **Tier-1 bench-prototype work is happening now** on the owner-personal path per the §71 amendment — the active workspace is at [`apps/custom_watch/`](../../apps/custom_watch/README.md).

- [ ] Trigger (a): app has a paying user base large enough to fund a parallel hardware effort without starving the software roadmap
- [ ] Trigger (b): an existing ODM (Mobvoi, Huami/Zepp, etc.) approaches us about a white-label firmware deal
- [ ] Trigger (c): a co-founder with shipped-consumer-hardware experience joins the project
- [ ] None of the above — keep `docs/custom_watch/` strategic content frozen at its current resolution; tier-1 owner-personal work continues under the §71 amendment but tier 2+ stays gated

Tier-1 (~$1–2k parts + 3–6 months of evenings) validates that the firmware skeleton works end-to-end against the existing backend. Anything past it — wearable prototype, production-intent unit, retail launch — requires a real team and a real budget and remains gated on the triggers above.

---

## Competitive positioning

| Feature | Run App | Strava | Nike Run Club | Garmin Connect | AllTrails |
|---|---|---|---|---|---|
| iOS | ✓ | ✓ | ✓ | ✓ | ✓ |
| Android | ✓ | ✓ | ✓ | ✓ | ✓ |
| Apple Watch | ✓ | ✓ | ✓ | — | Partial |
| Wear OS | ✓ | ✓ | — | — | — |
| Web app | ✓ | ✓ | — | Partial | ✓ |
| Route builder (free) | ✓ | Paywalled | — | ✓ | Partial |
| GPX import (free) | ✓ | Paywalled | — | ✓ | ✓ |
| Open-source maps (MapLibre) | ✓ | — | — | — | — |
| parkrun sync | ✓ | — | — | — | — |
| Live spectator tracking | ✓ | ✓ (Beacon, paid) | — | ✓ (LiveTrack) | — |
| Training plans | ✓ (premium) | — | ✓ (guided runs) | ✓ | — |
| VO2 max / fitness | ✓ (premium) | ✓ (paid) | — | ✓ (device) | — |

---

## Tech stack summary

| Layer | Technology | Phase |
|---|---|---|
| iOS + Android app | Flutter + Dart | 1 |
| Apple Watch | Native Swift + SwiftUI + WatchKit | 2 |
| Wear OS watch | Native Kotlin + Compose-for-Wear | 2 |
| Web app | SvelteKit 2 + Svelte 5 + TypeScript | 2b |
| Web maps | MapLibre GL JS (tiles via MapTiler, future: Protomaps self-hosted) | 2b |
| Web deployment | AWS (S3 + CloudFront + Lambda + Route 53) — see [decisions.md § 53](../architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) | 2b |
| Monorepo | Melos workspace (Flutter) + pnpm (web) | 1 |
| Maps (mobile) | flutter_map + MapLibre | 1 |
| GPX/KML parsing | Dart `gpx` package + `togeojson` (web) | 1 |
| Health sync | `health` pub.dev package (HealthKit + Health Connect) | 1 |
| Backend — core | Supabase (Postgres + Auth + Storage + Edge Functions) | 1 |
| Backend — real-time + jobs | Go service (WebSockets, background jobs, premium features) on Fly.io | 2 |
| Spatial queries | PostGIS extension in Supabase Postgres | 3 |
| Ephemeral data | Redis (Upstash) for live tracking positions | 2 |
| Subscriptions | RevenueCat (App Store + Play Store IAP) | 3 |
| CI/CD | GitHub Actions | 1 |

---

## Cost projection

| Users | Supabase | Go (Fly.io) | Redis (Upstash) | Total/month |
|---|---|---|---|---|
| 1K | Free | — | — | **$0** |
| 10K | $25 (Pro) | $5 | Free | **$30** |
| 50K | $25 | $15 | $10 | **$50** |
| 100K | $75 | $25 | $10 | **$110** |
| 500K | $599 (Team) | $50 | $25 | **$674** |

Map tile costs are minimal — MapTiler has a generous free tier, and Protomaps (self-hosted) eliminates tile costs entirely at scale. Budget for routing API costs (OSRM or Valhalla, both self-hostable).

---

## Deferred from Phase 1 (Android-specific)

These were considered during Android implementation and intentionally pushed to a later phase because they need server-side credentials, OAuth flows, or device APIs that don't fit a quick incremental change:

- **OAuth sign-in (Google/Apple)** on Android — only email/password works against the same Supabase backend as the web app. Needs deep link config and Android signing setup. Tracked under Phase 3 — see "External platform sync".
- **Strava and parkrun integrations** — moved to Phase 3 ("External platform sync"). Removed from the Android Settings UI in the meantime to avoid placeholder buttons.
- ~~**Heart rate from Bluetooth devices**~~ — shipped: `lib/ble_heart_rate.dart` with `flutter_blue_plus` against BLE Heart Rate Service 0x180D / characteristic 0x2A37, pairing UI in Settings, live BPM row during recording, `avg_bpm` written to `metadata` on save.
- **Persistent disk tile cache** — currently in-memory only via flutter_map_cache. Persistent caching needs Hive or sqlite init.
- ~~**Voice cues at custom intervals**~~ — shipped: configurable split interval in Settings (500m, 1km, 2km, 5km, or 0.5/1/2/5 mi).
- ~~**History filter by activity type**~~ — shipped: filter chips on the History screen (All / Run / Walk / Cycle / Hike).

---

## Known issues — runs storage + bulk import

The move from `runs.track` jsonb to Supabase Storage and the Strava/Health Connect bulk importers landed together. A few rough edges were left to fix in follow-up work:

### Real bugs (fix before shipping the importer to real users)

- [x] **External ID collision on re-import.** `ApiClient.saveRun` now upserts with `onConflict: 'external_id'` when `externalId` is set, so re-imports update the existing row.
- [x] **Storage object leak when runs are deleted.** `ApiClient.deleteRun` now deletes both the row and the gzipped track file from the `runs` Storage bucket. Wired into `RunDetailScreen` and `RunsScreen` bulk-delete flows.
- [x] **Public share pages can't read GPS tracks.** Added `is_public` column to `runs` table (migration `20260413_001_public_runs.sql`), RLS policy for anonymous read of public runs, Storage RLS policy for anonymous track download. Web share page uses `fetchPublicRun()`. Mobile share flow calls `makeRunPublic()` before opening the share sheet.

### Performance / UX improvements

- [x] **Bulk import is N serial round trips.** `ApiClient.saveRunsBatch` uploads tracks in parallel groups of 8 and upserts rows in chunks of 100. `ImportScreen` saves locally first, then batch-pushes to the cloud.
- [x] **Redundant track re-uploads on edit.** `saveRun` now preserves the existing `track_url` from metadata when the track list is empty, skipping the storage upload for metadata-only edits.
- [x] **Local duplication of tracks.** `RunDetailScreen._maybeFetchTrack` no longer persists the fetched track back to `LocalRunStore` — the track stays in Supabase Storage and is re-fetched on demand (fast via dio HTTP cache). Eliminates the ~300 MB on-device bloat.
- [x] **FIT file parsing** for Strava imports. A custom `FitParser` in `packages/gpx_parser` reads GPS record messages from FIT binary files. Strava importer now handles GPX, TCX, and FIT tracks.
- [x] **WorkManager-based periodic background sync.** `background_sync.dart` registers a periodic WorkManager task (hourly, network-connected constraint) that pushes unsynced runs when the app is closed.
- [x] **Backup ZIP scales to thousands of runs.** `BackupService` rewritten in May 2026 to stream to disk via `ZipFileEncoder` + lazy-decode via `InputFileStream` + download tracks in bounded-concurrency batches. Peak heap drops from ~300 MB to ~5 MB at 5 000 runs; OOM risk on mid-tier Android is gone. See `decisions.md § 66`.
- [x] **Server-side backup via `/v1/export?format=backup`.** The Go data-export service (`apps/job_worker/internal/dataexport/server.go`) gained a `format=backup` mode that emits the run-app-backup v1 shape — manifest + runs.json + routes.json + profile.json + per-run tracks/{id}.json.gz (raw gzipped bytes archived verbatim). Mobile `BackupService.createBackup` tries the server first when `LIVE_HUB_URL` is set + the user has a session; falls through to the local streaming writer on any non-200 / IO error / unconfigured build. The server cap stays at 5 000 runs — power users beyond that automatically land on the local writer. See `decisions.md § 66`.
- [x] **Web backup streams to disk.** `apps/web/src/lib/backup/backup.ts` now delegates to `buildBackupZip` in `backup_writer.ts`, which uses `@zip.js/zip.js`'s `BlobWriter` + `ZipWriter` to flush each entry's bytes to the underlying Blob (disk-backed on Chrome >250 KB) and `Promise.allSettled` in batches of 6 for parallel track downloads. JS-heap pressure no longer scales with archive size; browser tabs survive 5 000-run backups. See `decisions.md § 66`.

---

## Open risks

- **Apple Watch native Swift** adds a separate codebase. Scope carefully — keep the watch app lean (record + navigate only) and leave analytics on the phone.
- **parkrun scraping** can break without notice. Build it as a best-effort feature with graceful degradation.
- **Garmin Connect** developer program requires business approval. Do not block Phase 3 on this — use HealthKit/Health Connect as the primary Garmin data path for early users.
- **Map tile hosting** — MapTiler free tier covers early growth. Migrate to Protomaps (self-hosted PMTiles on S3/R2) when tile costs matter. This is on the roadmap.
- **Web app scope creep** — the web app is a power tool, not a second mobile app. Resist the urge to replicate every mobile screen. Keep it focused on route building, analytics, and account management.
- **Live tracking battery drain** — Publishing GPS every 3 seconds over WebSocket adds battery cost. Make it opt-in per run, not default. Test drain target: <5% additional per hour.
- **Training plan accuracy** — V1 plans are rule-based (Daniels' formula), which is proven science but not personalised. If user outcome data shows the rules aren't enough, add a Python ML service later — the Go service architecture supports this cleanly.
- **Go service as single point of failure** — The Go service handles WebSockets, background jobs, AND premium features. Keep these as separate goroutine pools so a spike in one doesn't starve the others. Health check each independently.

---

## Anti-spam / moderation — what's shipped, what's deferred

Phases 1 and 2 landed as a tightening of the search + create paths;
phase 3 shipped the smallest-useful reporting surface. The bigger
admin-tooling work is intentionally deferred until the first real
spam wave forces the prioritisation.

### Shipped

- [x] **Search ranking by reputation** — clubs sort by member_count
  alongside geographic distance; people sort by `public_runs_count`
  before falling through to alphabetical. Migration
  `20260906_001_search_ranking_member_count.sql` adds the
  `clubs.member_count` denorm + maintenance trigger. Web wires it via
  `apps/web/src/lib/social/search_ranking.ts`. (Anti-spam phase 1)
- [x] **Soft create-rate-limits** on clubs (5/hour) and routes
  (30/hour). BEFORE INSERT triggers call `enforce_create_rate_limit`
  which reuses the existing `rate_limits` table + `check_rate_limit`
  RPC. service_role + null-auth (migrations, seed) + forged inserts
  (caught by RLS instead) all bypass. Migration
  `20260907_001_create_rate_limits.sql`. (Anti-spam phase 2)
- [x] **User-submitted reports** on profiles, clubs, routes. A
  `reports` table with polymorphic `(target_kind, target_id)` ref + a
  `submit_report` SECURITY DEFINER RPC that validates the target
  exists, rejects self-reports, rate-limits at 10/hour, and refuses
  duplicate pending reports via a partial-unique index. RLS hides
  others' reports from each user. Migration
  `20260908_001_user_reports.sql`. Web: `ReportDialog.svelte` mounted
  on `/u/[id]`, `/clubs/[slug]`, `/routes/[id]`. (Anti-spam phase 3)
- [x] **Admin role + moderation page.** `app_admins (user_id)` allow-list
  + a `private.is_admin(uid)` oracle (SECURITY DEFINER, `private` schema
  so it's not a PostgREST RPC oracle — mirrors the membership oracles)
  back four admin-gated RPCs (`am_i_admin`, `fetch_pending_reports`,
  `fetch_reports_for_target`, `resolve_target_reports`). Every report RPC
  hard-denies a non-admin with `42501` server-side — the real boundary,
  since the web SPA can't gate on the client. Web: `/admin/reports` queue
  (one row per reported target, newest-active first) → detail modal →
  triage (mark reviewed/dismissed + note). **Web-only** back-office tooling
  ([decisions §142](../architecture/decisions.md#142-admin-authorization-is-db-enforced-via-app_admins--a-privateis_admin-oracle-never-client-side-route-gating)). Triage-only — no content takedown in v1.
  Migration `20270104_001_admin_moderation.sql`.

### Deferred

- [ ] **Auto-hide after N reports** from vetted reporters. Once an
  admin page exists, add a SECURITY DEFINER `auto_hide_target()`
  function that flips a `clubs.shadow_hidden` / `routes.shadow_hidden`
  / `user_profiles.shadow_hidden` boolean when ≥ N pending reports
  from distinct reporters with ≥ M public runs each accumulate.
  **Decisions settled (2026-06-12, backlog E1+E3 — build E1 & E3 together
  since the reputation gate is the counting rule):** N = 3 distinct vetted
  reports; M ≥ 5 public runs for a reporter to count; the owner IS notified
  ("hidden pending review"); admin revert from `/admin/reports`. CISO review
  was recommended (moderation surface) and the owner chose to proceed without
  it — record that in the build PR. Not yet built.
- [x] **Report buttons on more surfaces** — shipped (backlog E2,
  migration `20270115_001`). The MVP covered users / clubs / routes;
  this finalized `comment` as a first-class `ReportTargetKind` and
  added `club_post` + `run`. The `reports.target_kind` CHECK + the TS
  union now cover {user, club, route, comment, club_post, run} and are
  registered as a CHECK↔union guard pair; `submit_report` validates
  the new targets and rejects self-reports. Web: Report on each
  non-author club-feed post + on runs (run-detail + share-run).
  Mobile: report affordance on club posts + the public-run screen
  (byte-identical iOS twin). pgtap + e2e + widget tests.
- [ ] **Reputation-weighted reports.** A bot reporting a real user
  from 5 puppet accounts shouldn't auto-hide them. When the auto-hide
  feature ships, gate it on reporters with ≥ M public runs (the same
  threshold the search People tab will use once the suggested-search
  merge in decisions.md § 54 lands) so reports from drive-by accounts
  count for less.
- [x] **Friendly "slow down" toasts** for the create-rate-limit P0001
  errors — shipped (backlog E4). `data.ts` (createClub / saveRoute /
  importRoute) already rewraps the P0001 SQLSTATE into a friendly
  Error; the web create flows (ClubEditor, route builder, ImportRoute)
  now surface that via `showToast(..., 'error')` instead of an inline
  banner — bringing web to parity with mobile's `showTopBanner`.

---

## Competitor-parity backlog (unphased)

Generated from `docs/product/competitors.md` and confirmed scope with the user. These are the features that would close the gap to the strongest existing apps (Strava / Garmin / Nike Run Club / AllTrails / Runna / Komoot). They are **deliberately unphased** — ordering depends on three decisions the user still owes:

1. **Which competitor do we most want to displace first?** (Drives which bundle ships before the others — e.g. beating Runna means plan runner before segments; beating Strava means segments + social graph before plans.)
2. **Pricing model:** free forever / freemium / pay-once. Gates how much of the list sits behind a paywall.
3. **Premium boundary:** where the line runs between free and paid if freemium is chosen.

Until those three are answered, treat this list as a menu, not a sequence. Rough sizing is in weeks of single-dev work; most items carry schema changes that need the usual codegen + CI parity check (see `schema_codegen.md`). **Note (2026-06-03): this menu predates roughly half its items shipping** — rows now marked `[x]` shipped or partial were built ahead of the ordering decisions; the still-open rows are the real remaining menu.

| # | Feature | Rough size | Competitor it closes | Schema impact | Open decisions |
|---|---|---|---|---|---|
| 1 | **Training plan runner** — [x] web: schema + generator + editor + dashboard card + auto-match; [x] Android: engine port + plans list + create wizard + plan/workout detail + today's-workout card on Run tab idle; [x] live structured-workout execution loop (shipped on Android — [workout_execution.md](../features/workout_execution.md)) | **shipped** (web + Android + execution loop) | Runna, Garmin | `training_plans`, `plan_weeks`, `plan_workouts` (shipped) | Resolved — reused the existing audio-cue layer + a band overlay on the run screen, zero schema impact. |
| 2 | **External integrations (OAuth sync)**: Strava read + write, Garmin Connect, Health Connect, HealthKit, parkrun, RunSignUp | 4–6 wk + Garmin business approval | Strava, Garmin | `integrations` already exists — extend per provider; token refresh Edge Function | Webhook vs polling for Strava; Garmin app approval timeline |
| 3 | **Segments + leaderboards** ([x] **shipped** — v1 route-anchored boards + v2 tiered (gender / age-band) leaderboards with KOM/QOM crowns; client-side auto-effort. See Phase-3 social section above.) | shipped | Strava | `segments`, `segment_efforts` (migrations `20260526_001`, `20260829_001`) | Resolved: route-anchored v1; arbitrary-geometry HMM matching still deferred |
| 4 | **Heatmap / popular-route discovery** ([x] v1 shipped — public-routes-only heatmap via PostGIS `heatmap_points_in_bbox` RPC on top of densified `routes.geom`; web overlay on `/routes?tab=heatmap` with a MapLibre `heatmap` paint layer; refreshes on map moveend with 350 ms debounce, 5k point cap. Privacy: route opt-in already gates inclusion via `routes.is_public`. **[x] v2 shipped (web) — turned the blob into a route browser** laid out as a results sidebar beside a clean map (no more floating overlays stacking on each other or the map): a search + **Filters** popover holding the lens (`popular` / `friends` / `featured` / `hidden_gems` on `discoverable_routes_in_bbox`'s `p_filter` arg) and **multi-select race-distance bands** (5K / 10K / Half / Marathon / Ultra, combinable in any permutation, server-side via the parallel `p_dist_min[]`/`p_dist_max[]` bound arrays), MapLibre clustering on the route pins, a scrollable results list with per-route distance-band badges, the heat layer dimming as you zoom in, and **hover-to-preview** — route lines are hidden by default; hovering a dot or its list row reveals just that one route's line (cached, anti-flicker) with a synchronized highlight across the map + list. `friends` = public routes *created by* users you follow (there is no retained run↔route link to power "run by friends"); `hidden_gems` = un-run public routes past a 1 km sanity floor. **[x] Mobile parity shipped** — `routes_heatmap_screen.dart` (byte-identical twin) now has the same lens + race-distance band filters, pure-Dart pin clustering (no new dep), a results bottom sheet, and tap-to-preview (touch equivalent of hover); see [decisions § 102](../architecture/decisions.md).) | 2 wk | Strava, Komoot | Migrations `20260828_001_heatmap_points.sql`, `20261113_001_discoverable_routes_filter.sql`, `20261114_001_discoverable_routes_distance_bands.sql` | Resolved: opt-in (via existing `routes.is_public`) — no separate user-level toggle |
| 5 | **Trail / offline navigation** (turn-by-turn nav on a loaded route, offline tile packs, condition reports). [x] partial — "Save for offline" per-route pin on mobile + phone → Wear OS DataLayer push of starred routes so watches without network can still access them (see `decisions.md § 64`); turn-by-turn voice cues, offline tile packs, and condition reports still deferred | 3–4 wk | AllTrails, Komoot | `route_conditions` (user reports), tile-pack store on disk | Which routing engine for turn cues? |
| 6 | **Social graph** ([x] **shipped** — follow/unfollow + feed, kudos, threaded comments, privacy zones. See Phase-3 social section above.) | shipped | Strava, Nike Run Club | shipped as `user_follows`, `run_kudos`, `run_comments`, `user_settings.prefs.privacy_zones` (not the placeholder names in this row) | Resolved: public-by-default profiles; report surface shipped (see Anti-spam below) |
| 7 | **Gear tracking** ([x] shipped — `gear` + `run_gear` tables under migration `20260827_001_gear_tracking.sql`, RLS owner-scoped on gear and join-through-runs on assignments. `gear_with_distance` view aggregates per-item mileage. Web: `/settings/gear` tab with sub-tabs (shoes / bikes), retire/restore/delete, mileage bars with km/mi awareness. `RunGearChips.svelte` mounted on `/runs/[id]` with owner-only multi-select modal. Mobile (both twins): `GearScreen`, `gear_form_sheet.dart`, `run_gear_chips.dart`. Future: per-shoe wear-pattern logging, multi-pair "rotation" tagging, barcode import.) | 1 wk | Strava, Garmin | `gear` + `run_gear` | Resolved: manual entry for v1 |
| 8 | **Photos on runs and routes** ([x] **runs shipped** — `run_photos` + `run-photos` bucket + server-side EXIF strip; [x] **route photos shipped** — `route_photos` + private `route-photos` bucket, web + android (+ iOS twin), client-side EXIF strip, backlog C1) | done | Strava, AllTrails | `run_photos` + `route_photos` (buckets `run-photos` / `route-photos`) shipped — migrations `20260525_001` / `20270114_001` | Deferred: server-side thumbnails + EXIF worker for route photos, club-photo features |
| 9 | **Audio-coached / guided runs** ([x] **shipped** — TTS-narrated scripted workouts. `lib/training/guided_runs.ts` (web, parity twin `apps/mobile_android/lib/guided_runs.dart`) holds the cue library; web `/guided` + `/guided/[id]` are a preview surface (web doesn't record), mobile `guided_runs_screen.dart` speaks the cues via `audio_cues.dart` during a recording. TTS-only v1 — no pre-recorded voice talent.) | shipped (web preview + mobile TTS) | Nike Run Club | none (scripted library in code) | Resolved: TTS-only v1, no audio CDN |
| 10 | **Race calendar + results import** (event discovery near me, entry links, auto-match results when you record the race) | 2 wk | Garmin, Runna | `races`, `race_results`; import from RunSignUp + parkrun | Scope: local only or worldwide? |
| 11 | **Advanced analytics** ([x] **shipped** — VDOT/VO₂, training-load fitness/fatigue/form curves, race-time predictor, weekly/monthly breakdowns. See Phase-3 "Premium tier" + "Competitor-parity" sections above.) | shipped | Garmin, Runna | `fitness_snapshots` + derived from `runs` | Resolved: Daniels (VDOT) + Banister-style EWMA load |
| 12 | **Premium billing + feature gating** (Stripe Checkout, subscription webhook, `SubscriptionTier` honouring across web + mobile, customer portal) | 1–2 wk | All | `user_profiles.subscription_tier` already exists; add `stripe_customer_id`, `stripe_subscription_id` | Monthly vs annual; grandfather early users? |
| 13 | **Treadmill (BLE FTMS)** ([~] **mobile partial, backlog C3** — FTMS `0x1826` / `0x2ACD` reader + `TreadmillSample` stream (`ble_treadmill.dart`), Settings → Integrations pairing tile, and an additive opt-in distance seam in `run_recorder` (belt overrides GPS only in treadmill mode; GPS L0/L1 path untouched; writes `metadata.indoor_source='treadmill'`). **Deferred:** the live run-screen mode toggle — UI wiring against the shipped seam, no recorder change needed) — real-time speed / distance / incline from a paired treadmill. Mobile-only (web is not a recording surface). Spec + scope: [integrations.md § Treadmills (BLE FTMS)](../features/integrations.md#treadmills-ble-ftms--deferred). | Partial | Garmin, Runna (indoor) | None — `prefs.treadmill_device` + `metadata.indoor_source = "treadmill"` | FTMS covers ~60 % of treadmills; Peloton / NordicTrack / Echelon need per-vendor work. Punt or scope per-brand follow-ups when v1 ships. |

### Where each item lives in the repo

For whichever items the user green-lights, here's where the new surface lands — so future sessions can pick one up without re-deriving the map:

- **Web pages:** `apps/web/src/routes/<feature>/+page.svelte` + the data helpers in `src/lib/core/data.ts` (add a new section header). New types overlay in `src/lib/types.ts`.
- **Mobile Android:** `apps/mobile_android/lib/screens/<feature>_screen.dart` + a service singleton in `apps/mobile_android/lib/<feature>_service.dart` if there's non-trivial network state. Tab additions in `home_screen.dart`; 6 tabs is the current ceiling — past that, collapse under an existing tab.
- **Backend:** one migration per feature under `apps/backend/supabase/migrations/` with the same naming pattern (`YYYYMMDD_NNN_<feature>.sql`). Run `npm run gen:types && dart run scripts/gen_dart_models.dart` after each, commit both.
- **Edge Functions** for OAuth exchanges / webhooks: `apps/backend/supabase/functions/<provider>-<action>/index.ts`. One function per provider action (e.g. `strava-webhook`, `garmin-import`).
- **Decisions** for any non-obvious trade-off: append to `docs/architecture/decisions.md` in sequence (next free number is #11).
- **Feature doc stub** in `docs/product/features.md` under a "Competitor-parity features" section (stubs added below, flesh out on delivery).
- **Tests** — see `docs/testing/testing.md` for the per-feature-area test map.

*Last updated: 2026-06-03*
