# Run app — product roadmap

---

## Vision

A cross-platform running app that covers every device and surface a runner might use — iPhone, Android phone, Apple Watch, Wear OS, and a full desktop web app — with seamless Google Maps route planning, live spectator tracking, ML-powered training plans, and free access to the features every other app puts behind a paywall.

---

## Strategic pillars

1. **Google Maps first** — plan routes in the tool runners already know, import in one tap
2. **Watch parity** — Apple Watch and Wear OS treated as first-class platforms, not companions
3. **Free core** — route building, GPX import, and run history stay permanently free
4. **Open ecosystem** — sync with Strava, HealthKit, Health Connect, parkrun, and race results
5. **Web as a power tool** — the web app is where you plan, analyse, and manage; the phone and watch are where you run
6. **Scale-ready backend** — two-service architecture that grows from a single Supabase project to include a Go service for real-time and background processing

---

## Architecture evolution

The backend grows across phases. Each phase adds only what's needed — no premature infrastructure.

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

### Features

#### GPX / KML import from Google Maps
The primary differentiator. Users export a KML from Google My Maps and open it directly in the app. The route loads instantly on a map, ready to run. No account required. Free forever.

- Parse GPX, KML, KMZ, and GeoJSON formats
- Display route on map with distance and elevation summary
- Save route to local library for reuse

#### Live GPS run recording (phone)
Track position, pace, distance, and elapsed time using device GPS. Runs saved to local storage first — no backend required at this stage.

- Background location tracking (iOS + Android)
- Real-time pace and distance display
- Auto-pause on stop detection

#### Route overlay during run
Show the imported route on the map while running. Current position tracks against the planned line. Off-route haptic alerts when drifting more than 50m from the path.

- Live position marker on route
- Distance remaining to end
- Off-route detection and alert

#### Run history + basic stats
Persist completed runs locally with distance, duration, average pace, and a map trace of the actual path taken.

- Run list sorted by date
- Individual run detail view (map + stats)
- Weekly mileage summary on home screen

#### Cloud sync + auth
Apple Sign-In and Google Sign-In via Supabase Auth. Runs sync to Postgres so they persist across devices and app reinstalls.

- OAuth SSO (no email/password)
- Background sync on wifi
- Conflict resolution: device wins on merge

### Backend work (Phase 1)

Infrastructure hardening before public beta. No new services — all within Supabase.

- [ ] Move GPS tracks from JSONB `track` column to Supabase Storage (store `track_url` reference in row)
- [ ] Encrypt OAuth tokens in `integrations` table with `pgcrypto`
- [ ] Add rate limiting to Edge Function endpoints
- [ ] Validate Strava webhook signatures
- [ ] Set up Google Maps API billing alerts

### Milestone: internal TestFlight / Play Store internal track release

---

## Phase 2 — watch parity: wrist-first experience

**Target:** ~6 weeks after Phase 1
**Goal:** Both watch platforms feel like first-class running computers, not companion screens
**Backend:** Supabase + Go service

### Features

#### Apple Watch standalone GPS recording
Native Swift + WatchKit app. Record pace, HR, distance directly from the wrist without the phone nearby. Syncs to iPhone when back in Bluetooth range.

- Standalone workout session (no phone required)
- Heart rate via HealthKit sensor
- Haptic pace alerts (above / below target)
- Syncs run data via Watch Connectivity framework

#### Wear OS standalone GPS recording
Flutter on Wear OS. Same standalone capability for Android watch users. Syncs to phone via Data Layer API.

- Compose for Wear UI (Kotlin + Flutter hybrid)
- GPS + HR recording independent of phone
- Background sync on reconnect

#### Route navigation on watch
Push an imported route to the watch before a run. Shows a simplified map with current position, distance remaining, and direction arrows. Haptic alert on off-route deviation.

- Route preview on watch face before starting
- Live position on mini-map during run
- Off-route haptic + "recalculating" indicator

#### Glanceable tiles and complications
Wear OS Tiles and watchOS complications showing live pace, HR, and distance without opening the app. Critical for usability during a run.

- watchOS complication: pace + distance
- Wear OS tile: active run summary

#### Live spectator tracking
Friends and family can watch a runner's progress in real time via a shareable link. The runner's phone/watch publishes GPS position every 3 seconds to the Go service WebSocket hub. Spectators see the runner move on a map in their browser.

- Runner shares a live tracking link before starting
- Spectators see live position, pace, distance on a map (no app install needed)
- Works via WebSocket — low latency, low bandwidth
- Positions stored ephemerally in Redis (TTL 24h) for late joiners

### Backend work (Phase 2)

Deploy the Go service for real-time capabilities and background processing.

- [ ] Deploy Go service to Fly.io (~$5/month)
  - WebSocket hub for live spectator tracking
  - Background job queue (Postgres-backed via River)
  - Strava webhook handler (moved from Edge Function)
  - Token refresh worker (moved from Edge Function)
  - Data export worker (moved from Edge Function)
- [ ] Set up Upstash Redis for live position streams
- [ ] Add `personal_records` summary table with insert trigger (replaces slow `personal_records()` function)
- [ ] Add `jobs` table for Go worker queue
- [ ] Migrate Strava webhook, token refresh, data export from Edge Functions to Go service
- [ ] Only parkrun import remains as an Edge Function (simple, infrequent)

### Milestone: App Store + Play Store public beta

---

## Phase 2b — web app: plan big, review deep

**Target:** ~5 weeks (runs in parallel with or immediately after Phase 2)
**Goal:** A SvelteKit web app at `app.runapp.com` that handles everything better done on a big screen
**Backend:** No new services — database optimisations only

The web app is built with SvelteKit and shares zero UI code with Flutter, but calls the exact same Supabase REST API and connects to the Go service WebSocket for live tracking.

### Features

#### Full-screen route builder
The best route planning experience in the product. Google Maps JS API with click-to-place waypoints, drag-to-adjust paths, and road/trail snapping. Substantially more capable than the mobile version.

- Click to place waypoints, drag to reshape
- Road snap and trail mode toggles
- Auto-calculated distance and elevation profile as you draw
- Export as GPX, KML, or shareable link
- Save to account — appears instantly on mobile and watch

#### Run history dashboard
A rich read-only view of all your runs — the kind of data review that works better on a 27" screen than a phone.

- Calendar heatmap of runs by week (like GitHub contributions)
- Monthly and yearly mileage bar charts
- Personal records table (fastest 5k, 10k, half, full)
- Filter by source (recorded, Strava, parkrun, Garmin)

#### Deep run analysis
Click any run to open a full-page analysis view with the complete GPS trace and every metric in detail.

- Full-resolution interactive map with actual GPS track
- Elevation profile with per-km pace overlay
- Heart rate zone breakdown
- Splits table (pace, HR, elevation per km/mile)
- Comparison against previous runs on the same route

#### Live tracking spectator view (web)
The spectator page for live run tracking. Opens in any browser, no login required. Shows the runner's position on a map with pace and distance stats updating in real time.

- `app.runapp.com/live/{run_id}` — public spectator page
- Connects to Go service WebSocket
- Map auto-follows the runner's position
- Shows elapsed time, distance, current pace

#### Account and integrations management
The settings hub — easier to navigate on desktop than buried in a mobile settings screen.

- Connect / disconnect Strava, Garmin, parkrun
- Enter parkrun athlete number
- Download all data as GPX or CSV (GDPR compliance)
- Manage premium subscription

#### Public route and run pages
SEO-indexed public pages for shared routes and run activities — the organic growth engine.

- `app.runapp.com/routes/{id}` — shareable route with map, distance, elevation
- `app.runapp.com/runs/{id}` — shareable completed run with stats and trace
- Open Graph image cards for social sharing

### Backend work (Phase 2b)

Database performance optimisations for dashboard queries at scale.

- [ ] Create `mv_weekly_mileage` materialized view with `pg_cron` refresh (every 5 min)
- [ ] Add full-text search index on `routes.name` for route library search
- [ ] Verify dashboard queries perform under 2 seconds for users with 200+ runs

### Milestone: web app live at `app.runapp.com`

---

## Phase 3 — growth and monetisation

**Target:** ~8 weeks after Phase 2
**Goal:** Build the features that drive acquisition, retention, and revenue
**Backend:** Supabase + Go service (premium features added to Go service)

### Features

#### In-app route builder (free)
Draw routes directly on Google Maps inside the app — no export/import step. Strava paywalls this. Yours is free. Primary acquisition driver.

- Click-to-place waypoints on Google Maps
- Auto-snap to roads or trail mode
- Elevation preview before running
- Save to route library + shareable link

#### Community route library
Public browseable library of user-shared routes, sortable by location, distance, and surface type. Creates network effects and organic SEO discovery. Powered by PostGIS spatial queries.

- Public / private toggle per route
- "Popular near me" discovery feed (PostGIS `ST_DWithin` queries)
- Route ratings and comments
- Share to social (image card with map + stats)
- SEO-indexed public route pages

#### External platform sync

| Source | Method | Data |
|---|---|---|
| Apple HealthKit | `health` Flutter package | All workouts on device from any app |
| Android Health Connect | `health` Flutter package | All workouts on device from any app |
| Strava | Official OAuth 2.0 API + webhook | Activities, routes, segments |
| Garmin Connect | Official developer program (apply) | .FIT files, HR, training data |
| parkrun | Athlete number scrape | 5k times, event history |
| Race results | RunSignUp API + bib scrape | Finishing times, splits |

#### Premium tier — training and coaching (~$6/month)
Rule-based training intelligence served by the Go service. All V1 algorithms are proven exercise science formulas — no ML required. The paywall sits on top of coaching intelligence — the core app remains free. Managed via RevenueCat (abstracts App Store + Play Store in-app purchases).

If ML model training is needed in the future (personalised plans based on user outcome data), a Python service can be added at that point — the architecture supports it cleanly. Until then, TypeScript/Go handles everything.

**Training plan generator:**
- Adaptive weekly plans for 5k, 10k, half marathon, full marathon
- Calculates current fitness (VDOT from recent times) using Daniels' Running Formula
- Determines training phase (base → build → peak → taper)
- Generates workouts: easy, tempo, interval, long run with target paces
- Adjusts based on missed sessions and recovery patterns

**VO2 max estimation:**
- Estimates aerobic fitness from pace and heart rate data
- Cooper test formula with HR drift cross-reference
- Tracks VO2 max trend over time (improving / maintaining / declining)
- Updates after each qualifying run

**Race pace predictor:**
- Predicts finish time for 5k, 10k, half, and marathon
- Riegel formula (`T2 = T1 * (D2/D1)^1.06`) with VO2 max adjustment
- Confidence levels based on data quality

**Recovery advisor:**
- Acute training load (ATL) — 7-day exponentially weighted moving average
- Chronic training load (CTL) — 42-day EWMA
- Training stress balance (TSB = CTL - ATL)
- Recommends rest, easy, or hard session based on fatigue level
- Days until next recommended hard session

#### Elevation and pace analysis (post-run)
Elevation profile, per-kilometre splits, heart rate zones, and comparison against previous runs on the same route. The data layer that keeps runners coming back daily.

- Interactive elevation chart with pace overlay
- Split table (pace, HR, elevation per km/mile)
- Best effort tracking on named segments
- Compare against personal best on same route

### Backend work (Phase 3)

Add premium feature endpoints to the Go service and spatial database capabilities.

- [ ] Add premium endpoints to Go service:
  - `POST /training-plan` — generate weekly plan (Daniels' VDOT tables)
  - `GET /vo2max` — estimate from recent runs with HR data (Cooper formula)
  - `GET /race-predictor` — predict finish times (Riegel formula)
  - `GET /recovery` — training load and recovery recommendation (ATL/CTL/TSB)
  - All gated by `subscription_tier = 'premium'` check
- [ ] Enable PostGIS extension in Supabase
- [ ] Add `geom geography(LineString, 4326)` column to `routes` with spatial index
- [ ] Add `training_plans` table for generated plans
- [ ] Add `fitness_snapshots` table for VO2 max and training load history
- [ ] Connect RevenueCat webhook to update `subscription_tier` in `user_profiles`
- [ ] Apply for Garmin Connect developer program (do not block Phase 3 on approval)

### Milestone: App Store + Play Store general availability

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
| Google Maps integration | ✓ | — | — | — | — |
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
| Web maps | Google Maps JavaScript API | 2b |
| Web deployment | Vercel | 2b |
| Monorepo | Melos workspace (Flutter) + pnpm (web) | 1 |
| Maps (mobile) | Google Maps Flutter plugin | 1 |
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

Google Maps API costs are the wildcard — route builder and map tiles are billed per load. Set billing alerts from day one. Consider switching run display maps to Mapbox (cheaper at scale) while keeping Google Maps for the route builder.

---

## Open risks

- **Apple Watch native Swift** adds a separate codebase. Scope carefully — keep the watch app lean (record + navigate only) and leave analytics on the phone.
- **parkrun scraping** can break without notice. Build it as a best-effort feature with graceful degradation.
- **Garmin Connect** developer program requires business approval. Do not block Phase 3 on this — use HealthKit/Health Connect as the primary Garmin data path for early users.
- **Google Maps API costs** scale with usage. Set billing alerts from day one. Consider switching route display to Mapbox (cheaper at scale) while keeping the Google Maps route builder for the familiarity users expect.
- **Web app scope creep** — the web app is a power tool, not a second mobile app. Resist the urge to replicate every mobile screen. Keep it focused on route building, analytics, and account management.
- **Live tracking battery drain** — Publishing GPS every 3 seconds over WebSocket adds battery cost. Make it opt-in per run, not default. Test drain target: <5% additional per hour.
- **Training plan accuracy** — V1 plans are rule-based (Daniels' formula), which is proven science but not personalised. If user outcome data shows the rules aren't enough, add a Python ML service later — the Go service architecture supports this cleanly.
- **Go service as single point of failure** — The Go service handles WebSockets, background jobs, AND premium features. Keep these as separate goroutine pools so a spike in one doesn't starve the others. Health check each independently.

---

*Last updated: April 2026*
