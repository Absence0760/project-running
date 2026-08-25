# Run app — backend scaling plan

How the backend evolves from a single Supabase project to a two-service architecture (Supabase + Go) that supports live spectator tracking, training intelligence, and hundreds of thousands of users.

> **Status as of August 2026:** the two-service architecture below is partly live. The Go worker (`apps/job_worker/`) is deployed on Fly.io and drains **fourteen** job kinds — `map_match`, `token_refresh`, `strava_event`, `photo_process`, `route_photo_process`, `club_photo_process`, `notification_email`, `lifecycle_email`, `safety_email`, `safety_sms`, `web_push`, `native_push`, `weekly_digest`, `lifecycle_drip` (`internal/worker.go:359`, and that `switch` is the authoritative list) — and serves the `POST /v1/export` and `POST /v1/premium/*` endpoints. One caveat on `map_match`: `OSRM_URL` is deliberately unset in `fly.toml`, so `main.go:287` selects `PassthroughMatcher` and the job completes as a no-op — runs ship, just without the snapped line, until the sibling `osrm` app deploys. The live-spectator WebSocket hub (`apps/job_worker/internal/livehub/`) **is deployed and serving** — the worker went out 2026-07-21 and `live.threkir.com` is a live CNAME in Terraform (`infra/dns/main.tf`). What remains is the **client** cutover, not infra: `PUBLIC_LIVE_HUB_URL` / `LIVE_HUB_URL` are still unset, so recorders and spectators ride Supabase Realtime. Three Edge Functions (`refresh-tokens`, `strava-webhook`, `export-data`) have been superseded by the worker but are kept deployed as the rollback path. The narrative below predates these landings and describes the design intent — treat every SQL snippet as plan-of-record, not current state. Each of the six numbered sections now carries a **Shipped** note recording what actually landed and where it diverged from the sketch, and every box in the migration timeline is ticked with the migration or file that closed it. **Two boxes are still open**, both under Phase 2 and both `[~]`: the WebSocket-hub row, waiting on the client cutover alone, and the Upstash Redis row, whose code shipped but whose provider was never provisioned (`REDIS_URL` unset). A prior pass ticked the Redis row on the strength of the code existing; the box asks for infrastructure, and that half is not done.

---

## Starting point (Phase 1 MVP)

The plan below starts from the Phase 1 backend: a single Supabase project. (For where things stand *now* — the Go worker is live and several pieces below have shipped — see the status banner above.)

- **Postgres** — runs, routes, integrations, user profiles
- **Auth** — Apple Sign-In, Google Sign-In
- **Storage** — GPX files, data exports, avatars
- **Edge Functions** — Strava sync, parkrun import, token refresh, data export

This was the right choice for Phase 1: it handles CRUD, auth, and storage with zero ops. The issues below become real at scale — they didn't need fixing on day one, but the architecture anticipated them, and the Go worker + job queue (May 2026) and the live hub (deployed 2026-07-21) are this plan made real.

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

**Shipped** in `20260410_001_runs_to_storage.sql`, which drops `runs.track`
outright (`alter table runs drop column track`, line 15 — the repo had no
production data to backfill) and adds `track_url text`. One difference from the
sketch above: the stored object is gzipped JSON at `{user_id}/{run_id}.json.gz`
in a `runs` bucket, not `tracks/{user_id}/{run_id}.geojson` — see the
`runs.track` note in the root [`CLAUDE.md`](../../CLAUDE.md). The same migration
adds the four owner-scoped Storage RLS policies.

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

**Shipped, in two halves — and the `geom` column above is one of them.**
`20260415_001_postgis_nearby_routes.sql` enables PostGIS and adds
`routes.start_point geography(Point, 4326)` + `routes_start_point_gist` + a
`nearby_routes(lat, lng, radius_m)` RPC + a trigger that populates the point
from the first waypoint. That answers "routes *starting* near me", not "routes
that *pass* near me", so `20260607_001_routes_geom_linestring.sql` then added
the exact column this section proposed —
`routes.geom geography(LineString, 4326)` + `routes_geom_gist`, populated from
`waypoints` by an `ST_MakeLine` trigger — with `20260608_001` /
`20260610_001` / `20270509_001` layering the box, track-intersection, and
public-read paths on top of it. **This corrects an earlier correction:** the
Phase 3 checkbox below used to read that PostGIS "shipped it as `start_point`
…, not the `geom` name this line proposed", which was true of `20260415_001`
alone and stopped being true two months later. Both columns exist; they answer
different questions.

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

**Shipped** in `20260508_001_personal_records_cache.sql`: the
`personal_records` table, a `personal_records_distance_time` index, and three
triggers rather than the one sketched here — `runs_personal_records_insert`,
`_update` and `_delete`. The extra two are the point: an insert-only trigger
leaves a PR standing after the run that set it is edited or deleted, which is
the cache-versus-authoritative-query contract now written down in
[`derived_state.md`](derived_state.md).

### 4. Dashboard aggregations hit raw tables every time

**Problem:** `weekly_mileage()` scans the `runs` table on every dashboard load. Acceptable for hundreds of users, not for thousands.

**Fix (proposed, since reversed — do not copy this; see the Status note under
the snippet):** Materialized view refreshed by `pg_cron`.

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

-- Refresh every 15 minutes
select cron.schedule('refresh-weekly-mileage', '*/15 * * * *',
  'refresh materialized view concurrently mv_weekly_mileage');

-- IMPORTANT: matviews can't have RLS in PostgreSQL. Supabase's default
-- grants on the public schema cover them, so leaving the matview
-- world-readable would publish every user's mileage history to anon.
-- Always pair the matview with a revoke + a wrapped function that
-- gates by auth.uid(). See migration 20260517_001_revoke_mv_weekly_mileage.
revoke select on mv_weekly_mileage from anon, authenticated;
```

**Status: tried, and reversed — the matview above no longer exists.** It was
created in `20260407_001_performance.sql`, revoked from public read in
`20260517_001_revoke_mv_weekly_mileage.sql` after the data-isolation audit,
refreshed by pg_cron from `20260602_001` (retuned to 15 min in `20260706_001`)
— and **dropped in `20270530_001`**, having never acquired a reader across the
422 migrations of its life. See [decisions.md § 690](../architecture/decisions.md).

The premise of this section did not survive contact either. `weekly_mileage()`
does scan `runs`, but nothing calls it, and the dashboard's weekly chart
windows `runs` to 14 weeks off `runs_user_started_at` and buckets in
TypeScript — a per-user index range scan over tens of rows, not the growing
table scan this section assumed. And the matview shape above could not have
served that surface: `date_trunc('week', ...)` is ISO Monday-start (the
dashboard honours a Sunday-start `week_start_day` preference) and buckets a
`timestamptz` at the *session* timezone's midnight rather than the runner's
local one. Pre-aggregating this correctly means keying per user timezone and
per week-start preference. Do that only once a read path is actually hot;
provisioning it ahead of need is what produced 422 migrations' worth of
background compute for zero reads.

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

**Shipped — but not with the `pgcrypto` above, and the difference matters.**
`20260603_001_integrations_vault.sql` moves both tokens into **Supabase Vault**
(libsodium, platform-managed key), replacing the two plaintext columns with
`access_token_secret_id` / `refresh_token_secret_id` FKs into `vault.secrets`
and then `drop column`-ing the originals (lines 56–57). The
`get_integration_tokens` reader below did land, near-verbatim, as a
`SECURITY DEFINER` function over `vault.decrypted_secrets`. What did *not* land
is the `current_setting('app.encryption_key')` half: a passphrase read from a
GUC lives in `postgresql.conf`, gets logged by `log_statement`, and is visible
to anything that can `show` it — so the key never sits where a breach of this
same database would find it. Do not copy the snippet above.

### 6. No rate limiting or webhook validation

**Problem:** Edge Function endpoints are publicly accessible with no rate limiting. Strava webhooks aren't signature-verified.

**Fix:**
- Enable Supabase project-level rate limiting in the dashboard
- Validate Strava webhook signatures in the `strava-webhook` function
- Add per-user rate limiting for import endpoints (max 10 calls/hour)

**When:** Before public beta.

**Shipped, and the middle bullet was wrong when it was written.** Per-user
rate limiting is `20260604_001_rate_limits.sql` (a `SECURITY DEFINER`
`check_rate_limit` doing an atomic fixed-window increment) behind
`functions/_shared/rate_limit.ts`, whose posture is per-caller: fail-open by
default so a transient DB blip doesn't 429 everyone, `{ failClosed: true }` on
the destructive and expensive paths (`delete-account`, `export-data`, OAuth
code exchange). The Strava bullet asked for **signature** verification, which
Strava cannot satisfy — it does not sign webhook payloads. `strava-webhook`
therefore authenticates the caller with a constant-time shared-secret compare
(`timingSafeEqual`, header `X-Webhook-Secret` winning over the `?secret=`
query fallback) and refuses every POST outright when
`STRAVA_WEBHOOK_SECRET` is unset. `revenuecat-webhook` *is* HMAC-verified
(`x-revenuecat-hmac`, constant-time compare, plus replay protection), because
RevenueCat does sign.

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

**The last box is plan, not build.** The worker holds no Postgres connection: it reaches Supabase over
PostgREST with the service-role key, exactly as the clients above it do, just without RLS
(`internal/supabase.go:131`). See the Tech stack table below.

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

As built and deployed (`live.threkir.com`, since 2026-07-21; see `apps/job_worker/internal/livehub/`):

```
Runner (recorder) publishes:
  POST /v1/live/{run_id}/push           (HTTPS; recorder's ~5s broadcaster tick)
  → Authenticates via Supabase JWT — owner-only
  → Body: { lat, lng, pace, distance, elapsed }

Spectator subscribes:
  wss://live.threkir.com/v1/live/{run_id}/subscribe
  → Anon for is_public runs; owner-only (JWT) for private runs
  → On join: last-known snapshot, then position updates as they arrive
  GET /v1/live/{run_id}/snapshot         (late-joiner one-shot, 204 when empty)
```

**Data flow (as built — the three bullets this replaced described a design that did not ship):**
1. Runner publishes position → Go service fans out to all connected spectators, in-process
2. Each accepted push is also written to `live_run_pings` by a detached service-role insert
   (`internal/livehub/server.go:17`, 15 s timeout, best-effort and never surfaced to the recorder).
   That is the hub→Supabase-Realtime bridge of [decisions § 282](../architecture/decisions.md), and it —
   not Redis — is what a late joiner and the legacy Realtime spectator path read today
3. Nothing writes a "final track summary" on run completion. The client owns the finished run: it uploads
   the gzipped track to Storage and writes the `runs` row itself

The Redis tier is written but unprovisioned (`REDIS_URL` unset). When it lands it is **not** a stream:
`internal/livehub/redis_hub.go:21` defines a per-run pub/sub channel `live:{runID}:ch` plus a single
last-known key `live:{runID}:last` that `EXPIRE`s after 24 h. The channel is fan-out across replicas;
the key is the restart-survivable snapshot.

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

**Queue implementation:** a Postgres-backed queue — no extra infrastructure needed. Jobs are stored in a `jobs` table with status, retry count, and scheduled time. The Go service polls the queue.

**Shipped without River.** The `e.g., River for Go` this line used to recommend was never taken up: `apps/job_worker/go.mod` has no `riverqueue/river`, and the queue is a hand-rolled claim-and-dispatch loop (`internal/worker.go:359`) over the `jobs` table `20260609_001` created. The table below is the Phase-2 sketch, not the built set — parkrun import in particular never moved and is still the `parkrun-import` Edge Function. The authoritative list of what the worker actually drains is the `switch` at `internal/worker.go:359`, enumerated in the status banner at the top of this file.

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

**Shipped, with different verbs, paths and a different gate.** All four are **POSTs** under
`/v1/premium/` — `vo2max`, `race-predictor`, `recovery`, `training-plan` (`internal/premium/server.go:91`)
— not the mixed `GET`/`POST` top-level routes sketched above. And the tier is **not** read off the JWT: a
claim in a token issued before an expiry or a refund would still say `premium`, so `main.go:169` resolves
`subscription_tier` server-side against `user_profiles` on every call. The whole surface is fail-closed at
boot — with no token verification configured (`SUPABASE_JWT_SECRET` or `SUPABASE_URL` for JWKS), `main.go:691`
logs `premium: DISABLED` and every endpoint answers 503 rather than running unauthenticated.

### Deployment

- **Platform:** Fly.io — shipped as app `threkir-worker` in `ord` (`fly.toml:16`)
- **Instance size:** 256MB RAM, shared CPU (`fly.toml:117`), scales to 1GB under load
- **Cost:** ~$5/month at low traffic, ~$25/month at 10K DAU
- **Dependencies:** Supabase, **over PostgREST — there is no direct Postgres connection.** Every read and
  write goes through `/rest/v1/…` with the service-role key (`internal/supabase.go:131`,
  `internal/schema/schema.go:23`), which is why `go.mod` carries no Postgres driver. Redis (Upstash) is a
  dependency of the *design*, not of the running binary: `REDIS_URL` is unset, so nothing is provisioned

### Tech stack

Three rows of this table were plan-of-record that the build did not take. The **Built** column is the
whole of `apps/job_worker/go.mod` plus the stdlib.

| Concern | Planned | Built |
|---|---|---|
| HTTP framework | `net/http` (stdlib) or Chi | `net/http` — no router dependency |
| WebSocket | `nhooyr.io/websocket` | `github.com/coder/websocket` v1.8.15 (`go.mod:11`) — the same library under its current module path |
| Database | `jackc/pgx` (Postgres driver) | **none.** PostgREST over HTTPS with the service-role key (`internal/supabase.go:131`) |
| Job queue | `riverqueue/river` (Postgres-backed) | **none.** A hand-rolled claim-and-dispatch loop over the `jobs` table (`internal/worker.go:359`) |
| Auth validation | Verify Supabase JWTs using JWKS endpoint | as planned — `github.com/golang-jwt/jwt/v5`, JWKS from `SUPABASE_URL` (HS256 secret still accepted for legacy projects) |
| Config | Environment variables | as planned |
| Logging | `log/slog` (stdlib) | as planned |

The three remaining direct dependencies are `github.com/redis/go-redis/v9` (compiled in for the unprovisioned
`RedisHub`), `golang.org/x/image` (photo EXIF scrub / resize), and `github.com/alicebob/miniredis/v2` (tests).

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

**Not provisioned.** `REDIS_URL` is unset, so none of the three rows above exists in production. The live
hub runs its in-process map, and rate limiting was built in Postgres instead (`20260604_001_rate_limits.sql`
behind `functions/_shared/rate_limit.ts`) — a Redis counter was never needed for it. Before this can be
switched on, the Upstash DPA has to be executed and dated in
[`sub-processors.md`](../compliance/sub-processors.md): live pings carry GPS coordinates, so a hosted Redis
is a cross-border processor transfer, not just a cache.

### No other new infrastructure

The architecture intentionally avoids:
- **Kafka/RabbitMQ** — Postgres-backed job queue is sufficient at this scale
- **Elasticsearch** — PostGIS spatial queries and Postgres full-text search cover route discovery
- **Separate cache layer** — still avoided, but no longer for this reason. The materialized view this line pointed at was dropped in `20270530_001` after 422 migrations without a reader; the dashboard windows `runs` to 14 weeks off `runs_user_started_at` and buckets in TypeScript. There is no matview caching layer, and none is needed. See § 4 above and [decisions.md § 690](../architecture/decisions.md)
- **Kubernetes** — Cloud Run/Fly.io handles scaling without cluster management

---

## Migration timeline

Aligned with the existing product roadmap.

### Phase 1 — MVP (complete)

**Backend:** Supabase only.

**Fixes to apply now** — all five landed; "now" here means Phase 1, not today:
- [x] Move GPS tracks from JSONB to Storage (`track_url` column) — `20260410_001_runs_to_storage.sql`
- [x] Add rate limiting to Edge Function endpoints — `functions/_shared/rate_limit.ts`
- [x] Validate Strava webhook callers — `functions/strava-webhook/`. Strava does not sign payloads, so this landed as a constant-time shared-secret check rather than a signature check
- [x] Encrypt OAuth tokens — `20260603_001_integrations_vault.sql`. Done with Supabase Vault (libsodium, platform-managed key) rather than the pgcrypto this line asked for
- [x] Create an env template for backend secrets — `apps/backend/.env.example`

**No new services.** Edge Functions handle Strava, parkrun, and token refresh. The 150s timeout is fine because backfills are small (new users only).

### Phase 2 — watch parity

**Backend:** Supabase + Go service.

**New:**
- [x] Deploy Go service to Fly.io — app `threkir-worker` (`apps/job_worker/fly.toml:16`). It drains fourteen job kinds today, not the three this line named; the `switch` at `internal/worker.go:359` is the list
- [~] WebSocket hub for live spectator tracking (`apps/job_worker/internal/livehub/`). Code shipped + tested, **deployed 2026-07-21**, `live.threkir.com` CNAME live in `infra/dns/main.tf`. Still `[~]` for the client cutover alone — `PUBLIC_LIVE_HUB_URL` / `LIVE_HUB_URL` unset, so nothing connects to it yet
- [x] Move Strava webhook handler from Edge Function to Go (`apps/job_worker/internal/stravahook/`; EF kept as rollback)
- [x] Move token refresh from Edge Function to Go cron worker (`token_refresh` job kind; EF kept as rollback)
- [x] Move data export from Edge Function to Go background job (`POST /v1/export` via `apps/job_worker/internal/dataexport/`; EF kept as rollback)
- [~] Set up Upstash Redis for live position streams — **code only; no Redis is provisioned.** `internal/livehub/redis_hub.go` implements the multi-replica backend and `main.go:497` selects it, but `REDIS_URL` is unset, so the deployed hub logs `backend=in-process (single-replica)` (`main.go:510`) and `internal/livehub/bridge.go:40` says so outright. The earlier "activates on hub deploy" was falsified by the 2026-07-21 deploy itself: the hub went out and Redis did not come with it. Two things gate it — `apps/job_worker/deployment.md:9` keeps the app at `--ha=false` until `REDIS_URL` lands (the in-process hub shares no state, so a second machine silently breaks fan-out), and live pings are GPS coordinates, so pointing `REDIS_URL` at hosted Upstash is a cross-border processor transfer whose DPA is an explicit pre-cutover item in [`sub-processors.md`](../compliance/sub-processors.md)

**Migrate from Edge Functions:** Strava webhook, token refresh, data export. All three moved, and all three are still deployed as the rollback path.

The "only parkrun import remains" this line used to carry was never true and is now wrong by an order of magnitude: **sixteen** Edge Functions ship today (`auth-email`, `clip-public-track`, `delete-account`, `donations-checkout`, `events-cancel`, `events-checkout`, `events-connect-onboard`, `export-data`, `parkrun-import`, `race-listings-sync`, `race-results-import`, `refresh-tokens`, `revenuecat-webhook`, `strava-import`, `strava-webhook`, `stripe-events-webhook`). Migrating three jobs to Go did not make Edge Functions a residue — everything webhook-shaped, Stripe-shaped, or auth-shaped since has landed as one, because a function that must answer a third party's HTTP callback wants Supabase's JWT + service-role context far more than it wants the worker's queue.

**Database:**
- [x] Add `personal_records` summary table with trigger (`20260508_001`)
- [x] ~~Create `mv_weekly_mileage` materialized view~~ **created `20260407_001`, dropped `20270530_001`.** Refreshed by pg_cron from `20260602_001` (retuned to 15 min in `20260706_001`), revoked from public read in `20260517_001`, and never read by any client or RPC — so it was pure refresh cost for its whole life. The choice this line left open (wire a `SECURITY DEFINER` wrapper, or drop) was resolved in favour of dropping: see [decisions.md § 690](../architecture/decisions.md) for the evidence, including why a wrapper over *this* view's Monday-start / session-timezone bucketing could not have served the dashboard
- [x] Add `jobs` table for Go worker queue (`20260609_001_run_match_pipeline.sql`)

### Phase 2b — web app

**Backend:** No new services.

**Database:**
- [x] Ensure materialized views are performant for dashboard queries — **closed by `20270530_001`, vacuously and deliberately: there are now no materialized views.** The only one the repo ever had had no read path, so there was never a dashboard query to grade; the prior question this line was blocked on (wire a reader, or drop) was answered by dropping. Nothing about dashboard performance regressed, because nothing read it. If a matview returns, this box reopens against whatever read path justified it — [decisions.md § 690](../architecture/decisions.md) records the shape such a view would have to have
- [x] Index `routes.name` for route library search — `20270316_001_search_trgm_indexes.sql`, as a **trigram** GIN index (`routes_name_trgm`, `gin_trgm_ops`), not the full-text index this line originally asked for. `search_public_routes` matches with `ILIKE '%term%'`, which a `to_tsvector` index cannot serve; the same migration therefore **drops** `routes_name_search`, the real FTS index `20260407_001` had added, because nothing ever queried it with `@@ tsquery` and it cost every `routes` write while reading as "already indexed"

### Phase 3 — growth and monetisation

**Backend:** Supabase + Go service (premium features added to Go).

**New:**
- [x] Add premium endpoints to Go service (training plan, VO2 max, race predictor, recovery) — `internal/premium/`, mounted in `main.go`
- [x] Gate premium endpoints by subscription tier — `main.go` `premiumBackend.FetchUserSubscriptionTier`. Resolved server-side against `user_profiles` rather than read off the JWT, so a stale token cannot buy access
- [x] Connect RevenueCat webhook to update `subscription_tier` in `user_profiles` — `functions/revenuecat-webhook/` (HMAC-verified)

**Database:**
- [x] Enable PostGIS extension — `20260415_001_postgis_nearby_routes.sql`
- [x] Add a geography column to `routes` with a spatial index — **two** of them, and one is the `geom` this line proposed. `20260415_001_postgis_nearby_routes.sql` shipped `start_point geography(Point, 4326)` + `routes_start_point_gist` (answering "routes *starting* near me"), then `20260607_001_routes_geom_linestring.sql` shipped `geom geography(LineString, 4326)` + `routes_geom_gist`, trigger-populated from `waypoints` by `ST_MakeLine` exactly as § 2 sketched. An earlier pass through this checklist recorded that the `geom` name did *not* ship, which was true of `20260415_001` alone and had already stopped being true; see § 2 above
- [x] Add `training_plans` table — `20260419_001_training_plans.sql` for generated plans
- [x] Add `fitness_snapshots` table — `20260507_001_fitness_snapshots.sql` for VO2 max history

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

## Monorepo structure (as built)

The Go service shipped as a **top-level `apps/job_worker/`**, not nested under `apps/backend/`. The single binary serves both background jobs and the HTTP/WS endpoints (live hub, data export, premium, Strava webhook). Authoritative layout is the cheat-sheet in the root [`CLAUDE.md`](../../CLAUDE.md); the backend-relevant slice:

```
run-app/
├── apps/
│   ├── mobile_android/      # Flutter (Android) — canonical mobile target
│   ├── mobile_ios/          # Flutter (iOS) — lib/ + test/ byte-identical to mobile_android
│   ├── watch_wear/          # Native Kotlin + Compose-for-Wear (Wear OS)
│   ├── watch_ios/           # Native SwiftUI (watchOS)
│   ├── custom_watch/        # Rust + Embassy firmware (ultra-watch research)
│   ├── web/                 # SvelteKit 2 + Svelte 5
│   ├── backend/
│   │   └── supabase/        # Postgres schema, migrations, Edge Functions, seed.sql
│   └── job_worker/          # Go service — background jobs + real-time + premium HTTP
│       ├── main.go
│       ├── internal/
│       │   ├── livehub/         # live spectator WS hub (+ Redis backend, privacy clip, JWT auth)
│       │   ├── stravahook/      # Strava webhook ingest endpoint
│       │   ├── dataexport/      # POST /v1/export (CSV / GPX-zip)
│       │   ├── premium/         # Pro-only VO2max / race-predictor / recovery / plan endpoints
│       │   ├── bouncehook/      # inbound bounce / complaint webhook
│       │   ├── unsubscribe/     # RFC 8058 one-click opt-out endpoints
│       │   ├── webpush/ nativepush/  # push transports
│       │   ├── digesttoken/ supajwt/ supakey/ schema/  # tokens, JWT verify, keys, PostgREST table names
│       │   ├── exif/            # photo EXIF scrub
│       │   ├── matcher*.go      # map-match (OSRM when OSRM_URL is set; passthrough otherwise)
│       │   ├── worker.go        # claim + dispatch loop; its `switch` is the job-kind list
│       │   └── handler_*.go     # one per job kind — fourteen kinds today, not the four the worker shipped with
│       ├── go.mod
│       ├── Dockerfile
│       ├── fly.toml
│       └── osrm/                # OSRM sidecar config
├── packages/                # Shared Dart: core_models, api_client, run_recorder, gpx_parser, ui_kit
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

*Last updated: August 2026*
