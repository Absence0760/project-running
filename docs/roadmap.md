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

- [ ] Parse GPX, KML, KMZ, and GeoJSON formats
- [ ] Display route on map with distance and elevation summary
- [ ] Save route to local library for reuse

### Live GPS run recording (phone)

Track position, pace, distance, and elapsed time using device GPS. Runs saved to local storage first — no backend required at this stage.

- [ ] Background location tracking (iOS + Android)
- [ ] Real-time pace and distance display
- [ ] Auto-pause on stop detection

### Route overlay during run

Show the imported route on the map while running. Current position tracks against the planned line. Off-route haptic alerts when drifting more than 50m from the path.

- [ ] Live position marker on route
- [ ] Distance remaining to end
- [ ] Off-route detection and alert

### Run history + basic stats

Persist completed runs locally with distance, duration, average pace, and a map trace of the actual path taken.

- [x] Run list sorted by date
- [x] Individual run detail view (map + stats)
- [x] Weekly mileage summary on home screen

### Cloud sync + auth

- [x] Supabase Auth with email/password sign-in and sign-up
- [x] Google and Apple OAuth scaffolded (needs provider credentials to enable)
- [x] Auth callback route for OAuth redirect
- [ ] Background sync on wifi (mobile)
- [ ] Conflict resolution: device wins on merge

### Backend work (Phase 1)

- [x] Database schema: runs, routes, integrations, user_profiles tables
- [x] Row-level security policies on all tables
- [x] Database functions (weekly_mileage, personal_records)
- [x] Seed script with test user and mock data
- [x] Edge Functions: parkrun-import, strava-import, strava-webhook, refresh-tokens, export-data
- [ ] Move GPS tracks from JSONB `track` column to Supabase Storage (store `track_url` reference in row)
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
