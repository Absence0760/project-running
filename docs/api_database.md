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
| `app` | Recorded live on the phone |
| `watch` | Recorded live on a paired watch (Wear OS or Apple Watch) |
| `healthkit` | Imported from Apple HealthKit |
| `healthconnect` | Imported from Android Health Connect |
| `strava` | Synced from Strava API |
| `garmin` | Synced from Garmin Connect API |
| `parkrun` | Scraped from parkrun results page |
| `race` | Scraped from race results site |

**`track` shape:**

```json
[
  { "lat": 51.5074, "lng": -0.1278, "ele": 12.4, "ts": "2025-04-05T08:00:00Z", "bpm": 142 },
  { "lat": 51.5075, "lng": -0.1279, "ele": 12.6, "ts": "2025-04-05T08:00:05Z", "bpm": 145 }
]
```

`lat` / `lng` are required; `ele`, `ts`, and `bpm` are optional per-point fields.
`bpm` carries per-sample heart rate (integer, 30–230) when the recorder captured
HR alongside GPS — used by the run-detail zone-distribution card. Most historical
runs only carry scalar `metadata.avg_bpm`; consumers should gracefully fall back
when `bpm` is absent.

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
  user_id         uuid references auth.users not null,  -- uploader (audit trail)
  club_id         uuid references clubs(id) on delete cascade,  -- nullable; set = club-owned
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
create index routes_club_id on routes (club_id, created_at desc) where club_id is not null;
```

**`start_point`** is a PostGIS `geography(Point, 4326)` column storing the route's starting coordinates. It is auto-populated by a `BEFORE INSERT OR UPDATE` trigger from `waypoints->0->>'lat'/'lng'`. A GiST spatial index powers the `nearby_routes` RPC for proximity search.

**`club_id`** makes a route club-owned: any club admin can edit it, any member can read it regardless of `is_public`. Two RLS policies layer on top of the existing user-owned + public-readable policies — `"club members read club routes"` (SELECT where `club_id is not null and is_club_member(club_id)`) and `"club admins write club routes"` (ALL where `club_id is not null and is_club_admin(club_id)`). See `docs/decisions.md § 30` and `docs/clubs.md § Club-owned routes`.

---

### `saved_routes`

Bookmarks. RouteExplorer's bookmark icon inserts a reference here rather than cloning the row, so the canonical route accumulates `run_count` instead of fragmenting across duplicates.

```sql
create table saved_routes (
  user_id  uuid references auth.users(id) on delete cascade not null,
  route_id uuid references routes(id) on delete cascade not null,
  saved_at timestamptz not null default now(),
  primary key (user_id, route_id)
);

create index saved_routes_user_id on saved_routes (user_id, saved_at desc);
create index saved_routes_route_id on saved_routes (route_id);
```

RLS: `"users manage their own saves"` (`for all using auth.uid() = user_id`). The underlying route is gated independently by routes RLS, so a saved row whose route is later deprived of a public flag will simply stop being readable.

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

### `run_kudos` / `run_comments`

Engagement on runs (decisions §32). Visibility tracks the parent run's RLS via an EXISTS subquery, so engagement on a private run is invisible to anyone but the owner.

```sql
create table run_kudos (
  user_id   uuid references auth.users(id) on delete cascade not null,
  run_id    uuid references runs(id) on delete cascade not null,
  given_at  timestamptz not null default now(),
  primary key (user_id, run_id)
);

create table run_comments (
  id                 uuid primary key default gen_random_uuid(),
  run_id             uuid references runs(id) on delete cascade not null,
  author_id          uuid references auth.users(id) on delete cascade not null,
  parent_comment_id  uuid references run_comments(id) on delete cascade,
  body               text not null check (length(body) between 1 and 2000),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
```

Threading is one level deep, enforced by the INSERT policy: `parent_comment_id is null OR (the parent's parent_comment_id is null)`. The depth check delegates to the SECURITY DEFINER helper `_run_comment_parent_is_top_level(uuid)` because PostgreSQL's RLS planner flags any policy that selects from its own table as recursive — even when the runtime path is acyclic — and would otherwise return `infinite recursion detected in policy for relation "run_comments"` on every authenticated INSERT (fixed in `20260529_001`). Run owner can DELETE any comment on their run for moderation; otherwise authors edit / delete their own. The `run_comments_set_updated_at` BEFORE-UPDATE trigger keeps `updated_at` honest so consumers can tell edited comments apart.

### `run_photos`

Photos attached to a run (decisions §36). Metadata in Postgres, bytes in the public-read `run-photos` Storage bucket at `{owner_id}/{photo_id}.{ext}`. Visibility tracks the parent run via EXISTS — same shape as `run_kudos` / `run_comments`.

```sql
create table run_photos (
  id            uuid primary key default gen_random_uuid(),
  run_id        uuid references runs(id) on delete cascade not null,
  owner_id      uuid references auth.users(id) on delete cascade not null,
  storage_path  text not null,            -- {owner_id}/{photo_id}.{ext}
  caption       text check (caption is null or length(caption) <= 280),
  position_idx  smallint not null default 0,
  created_at    timestamptz not null default now()
);
```

In v1 `owner_id` is enforced to equal `runs.user_id` at INSERT time; the column is kept distinct so a future club-photo feature can opt in via a migration without restructuring. Run owner OR photo owner can DELETE (moderation primitive matching the run-comments shape). Storage policies allow public-read on the bucket and per-user-folder INSERT/DELETE. Known gaps: no server-side thumbnail generation and no EXIF stripping.

### `notifications`

Inbox rows for the social loop (decisions §38). Materialised by `after insert` SECURITY DEFINER triggers on `run_kudos`, `run_comments`, and `user_follows` so the notification lands in the same transaction as the source write.

```sql
create table notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  actor_id    uuid references auth.users(id) on delete set null,
  kind        text not null check (kind in ('kudos','comment','comment_reply','follow')),
  run_id      uuid references runs(id) on delete cascade,
  comment_id  uuid references run_comments(id) on delete cascade,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
```

Two indexes: `(user_id, created_at desc)` for the list view, and a **partial** `(user_id, created_at desc) where read_at is null` so the bell-badge count query is O(unread). Source FKs use `on delete cascade` so notifications die with their parent (deleted run, deleted comment), keeping the inbox honest without a cleanup job.

RLS: users SELECT / UPDATE (mark read) / DELETE their own rows. INSERT is closed to regular users — only the SECURITY DEFINER trigger functions write rows. The triggers also defensively skip self-actions (`actor = recipient`) even though the source-table CHECKs already block them.

### `segments` / `segment_efforts`

Segments + leaderboards (decisions §37). v1 segments are slices of a *saved route* — `(route_id, start_distance_m, end_distance_m)` — not arbitrary geometry. Visibility on both tables tracks the parent route via EXISTS.

```sql
create table segments (
  id                uuid primary key default gen_random_uuid(),
  route_id          uuid references routes(id) on delete cascade not null,
  name              text not null check (length(name) between 1 and 120),
  start_distance_m  numeric not null check (start_distance_m >= 0),
  end_distance_m    numeric not null,
  length_m          numeric generated always as (end_distance_m - start_distance_m) stored,
  created_by        uuid references auth.users(id) on delete set null,
  created_at        timestamptz not null default now(),
  check (end_distance_m > start_distance_m),
  check (end_distance_m - start_distance_m >= 100)
);

create table segment_efforts (
  id            uuid primary key default gen_random_uuid(),
  segment_id    uuid references segments(id) on delete cascade not null,
  run_id        uuid references runs(id) on delete cascade not null,
  user_id       uuid references auth.users(id) on delete cascade not null,
  time_seconds  numeric not null check (time_seconds > 0),
  started_at    timestamptz not null,
  created_at    timestamptz not null default now(),
  unique (segment_id, run_id)
);
```

Anyone who can read the parent route can create a segment (Strava-style community contribution); `created_by` is enforced as `auth.uid()`. Effort visibility = segment AND run readability so private runs don't surface on a public segment's leaderboard. **Auto-effort generation is client-side**: there's no trigger because `pg_net` isn't wired and downloading from Postgres is gross. The browser walks the run track via `lib/segments.ts#computeEffortFromTrack` (haversine cumulative distance + timestamp interpolation) on the run-detail page, then INSERTs new efforts via the regular RLS-gated path. The unique constraint makes this idempotent.

---

### `user_profiles`

Supplementary user data not stored in `auth.users`. As of `20260521_001_user_follows.sql` profiles are world-readable to authenticated users (the new `"profiles are readable by anyone authenticated"` policy is additive to the existing self-only `"users own their profile"`). This is required for follow / feed / club-member rendering and was a latent bug fix — pre-migration, all cross-user enrichment queries silently returned empty rows. See `docs/decisions.md § 31` for the trade-off.

```sql
create table user_profiles (
  id                uuid primary key references auth.users,
  display_name      text,
  avatar_url        text,
  parkrun_number    text,                   -- e.g. 'A123456' (world-readable)
  preferred_unit    text default 'km',      -- 'km' | 'mi'
  subscription_tier text default 'free',    -- 'free' | 'premium' (world-readable)
  subscription_at   timestamptz,
  created_at        timestamptz default now()
);
```

### `clone_plan_template(template_id uuid, new_start_date date)`

SECURITY DEFINER RPC for plan-template adoption (decisions §35). Verifies the caller can SELECT the template (own plan or club member of the template's `club_id`), then duplicates `training_plans` + `plan_weeks` + `plan_workouts` into a new user-owned plan anchored at `new_start_date`. All workout `scheduled_date` values are shifted by the date offset between the template's `start_date` and the new start date. The new plan's `parent_template_id` points back at the template; `is_template = false` and `status = 'active'`. Returns the new plan's id. Granted to `authenticated`.

### `clip_track_for_user(target_user_id uuid, points jsonb)`

SECURITY DEFINER RPC for privacy-zone clipping (decisions §33). Reads `user_settings.prefs.privacy_zones` for the target user, walks the input points dropping in-zone leading + trailing entries, and returns the contiguous middle as jsonb. Zones never leave the database. Granted to `anon` + `authenticated` so anonymous `/share/run/[id]` and `/share/route/[id]` viewers also receive clipped output. Input is capped at 50 000 points (raise on overflow) to bound the residual dense-grid probe attack. Returns input unchanged when the target user has no zones configured. Helpers `privacy_distance_m(lat1, lng1, lat2, lng2)` and `privacy_in_any_zone(lat, lng, zones_json)` are exposed in the same migration but used only internally by the RPC.

### `user_follows`

Asymmetric follow graph. One row per `(follower, followee)` pair; CHECK blocks self-follow; cascading deletes on both sides. RLS: anyone authenticated can SELECT (graph is public); only the follower can INSERT or DELETE their own row. See `decisions.md § 31`.

```sql
create table user_follows (
  follower_id  uuid references auth.users(id) on delete cascade not null,
  followee_id  uuid references auth.users(id) on delete cascade not null,
  followed_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  constraint user_follows_no_self_follow check (follower_id <> followee_id)
);
```

Indexes: `(follower_id, followed_at desc)` for "people I follow," `(followee_id, followed_at desc)` for "my followers." The activity feed query (`fetchFollowingFeed`) resolves the followee set first, then queries `runs` filtered by `user_id IN (...)` and `is_public = true`.

### `clubs` / `club_members` / `events` / `event_attendees` / `club_posts`

The social layer. See `docs/clubs.md` for surfaces and `docs/roadmap.md § Clubs and events` for phasing. Added in `20260416_001_clubs_and_events.sql`.

```sql
create table clubs (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid references auth.users not null,
  name          text not null,
  slug          text unique not null,                 -- URL-safe, generated from name
  description   text,
  avatar_url    text,
  location_label text,                                -- freeform "Austin, TX" — no geo yet
  is_public     boolean default true,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

create table club_members (
  club_id     uuid references clubs on delete cascade not null,
  user_id     uuid references auth.users on delete cascade not null,
  role        text not null default 'member',         -- 'owner' | 'admin' | 'member'
  joined_at   timestamptz default now(),
  primary key (club_id, user_id)
);

-- One-off events. Recurrence is Phase 2 (see roadmap).
create table events (
  id              uuid primary key default gen_random_uuid(),
  club_id         uuid references clubs on delete cascade not null,
  title           text not null,
  description     text,
  starts_at       timestamptz not null,
  duration_min    integer,
  meet_lat        double precision,
  meet_lng        double precision,
  meet_label      text,
  route_id        uuid references routes on delete set null,
  distance_m      numeric(10, 2),
  pace_target_sec integer,                            -- seconds per km
  capacity        integer,
  created_by      uuid references auth.users not null,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

create table event_attendees (
  event_id   uuid references events on delete cascade not null,
  user_id    uuid references auth.users on delete cascade not null,
  status     text not null default 'going',            -- 'going' | 'maybe' | 'declined'
  joined_at  timestamptz default now(),
  primary key (event_id, user_id)
);

-- Owner/admin broadcast updates. event_id is optional — posts can be
-- pinned to a specific event (shows on the event page) or general (shows on
-- the club feed only).
create table club_posts (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid references clubs on delete cascade not null,
  event_id    uuid references events on delete cascade,
  author_id   uuid references auth.users not null,
  body        text not null,
  created_at  timestamptz default now()
);
```

**Helper functions** (RLS readability): `is_club_member(club_id)` and `is_club_admin(club_id)` — `security definer` functions that encapsulate the `club_members` lookup so every policy below can read cleanly. A trigger auto-enrolls the owner as an `owner`-role member on club insert, so the helpers work uniformly for owners too.

**Narrow unions** (client-side, no DB CHECK): `ClubRole = 'owner' | 'admin' | 'member'`, `RsvpStatus = 'going' | 'maybe' | 'declined'`. See `apps/web/src/lib/types.ts`.

---

### `user_coach_usage`

Daily usage tracking for the AI Coach. One row per user per day, incremented by the coach endpoint on every message. The daily limit prevents runaway API costs.

```sql
create table user_coach_usage (
  user_id     uuid not null references auth.users(id) on delete cascade,
  usage_date  date not null default current_date,
  message_count integer not null default 0,
  primary key (user_id, usage_date)
);
```

**RPCs:**

- `increment_coach_usage(p_user_id uuid) → integer` — upserts today's row and returns the new count. `security definer` so the coach endpoint can call it in one round trip. Guarded: `auth.uid() != p_user_id` raises `not authorized`, so a malicious caller can't exhaust another user's quota.
- `get_coach_usage(p_user_id uuid) → integer` — read-only; returns today's count without incrementing. Used by `CoachChat.svelte` to show "N of M remaining" before the user types. Same `auth.uid()` guard as `increment_coach_usage`.

---

### `coach_messages`

Per-account chat history for the AI Coach. One row per message authored by either the runner (`role = 'user'`) or the LLM (`role = 'assistant'`), scoped to a `(user_id, plan_id)` thread. `plan_id` is nullable so the "no active plan" thread is distinguishable from per-plan threads. Replaces an earlier localStorage-only persistence that didn't survive a sign-in on a different device.

```sql
create table coach_messages (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  plan_id      uuid references training_plans(id) on delete set null,
  role         text not null check (role in ('user', 'assistant')),
  content      text not null,
  reaction     text check (reaction in ('up', 'down')),
  archived_at  timestamptz,
  created_at   timestamptz not null default now()
);
```

**Active vs archived:** `archived_at` is null for messages in the live thread; "Start new conversation" updates every active row in a `(user, plan)` to the same `now()` timestamp, grouping them as one historical conversation. All rows sharing an `archived_at` value within a `(user, plan)` form one archive — the History panel queries `select distinct archived_at where archived_at is not null`, lists each, and lets the user view (read-only) or delete an archive. Per-archive delete is `delete where archived_at = $T` (RLS-scoped).

**Reactions:** `reaction` is set by the runner via inline thumbs-up / thumbs-down on assistant bubbles. Per-message, owner-only — there's no multi-user voting model, just a personal save-this / not-useful signal.

Index `coach_messages_user_plan_archive_created_idx` on `(user_id, plan_id, archived_at, created_at)` covers the three hot read shapes without a sort step:
1. Active thread: `where user_id = X and plan_id = Y and archived_at is null order by created_at`
2. Per-archive thread: `where user_id = X and plan_id = Y and archived_at = $T order by created_at`
3. Archive list: `select distinct archived_at where user_id = X and plan_id = Y and archived_at is not null`

`plan_id` uses `on delete set null` (not cascade) so deleting a plan leaves the conversation intact under "no plan" — runners don't lose chat history when they archive a finished plan.

RLS + GRANTs: standard owner-only on every command. `select`, `insert`, `delete` gated on `auth.uid() = user_id`. UPDATE is also gated by an owner-only policy, but the `authenticated` role only has column-level UPDATE on `(archived_at, reaction)` — `content`, `role`, `plan_id`, `created_at` are immutable to clients, enforced at the GRANT layer (PostgREST rejects mutations that touch other columns). This preserves the audit trail of who-said-what without trusting the client to behave.

Realtime: published on `supabase_realtime` so a client that reloads mid-stream picks the assistant reply up via subscription when the in-flight server request finishes.

---

### `monthly_funding`

Monthly funding tracker for the donate page's progress bar. One row per month, keyed by the first of the month (e.g. `'2026-05-01'`). Updated by the project owner when donations land. Publicly readable — the whole point is transparency.

Write path: service role only. RLS is enabled with a single `select` policy (`using (true)`); there are no INSERT/UPDATE/DELETE policies by design. All writes go through direct SQL or a service-role context (e.g. a webhook or admin script). No client-side write policy will be added.

```sql
create table monthly_funding (
  month             date primary key,
  amount_received   numeric(10,2) not null default 0,
  donor_count       integer not null default 0,
  updated_at        timestamptz not null default now()
);
```

---

### `device_tokens`

Push-notification device tokens. One row per (user, device). Prepared in
migration `20260506_001_device_tokens.sql` for the Phase 4b Clubs push
flows (event-day reminders, admin-update fan-out) but no sender is wired
today — the table exists so clients can register tokens on sign-in
without blocking on the server side.

```sql
create table device_tokens (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references auth.users(id) on delete cascade,
  platform               text not null check (platform in ('ios', 'android', 'web')),
  token                  text not null,
  app_version            text,
  locale                 text,
  notifications_enabled  boolean not null default true,
  last_seen_at           timestamptz not null default now(),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (user_id, token)
);
```

Indexes: `device_tokens_active` (partial index on `user_id` where
`notifications_enabled`, the fan-out read shape) and
`device_tokens_platform` (for platform-wide audits). RLS scopes reads /
writes to `auth.uid() = user_id`; the push worker reads with the
service-role key to fan out. A trigger touches `updated_at` on update.

---

### `fitness_snapshots`

Time-series store for Pro-tier training-load metrics (VDOT, VO2 max,
ATL, CTL, TSB). Prepared in migration `20260507_001_fitness_snapshots.sql`.
No endpoint writes to it yet — the Pro tier today unlocks "unlimited AI
Coach" and "priority processing" (see `decisions.md § 23`); the
recovery-advisor / race-predictor features that will consume this table
are tracked under `roadmap.md § Phase 3 — Premium tier`.

```sql
create table fitness_snapshots (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references auth.users(id) on delete cascade,
  computed_at            timestamptz not null default now(),
  vdot                   numeric(5, 2),
  vo2_max                numeric(5, 2),
  acute_load             numeric(8, 2),
  chronic_load           numeric(8, 2),
  training_stress_bal    numeric(8, 2),
  qualifying_run_count   integer not null default 0,
  source                 text not null default 'server'
                          check (source in ('server', 'client')),
  notes                  text,
  created_at             timestamptz not null default now()
);
```

Index `fitness_snapshots_user_time` on `(user_id, computed_at desc)`
covers both the "latest snapshot" + "time window" read shapes. RLS:
users see and write their own rows; the server-side recompute job
writes via service role. RPC `latest_fitness_snapshot()` exists as a
single-round-trip convenience for dashboard cards.

---

### `personal_records`

Cache table for per-distance PBs (`5k` / `10k` / `half_marathon` /
`marathon`). Backed by triggers on `runs` so reads are a single indexed
lookup instead of the full aggregation that
[`personal_records()`](#personal_records-1) does. Shipped in migration
`20260508_001_personal_records_cache.sql`. The existing
`personal_records()` SQL function stays in place for callers that
haven't migrated.

```sql
create table personal_records (
  user_id       uuid not null references auth.users(id) on delete cascade,
  distance      text not null check (distance in ('5k', '10k', 'half_marathon', 'marathon')),
  best_time_s   integer not null,
  run_id        uuid references runs(id) on delete set null,
  achieved_at   timestamptz not null,
  updated_at    timestamptz not null default now(),
  primary key (user_id, distance)
);
```

Triggers: `runs_personal_records_insert / update / delete` call
`refresh_personal_records_for_user(uid)`, a `security definer` helper
that deletes + re-inserts the caller's four rows (full rebuild per
user on any run change — simpler to reason about than incremental).
The helper is guarded: `auth.uid() is not null and auth.uid() !=
p_user_id` raises `not authorized`, so a logged-in attacker can't call
the RPC with a victim's id. Service-role / seed inserts run with
`auth.uid() = null` and skip the guard — the trigger path is unchanged.
Backfill runs once in the migration via a `do $$ for uid in … $$` loop.
Second index `personal_records_distance_time` on `(distance,
best_time_s asc)` prepared for a future leaderboard view. RLS today
scopes reads to the owner; broader read policy is a follow-up when
the leaderboard UI lands.

---

### `live_run_pings`

Ephemeral per-sample GPS feed for the `/live/{run_id}` spectator page.
Shipped in migration `20260509_001_live_run_pings.sql`.

```sql
create table live_run_pings (
  id            bigserial primary key,
  run_id        uuid not null references runs(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  at            timestamptz not null default now(),
  lat           double precision not null,
  lng           double precision not null,
  ele           double precision,
  elapsed_s     integer,
  distance_m    double precision,
  bpm           integer
);
```

- Added to `supabase_realtime` publication so change streams fan out to
  subscribed browsers.
- RLS: `select` when the parent run is public or owned by the caller;
  `insert` / `delete` restricted to `auth.uid() = user_id` and (for
  insert) a live run owned by the caller.
- Recorder contract: one row per GPS sample (3–10 s cadence), delete
  on finish. `cleanup_stale_live_run_pings()` (callable via service
  role) wipes rows older than 4 hours as a safety net.

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

-- user_coach_usage: users can read/insert/update their own rows only.
alter table user_coach_usage enable row level security;
-- (select/insert/update policies scoped to auth.uid() = user_id)

-- monthly_funding: publicly readable by anyone. Write restricted to
-- service role (project owner).
alter table monthly_funding enable row level security;
create policy "monthly_funding_public_read"
  on monthly_funding for select using (true);

-- clubs: public clubs readable by anyone; private clubs readable only by
-- members (+ owner). Only authenticated users can create. Updates/deletes
-- gated by is_club_admin and owner_id respectively.
alter table clubs enable row level security;
-- events, event_attendees, club_posts inherit visibility from the parent
-- club. Admin-only inserts for events and posts. Users manage their own RSVP
-- row and leave their own club membership row. See
-- 20260416_001_clubs_and_events.sql for the full set.
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

### `POST /delete-account`

Permanently deletes the authenticated user's account and all associated data.

**Flow:**
1. Authenticate user via JWT
2. Delete all Storage files in the `runs` bucket under `{user_id}/`
3. Delete the auth user via `admin.deleteUser()` — row data in `runs`, `routes`, `user_profiles`, `user_settings`, etc. cascades automatically via `ON DELETE CASCADE` foreign keys

**Response:**
```json
{ "ok": true }
```

No request body required. Irreversible.

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

### `nearby_routes(lat, lng, radius_m, max_results)`

Returns public routes within a radius of a geographic point, sorted by distance. Requires PostGIS.

```sql
select * from nearby_routes(51.5074, -0.1278, 50000, 50);
```

**Parameters:**
- `lat` / `lng` — center point (WGS84 degrees)
- `radius_m` — search radius in metres (default 50000 = 50 km)
- `max_results` — maximum rows returned (default 50)

**Returns:** same columns as `routes` table, ordered by distance from the center point.

---

## Supabase Storage

Used for GPX file storage and data exports.

### Buckets

| Bucket | Access | Purpose |
|---|---|---|
| `runs` | Private (RLS) | Gzipped GPS tracks (`{user_id}/{run_id}.json.gz`). Public read via RLS when `runs.is_public = true`. |
| `routes` | Private (RLS) | Uploaded GPX/KML files |
| `run-photos` | Public read | Photos attached to runs (`{owner_id}/{photo_id}.{ext}`). Per-user-folder INSERT/DELETE policies. See `decisions.md § 36`. |
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
