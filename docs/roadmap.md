# Run app — product roadmap

---

## Vision

A cross-platform running app that covers every device and surface a runner might use — iPhone, Android phone, Apple Watch, Wear OS, and a full desktop web app — with seamless Google Maps route planning and free access to the features every other app puts behind a paywall.

---

## Strategic pillars

1. **Google Maps first** — plan routes in the tool runners already know, import in one tap
2. **Watch parity** — Apple Watch and Wear OS treated as first-class platforms, not companions
3. **Free core** — route building, GPX import, and run history stay permanently free
4. **Open ecosystem** — sync with Strava, HealthKit, Health Connect, parkrun, and race results
5. **Web as a power tool** — the web app is where you plan, analyse, and manage; the phone and watch are where you run

---

## Phase 1 — MVP: prove the core loop

**Target:** ~8 weeks
**Goal:** A working, testable app that covers plan → run → review

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

### Milestone: internal TestFlight / Play Store internal track release

---

## Phase 2 — watch parity: wrist-first experience

**Target:** ~6 weeks after Phase 1
**Goal:** Both watch platforms feel like first-class running computers, not companion screens

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

### Milestone: App Store + Play Store public beta

---

## Phase 2b — web app: plan big, review deep

**Target:** ~5 weeks (runs in parallel with or immediately after Phase 2)
**Goal:** A SvelteKit web app at `app.runapp.com` that handles everything better done on a big screen

The web app is built with SvelteKit and shares zero UI code with Flutter, but calls the exact same Supabase REST API. No new backend work needed — it's purely a new client.

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

### Milestone: web app live at `app.runapp.com`

---

## Phase 3 — growth and monetisation

**Target:** ~8 weeks after Phase 2
**Goal:** Build the features that drive acquisition, retention, and revenue

### Features

#### In-app route builder (free)
Draw routes directly on Google Maps inside the app — no export/import step. Strava paywalls this. Yours is free. Primary acquisition driver.

- Click-to-place waypoints on Google Maps
- Auto-snap to roads or trail mode
- Elevation preview before running
- Save to route library + shareable link

#### Elevation and pace analysis (post-run)
Elevation profile, per-kilometre splits, heart rate zones, and comparison against previous runs on the same route. The data layer that keeps runners coming back daily.

- Interactive elevation chart with pace overlay
- Split table (pace, HR, elevation per km/mile)
- Best effort tracking on named segments
- Compare against personal best on same route

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
AI-generated weekly training plans, VO2 max estimates, recovery time suggestions, and race pace calculators. The paywall sits on top of coaching intelligence — the core app remains free.

- Adaptive training plan (5k, 10k, half, full marathon)
- Weekly mileage targets with recovery flagging
- VO2 max estimate from HR + pace data
- Race day pace calculator

#### Community route library
Public browseable library of user-shared routes, sortable by location, distance, and surface type. Creates network effects and organic SEO discovery.

- Public / private toggle per route
- Route ratings and comments
- "Popular near me" discovery feed
- Share to social (image card with map + stats)

### Milestone: App Store + Play Store general availability

---

## Competitive positioning

| Feature | Your app | Strava | Nike Run Club | Garmin Connect | AllTrails |
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

---

## Tech stack summary

| Layer | Technology |
|---|---|
| iOS + Android app | Flutter + Dart |
| Apple Watch | Native Swift + SwiftUI + WatchKit |
| Wear OS watch | Flutter + Compose for Wear |
| Web app | SvelteKit 2 + Svelte 5 + TypeScript |
| Web maps | Google Maps JavaScript API |
| Web deployment | Vercel |
| Monorepo | Melos workspace (Flutter) + npm workspaces (web) |
| Maps (mobile) | Google Maps Flutter plugin |
| GPX/KML parsing | Dart `gpx` package + `togeojson` (web) |
| Health sync | `health` pub.dev package (HealthKit + Health Connect) |
| Backend | Supabase (Postgres + Auth + Storage + Edge Functions) |
| CI/CD | GitHub Actions |

---

## Open risks

- **Apple Watch native Swift** adds a separate codebase. Scope carefully — keep the watch app lean (record + navigate only) and leave analytics on the phone.
- **parkrun scraping** can break without notice. Build it as a best-effort feature with graceful degradation.
- **Garmin Connect** developer program requires business approval. Do not block Phase 3 on this — use HealthKit/Health Connect as the primary Garmin data path for early users.
- **Google Maps API costs** scale with usage. Set billing alerts from day one. Consider switching route display to Mapbox (cheaper at scale) while keeping the Google Maps route builder for the familiarity users expect.
- **Web app scope creep** — the web app is a power tool, not a second mobile app. Resist the urge to replicate every mobile screen. Keep it focused on route building, analytics, and account management.

---

*Last updated: April 2026*
