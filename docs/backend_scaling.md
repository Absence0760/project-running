# Run app — backend scaling plan

How the backend evolves from a single Supabase project to a two-service architecture (Supabase + Go) that supports live spectator tracking, training intelligence, and hundreds of thousands of users.

---

## Current state

The MVP backend is a single Supabase project:

- **Postgres** — runs, routes, integrations, user profiles
- **Auth** — Apple Sign-In, Google Sign-In
- **Storage** — GPX files, data exports, avatars
- **Edge Functions** — Strava sync, parkrun import, token refresh, data export

This is the right choice for Phase 1. It handles CRUD, auth, and storage with zero ops. The issues below become real at scale — they don't need fixing today, but the architecture should anticipate them.

---

## Architectural issues to fix before scaling

### 1. GPS tracks stored as JSONB in the `runs` table

**Problem:** A 10km run at 1 GPS point/second = ~3,600 waypoints = ~180KB of JSONB per row. At 100K users running 3x/week, this adds ~54GB/week of JSONB blobs to the main query table. Every `SELECT` on `runs` pays the cost of scanning past these blobs, even when the track isn't needed.

**Fix:** Move GPS tracks to Supabase Storage as GeoJSON files. Store a reference in the row.

```sql
-- Migration: move track from JSONB to Storage
alter table runs add column track_url text;
-- track_url = 'tracks/{user_id}/{run_id}.geojson'
-- After backfill, drop the track column:
-- alter table runs drop column track;
```

**When:** Before public beta (end of Phase 1).

### 2. No PostGIS for spatial queries

**Problem:** The Phase 3 community route library requires "routes near me" queries. Without PostGIS, this means a full table scan over JSONB waypoints.

**Fix:** Enable PostGIS (built into Supabase), add a geometry column to `routes`, and create a spatial index.

```sql
create extension if not exists postgis;

alter table routes add column geom geography(LineString, 4326);

-- Populate from existing waypoints
update routes set geom = ST_MakeLine(
  array(
    select ST_Point((wp->>'lng')::float, (wp->>'lat')::float)
    from jsonb_array_elements(waypoints) as wp
  )
);

create index routes_geom_idx on routes using gist (geom);

-- Query: routes within 10km of a point
select * from routes
where is_public = true
and ST_DWithin(geom, ST_Point(-0.1278, 51.5074)::geography, 10000);
```

**When:** Before Phase 3 community library launch.

### 3. `personal_records()` function does a full table scan

**Problem:** The function uses `CASE WHEN distance_m BETWEEN x AND y` across all user runs on every call. No index can optimise this.

**Fix:** Create a summary table updated by a trigger on `runs` insert.

```sql
create table personal_records (
  user_id     uuid references auth.users not null,
  distance    text not null,        -- '5k', '10k', 'half', 'marathon'
  best_time_s integer not null,
  achieved_at timestamptz not null,
  run_id      uuid references runs not null,
  primary key (user_id, distance)
);

alter table personal_records enable row level security;
create policy "users own their records"
  on personal_records for all using (auth.uid() = user_id);

-- Trigger function: update PRs on run insert
create or replace function update_personal_records()
returns trigger language plpgsql as $$
declare
  dist_label text;
begin
  dist_label := case
    when NEW.distance_m between 4900 and 5100 then '5k'
    when NEW.distance_m between 9900 and 10100 then '10k'
    when NEW.distance_m between 21000 and 21200 then 'Half marathon'
    when NEW.distance_m between 42100 and 42300 then 'Marathon'
    else null
  end;

  if dist_label is null then return NEW; end if;

  insert into personal_records (user_id, distance, best_time_s, achieved_at, run_id)
  values (NEW.user_id, dist_label, NEW.duration_s, NEW.started_at, NEW.id)
  on conflict (user_id, distance) do update
    set best_time_s = excluded.best_time_s,
        achieved_at = excluded.achieved_at,
        run_id      = excluded.run_id
    where excluded.best_time_s < personal_records.best_time_s;

  return NEW;
end;
$$;

create trigger trg_update_prs
  after insert on runs
  for each row execute function update_personal_records();
```

**When:** Before web dashboard launch (Phase 2b).

### 4. Dashboard aggregations hit raw tables every time

**Problem:** `weekly_mileage()` scans the `runs` table on every dashboard load. Acceptable for hundreds of users, not for thousands.

**Fix:** Materialized view refreshed by `pg_cron`.

```sql
create materialized view mv_weekly_mileage as
  select
    user_id,
    date_trunc('week', started_at)::date as week_start,
    sum(distance_m) as total_distance_m,
    count(*) as run_count,
    sum(duration_s) as total_duration_s
  from runs
  group by user_id, date_trunc('week', started_at)
  order by week_start;

create unique index mv_weekly_mileage_idx on mv_weekly_mileage (user_id, week_start);

-- Refresh every 5 minutes
select cron.schedule('refresh-weekly-mileage', '*/5 * * * *',
  'refresh materialized view concurrently mv_weekly_mileage');
```

**When:** Before web dashboard launch (Phase 2b).

### 5. OAuth tokens stored in plaintext

**Problem:** `access_token` and `refresh_token` in the `integrations` table are plaintext. RLS prevents cross-user access, but a database breach exposes all tokens.

**Fix:** Encrypt with `pgcrypto`.

```sql
create extension if not exists pgcrypto;

-- Encrypt on write
update integrations set
  access_token = pgp_sym_encrypt(access_token, current_setting('app.encryption_key')),
  refresh_token = pgp_sym_encrypt(refresh_token, current_setting('app.encryption_key'));

-- Read via function (decrypts server-side, never exposes raw token to client)
create or replace function get_integration_tokens(p_provider text)
returns table (access_token text, refresh_token text, token_expiry timestamptz)
language sql stable security definer
as $$
  select
    pgp_sym_decrypt(i.access_token::bytea, current_setting('app.encryption_key')),
    pgp_sym_decrypt(i.refresh_token::bytea, current_setting('app.encryption_key')),
    i.token_expiry
  from integrations i
  where i.user_id = auth.uid() and i.provider = p_provider;
$$;
```

**When:** Before Strava integration goes live.

### 6. No rate limiting or webhook validation

**Problem:** Edge Function endpoints are publicly accessible with no rate limiting. Strava webhooks aren't signature-verified.

**Fix:**
- Enable Supabase project-level rate limiting in the dashboard
- Validate Strava webhook signatures in the `strava-webhook` function
- Add per-user rate limiting for import endpoints (max 10 calls/hour)

**When:** Before public beta.

---

## Multi-service architecture

As the product grows beyond Phase 1, Supabase Edge Functions can't handle:

1. **Live spectator tracking** — thousands of concurrent WebSocket connections
2. **Background job processing** — long-running Strava backfills, retries, scheduling
3. **Premium features** — training plans, VO2 max, recovery advice (rule-based math, not ML)

The solution is one additional Go service that sits alongside Supabase — not replaces it.

> **Why not Python?** V1 of every premium feature is rule-based math (Daniels' VDOT tables, Cooper formula, Riegel formula, EWMA calculations). TypeScript or Go handles this fine. If ML model training is needed in the future (personalised plans trained on user outcome data), a Python service can be added at that point. The architecture supports it cleanly — but don't add a second language until you need it.

### Target architecture

```
Clients (mobile, watch, web)
         │
         ▼
    Supabase (unchanged)
    ├── Postgres + PostGIS      ← CRUD, auth, RLS, spatial queries
    ├── Auth                    ← Apple/Google SSO
    ├── Storage                 ← GPS tracks, exports, avatars
    └── Realtime                ← Postgres change notifications
         │
         ▼
    Go service
    ├── WebSocket hub
    │   ├── Runner position publish
    │   └── Spectator subscription
    ├── Background job queue
    │   ├── Strava activity sync
    │   ├── Token refresh worker
    │   └── Data export worker
    ├── Strava webhook handler
    └── Premium feature endpoints
        ├── Training plan generator
        ├── VO2 max estimation
        ├── Race pace predictor
        └── Recovery advisor
         │
         ▼
    ┌───────────────────────┐
    │     Supabase DB       │
    │  (direct connection)  │
    └───────────────────────┘
```

### How clients connect

| Client action | Target | Protocol |
|---|---|---|
| CRUD (runs, routes, profiles) | Supabase PostgREST | HTTPS REST |
| Auth (login, signup) | Supabase Auth | HTTPS REST |
| File upload/download | Supabase Storage | HTTPS REST |
| Live position during run | Go service | WebSocket |
| Watch a friend's run live | Go service | WebSocket |
| Generate training plan | Go service | HTTPS REST |
| Get VO2 max estimate | Go service | HTTPS REST |
| Recovery recommendation | Go service | HTTPS REST |

Clients still talk to Supabase for 90%+ of requests. The Go service handles real-time, background jobs, and premium features.

---

## Go service — real-time and background jobs

### Why Go

- **WebSocket performance:** ~10KB memory per connection vs ~1MB in Node.js. A single $5/month instance can hold 50,000 concurrent connections.
- **Concurrency model:** Goroutines handle thousands of simultaneous operations without callback complexity.
- **Long-running workers:** No cold starts, no function timeouts. A background job can run for minutes.
- **Low operational cost:** Single static binary, minimal memory, fast startup.

### Responsibilities

#### 1. Live spectator tracking (WebSocket hub)

During a run, the runner's phone/watch publishes GPS position to the Go service every 3 seconds. Friends and family connect via a spectator URL and see the runner move in real time.

```
Runner connects:
  ws://go-service/track/{run_id}
  → Authenticates via Supabase JWT
  → Publishes: { lat, lng, pace, distance, elapsed }

Spectator connects:
  ws://go-service/watch/{run_id}
  → No auth required (public link)
  → Receives: position updates every 3 seconds
  → Receives: summary on run complete
```

**Data flow:**
1. Runner publishes position → Go service fans out to all connected spectators
2. Go service writes position to a Redis stream (ephemeral, TTL 24h) for late joiners
3. On run complete, Go service writes final track summary to Postgres

**Scale target:** 1,000 concurrent runners, 10 spectators each = 11,000 WebSocket connections. One Go instance handles this comfortably.

#### 2. Background job queue

Replaces Supabase Edge Functions for operations that need retries, long runtimes, or scheduling.

| Job | Trigger | Timeout | Retry |
|---|---|---|---|
| Strava activity sync | Webhook POST | 5 min | 3x exponential |
| Strava backfill (90 days) | User action | 10 min | 3x exponential |
| Token refresh | Scheduled (every 4h) | 30 sec | 3x |
| parkrun import | User action | 2 min | 2x |
| Data export (GDPR) | User action | 5 min | 2x |

**Queue implementation:** Use a Postgres-backed queue (e.g., River for Go) — no extra infrastructure needed. Jobs are stored in a `jobs` table with status, retry count, and scheduled time. The Go service polls the queue.

```sql
create table jobs (
  id          bigserial primary key,
  kind        text not null,          -- 'strava_sync', 'token_refresh', etc.
  payload     jsonb not null,
  status      text default 'pending', -- 'pending', 'running', 'completed', 'failed'
  attempts    integer default 0,
  max_retries integer default 3,
  run_at      timestamptz default now(),
  completed_at timestamptz,
  error       text,
  created_at  timestamptz default now()
);

create index jobs_pending on jobs (run_at) where status = 'pending';
```

#### 3. Strava webhook handler

Moves from Edge Function to Go service. Validates webhook signatures, enqueues activity sync as a background job.

#### 4. Premium feature endpoints (Phase 3)

Rule-based training intelligence. All algorithms are proven exercise science — no ML needed for V1.

**`POST /training-plan`** — Generate a weekly training plan:
1. Fetch user's last 12 weeks of runs from Postgres
2. Calculate current fitness using Daniels' VDOT tables
3. Determine training phase (base → build → peak → taper)
4. Generate workouts (easy, tempo, interval, long run) with target paces
5. Adjust based on missed sessions and recovery patterns

**`GET /vo2max`** — Estimate aerobic fitness:
1. Filter recent runs with HR data (steady effort, low HR variability)
2. Apply Cooper test formula: `VO2max = (distance_m - 504.9) / 44.73`
3. Cross-reference with pace-at-threshold-HR
4. Return estimate with confidence level and trend

**`GET /race-predictor`** — Predict finish times:
1. Use Riegel formula: `T2 = T1 * (D2/D1)^1.06`
2. Adjust with VO2 max estimate
3. Return predictions for 5k, 10k, half, marathon with confidence levels

**`GET /recovery`** — Training load and recovery advice:
1. Calculate acute training load (ATL) — 7-day EWMA of distance × intensity
2. Calculate chronic training load (CTL) — 42-day EWMA
3. Training stress balance: TSB = CTL - ATL
4. Recommend rest/easy/hard based on TSB threshold

All premium endpoints gated by `subscription_tier = 'premium'` check against Supabase JWT.

### Deployment

- **Platform:** Fly.io or Google Cloud Run
- **Instance size:** 256MB RAM, shared CPU (scales to 1GB under load)
- **Cost:** ~$5/month at low traffic, ~$25/month at 10K DAU
- **Dependencies:** Supabase Postgres (direct connection string), Redis (Upstash, ~$0/month at low volume)

### Tech stack

| Concern | Choice |
|---|---|
| HTTP framework | `net/http` (stdlib) or Chi |
| WebSocket | `nhooyr.io/websocket` |
| Database | `jackc/pgx` (Postgres driver) |
| Job queue | `riverqueue/river` (Postgres-backed) |
| Auth validation | Verify Supabase JWTs using JWKS endpoint |
| Config | Environment variables |
| Logging | `log/slog` (stdlib) |

---

## Future: Python service for ML (not planned yet)

If user outcome data shows that rule-based training plans aren't personalised enough, a Python service can be added to train ML models on user data. This would:

- Train models on which training plans led to user improvement (scikit-learn / PyTorch)
- Generate personalised plans per user segment (beginner, intermediate, advanced)
- Deploy to Cloud Run (scale-to-zero, ~$0/month when idle)
- Read from the same Supabase Postgres database

The Go service architecture supports this cleanly — premium endpoints would call the Python service for model inference while keeping the rule-based fallback. But this is speculative until there's enough user data to justify it (likely 6-12 months post-premium-launch with 10K+ active premium users).

---

## Infrastructure dependencies

### Redis (added in Phase 2)

Used only by the Go service for ephemeral real-time data.

| Use case | Data | TTL |
|---|---|---|
| Live runner positions | Stream of `{lat, lng, pace}` per run | 24 hours |
| Spectator session count | Counter per run ID | Duration of run |
| Rate limiting | Request counters per user | 1 hour |

**Provider:** Upstash (serverless Redis). Free tier covers early usage. ~$10/month at scale.

### No other new infrastructure

The architecture intentionally avoids:
- **Kafka/RabbitMQ** — Postgres-backed job queue is sufficient at this scale
- **Elasticsearch** — PostGIS spatial queries and Postgres full-text search cover route discovery
- **Separate cache layer** — Materialized views handle dashboard caching within Postgres
- **Kubernetes** — Cloud Run/Fly.io handles scaling without cluster management

---

## Migration timeline

Aligned with the existing product roadmap.

### Phase 1 — MVP (current)

**Backend:** Supabase only.

**Fixes to apply now:**
- [ ] Move GPS tracks from JSONB to Storage (`track_url` column)
- [ ] Add rate limiting to Edge Function endpoints
- [ ] Validate Strava webhook signatures
- [ ] Encrypt OAuth tokens with pgcrypto
- [ ] Create `.env.local` template for backend secrets

**No new services.** Edge Functions handle Strava, parkrun, and token refresh. The 150s timeout is fine because backfills are small (new users only).

### Phase 2 — watch parity

**Backend:** Supabase + Go service.

**New:**
- [ ] Deploy Go service to Fly.io
- [ ] WebSocket hub for live spectator tracking
- [ ] Move Strava webhook handler from Edge Function to Go
- [ ] Move token refresh from Edge Function to Go cron worker
- [ ] Move data export from Edge Function to Go background job
- [ ] Set up Upstash Redis for live position streams

**Migrate from Edge Functions:** Strava webhook, token refresh, data export. Only parkrun import remains as an Edge Function (simple, infrequent).

**Database:**
- [ ] Add `personal_records` summary table with trigger
- [ ] Create `mv_weekly_mileage` materialized view with pg_cron refresh
- [ ] Add `jobs` table for Go worker queue

### Phase 2b — web app

**Backend:** No new services.

**Database:**
- [ ] Ensure materialized views are performant for dashboard queries
- [ ] Add full-text search index on `routes.name` for route library search

### Phase 3 — growth and monetisation

**Backend:** Supabase + Go service (premium features added to Go).

**New:**
- [ ] Add premium endpoints to Go service (training plan, VO2 max, race predictor, recovery)
- [ ] Gate premium endpoints by `subscription_tier = 'premium'` in Supabase JWT
- [ ] Connect RevenueCat webhook to update `subscription_tier` in `user_profiles`

**Database:**
- [ ] Enable PostGIS extension
- [ ] Add `geom` column to `routes` with spatial index
- [ ] Add `training_plans` table for generated plans
- [ ] Add `fitness_snapshots` table for VO2 max history

```sql
create table training_plans (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users not null,
  goal        text not null,
  target_date date,
  sessions    jsonb not null,
  week_start  date not null,
  created_at  timestamptz default now()
);

create table fitness_snapshots (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users not null,
  vo2_max     numeric(5, 1),
  atl         numeric(6, 1),       -- acute training load
  ctl         numeric(6, 1),       -- chronic training load
  tsb         numeric(6, 1),       -- training stress balance
  measured_at timestamptz default now()
);
```

---

## Monorepo structure (after all services)

```
run-app/
├── apps/
│   ├── mobile_ios/          # Flutter iOS
│   ├── mobile_android/      # Flutter Android
│   ├── watch_ios/           # Native Swift
│   ├── watch_wear/          # Flutter Wear OS
│   ├── web/                 # SvelteKit
│   └── backend/
│       ├── supabase/        # Postgres schema, Edge Functions
│       └── go-service/      # Go real-time + background jobs + premium
│           ├── cmd/server/
│           ├── internal/
│           │   ├── ws/           # WebSocket hub
│           │   ├── jobs/         # Background job handlers
│           │   ├── strava/       # Strava API client
│           │   ├── premium/      # Training plans, VO2 max, recovery
│           │   └── auth/         # JWT validation
│           ├── go.mod
│           ├── Dockerfile
│           └── fly.toml
├── packages/                # Shared Dart packages
└── docs/
```

---

## Cost projection

| Users | Supabase | Go (Fly.io) | Redis (Upstash) | Total |
|---|---|---|---|---|
| 1K | Free tier | — | — | **$0** |
| 10K | Pro ($25) | $5/month | Free tier | **$30** |
| 50K | Pro ($25) | $15/month | $10/month | **$50** |
| 100K | Pro ($25) + compute add-on ($50) | $25/month | $10/month | **$110** |
| 500K | Team ($599) | $50/month | $25/month | **$674** |

These are rough estimates. Actual costs depend heavily on read/write patterns, GPS track sizes, and live tracking usage.

Map tile costs are minimal — MapTiler has a generous free tier, and Protomaps (self-hosted PMTiles on S3/R2) eliminates tile costs entirely at scale.

---

*Last updated: April 2026*
