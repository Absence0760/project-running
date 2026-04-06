# Run app — architecture

---

## Overview

A cross-platform running app targeting iOS, Android, Apple Watch, Wear OS, and a full desktop web app. Built on a Flutter monorepo for mobile and a Next.js web app, sharing a single Supabase backend and Google Maps for route planning and navigation.

The architecture is designed around three principles:

- **Offline first** — runs record and save locally; sync happens in the background
- **Platform parity** — watch apps are standalone GPS computers, not thin companions
- **Open data** — import and export via standard formats (GPX, FIT, TCX) and official APIs

The web app and mobile apps are separate codebases — different languages, different UI frameworks — but share exactly the same Supabase backend, database schema, and REST API. No duplication of business logic.

---

## Repository structure

```
run-app/                          # Monorepo root
├── apps/
│   ├── mobile_ios/               # Flutter iOS app target
│   ├── mobile_android/           # Flutter Android app target
│   ├── watch_ios/                # Native Swift + WatchKit (Xcode project)
│   ├── watch_wear/               # Flutter Wear OS target
│   ├── web/                      # Next.js 14 web app (TypeScript)
│   │   ├── app/                  # App Router pages
│   │   │   ├── routes/           # Route builder + library
│   │   │   ├── runs/             # Run history + detail
│   │   │   ├── dashboard/        # Stats and analytics
│   │   │   └── settings/         # Integrations + account
│   │   ├── components/           # React components
│   │   ├── lib/                  # Supabase client, API helpers
│   │   └── package.json
│   └── backend/                  # Supabase Edge Functions (Node.js / TypeScript)
├── packages/
│   ├── core_models/              # Shared Dart: Run, Route, Waypoint types
│   ├── gpx_parser/               # GPX, KML, KMZ, GeoJSON parsing
│   ├── run_recorder/             # GPS tracking, pace, distance logic
│   ├── api_client/               # REST client + auth token management
│   └── ui_kit/                   # Shared Flutter widgets + design tokens
├── tooling/
│   ├── melos.yaml                # Flutter workspace config + scripts
│   ├── package.json              # npm workspace root (web app)
│   ├── .github/workflows/        # CI/CD pipelines
│   └── analysis_options.yaml    # Shared Dart lint rules
└── README.md
```

> Note: the `packages/` layer is Flutter/Dart only. The web app (`apps/web/`) is a standalone Next.js project — it shares the Supabase backend but has no code dependency on the Dart packages.

### Melos workspace config

```yaml
# melos.yaml
name: run-app
packages:
  - apps/**
  - packages/**
command:
  bootstrap:
    usePubspecOverrides: true
scripts:
  test:       melos exec -- flutter test
  analyze:    melos exec -- flutter analyze
  build:ios:  melos exec --scope="mobile_ios" -- flutter build ipa
  build:android: melos exec --scope="mobile_android" -- flutter build appbundle
```

---

## Layer diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Client layer                                                            │
│                                                                          │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌─────────┐ ┌─────────────┐ │
│  │ iOS app   │ │Android app│ │Apple Watch│ │ Wear OS │ │  Web app    │ │
│  │ Flutter   │ │  Flutter  │ │Swift+WKit │ │ Flutter │ │  Next.js   │ │
│  └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └────┬────┘ └──────┬──────┘ │
│        │             │       WatchConnectivity    │             │        │
└────────┼─────────────┼─────────────┼─────────────┼─────────────┼────────┘
         │             │             │             │             │
┌────────▼─────────────▼─────────────▼─────────────▼─────────────┘
│  Shared Dart layer  (packages/)  ~80% mobile code reuse         │
│  core_models │ gpx_parser │ run_recorder │ api_client │ ui_kit   │
└──────────────────────────────────┬──────────────────────────────┘
                                   │ HTTPS / REST  (all clients)
┌──────────────────────────────────▼──────────────────────────────┐
│  Backend  (Supabase)                                            │
│  Postgres DB │ Auth (Apple/Google SSO) │ Storage │ Edge Fns    │
└──────────────────────────────────┬──────────────────────────────┘
                                   │ OAuth / webhooks
┌──────────────────────────────────▼──────────────────────────────┐
│  External integrations                                          │
│  Google Maps API │ Strava API │ Garmin Connect │ HealthKit      │
│  Health Connect  │ parkrun    │ RunSignUp      │ Elevation API  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Client apps

### Flutter phone apps (iOS + Android)

Both phone targets share ~80% of their code via the shared `packages/` layer. Platform-specific code is isolated to platform channels and plugin configuration.

**Key responsibilities:**
- Route planning and GPX/KML import
- Live GPS run recording with map overlay
- Post-run analysis (elevation, pace splits, HR zones)
- Sync management (HealthKit, Health Connect, Strava)
- Auth flow and account management

**Platform-specific code:**
- iOS: `MapKit` for turn-by-turn, `HealthKit` permissions, `Watch Connectivity`
- Android: `Health Connect` permissions, `Wear Data Layer` API

### Apple Watch app (native Swift)

A standalone Xcode project living at `apps/watch_ios/`. Separate from Flutter — managed directly in Xcode, deployed via the iOS app target.

**Why native Swift:** Apple does not allow third-party frameworks (including Flutter) to run on watchOS. Swift + SwiftUI + WatchKit is the only supported path.

**Key responsibilities:**
- Standalone GPS workout recording (phone-independent)
- Live pace, HR, and distance display on watch face
- Route navigation with mini-map and off-route haptic alerts
- Sync recorded runs to iPhone via `WCSession` on reconnect

**Architecture pattern:**
```
WatchKit Extension
├── WorkoutManager.swift       # HealthKit workout session
├── LocationManager.swift      # GPS tracking
├── RouteNavigator.swift       # Off-route detection
└── WatchConnectivity.swift    # Sync with iPhone
```

### Wear OS app (Flutter)

Flutter runs natively on Wear OS. Uses `compose_for_wear` plugin for watch-appropriate UI components (rounded layouts, rotary input, swipe-to-dismiss).

**Key responsibilities:**
- Standalone GPS workout recording
- Live metrics display (Tiles API for glanceable data)
- Route navigation synced from phone via Data Layer
- Sync to phone via `wear` Flutter plugin

### Web app (Next.js)

A standalone Next.js 14 app at `apps/web/`, deployed to Vercel. It is intentionally not a full-featured clone of the mobile app — its purpose is the things that are genuinely better on a large screen.

**Stack:** Next.js 14 App Router · TypeScript · Tailwind CSS · Supabase JS client · Google Maps JS API · Recharts

**Key responsibilities:**
- Full-screen route builder (the best route planning experience in the product)
- Deep run analytics dashboard — charts, splits, personal records
- Account and integrations management (Strava, Garmin, parkrun)
- Public shareable pages for routes and runs (SEO-indexed)

**Auth:** Supabase Auth with `@supabase/ssr` — server-side session management via cookies. No separate auth system — same user accounts as mobile.

**Page structure:**

```
app/
├── (auth)/
│   └── login/                  # Google + Apple sign-in
├── dashboard/                  # Weekly mileage, heatmap, records
├── routes/
│   ├── page.tsx                # Route library list
│   ├── new/page.tsx            # Full-screen Google Maps route builder
│   └── [id]/page.tsx           # Route detail (public or private)
├── runs/
│   ├── page.tsx                # Run history with filters
│   └── [id]/page.tsx           # Run detail — map + full analysis
└── settings/
    ├── integrations/page.tsx   # Connect Strava, Garmin, parkrun
    └── account/page.tsx        # Profile, subscription, data export
```

**Route builder (web-specific):**

The web route builder uses the Google Maps JavaScript API directly — more capable than the Flutter plugin. Users click to place waypoints, drag to reshape, toggle road/trail snapping, and get a live elevation profile as they draw. Routes save to Supabase and appear instantly on mobile.

```typescript
// apps/web/components/RouteBuilder.tsx
const map = new google.maps.Map(ref.current, { ... });
const directionsService = new google.maps.DirectionsService();
const poly = new google.maps.Polyline({ map, path: [] });

// On each waypoint click → request directions segment → append to polyline
// Export final polyline → encode as GPX → upload to Supabase Storage
```

---

## Shared packages

### `core_models`

Dart data classes shared across all Flutter apps. No business logic — pure data types with JSON serialisation.

```dart
class Run {
  final String id;
  final DateTime startedAt;
  final Duration duration;
  final double distanceMetres;
  final List<Waypoint> track;   // GPS trace
  final String? routeId;        // linked planned route, if any
  final RunSource source;       // recorded, strava, garmin, parkrun...
}

class Route {
  final String id;
  final String name;
  final List<Waypoint> waypoints;
  final double distanceMetres;
  final double elevationGainMetres;
}

class Waypoint {
  final double lat;
  final double lng;
  final double? elevationMetres;
  final DateTime? timestamp;
}
```

### `gpx_parser`

Parses GPX, KML, KMZ, and GeoJSON into `Route` objects. No external network calls — pure file parsing.

```dart
class RouteParser {
  static Route fromGpx(String xmlString) { ... }
  static Route fromKml(String xmlString) { ... }
  static Route fromGeoJson(Map<String, dynamic> json) { ... }
}
```

### `run_recorder`

Manages a live GPS recording session. Streams position updates, calculates pace, detects off-route deviation, handles auto-pause.

```dart
class RunRecorder {
  Stream<RunSnapshot> get snapshots;   // emits every GPS update
  Future<void> start({Route? route});  // begin recording
  Future<Run> stop();                  // finalise and return completed Run
}
```

### `api_client`

Typed HTTP client for the Supabase REST API. Handles token refresh, retry logic, and offline queuing.

```dart
class ApiClient {
  Future<void> saveRun(Run run);
  Future<List<Run>> getRuns({int limit = 20, DateTime? before});
  Future<void> saveRoute(Route route);
  Future<List<Route>> getRoutes();
}
```

### `ui_kit`

Shared Flutter widgets used by both phone apps. Ensures visual consistency across platforms.

- `RunMap` — Google Maps widget with route overlay and live position
- `StatCard` — metric display card (distance, pace, HR)
- `RunListTile` — run history row
- `ElevationChart` — post-run elevation + pace chart
- `ImportSheet` — bottom sheet for GPX/KML file selection

---

## Backend

Hosted on **Supabase** (Postgres + Auth + Storage + Edge Functions). Single project serves both iOS and Android.

### Database schema (key tables)

```sql
-- Users managed by Supabase Auth
create table runs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users not null,
  started_at  timestamptz not null,
  duration_s  integer not null,
  distance_m  numeric not null,
  track       jsonb,           -- array of {lat, lng, ele, ts}
  route_id    uuid references routes,
  source      text not null,   -- 'recorded' | 'strava' | 'garmin' | 'parkrun'
  external_id text,            -- source platform's ID for deduplication
  created_at  timestamptz default now()
);

create table routes (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users not null,
  name          text not null,
  waypoints     jsonb not null,
  distance_m    numeric not null,
  elevation_m   numeric,
  is_public     boolean default false,
  created_at    timestamptz default now()
);

create table integrations (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users not null,
  provider      text not null,  -- 'strava' | 'garmin' | 'parkrun'
  access_token  text,
  refresh_token text,
  token_expiry  timestamptz,
  external_id   text,           -- athlete ID on the provider
  created_at    timestamptz default now(),
  unique (user_id, provider)
);
```

### Row-level security

All tables have RLS enabled. Users can only read and write their own data.

```sql
alter table runs enable row level security;
create policy "users own their runs"
  on runs for all using (auth.uid() = user_id);
```

### Edge Functions

Thin TypeScript functions deployed to Supabase Edge Functions (Deno runtime).

| Function | Trigger | Purpose |
|---|---|---|
| `strava-webhook` | POST (Strava push) | Receive activity created/updated event, fetch full activity, save run |
| `strava-import` | POST (user action) | OAuth token exchange, backfill last 90 days of activities |
| `parkrun-import` | POST (user action) | Fetch athlete results page by athlete number, parse HTML, save runs |
| `refresh-tokens` | Scheduled (cron) | Refresh expiring Strava access tokens before they expire |

---

## External integrations

### Strava (official OAuth 2.0)

```
User taps "Connect Strava"
  → App opens Strava OAuth URL
  → User authorises
  → Strava redirects with auth code
  → Edge Function exchanges code for tokens
  → Tokens stored in integrations table
  → Strava webhook registered
  → Future activities push automatically
```

**Key endpoints used:**
- `GET /athlete/activities` — backfill historical runs
- `GET /activities/{id}/streams` — fetch GPS trace
- `POST /push_subscriptions` — register webhook

### Apple HealthKit (iOS SDK, on-device)

No server involved. Flutter `health` package reads workouts directly from HealthKit on the device.

```dart
final health = HealthFactory();
await health.requestAuthorization([HealthDataType.WORKOUT]);
final workouts = await health.getHealthDataFromTypes(
  startTime: DateTime.now().subtract(Duration(days: 365)),
  endTime: DateTime.now(),
  types: [HealthDataType.WORKOUT],
);
// Filter activityType == HKWorkoutActivityType.running
// Map to Run objects and save via ApiClient
```

### Android Health Connect (Android SDK, on-device)

Same `health` package — single Dart API abstracts both platforms.

```dart
// Identical call on Android — package handles the platform difference
final workouts = await health.getHealthDataFromTypes(...);
```

### parkrun (scrape by athlete number)

```
User enters athlete number (e.g. A123456)
  → Edge Function fetches parkrun.org.uk/results/athleteresultshistory/?athleteNumber=A123456
  → Parse HTML results table (BeautifulSoup / Cheerio)
  → Extract: event, date, time, position, age grade
  → Save as Run objects with source='parkrun'
  → Deduplicate by external_id = parkrun event + date
```

### Garmin Connect (official developer program)

Requires business approval from Garmin. Integrate in Phase 3.

- Apply at `developer.garmin.com/gc-developer-program`
- OAuth 2.0 flow identical to Strava
- Push webhooks deliver `.FIT` files on device sync
- Until approved: HealthKit/Health Connect captures Garmin data via the Garmin Connect mobile app

---

## Data flow: recording a run

```
1. User taps Start (phone or watch)
2. RunRecorder begins GPS location stream
3. Each position update → RunSnapshot emitted
4. UI updates pace, distance, map position in real time
5. If route loaded → RouteNavigator checks deviation
6. Off-route (>50m) → haptic alert
7. User taps Stop
8. RunRecorder.stop() → returns completed Run
9. Run saved to local SQLite (drift package)
10. ApiClient.saveRun() → POST to Supabase (background)
11. If watch recording → WCSession transfers data to phone
12. Phone merges watch run into local store
```

## Data flow: importing a GPX route

```
1. User shares KML from Google Maps → app receives file
2. RouteParser.fromKml() → Route object
3. Route displayed on map (distance, elevation summary)
4. User taps Save → ApiClient.saveRoute()
5. Route appears in library, available to start a run against
```

---

## Tech stack

| Concern | Technology | Notes |
|---|---|---|
| iOS + Android UI | Flutter 3.x + Dart | Single codebase, ~80% shared |
| Apple Watch | Swift 5 + SwiftUI + WatchKit | Separate Xcode project in monorepo |
| Wear OS | Flutter + `wear` plugin | Compose for Wear via platform channel |
| Web app | Next.js 14 + TypeScript | App Router, deployed to Vercel |
| Web maps | Google Maps JavaScript API | Route builder, run replay |
| Web charts | Recharts | Elevation, pace, HR zone visualisations |
| Web auth | Supabase Auth + `@supabase/ssr` | SSR-safe cookie sessions |
| Monorepo tooling | Melos (Flutter) + npm workspaces (web) | Separate toolchains, same repo |
| Maps (mobile) | Google Maps Flutter plugin | Route display, live position |
| GPS parsing | `gpx` + custom KML parser | Dart (mobile), `togeojson` (web) |
| Health sync | `health` pub.dev package | Abstracts HealthKit + Health Connect |
| Local storage | `drift` (SQLite) | Offline-first run storage on mobile |
| Backend | Supabase | Postgres + Auth + Storage + Edge Functions |
| Auth | Supabase Auth | Apple Sign-In + Google Sign-In |
| CI/CD | GitHub Actions | Per-app matrix jobs |
| Lint | `flutter_lints` + ESLint | Per-platform lint config |

---

## CI/CD pipeline

```yaml
# .github/workflows/ci.yml
jobs:
  test-packages:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: dart pub global activate melos
      - run: melos bootstrap
      - run: melos run test
      - run: melos run analyze

  build-ios:
    runs-on: macos-latest
    steps:
      - run: flutter build ipa --no-codesign

  build-android:
    runs-on: ubuntu-latest
    steps:
      - run: flutter build appbundle

  build-watch-swift:
    runs-on: macos-latest
    steps:
      - run: |
          xcodebuild -scheme WatchApp \
            -destination 'platform=watchOS Simulator,name=Apple Watch Series 9' \
            build

  build-web:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm ci --workspace=apps/web
      - run: npm run lint --workspace=apps/web
      - run: npm run build --workspace=apps/web
      # Vercel deployment handled automatically on push to main
```

Web app deploys to Vercel via the Vercel GitHub integration — no manual deploy step needed. Preview deployments are created automatically for every pull request.

---

## Security considerations

- **Row-level security** enforced on all Supabase tables — no user can access another user's data even if they have a valid JWT
- **Strava tokens** stored server-side in the `integrations` table, never sent to the client
- **parkrun athlete numbers** are public — no passwords stored
- **GPS data** stored as JSONB blobs in Postgres, encrypted at rest by Supabase
- **Apple Sign-In** on iOS 13+ — no email/password surface to attack
- **Web app sessions** managed server-side via `@supabase/ssr` — auth cookies are httpOnly and not accessible to JavaScript
- **Public route/run pages** use Supabase `is_public` flag — RLS policies enforce that only explicitly shared records are readable without auth
- **Environment secrets** (`SUPABASE_URL`, `STRAVA_CLIENT_SECRET`, `MAPS_API_KEY`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`) stored in GitHub Actions secrets and Vercel environment variables — never committed to the repo

---

*Last updated: April 2026*
