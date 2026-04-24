# Run app — product roadmap

---

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
- [ ] Parse on iOS

### Live GPS run recording (phone)

Track position, pace, distance, and elapsed time using device GPS. Runs saved to local storage first — no backend required at this stage.

- [x] Background location tracking (Android — geolocator foreground service)
- [x] Background location tracking (iOS — CLLocationManager background mode via run_recorder; Info.plist UIBackgroundModes:location + NSLocationAlwaysAndWhenInUseUsageDescription; verified on simulator)
- [x] Real-time pace and distance display (Android)
- [x] ~~Auto-pause on stop detection~~ (Android) — *removed*: replaced by moving time derived from the GPS track at summary time. See [decisions.md § 4](decisions.md).
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
- [x] Multi-goal dashboard — distance / time / avg-pace / run-count, weekly or monthly, with per-goal progress feedback (Android)
- [x] Browsable weekly/monthly summary — navigate to previous periods from dashboard, share as text or screenshot (Android)

### Cloud sync + auth

- [x] Supabase Auth with email/password sign-in and sign-up
- [x] Google and Apple OAuth scaffolded (needs provider credentials to enable); iOS: Apple Sign-In scaffolded behind _kAppleSignInEnabled = false pending Services ID setup
- [x] Auth callback route for OAuth redirect
- [x] Onboarding flow on first launch with location permission request (Android)
- [x] Offline-only mode — runs work without backend or auth (Android)
- [x] UUID run IDs to avoid sync collisions across devices
- [x] Pull remote runs from Supabase, merge with local store (Android)
- [x] Bulk sync button for unsynced runs (Android)
- [x] Backup all runs as JSON via system share sheet (Android)
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
- [ ] Encrypt OAuth tokens in `integrations` table with `pgcrypto`
- [ ] Add rate limiting to Edge Function endpoints
- [ ] Validate Strava webhook signatures
- [ ] Set up MapTiler API usage monitoring

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
- [ ] Syncs run data via Watch Connectivity framework

### Wear OS standalone GPS recording

- [x] Compose-for-Wear UI (pure Kotlin rewrite — see [decisions.md § 15](decisions.md))
- [x] GPS recording independent of phone (`FusedLocationProviderClient` in `GpsRecorder.kt`)
- [x] HR recording via Health Services (`MeasureClient` in `HeartRateMonitor.kt`, average pushed to `run.metadata.avg_bpm`)
- [x] Ultra-length (10h+) recording: streaming on-disk track writer, rolling-HR aggregation, checkpoint-by-reference, throttled notification refresh, streamed gzip upload, low-battery pre-run warning
- [x] Live race mode: server-authoritative Arm/GO/End + per-runner pings feeding a spectator leaderboard, auto-submitted `event_results` rows, optional organiser approval gating
- [ ] Auto-sync on reconnect (today `drainQueue` fires on app start + after stop; connectivity-change listener is a TODO)

### Route navigation on watch

- [ ] Route preview on watch face before starting
- [ ] Live position on mini-map during run
- [ ] Off-route haptic + "recalculating" indicator

### Glanceable tiles and complications

- [ ] watchOS complication: pace + distance
- [ ] Wear OS tile: active run summary

### Live spectator tracking

- [x] `/live/{run_id}` spectator page with MapLibre map (simulated runner)
- [x] Live position dot, trace line, pace/distance/elapsed stats
- [ ] Runner shares a live tracking link before starting
- [ ] WebSocket connection to Go service (replace simulation)
- [ ] Positions stored ephemerally in Redis (TTL 24h) for late joiners

### Backend work (Phase 2)

- [ ] Deploy Go service to Fly.io (~$5/month)
  - [ ] WebSocket hub for live spectator tracking
  - [ ] Background job queue (Postgres-backed via River)
  - [ ] Strava webhook handler (moved from Edge Function)
  - [ ] Token refresh worker (moved from Edge Function)
  - [ ] Data export worker (moved from Edge Function)
- [ ] Set up Upstash Redis for live position streams
- [ ] Add `personal_records` summary table with insert trigger
- [ ] Add `jobs` table for Go worker queue
- [ ] Migrate Strava webhook, token refresh, data export from Edge Functions to Go service

### Milestone: App Store + Play Store public beta

---

## Phase 2b — web app: plan big, review deep

**Target:** ~5 weeks (runs in parallel with or immediately after Phase 2)
**Goal:** A SvelteKit web app at `app.runapp.com` that handles everything better done on a big screen
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
- [ ] Comparison against previous runs on same route

### Live tracking spectator view (web)

- [x] Public page at `/live/{run_id}` (no auth required)
- [x] MapLibre map with runner dot and trace line
- [x] Live distance, elapsed time, pace stats
- [x] Pulsing "LIVE" badge
- [x] Map auto-follows runner position
- [x] Open Graph and SEO meta tags
- [ ] Connect to Go service WebSocket (currently simulated)

### Account and integrations management

- [x] Connect / disconnect Strava, Garmin, parkrun, HealthKit (persisted to Supabase)
- [x] Account settings page (display name, preferred units)
- [x] Enter parkrun athlete number
- [x] Download all data as CSV (GDPR compliance)
- [ ] Manage premium subscription

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
- [ ] `pg_cron` job to refresh materialized view (every 5 min)
- [ ] Verify dashboard queries perform under 2 seconds for users with 200+ runs

### Milestone: web app live at `app.runapp.com`

---

## Phase 3 — growth and monetisation

**Target:** ~8 weeks after Phase 2
**Goal:** Build the features that drive acquisition, retention, and revenue
**Backend:** Supabase + Go service (premium features added to Go service)

### In-app route builder (free)

- [ ] Click-to-place waypoints on MapLibre (mobile)
- [ ] Auto-snap to roads or trail mode
- [ ] Elevation preview before running
- [ ] Save to route library + shareable link

### Community route library

- [x] Public / private toggle per route
- [x] Explore Routes screen — search public routes by name (full-text), filter by distance range and surface type, save to library, paginated results (Android)
- [x] "Popular near me" discovery feed — PostGIS `ST_DWithin` queries via `nearby_routes` RPC, `start_point geography(Point)` column with auto-populate trigger, "Near Me" tab on Android explore screen (geolocator) and web explore page (browser Geolocation API)
- [x] Route ratings and comments — `route_reviews` table (1-5 stars + optional comment, one per user per route), reviews section on route detail screen, avg rating in stats row, submit/edit review dialog
- [ ] Share to social (image card with map + stats)
- [ ] SEO-indexed public route pages

### Clubs and events — social layer

Phased rollout so the schema doesn't sprawl. MVP is club-owned events only, enum-based recurrence (Phase 2), and open-join clubs with invite-link sharing (Phase 2). See `docs/clubs.md` for surfaces and `apps/backend/supabase/migrations/20260416_001_clubs_and_events.sql` for schema.

- [x] **Phase 1 — MVP (web only):** `clubs` / `club_members` / `events` / `event_attendees` / `club_posts` tables with RLS; browse/create/view clubs, create one-off events, RSVP, owner/admin text updates. No recurrence, no invites, no notifications. Web routes: `/clubs`, `/clubs/new`, `/clubs/[slug]`, `/clubs/[slug]/events/new`, `/clubs/[slug]/events/[id]`.
- [x] **Phase 2 — recurrence + invites:** Enum recurrence (`weekly` / `biweekly` / `monthly` + `byday[]` + `until_date`) with instance expansion on the client; per-instance RSVPs (`event_attendees` pkey extended with `instance_start`); join policies (`open` / `request` / `invite`) with a pending-requests admin panel; shareable invite tokens on clubs + `/clubs/join/[token]` landing route; one-level threaded replies on posts. Migration: `20260417_001_phase2_social.sql`.
- [x] **Phase 3 — Android mirror:** `clubs_screen.dart` (Browse + My clubs), `club_detail_screen.dart` (feed / events / members tabs with threaded post replies and member post composer), `event_detail_screen.dart` (per-instance RSVP + admin update composer), `upcoming_event_card.dart` replaces the Last-Run card on the Run tab when the user has RSVP'd `going` to an event within 48h. Clubs added as a 6th bottom-nav tab. Recurrence is ported to Dart (`recurrence.dart`) so instance expansion stays consistent with web. Club/event creation is deliberately not on Android — admins still use the web app for those.
- [x] **Phase 4a — realtime (web + Android):** Supabase Realtime is enabled on `club_posts`, `event_attendees`, and `club_members` (migration `20260418_001_social_realtime.sql`). Web club / event detail pages and Android `ClubDetailScreen` / `EventDetailScreen` subscribe via `postgres_changes` and debounce reloads at 250ms. Payloads are ignored in favour of a fresh enriched fetch so RLS stays authoritative.
- [ ] **Phase 4b — push (FCM / APNs):** Event-day reminders (scheduled), admin-update fan-out, and a `device_tokens` table. Blocked on user-supplied Firebase project + service account credentials; not started.

### External platform sync

| Source | Method | Status |
|---|---|---|
| Apple HealthKit | `health` Flutter package | [ ] Not started |
| Android Health Connect | `health` Flutter package | [ ] Not started |
| Strava | Official OAuth 2.0 API + webhook | [ ] Edge Function exists, not wired |
| Garmin Connect | Official developer program (apply) | [ ] Not started |
| parkrun | Athlete number scrape | [ ] Edge Function exists, not wired |
| Race results | RunSignUp API + bib scrape | [ ] Not started |

### AI Coach (free, usage-capped)

Claude-powered training advisor embedded in the web app. Reviews the runner's plan and recent runs; does not generate plans or prescribe medical/nutrition advice (see `decisions.md #12`).

- [x] Server endpoint (`/api/coach/+server.ts`) with prompt-cached system prompt + context dump
- [x] `CoachChat.svelte` UI with suggestion chips and cache-hit stats
- [x] Daily usage limit of 10 messages per user (`user_coach_usage` table, `increment_coach_usage` / `get_coach_usage` RPCs)
- [x] Personality tones — `coach_personality` user setting (`supportive` / `drill_sergeant` / `analytical`) fed into the system prompt
- [x] User preferences (date of birth, HR zones, resting/max HR, weekly mileage goal) fed into context for personalised advice

### Monetisation — Pro tier + one-off donations

The original free-with-donations pivot (`decisions.md #18`) was superseded by the Pro-tier revival (`decisions.md #23`). Infrastructure from the donations era is kept: no features are hidden behind the paywall today; Pro changes behaviour inside two features (coach cap, processing priority) rather than gating screens.

- [x] Core gate infrastructure — `isLocked()` still returns `false` for every registered key (see `decisions.md #18` for why we retained the scaffolding)
- [x] `/settings/upgrade` page rewritten as a two-card layout: Pro plan ($9.99 / mo) + one-off Donate button (see `decisions.md #23`)
- [x] `/api/coach/+server.ts` skips the 10 / day rate limit for users where `is_user_pro(uid)` is true
- [x] `features.ts` — `isPro()` helper + `priority_processing` feature-registry entry
- [x] `monthly_funding` table retained but no longer read by the UI
- [x] Custom `ConfirmDialog.svelte` replacing all browser `confirm()`/`alert()`/`prompt()` calls (see `decisions.md #19`)
- [x] `ToastContainer.svelte` + `toast.svelte.ts` for transient success/error/info feedback
- [ ] RevenueCat web SDK wired behind the "Get Pro" button (`Purchases.configure` + checkout flow)
- [ ] `purchases_flutter` wired on mobile — "Get Pro" flow on Android + iOS
- [ ] Tier-aware rate-limiting on Edge Functions / Go service so the *priority processing* bullet has concrete enforcement beyond the coach-cap bypass

### Premium tier — training and coaching (deferred, see decisions.md #18 and #23)

This section predates the Pro-tier revival and tracks features that were *originally* premium-gated (structured workout runner, plan generator, VO2 max, race predictor, recovery advisor). Under the current model (`decisions.md #23`) Pro unlocks **unlimited coach + priority processing** rather than gating whole features — so the items below are roadmap work, not paywall work, until product direction says otherwise.

**Structured training plan runner (workout execution):**

The foundation under both the generator and any hand-built plan: a data model for a *plan* (goal race + weeks + per-day planned workouts), the surfaces that render "today's workout" to the runner, and the execution loop that drives live pace targets from the planned workout and auto-matches recorded runs back to it. This unlocks the use case where the runner pastes a plan from a coach or a book (e.g. a 32-week marathon plan with phase-banded paces) and the app walks them through it day by day. Own feature because it's valuable with or without plan *generation* — a generated plan is just one of several inputs to the runner.

- [ ] Data model:
  - [ ] `training_plans` table: `id`, `user_id`, `name`, `goal_event_id` (nullable FK to `events`), `goal_time_seconds`, `start_date`, `end_date`, `status` (`active` / `completed` / `abandoned`), `notes`
  - [ ] `plan_weeks`: `id`, `plan_id`, `week_index`, `phase_label` (`base` / `build` / `race_specific` / `taper` — free-form string), `target_volume_metres`, `notes`
  - [ ] `plan_workouts`: `id`, `week_id`, `scheduled_date`, `kind` (enum: `easy` / `long` / `recovery` / `tempo` / `interval` / `marathon_pace` / `race` / `rest`), `target_distance_metres`, `target_duration_seconds`, `target_pace_sec_per_km` (nullable), `target_pace_tolerance_sec` (nullable), `structure_json` (for structured workouts like `4×1 mi @ 7:00 w/ 1 mi easy`), `notes`, `completed_run_id` (nullable FK to `runs` once matched)
  - [ ] Dart + TS type regeneration via the existing `gen:types` flow — see `docs/schema_codegen.md`
- [ ] Plan editor (web-first, mobile read-only in v1):
  - [ ] Create a plan from scratch: set goal race, date, target time, number of weeks
  - [ ] Import from templates: paste markdown table, parse into weeks/workouts, or import from a small built-in library (generic 16-week marathon / 12-week half / C25K)
  - [ ] Edit per-day workouts inline: kind, distance, target pace, notes
  - [ ] Bulk operations: duplicate a week, shift the plan forward/back by N days, mark a week as recovery
- [ ] Dashboard + run-tab surfaces:
  - [ ] "Today's workout" card on the dashboard: type, distance, target pace, quick "Start workout" button
  - [ ] This-week view: 7-day strip with planned vs completed state per day
  - [ ] Plan progress: weeks completed, adherence % (planned miles vs actual), long-run longest, phase marker
- [ ] Execution loop:
  - [ ] "Start workout" opens the run screen pre-configured: activity type from workout kind, target pace locked in, audio cues tuned to the workout's tolerance (e.g. tight band for intervals, loose band for easy runs)
  - [ ] Live "workout progress" overlay during structured workouts — shows the current rep / recovery, upcoming target, reps remaining
  - [ ] Post-run: the completed `run_id` auto-links to the planned workout (same day, same activity) and the workout card flips to "done" with a side-by-side comparison of planned vs actual
  - [ ] Manual override: runner can un-link, re-link to a different planned workout, or mark a workout as skipped without deleting it
- [ ] Adherence feedback:
  - [ ] "N of M workouts completed this week" summary
  - [ ] Flag when weekly mileage drifts >20% under or over plan (both directions matter — over-running the easy weeks is a real failure mode)
  - [ ] Missed-workout recovery: suggest whether to make up a missed long run or skip it, driven by simple rules (phase + proximity to recovery week)
- [ ] Sharing and handoff:
  - [ ] Export a plan as markdown or JSON (round-trip with the paste-import path)
  - [ ] Public plan library — users can publish a plan they followed and others can clone it into their own account (deferred until community infra lands, see § Community)

**Scope note:** this is the single largest feature on the Phase 3 list. Budget weeks, not days. Build in this order: data model + web plan editor first (read-heavy), then dashboard "today's workout" card, then the run-tab execution loop. Structured-workout execution (intervals with live rep tracking) is the final layer and can be skipped in v1 if it blocks ship.

**Training plan generator:**
- [ ] Adaptive weekly plans for 5k, 10k, half marathon, full marathon
- [ ] VDOT calculation using Daniels' Running Formula
- [ ] Training phase determination (base → build → peak → taper)
- [ ] Workout generation: easy, tempo, interval, long run with target paces
- [ ] Adjustment based on missed sessions and recovery patterns
- [ ] Output plugs into the plan-runner data model above — the generator produces `training_plans` + `plan_weeks` + `plan_workouts` rows, same as a hand-built plan

**VO2 max estimation:**
- [ ] Estimate from pace and heart rate data (Cooper formula)
- [ ] Track VO2 max trend over time
- [ ] Update after each qualifying run

**Race pace predictor:**
- [ ] Predict finish times (Riegel formula with VO2 max adjustment)
- [ ] Confidence levels based on data quality

**Recovery advisor:**
- [ ] Acute training load (ATL) — 7-day EWMA
- [ ] Chronic training load (CTL) — 42-day EWMA
- [ ] Training stress balance (TSB = CTL - ATL)
- [ ] Rest/easy/hard session recommendation
- [ ] Days until next recommended hard session

### Elevation and pace analysis (post-run)

- [x] Elevation profile with chart
- [x] Split table (pace, elevation per km)
- [x] Interactive elevation chart with pace overlay — tap/drag crosshair shows elevation, distance, and local pace; fill colored by pace zones (green fast, amber avg, red slow)
- [x] Best effort tracking — auto-detect fastest 1k, 1mi, 5k, 10k, half marathon, marathon within a single run
- [x] Compare against personal best on same route — Route History section shows PB, time delta, and attempt ranking when run has a routeId

### Backend work (Phase 3)

- [ ] Add premium endpoints to Go service:
  - [ ] `POST /training-plan` — generate weekly plan (Daniels' VDOT tables)
  - [ ] `GET /vo2max` — estimate from recent runs with HR data
  - [ ] `GET /race-predictor` — predict finish times (Riegel formula)
  - [ ] `GET /recovery` — training load and recovery recommendation
  - [ ] Gate all by `subscription_tier = 'premium'`
- [ ] Enable PostGIS extension in Supabase
- [ ] Add `geom geography(LineString, 4326)` column to `routes` with spatial index
- [ ] Add `training_plans` table for generated plans
- [ ] Add `fitness_snapshots` table for VO2 max and training load history
- [ ] Connect RevenueCat webhook to update `subscription_tier` in `user_profiles`
- [ ] Apply for Garmin Connect developer program

### Milestone: App Store + Play Store general availability

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
  - [ ] Pick one of Valhalla Meili, OSRM, or GraphHopper — evaluate on running-specific tracks (trails, parks, urban grid)
  - [ ] Deploy alongside Supabase (Docker image + OSM extract for target region, start country-level then global)
  - [ ] OSM extract refresh pipeline (monthly diffs from Geofabrik)
  - [ ] Expose as an authenticated endpoint (`POST /runs/:id/match`)
- [ ] Wire up sync path:
  - [ ] `ApiClient.saveRun` triggers matching on the backend after upload
  - [ ] Store both the raw and matched tracks (so future re-matching with better data/algorithms is possible)
  - [ ] Return the matched geometry to the client for display
- [ ] Client display:
  - [ ] `run_detail_screen` prefers the matched track when available, falls back to raw
  - [ ] `live_run_map` during recording still shows the raw track (live matching is out of scope — it's too slow and too expensive per fix)
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

- [x] New section in `docs/features.md` (or a new `docs/parity.md`) with a table: **Feature × [Android, iOS, Web, Wear OS, Apple Watch]**, each cell `✓` / `✗` / `Partial` / `N/A`. Shipped as [`docs/parity.md`](parity.md).
- [x] Link from each feature's "Phase X" entry in `docs/features.md` to its row in the matrix. Each feature's spec now has a `**Parity:** [see matrix](parity.md#...)` line immediately under its header.
- [x] PR template checkbox: "Updated the feature parity matrix if this PR adds or changes a user-visible feature." Lives in [`.github/pull_request_template.md`](../.github/pull_request_template.md) under *Docs checklist*.
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
| Web deployment | Vercel | 2b |
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

## Competitor-parity backlog (unphased)

Generated from `docs/competitors.md` and confirmed scope with the user. These are the features that would close the gap to the strongest existing apps (Strava / Garmin / Nike Run Club / AllTrails / Runna / Komoot). They are **deliberately unphased** — ordering depends on three decisions the user still owes:

1. **Which competitor do we most want to displace first?** (Drives which bundle ships before the others — e.g. beating Runna means plan runner before segments; beating Strava means segments + social graph before plans.)
2. **Pricing model:** free forever / freemium / pay-once. Gates how much of the list sits behind a paywall.
3. **Premium boundary:** where the line runs between free and paid if freemium is chosen.

Until those three are answered, treat this list as a menu, not a sequence. Rough sizing is in weeks of single-dev work; most items carry schema changes that need the usual codegen + CI parity check (see `schema_codegen.md`).

| # | Feature | Rough size | Competitor it closes | Schema impact | Open decisions |
|---|---|---|---|---|---|
| 1 | **Training plan runner** — [x] web: schema + generator + editor + dashboard card + auto-match; [x] Android: engine port + plans list + create wizard + plan/workout detail + today's-workout card on Run tab idle; [ ] live structured-workout execution loop (**specced in [workout_execution.md](workout_execution.md)**, ~4 dev-days, no new schema) | 6–8 wk (web + Android shipped, execution loop specced + estimated ~4 days) | Runna, Garmin | `training_plans`, `plan_weeks`, `plan_workouts` (shipped) | Spec resolved — reuse existing audio-cue layer, band overlay on the run screen, zero schema impact. |
| 2 | **External integrations (OAuth sync)**: Strava read + write, Garmin Connect, Health Connect, HealthKit, parkrun, RunSignUp | 4–6 wk + Garmin business approval | Strava, Garmin | `integrations` already exists — extend per provider; token refresh Edge Function | Webhook vs polling for Strava; Garmin app approval timeline |
| 3 | **Segments + leaderboards** (segment creation, automatic matching on new runs, weekly / all-time boards) | 2–3 wk | Strava | `segments`, `segment_efforts`; PostGIS line matching | Public vs private segments; anti-cheat |
| 4 | **Heatmap / popular-route discovery** (anonymised aggregation tile layer) | 2 wk | Strava, Komoot | Materialised tile table or a Go tile service | Opt-in vs opt-out privacy default |
| 5 | **Trail / offline navigation** (turn-by-turn nav on a loaded route, offline tile packs, condition reports) | 3–4 wk | AllTrails, Komoot | `route_conditions` (user reports), tile-pack store on disk | Which routing engine for turn cues? |
| 6 | **Social graph** (follow / unfollow, kudos, activity comments, privacy zones) | 2–3 wk | Strava, Nike Run Club | `follows`, `kudos`, `comments`, `privacy_zones` on `user_profiles` | Default profile visibility; block / report surface |
| 7 | **Gear tracking** (shoes, bikes; mileage per item; retirement reminders) | 1 wk | Strava, Garmin | `gear`, `run_gear` (link table) | Manual only v1 vs future barcode import |
| 8 | **Photos on runs and routes** (multi-photo per run, map-pinned, auto-attached from camera roll by timestamp) | 3–4 d | Strava, AllTrails | `run_photos`, `route_photos`; Storage bucket `photos` | Max photos per run; server-side thumbnailing? |
| 9 | **Audio-coached / guided runs** (library of pre-recorded workouts, TTS-narrated pace cues) | 3–4 wk | Nike Run Club | `audio_workouts`, `audio_segments`; audio CDN strategy | Voice talent budget; TTS-only v1? |
| 10 | **Race calendar + results import** (event discovery near me, entry links, auto-match results when you record the race) | 2 wk | Garmin, Runna | `races`, `race_results`; import from RunSignUp + parkrun | Scope: local only or worldwide? |
| 11 | **Advanced analytics** (VDOT, training load / fitness / freshness curves, weekly/monthly breakdowns, race-time predictor) | 2 wk | Garmin, Runna | No new tables — derived from `runs` | Algorithm source of truth: Daniels vs Banister |
| 12 | **Premium billing + feature gating** (Stripe Checkout, subscription webhook, `SubscriptionTier` honouring across web + mobile, customer portal) | 1–2 wk | All | `user_profiles.subscription_tier` already exists; add `stripe_customer_id`, `stripe_subscription_id` | Monthly vs annual; grandfather early users? |

### Where each item lives in the repo

For whichever items the user green-lights, here's where the new surface lands — so future sessions can pick one up without re-deriving the map:

- **Web pages:** `apps/web/src/routes/<feature>/+page.svelte` + the data helpers in `src/lib/data.ts` (add a new section header). New types overlay in `src/lib/types.ts`.
- **Mobile Android:** `apps/mobile_android/lib/screens/<feature>_screen.dart` + a service singleton in `apps/mobile_android/lib/<feature>_service.dart` if there's non-trivial network state. Tab additions in `home_screen.dart`; 6 tabs is the current ceiling — past that, collapse under an existing tab.
- **Backend:** one migration per feature under `apps/backend/supabase/migrations/` with the same naming pattern (`YYYYMMDD_NNN_<feature>.sql`). Run `npm run gen:types && dart run scripts/gen_dart_models.dart` after each, commit both.
- **Edge Functions** for OAuth exchanges / webhooks: `apps/backend/supabase/functions/<provider>-<action>/index.ts`. One function per provider action (e.g. `strava-webhook`, `garmin-import`).
- **Decisions** for any non-obvious trade-off: append to `docs/decisions.md` in sequence (next free number is #11).
- **Feature doc stub** in `docs/features.md` under a "Competitor-parity features" section (stubs added below, flesh out on delivery).
- **Tests** — see `docs/testing.md` for the per-feature-area test map.

*Last updated: April 2026*
