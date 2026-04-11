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
- [ ] Background location tracking (iOS)
- [x] Real-time pace and distance display (Android)
- [x] Auto-pause on stop detection (Android, toggleable)
- [x] Manual pause/resume (Android)
- [x] Lap markers (Android)
- [x] Wakelock during run (Android)
- [x] Activity types — run, walk, cycle, hike — with per-type pace/speed display, calorie multipliers, split intervals, and GPS filters (Android)
- [x] Audio cues for splits and pace alerts via TTS (Android)
- [x] Step count and cadence via pedometer (Android)
- [x] Live HTTP tile cache so revisited tiles work without network (Android)

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
- [x] Edit run title and notes (Android)
- [x] Share run as GPX (Android)
- [x] Share run as image card — map + headline stats (Android)
- [x] Delete runs (Android)
- [x] History sort by newest, oldest, longest, fastest (Android)
- [x] Personal Bests on dashboard — longest run, fastest pace, fastest 5k (Android)
- [x] Weekly distance goal with progress bar (Android)

### Cloud sync + auth

- [x] Supabase Auth with email/password sign-in and sign-up
- [x] Google and Apple OAuth scaffolded (needs provider credentials to enable)
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
      GPX/TCX track files, FIT skipped)
- [x] Health Connect import — pulls workouts from Google Fit, Samsung Health,
      Garmin Connect, Fitbit, Runna, etc. (Android, summary only — no GPS routes)
- [ ] WorkManager-based periodic background sync (Android, when app is closed)

### Backend work (Phase 1)

- [x] Database schema: runs, routes, integrations, user_profiles tables
- [x] Row-level security policies on all tables
- [x] Database functions (weekly_mileage, personal_records)
- [x] Seed script with test user and mock data
- [x] Edge Functions: parkrun-import, strava-import, strava-webhook, refresh-tokens, export-data
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

- [ ] Standalone workout session (no phone required)
- [ ] Heart rate via HealthKit sensor
- [ ] Haptic pace alerts (above / below target)
- [ ] Syncs run data via Watch Connectivity framework

### Wear OS standalone GPS recording

- [ ] Compose for Wear UI (Kotlin + Flutter hybrid)
- [ ] GPS + HR recording independent of phone
- [ ] Background sync on reconnect

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

- [ ] Public / private toggle per route
- [ ] "Popular near me" discovery feed (PostGIS `ST_DWithin` queries)
- [ ] Route ratings and comments
- [ ] Share to social (image card with map + stats)
- [ ] SEO-indexed public route pages

### External platform sync

| Source | Method | Status |
|---|---|---|
| Apple HealthKit | `health` Flutter package | [ ] Not started |
| Android Health Connect | `health` Flutter package | [ ] Not started |
| Strava | Official OAuth 2.0 API + webhook | [ ] Edge Function exists, not wired |
| Garmin Connect | Official developer program (apply) | [ ] Not started |
| parkrun | Athlete number scrape | [ ] Edge Function exists, not wired |
| Race results | RunSignUp API + bib scrape | [ ] Not started |

### Premium tier — training and coaching (~$6/month)

**Training plan generator:**
- [ ] Adaptive weekly plans for 5k, 10k, half marathon, full marathon
- [ ] VDOT calculation using Daniels' Running Formula
- [ ] Training phase determination (base → build → peak → taper)
- [ ] Workout generation: easy, tempo, interval, long run with target paces
- [ ] Adjustment based on missed sessions and recovery patterns

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
- [ ] Interactive elevation chart with pace overlay
- [ ] Best effort tracking on named segments
- [ ] Compare against personal best on same route

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

- [ ] New section in `docs/features.md` (or a new `docs/parity.md`) with a table: **Feature × [Android, iOS, Web, Wear OS, Apple Watch]**, each cell `✓` / `✗` / `Partial` / `N/A`.
- [ ] Link from each feature's "Phase X" entry in `docs/features.md` to its row in the matrix.
- [ ] PR template checkbox: "Updated the feature parity matrix if this PR adds or changes a user-visible feature."
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
| Wear OS watch | Flutter | 2 |
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
- **Heart rate from Bluetooth devices** — needs flutter_blue_plus and per-device GATT characteristic handling.
- **Persistent disk tile cache** — currently in-memory only via flutter_map_cache. Persistent caching needs Hive or sqlite init.
- **Voice cues at custom intervals** — only fixed km/mi splits and pace alerts.
- **History filter** by date range or activity type — only sort options exist.

---

## Known issues — runs storage + bulk import

The move from `runs.track` jsonb to Supabase Storage and the Strava/Health Connect bulk importers landed together. A few rough edges were left to fix in follow-up work:

### Real bugs (fix before shipping the importer to real users)

- [ ] **External ID collision on re-import.** `runs.external_id` is a unique index, but the Strava and Health Connect importers generate fresh run UUIDs each pass, so re-running an import will crash on the second Strava activity with a duplicate `external_id`. Fix: change `ApiClient.saveRun` to `upsert(..., onConflict: 'external_id')` when `externalId` is set, so re-imports update the existing row instead of inserting a duplicate.
- [ ] **Storage object leak when runs are deleted.** `LocalRunStore.delete` and any future `ApiClient.deleteRun` currently remove the row but leave the gzipped track file in the `runs` bucket forever. Fix: add `deleteRun(id)` to `ApiClient` that deletes the row AND the Storage object, or add a Postgres trigger that calls `pg_net.http_delete` on row delete.
- [ ] **Public share pages can't read GPS tracks.** The `/share/run/{id}` page on the web app is meant to be public, but the `runs` Storage bucket is private with owner-only RLS, so `fetchTrack()` returns 403 for anonymous viewers. Three fixes: make the bucket public (simplest, loses access control), generate signed URLs server-side for public runs (extra hop), or add an RLS policy that grants anonymous read when the run row has `is_public = true` (cleanest, most work — requires adding `is_public` to the `runs` table).

### Performance / UX improvements

- [ ] **Bulk import is N serial round trips.** The Strava importer uploads 2,000 tracks and upserts 2,000 rows one at a time. A power user re-import can take 10+ minutes and trip Supabase rate limits. Fix: batch row upserts in chunks of 100 via `insert([...])`, parallelise storage uploads in groups of 5–10 via `Future.wait`. Expected: ~5× throughput improvement.
- [ ] **Redundant track re-uploads on edit.** When `LocalRunStore.update` marks a run unsynced and the sync service later calls `saveRun`, `saveRun` re-uploads the full gzipped track even though only the title/notes changed. Fix: skip the upload in `saveRun` when the run already has `metadata['track_url']` set and we're editing metadata, not recording.
- [ ] **Local duplication of tracks.** After lazy-loading a cloud track into `RunDetailScreen`, the full track is saved back to `LocalRunStore` as plain JSON while the gzipped copy stays in Storage. Correct behaviour but a power user with 5 years of imported history has ~300 MB of duplicated tracks on device. Fix later: either gzip the local JSON files or keep the on-disk copy and drop it from the Storage cache eagerly.
- [ ] **FIT file parsing** for Strava imports. FIT files (Garmin, Wahoo, COROS default exports) are skipped with an error. Users have to re-export as GPX/TCX from Strava. A `fit_parser` Dart package exists but is less polished than xml parsing. Lower priority — most Strava users get GPX/TCX anyway.
- [ ] **WorkManager-based periodic background sync.** Current `SyncService` covers app foreground and connectivity change events. True-when-app-is-closed sync needs `workmanager` plus Android-specific setup for periodic work, network constraints, and Doze handling.

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

*Last updated: April 2026*
