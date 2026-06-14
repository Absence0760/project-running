---
name: Shipped feature delivery record
description: Historical implementation checklists for delivered roadmap phases (1, 2, 2b, and shipped Phase 3 items), moved out of roadmap.md on 2026-06-14 to keep the roadmap forward-looking. The roadmap keeps a one-line ✓ summary + pointer per feature.
---

# Shipped feature delivery record

Moved out of [roadmap.md](roadmap.md) on 2026-06-14. These are the full delivery checklists for features that have shipped + been tested in-repo. The roadmap itself keeps each feature's heading with a one-line ✓ summary and a pointer here.

## Phase 1 — MVP: prove the core loop

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

## Phase 2 — watch parity: wrist-first experience

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

### Live spectator tracking

- [x] `/live/{run_id}` spectator page with MapLibre map (simulated runner)
- [x] Live position dot, trace line, pace/distance/elapsed stats
- [x] Runner shares a live tracking link before starting — pre-start "Share live link" button on `run_screen.dart` pre-mints the run id so the URL is stable across the "share now → tap GO later" gap; URL points at `/live/{run_id}` on the configured web host (`WEB_BASE_URL`).
- [x] Mobile recorder writes per-ping rows to `live_run_pings` while a run is in flight — `LiveBroadcaster` (Android + iOS twin) attached on Share-live-link tap, throttled 5 s, swallows network failures (L4); `ApiClient.beginLiveBroadcast` pre-creates the parent `runs` row with `is_public=true` so anon spectators on the share URL can read; `endLiveBroadcast` wipes pings on stop and `cleanup_stale_live_run_pings` (cron, 4 h) handles the crash path.
- [x] WebSocket connection to Go service (replace simulation) — both ends shipped. Mobile recorder routes pings through `apps/mobile_android/lib/live_hub_client.dart` when `LIVE_HUB_URL` is in `dotenv.env`; web spectator opens a WS to `${PUBLIC_LIVE_HUB_URL}/v1/live/{run_id}/subscribe` when set (with auto-reconnect + late-joiner snapshot via `fetchLiveSnapshot`). Both gracefully fall back to the Supabase Realtime path when unset. The Go-side hub lives in `apps/job_worker/internal/livehub/` (see #12). Env-flip lands once the Fly.io app is provisioned.
- [x] Positions stored ephemerally in Redis (TTL 24h) for late joiners — **code shipped** as `apps/job_worker/internal/livehub/redis_hub.go` (pub/sub on `live:{runID}:ch`, last-known `live:{runID}:last` + history ring, all 24h-TTL'd; 14 miniredis tests). `main.go` picks the backend at boot from `REDIS_URL` (else the in-process map, which is the single-replica dev default). See the "Set up Upstash Redis" item under Backend work (Phase 2) below — only the operator env-flip remains.

## Phase 2b — web app: plan big, review deep

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

## Phase 3 — growth and monetisation

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
