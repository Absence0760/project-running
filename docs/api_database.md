# Run app — API and database reference

Complete reference for the Supabase backend: database schema, row-level security policies, Edge Functions, and the REST API surface consumed by all clients.

---

## Database schema

All tables live in the `public` schema. Users are managed by `auth.users` (Supabase Auth) — no custom users table needed.

### `runs`

Every recorded or imported run.

```sql
create table runs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users not null,
  started_at    timestamptz not null,
  duration_s    integer not null,           -- elapsed seconds
  distance_m    numeric(10, 2) not null,    -- metres
  route_id      uuid references routes,     -- linked planned route, if any
  source        text not null,              -- see RunSource enum below
  external_id   text unique,               -- deduplication key
  metadata      jsonb,                     -- source-specific extra fields
  track_url     text,                      -- Storage path: {user_id}/{run_id}.json.gz
  is_public     boolean default false,     -- visible at /share/run/{id}
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- Index for timeline queries
create index runs_user_started_at on runs (user_id, started_at desc);

-- Index for deduplication upserts
create unique index runs_external_id on runs (external_id) where external_id is not null;

-- Index for public share pages
create index runs_public on runs (is_public, started_at desc) where is_public = true;
```

**GPS tracks** are stored as gzipped JSON files in the `runs` Storage bucket at `{user_id}/{run_id}.json.gz`. The `track_url` column points to the file. Tracks are never returned by list queries -- they are fetched on demand when the run detail screen is opened.

**`source` values:**

| Value | Meaning |
|---|---|
| `app` | Recorded live in this app |
| `healthkit` | Imported from Apple HealthKit |
| `healthconnect` | Imported from Android Health Connect |
| `strava` | Synced from Strava API |
| `garmin` | Synced from Garmin Connect API |
| `parkrun` | Scraped from parkrun results page |
| `race` | Scraped from race results site |

**`track` shape:**

```json
[
  { "lat": 51.5074, "lng": -0.1278, "ele": 12.4, "ts": "2025-04-05T08:00:00Z" },
  { "lat": 51.5075, "lng": -0.1279, "ele": 12.6, "ts": "2025-04-05T08:00:05Z" }
]
```

**`metadata` shape (source-dependent):**

```json
// parkrun
{ "event": "Richmond", "position": 42, "age_grade": "54.23%", "run_number": 17 }

// race
{ "race_name": "Richmond Half Marathon", "bib": "1234", "overall_place": 142, "chip_time": "1:47:23" }
```

---

### `routes`

Planned routes — imported from GPX/KML or built in the route builder.

```sql
create table routes (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users not null,
  name            text not null,
  waypoints       jsonb not null,           -- [{lat, lng, ele}, ...]
  distance_m      numeric(10, 2) not null,
  elevation_m     numeric(8, 2),            -- total gain in metres
  surface         text default 'road',      -- 'road' | 'trail' | 'mixed'
  is_public       boolean default false,
  slug            text unique,              -- for shareable URLs
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

create index routes_user_id on routes (user_id, created_at desc);
create index routes_public on routes (is_public, created_at desc) where is_public = true;
```

---

### `integrations`

OAuth tokens and connection state for each external platform per user.

```sql
create table integrations (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users not null,
  provider        text not null,            -- 'strava' | 'garmin' | 'parkrun' | 'runsignup'
  access_token    text,                     -- encrypted at rest by Supabase
  refresh_token   text,
  token_expiry    timestamptz,
  external_id     text,                     -- athlete ID on the provider
  scope           text,                     -- OAuth scopes granted
  last_sync_at    timestamptz,
  sync_cursor     text,                     -- pagination cursor for backfill
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  unique (user_id, provider)
);
```

---

### `route_reviews`

User ratings and comments on public routes. One review per user per route.

```sql
create table route_reviews (
  id          uuid primary key default gen_random_uuid(),
  route_id    uuid references routes not null,
  user_id     uuid references auth.users not null,
  rating      smallint not null check (rating >= 1 and rating <= 5),
  comment     text,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (route_id, user_id)
);

create index route_reviews_route on route_reviews (route_id, created_at desc);
```

---

### `user_profiles`

Supplementary user data not stored in `auth.users`.

```sql
create table user_profiles (
  id                uuid primary key references auth.users,
  display_name      text,
  avatar_url        text,
  parkrun_number    text,                   -- e.g. 'A123456'
  preferred_unit    text default 'km',      -- 'km' | 'mi'
  subscription_tier text default 'free',    -- 'free' | 'premium'
  subscription_at   timestamptz,
  created_at        timestamptz default now()
);
```

---

## Row-level security

RLS is enabled on every table. Policies ensure users can only access their own data, with a specific carve-out for public routes.

```sql
-- runs
alter table runs enable row level security;

create policy "users own their runs"
  on runs for all
  using (auth.uid() = user_id);

create policy "public runs are readable by anyone"
  on runs for select
  using (is_public = true);

-- routes
alter table routes enable row level security;

create policy "users own their routes"
  on routes for all
  using (auth.uid() = user_id);

create policy "public routes are readable by anyone"
  on routes for select
  using (is_public = true);

-- integrations
alter table integrations enable row level security;

create policy "users own their integrations"
  on integrations for all
  using (auth.uid() = user_id);

-- user_profiles
alter table user_profiles enable row level security;

create policy "users own their profile"
  on user_profiles for all
  using (auth.uid() = id);

-- route_reviews
alter table route_reviews enable row level security;

create policy "reviews on public routes are readable by anyone"
  on route_reviews for select
  using (
    exists (select 1 from routes where routes.id = route_reviews.route_id and routes.is_public = true)
  );

create policy "users manage their own reviews"
  on route_reviews for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
```

---

## Edge Functions

All Edge Functions are TypeScript running on the Deno runtime, deployed to Supabase Edge Functions.

Base URL: `https://{project-ref}.supabase.co/functions/v1/`

Authentication: all functions require a valid Supabase JWT in the `Authorization: Bearer {token}` header, except the Strava webhook which uses a shared secret.

---

### `POST /strava-import`

Initiates the Strava OAuth flow and backfills the last 90 days of activities.

**Request:**
```json
{ "code": "abc123", "scope": "activity:read_all" }
```

**Flow:**
1. Exchange `code` for access + refresh tokens via Strava
2. Fetch athlete profile to get Strava athlete ID
3. Store tokens in `integrations` table
4. Register Strava webhook subscription (if not already registered)
5. Backfill: fetch paginated activities from past 90 days
6. For each activity: fetch GPS stream, map to `Run`, upsert

**Response:**
```json
{ "imported": 47, "athlete_id": "12345678" }
```

---

### `POST /strava-webhook`

Receives push events from Strava when a user creates, updates, or deletes an activity. Called by Strava — not by clients.

**Strava verification (GET):**
```
GET /strava-webhook?hub.challenge=abc&hub.verify_token={secret}
→ { "hub.challenge": "abc" }
```

**Activity created (POST):**
```json
{
  "object_type": "activity",
  "object_id": 987654321,
  "aspect_type": "create",
  "owner_id": 12345678,
  "event_time": 1712300000
}
```

**Flow:**
1. Verify `hub.verify_token` matches env secret
2. Look up user by Strava athlete ID
3. Fetch activity detail + GPS stream from Strava
4. Upsert as `Run` with `external_id = strava:{activity_id}`

---

### `POST /parkrun-import`

Fetches and imports a user's full parkrun history.

**Request:**
```json
{ "athleteNumber": "A123456" }
```

**Flow:**
1. Validate athlete number format (`A` followed by digits)
2. Fetch `parkrun.org.uk/results/athleteresultshistory/?athleteNumber={n}`
3. Parse HTML results table with Cheerio
4. Map rows to `Run` objects with `source = 'parkrun'`
5. Upsert with deduplication on `external_id`

**Response:**
```json
{ "imported": 23, "skipped": 0 }
```

---

### `POST /refresh-tokens`

Scheduled function (cron: every 4 hours) that refreshes Strava access tokens before they expire.

**Flow:**
1. Query `integrations` where `provider = 'strava'` and `token_expiry < now() + interval '1 hour'`
2. For each: POST to Strava `/oauth/token` with refresh token
3. Update `integrations` with new access token and expiry

No request body — triggered by Supabase cron, not by clients.

---

### `POST /export-data`

Exports all of a user's runs as a GPX zip or CSV. GDPR data portability.

**Request:**
```json
{ "format": "gpx" }   // or "csv"
```

**Response:**
A signed Supabase Storage URL pointing to the generated file, valid for 10 minutes.

---

## REST API (Supabase auto-generated)

Supabase generates a full REST API from the database schema automatically. Clients use the `supabase-js` (web) or `supabase-dart` (Flutter) clients which call these endpoints.

Base URL: `https://{project-ref}.supabase.co/rest/v1/`

All requests require:
- `apikey: {publishable_key}` header
- `Authorization: Bearer {user_jwt}` header

### Runs

```
GET    /runs                              # list user's runs (paginated)
GET    /runs?id=eq.{id}                  # single run
POST   /runs                             # create run
PATCH  /runs?id=eq.{id}                  # update run
DELETE /runs?id=eq.{id}                  # delete run
```

**Common query patterns:**

```typescript
// Last 20 runs, newest first
const { data } = await supabase
  .from('runs')
  .select('*')
  .order('started_at', { ascending: false })
  .limit(20);

// Runs in date range
const { data } = await supabase
  .from('runs')
  .select('id, started_at, distance_m, duration_s')
  .gte('started_at', startDate.toISOString())
  .lte('started_at', endDate.toISOString());

// Weekly mileage aggregate
const { data } = await supabase.rpc('weekly_mileage', {
  weeks_back: 12,
});
```

### Routes

```
GET    /routes                           # list user's routes + public routes
GET    /routes?id=eq.{id}               # single route
GET    /routes?is_public=eq.true        # public route library
POST   /routes                          # create route
PATCH  /routes?id=eq.{id}              # update route
DELETE /routes?id=eq.{id}              # delete route
```

### User profiles

```
GET    /user_profiles?id=eq.{user_id}   # fetch profile
PATCH  /user_profiles?id=eq.{user_id}   # update profile
```

---

## Database functions (RPCs)

Custom Postgres functions exposed via `supabase.rpc()`.

### `weekly_mileage(weeks_back integer)`

Returns total distance per week for the chart on the dashboard.

```sql
create or replace function weekly_mileage(weeks_back integer default 12)
returns table (week_start date, total_distance_m numeric)
language sql stable
as $$
  select
    date_trunc('week', started_at)::date as week_start,
    sum(distance_m) as total_distance_m
  from runs
  where
    user_id = auth.uid()
    and started_at >= now() - (weeks_back || ' weeks')::interval
  group by 1
  order by 1;
$$;
```

### `personal_records()`

Returns the user's best time for each standard distance.

```sql
create or replace function personal_records()
returns table (distance text, best_time_s integer, achieved_at timestamptz)
language sql stable
as $$
  select
    case
      when distance_m between 4900 and 5100 then '5k'
      when distance_m between 9900 and 10100 then '10k'
      when distance_m between 21000 and 21200 then 'Half marathon'
      when distance_m between 42100 and 42300 then 'Marathon'
    end as distance,
    min(duration_s) as best_time_s,
    (array_agg(started_at order by duration_s))[1] as achieved_at
  from runs
  where
    user_id = auth.uid()
    and source in ('app', 'strava', 'garmin', 'healthkit', 'healthconnect')
  group by 1
  having count(*) > 0;
$$;
```

---

## Supabase Storage

Used for GPX file storage and data exports.

### Buckets

| Bucket | Access | Purpose |
|---|---|---|
| `runs` | Private (RLS) | Gzipped GPS tracks (`{user_id}/{run_id}.json.gz`). Public read via RLS when `runs.is_public = true`. |
| `routes` | Private (RLS) | Uploaded GPX/KML files |
| `exports` | Private (signed URLs) | User data export files |
| `avatars` | Public | User profile photos |

### File naming

```
routes/{user_id}/{route_id}.gpx
exports/{user_id}/{timestamp}.zip
avatars/{user_id}/avatar.jpg
```

### Uploading a route file (Flutter)

```dart
final bytes = File(gpxFilePath).readAsBytesSync();
await supabase.storage
    .from('routes')
    .uploadBinary(
      '${userId}/${routeId}.gpx',
      bytes,
      fileOptions: const FileOptions(contentType: 'application/gpx+xml'),
    );
```

---

## Auth

Supabase Auth handles all user management. No custom auth code needed.

### Providers enabled

- Apple Sign-In (required for iOS App Store apps that offer social login)
- Google Sign-In

### Flutter auth flow

```dart
// Sign in with Apple
await supabase.auth.signInWithApple();

// Sign in with Google
await supabase.auth.signInWithOAuth(
  OAuthProvider.google,
  redirectTo: 'io.runapp://auth/callback',
);

// Listen to auth state changes
supabase.auth.onAuthStateChange.listen((data) {
  final session = data.session;
  // Redirect to home or login based on session
});
```

### SvelteKit auth (web)

```typescript
// apps/web/src/lib/supabase-server.ts
import { createServerClient } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import type { Cookies } from '@sveltejs/kit';

export function createClient(cookies: Cookies) {
  return createServerClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
    cookies: {
      getAll: () => cookies.getAll(),
      setAll: (cookiesToSet) => {
        cookiesToSet.forEach(({ name, value, options }) => {
          cookies.set(name, value, { ...options, path: '/' });
        });
      },
    },
  });
}
```

---

## Migrations

Database migrations are managed with the Supabase CLI.

```bash
# Create a new migration
supabase migration new {description}
# → creates supabase/migrations/{timestamp}_{description}.sql

# Apply locally
supabase db reset

# Push to production
supabase db push --project-ref {ref}

# Check status
supabase migration list --project-ref {ref}
```

### Migration naming convention

```
20250405_001_initial_schema.sql
20250410_002_add_metadata_to_runs.sql
20250415_003_add_routes_slug.sql
20250420_004_weekly_mileage_function.sql
```

---

*Last updated: April 2026*
