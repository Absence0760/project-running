# Run app — API and database reference

Complete reference for the Supabase backend: database schema, row-level security policies, Edge Functions, and the REST API surface consumed by all clients.

---

**Contents:** [Database schema](#database-schema) (Core: runs & routes · Social graph & feed · Clubs & events · Training & coaching · Profile, settings & devices · Fitness & analytics · Integrations & background jobs · Billing · Infrastructure) · [Row-level security](#row-level-security) · [Edge Functions](#edge-functions) · [REST API](#rest-api-supabase-auto-generated) · [Database functions (RPCs)](#database-functions-rpcs) · [Supabase Storage](#supabase-storage) · [Auth](#auth) · [Migrations](#migrations)

## Database schema

All tables live in the `public` schema. Users are managed by `auth.users` (Supabase Auth) — no custom users table needed.

### Core: runs & routes

#### `runs`

Every recorded or imported run.

```sql
create table runs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users not null,
  started_at    timestamptz not null,
  duration_s    integer not null,           -- elapsed seconds
  distance_m    numeric(10, 2) not null,    -- metres
  route_id      uuid references routes,     -- linked planned route, if any
  event_id      uuid references events,     -- linked club event instance, if any
  source        text not null,              -- see RunSource enum below
  activity_type text not null default 'run' -- run|walk|hike|cycle|stroller (CHECK). Promoted from metadata in 20261207_001 (F3)
                check (activity_type in ('run','walk','hike','cycle','stroller')),
  is_dnf        boolean not null default false, -- did-not-finish; PR engine excludes these. Promoted from metadata in 20261207_001 (F3)
  external_id   text unique,                -- deduplication key
  metadata      jsonb,                      -- source-specific extra fields (avg_bpm, steps, elevation_m, provider ids, …)
  track_url     text,                       -- Storage path: {user_id}/{run_id}.json.gz
  hr_series_url text,                        -- Storage path: {user_id}/{run_id}.hr.json.gz (indoor/trackless HR series)
  is_public     boolean default false,      -- visible at /share/run/{id}
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);
-- NB: there is no `kind` column. 20261204_001 added one as a future
-- modality discriminator; 20261206_001 (F1/D1) dropped it as vestigial —
-- `runs` is running-only and the `activities` view is the modality union.

-- Index for timeline queries
create index runs_user_started_at on runs (user_id, started_at desc);

-- Index for deduplication upserts
create unique index runs_external_id on runs (external_id) where external_id is not null;

-- Index for public share pages
create index runs_public on runs (is_public, started_at desc) where is_public = true;
```

**`runs_user_started_at` is NOT redundant with `runs_user_source`** (F2f, verified by EXPLAIN). The audit hypothesised that `runs_user_source (user_id, source, started_at DESC)` (migration `20260407_001`) might subsume `runs_user_started_at (user_id, started_at DESC)`. It does not: the history / dashboard list query filters on `user_id` and orders by `started_at DESC` with **no `source` predicate**, and `started_at` is the *third* column of `runs_user_source` (behind `source`), so that index can't supply the ordering without a `source` equality. EXPLAIN over 5 000 synthetic runs picks `runs_user_started_at` for the no-source query; dropping it forces a Seq Scan + top-N Sort (cost ~222 vs ~6), and even with `enable_seqscan=off` the planner falls back to a bitmap scan on `runs_user_distance` + Sort — it never chooses `runs_user_source` for an ordered scan. Both indexes are kept: `runs_user_source` serves the source-filtered dashboard query, `runs_user_started_at` serves the unfiltered timeline.

**GPS tracks** are stored as gzipped JSON files in the `runs` Storage bucket at `{user_id}/{run_id}.json.gz`. The `track_url` column points to the file. Tracks are never returned by list queries -- they are fetched on demand when the run detail screen is opened.

**Indoor/trackless HR series** live in a sibling sidecar object in the *same* `runs` bucket at `{user_id}/{run_id}.hr.json.gz` (gzipped JSON array of `{ bpm, ts? }`), pointed to by `hr_series_url`. An indoor or treadmill FIT carries heart rate but no GPS fix, so the run imports with an empty `track` and the per-point `bpm` the HR-zone breakdown needs would otherwise be lost. The sidecar is owner-only audit data: it carries **no location**, is gated by the same `{user_id}/...` bucket RLS as the track, is pinned to its canonical path by the `runs_hr_series_url_path_shape` CHECK (mirrors `runs_track_url_path_shape`), and is **never** exposed through `public_runs` or `clip_track_for_user` (it never enters the coordinate pipeline). See [decisions.md § 116](../architecture/decisions.md). Migration `20261127_001`.

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

**Public reads go through the `public_runs` view, not the base table.** Migration `20260626_001_public_runs_view.sql` adds a redacted projection over `runs` that:

- omits `external_id` (which leaks third-party activity ids — `strava:<id>`, `parkrun:<event>:<date>`, `garmin:<file_id>`),
- strips audit/sync/training-plan-linkage keys from `metadata` (denylist in lockstep with [metadata.md](metadata.md)'s "Public-safe?" column — `imported_from`, `*_id`, `*_activity_type`, `last_modified_at`, `recovered_from_crash`, `in_progress*`, `manual_entry`, `indoor_estimated`, `distance_source`, `plan_workout_id`, `workout_step_results`, `workout_adherence`, `source_file`, `max_bpm`),
- nulls `route_id` / `event_id` when the joined route or event isn't itself public (via SECURITY DEFINER helpers `is_public_route_by_id` / `is_public_event_by_id`),
- restricts to `is_public = true`,
- exposes `activity_type` + `is_dnf` as **columns** (public-safe — both were public-safe metadata keys before they were promoted to real columns in `20261207_001`, F3; the view now selects the columns and the keys no longer ride in the `metadata` projection),
- omits `updated_at` — same signal as `metadata.last_modified_at` (already stripped); leaks last-edit / last-sync timestamps to anyone with the share link (`20260807_001`).
- omits `track_url` (the `{user_id}/{run_id}.json.gz` Storage path — dropped `20260924_001` for defence-in-depth so a future Storage-RLS loosening can't re-open direct download from a leaked path) but exposes a derived boolean `has_track` (`track_url IS NOT NULL`, `20261105_001`) so the feed / `/u/[id]` map-thumbnail gate has a safe existence signal without the path. Non-owner thumbnails fetch the clipped trace by `run_id` through the `clip-public-track` Edge Function, which derives the path itself.

**`source` is intentionally kept** in the view: `RunShareView.svelte` renders it as a source badge ("Strava", "Garmin", "parkrun") so a follower can tell where the run came from. The trade-off is provider-context disclosure (a Strava-tagged badge implies the user has a Strava account) vs. UX recognisability — UX wins because the user opted into sharing. If you ever drop the badge, also drop `r.source` from the view.

Granted to `anon` + `authenticated`. Every public-runs reader (`fetchPublicRun`, `fetchPublicRunsByUser`, `fetchFollowingFeed` on web; `fetchPublicRunById`, `fetchPublicRunsByUser`, `fetchFollowingFeed` on mobile) reads the view, not the base table — architecture-guard tests on both platforms enforce this. Owner-context reads (`select * from runs where user_id = auth.uid()`) keep the bare-table path because they need the unredacted columns. Decisions §33's wire-leak follow-up entry has the full motivation.

---

#### `routes`

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
  is_starred      boolean not null default false,  -- owner-curated "show on watch"
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

create index routes_user_id on routes (user_id, created_at desc);
create index routes_public on routes (is_public, created_at desc) where is_public = true;
create index routes_club_id on routes (club_id, created_at desc) where club_id is not null;
create index idx_routes_user_starred on routes (user_id, updated_at desc) where is_starred;
```

**`start_point`** is a PostGIS `geography(Point, 4326)` column storing the route's starting coordinates. It is auto-populated by a `BEFORE INSERT OR UPDATE` trigger from `waypoints->0->>'lat'/'lng'`. A GiST spatial index powers the `nearby_routes` RPC for proximity search.

**`geom`** is the matching `geography(LineString, 4326)` column for the *full* route, populated from `waypoints` by the same kind of `BEFORE INSERT OR UPDATE` trigger (`routes_set_geom`). Backed by `routes_geom_gist`. Unlocks queries that `start_point` can't answer — "routes that pass through this area", "routes that intersect another route", "routes near a run's track" — via `ST_Intersects` / `ST_DWithin` against the line itself. Both client codegens emit it as opaque (`unknown` in TS, `dynamic` in Dart); the binary EWKB never reaches a renderer, so callers should keep using `waypoints` for drawing and reach for `geom` only inside RPC bodies. Routes with fewer than two valid lat/lng waypoints store `null` (a LineString needs at least two points).

**`club_id`** makes a route club-owned: any club admin can edit it, any member can read it regardless of `is_public`. Two RLS policies layer on top of the existing user-owned + public-readable policies — `"club members read club routes"` (SELECT where `club_id is not null and is_club_member(club_id)`) and `"club admins write club routes"` (ALL where `club_id is not null and is_club_admin(club_id)`). See `docs/architecture/decisions.md § 30` and `docs/features/clubs.md § Club-owned routes`. The owner policy `"users own their routes"` carries a `with check (auth.uid() = user_id and (club_id is null or private.is_club_admin(club_id)))` (migration `20270123_001`) so the OR'd permissive evaluation can't be used to set `club_id` to a club you don't administer — a non-admin can only ever write personal (`club_id is null`) rows. The same owner-path `club_id` lockdown is applied to `training_plans` (`"users own their plans"`, club branch additionally requires `is_template = true`) and `session_plans` (`"authors own their session plans"`).

**`is_starred`** is the owner's "what I actually run" flag. The watch's route picker fetches `is_starred=eq.true&order=updated_at.desc&limit=30` so a 1.4-inch round screen never has to scroll through every saved route. When the starred query returns nothing (first-launch / un-curated user), the watch falls back to the 10 most-recently-updated owned routes so the picker isn't empty. Toggleable from web (`/routes` cards + `/routes/[id]` header) and mobile (routes list + detail screen); read-only from the watch. Backed by a partial index keyed on `(user_id, updated_at desc)` so the watch fetch is index-only.

**Public reads go through the `public_routes` view, not the base table.** Migration `20260703_001_drop_routes_public_select_policy.sql` drops the bare-table public-read RLS; non-owner reads (anon + authenticated) consume `public_routes` instead. The view is a thin projection over `routes` filtered to `is_public = true` with `geom` cast back to `unknown`/`dynamic` for the row-type generators. Cross-references the same shape used by `public_runs` (decisions §33). Every public-routes reader on web (`fetchPublicRoutes`, `searchPublicRoutes`, `fetchPublicRouteById`) and mobile (`api_client.fetchRouteById` for non-owners) reads the view. Owner-context reads keep the bare-table path because they need the unredacted columns.

**`public_routes.user_id` is intentionally exposed.** Combined with `public_runs.user_id`, it makes `auth.users.id` (UUID) a stable cross-link between a public route, the public runs that ran on it, and the runner's `/u/[id]` profile page. That linkage is the entire point of the social surface — followers click through from a friend's run to the route they used, then to their profile. The trade-off is that a runner can't share a single public route or run without publishing their auth UUID as a durable identifier; if/when handles ship (decisions §31), the UUID will be aliased but the cross-link will still be present at the schema layer.

**`public_profiles` view** (migration `20260824_001_public_profiles_view.sql`) — anon-readable projection of `user_profiles` exposing only `id`, `display_name`, `avatar_url`. The base `user_profiles` table is owner-only by RLS (`auth.uid() = id`), which blocked the prerendered share pages from baking the runner's name into the og:title. The view restores that single read path with the same privacy posture as `/u/[id]` (display_name + avatar are already on every share-page body via RunSocial / kudos / comments for any authed viewer; the only delta is anon crawlers now see the same name on the unfurl card). No way to enumerate "all users" — callers must supply a uuid up-front (typically from a `public_runs` / `public_routes` row). To retract per-user, add a `crawler_visible` flag to `user_profiles` and a `WHERE` clause on the view; v1 ships it unconditionally readable.

---

#### `saved_routes`

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

#### `route_reviews`

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

#### `route_markers`

Course markers along a route line — aid stations, cut-offs, crew/parking
access, hazards, notes, climbs (migration `20270129_001`). Owner-writable;
readable when the parent route is visible (`private.is_route_visible_to`).
`position_m` is derived from `routes.geom` by a trigger. The canonical display
read is the `route_markers_for_viewer(route_id)` RPC, which additionally
redacts markers inside the owner's privacy zones for non-owners. See
[../features/route_markers.md](../features/route_markers.md).

```sql
create table route_markers (
  id          uuid primary key default gen_random_uuid(),
  route_id    uuid references routes(id) on delete cascade not null,
  user_id     uuid references auth.users(id) on delete cascade not null,
  kind        text not null
              check (kind in ('aid_station','cutoff','crew_access',
                              'hazard','note','climb','custom')),
  label       text not null check (length(label) between 1 and 120),
  lat         double precision not null,
  lng         double precision not null,
  position_m  numeric(10,2),   -- derived from routes.geom by trigger
  meta        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index route_markers_route_pos on route_markers (route_id, position_m);
```

---

#### `route_conditions`

Community condition reports on a saved route — "creek crossing flooded",
"trail closed for logging", "ice on the north face" (migration
`20270215_001`). Unlike `route_markers` (owner-only), the INSERT is
**visibility-gated** so **any signed-in viewer** of the route can file a
report (`auth.uid() = user_id and exists (select 1 from routes where routes.id
= route_conditions.route_id)`, picking up `routes` RLS); DELETE is the author
**or** the route owner (spam cleanup). `condition` + `severity` are narrow
unions (CHECK + TS unions `RouteConditionKind`/`RouteConditionSeverity` +
`check_constraint_unions.mjs` guard). The anchor (`lat`/`lng`) is optional;
`position_m` is derived from `routes.geom` by trigger (null when unanchored).
The canonical display read is the `route_conditions_for_viewer(p_route_id)`
SECURITY DEFINER RPC, which gates visibility and **nulls the
lat/lng/position_m of any report inside the owner's privacy zones for a
non-owner** (the condition analogue of `route_markers_for_viewer`; client read
fails closed to `[]`). See [../features/trail_navigation.md](../features/trail_navigation.md)
+ [decisions.md § 171](../architecture/decisions.md).

```sql
create table route_conditions (
  id          uuid primary key default gen_random_uuid(),
  route_id    uuid references routes(id) on delete cascade not null,
  user_id     uuid references auth.users(id) on delete cascade not null,
  condition   text not null
              check (condition in ('clear','muddy','flooded','snow_ice',
                                   'overgrown','closed','hazard','other')),
  severity    text not null default 'info'
              check (severity in ('info','caution','impassable')),
  note        text check (note is null or length(note) between 1 and 500),
  lat         double precision check (lat is null or lat between -90 and 90),
  lng         double precision check (lng is null or lng between -180 and 180),
  position_m  numeric(10,2),   -- derived from routes.geom by trigger
  created_at  timestamptz not null default now()
);

create index route_conditions_route_recent
  on route_conditions (route_id, created_at desc);
```

---

#### `run_matched_tracks`

Per-run map-match output state. One row per run, populated by a trigger when `runs.track_url` lands or changes.

```sql
create table run_matched_tracks (
  run_id uuid primary key references runs(id) on delete cascade,
  status text not null default 'pending',
  matched_track_url text,
  attempts smallint not null default 0,
  matched_at timestamptz,
  algorithm text,
  algorithm_version text,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint run_matched_tracks_status_check
    check (status in ('pending', 'matched', 'failed', 'skipped'))
);

create index run_matched_tracks_pending
  on run_matched_tracks (created_at)
  where status = 'pending';
```

- **`status`**: narrow union `pending | matched | failed | skipped`. Trigger inserts `pending`; the worker writes `matched` / `failed`. `skipped` is reserved for runs the worker decides not to match (too short, too noisy).
- **RLS**: owner read only — owner of the parent run can SELECT, nobody can INSERT / UPDATE / DELETE through the API. The Go matching worker authenticates with the service role key and bypasses RLS.
- **Reset on re-upload**: when `runs.track_url` is updated to a different value, the trigger resets the row back to `pending` (clears `matched_track_url`, `attempts`, `matched_at`, `error_message`, `algorithm` / `algorithm_version`) and stamps `source_track_url` with `NEW.track_url` so the matcher re-processes against the fresh data.
- **`source_track_url`** (added in migration `20260611_001`): the `runs.track_url` value the row's match output is tagged against. Set by the trigger on every insert and every reset. The Go worker reads this at job start, runs the matcher, then PATCHes the row conditionally on `?source_track_url=eq.<value>`. A re-upload landing between read and write changes `source_track_url`, the conditional PATCH affects 0 rows, the worker discards its stale result and the fresh job (already queued by the trigger) produces the right answer. Closes the re-upload race at the DB level — no application-side attempts-CAS needed.

### Social graph & feed

#### `user_follows`

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

#### `run_kudos` / `run_comments`

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

#### `run_photos`

Photos attached to a run (decisions §36). Metadata in Postgres, bytes in the **private** `run-photos` Storage bucket at `{owner_id}/{photo_id}.{ext}` (migration `20260712_001` flipped the bucket public flag; the previous "public-read with policy gate" model didn't actually work — Supabase routes public-bucket reads through an unauthenticated CDN endpoint that bypasses RLS on `storage.objects`). Visibility tracks the parent run via EXISTS — same shape as `run_kudos` / `run_comments` — and is now properly enforced by the storage SELECT policy from `20260705_001`. Clients access bytes via `createSignedUrl(s)` with a 1-hour TTL.

```sql
create table run_photos (
  id            uuid primary key default gen_random_uuid(),
  run_id        uuid references runs(id) on delete cascade not null,
  owner_id      uuid references auth.users(id) on delete cascade not null,
  storage_path  text not null,            -- {owner_id}/{photo_id}.{ext}
  caption       text check (caption is null or length(caption) <= 280),
  position_idx  smallint not null default 0,
  created_at    timestamptz not null default now(),
  event_id              uuid references events(id) on delete set null,  -- #49 gallery tag
  event_instance_start  timestamptz
);
```

In v1 `owner_id` is enforced to equal `runs.user_id` at INSERT time; the column is kept distinct so a future club-photo feature can opt in via a migration without restructuring. Run owner OR photo owner can DELETE (moderation primitive matching the run-comments shape). Storage policies gate SELECT on `is_run_visible_to(rp.run_id, auth.uid())` (joining through `run_photos`) and INSERT/DELETE on the per-user folder. The bucket is private; clients use signed URLs with a 1 h TTL. **EXIF stripping** is two-layered: the `job_worker` `photo_process` handler re-encodes uploads server-side to drop metadata, and the mobile clients additionally strip the EXIF/XMP APP1 segment *before* upload (`apps/mobile_android/lib/exif_strip.dart`, persona family-club #52) so a geotagged original never sits in the bucket during the async-worker window. Web still relies on the server worker alone. **Event gallery (#49, migration `20261025_001`):** `event_id` + `event_instance_start` tag a photo to an event occurrence; a `for select` policy makes event-tagged photos readable by anyone who can read the event (the `exists (… from events …)` subquery inherits the events RLS), so the gallery aggregates attendees' photos even across private runs. The INSERT policy additionally requires the uploader can see the tagged event.

#### `route_photos`

Photos attached to a route (backlog C1 — the `run_photos` capability applied to routes; migration `20270114_001`). Metadata in Postgres, bytes in the **private** `route-photos` Storage bucket at `{owner_id}/{photo_id}.{ext}`. The bucket is private from the start (no public flag to flip) so RLS on `storage.objects` is always enforced; clients access bytes via `createSignedUrl(s)` with a 15-min TTL.

```sql
create table route_photos (
  id              uuid primary key default gen_random_uuid(),
  route_id        uuid references routes(id) on delete cascade not null,
  owner_id        uuid references auth.users(id) on delete cascade not null,
  storage_path    text not null,            -- {owner_id}/{photo_id}.{ext}
  thumb_512_path  text,                      -- service-role-only 512w thumb
  caption         text check (caption is null or length(caption) <= 280),
  position_idx    smallint not null default 0,
  created_at      timestamptz not null default now()
);
```

The owner of the parent route attaches photos (INSERT policy: `auth.uid() = owner_id AND owns the route`). Photo owner OR route owner can DELETE (moderation). SELECT gates on `private.is_route_visible_to(route_id, auth.uid())` (own / public / club-member) on both the table and the Storage bytes (joining through `route_photos.storage_path` OR `thumb_512_path`), so a route flipping public→private propagates within the signed-URL TTL. `storage_path` + `thumb_512_path` carry owner-prefix-shape CHECKs; a BEFORE-UPDATE trigger blocks clearing `storage_path` (use DELETE) and another blocks user-side `thumb_512_path` writes (service-role only). **EXIF stripping is two-layered** (matching `run_photos`, migration `20270224_001`): the clients strip the EXIF/XMP APP1 segment *before* upload (web `stripExifFromFile`, mobile `stripJpegExif`), and the Go `job_worker` `route_photo_process` handler re-strips server-side + generates the 512w gallery thumbnail (`{owner}/{photo_id}_512.jpg`) and PATCHes `thumb_512_path` (service-role). Two enqueue triggers fire the job: an AFTER INSERT (web upload-then-insert) and an AFTER UPDATE OF `storage_path` (mobile insert-placeholder-then-PATCH); the service-role thumb PATCH never re-enqueues. Clients prefer the thumbnail in galleries and fall back to the original while the column is still null. Pinned by `rls_route_photos_test.sql` (13 assertions) + `route_photos_enqueue_process_test.sql` (6 assertions).

#### `notifications`

Inbox rows for the social loop (decisions §38). Materialised by `after insert` (kudos / comments / follows / club posts / completed runs) and `after insert or update` (event RSVPs) SECURITY DEFINER triggers on `run_kudos`, `run_comments`, `user_follows`, `event_attendees`, `club_posts`, and `runs` so the notification lands in the same transaction as the source write.

```sql
create table notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  actor_id    uuid references auth.users(id) on delete set null,
  kind        text not null check (kind in ('kudos','comment','comment_reply','follow','event_rsvp','event_cancel','plan_update','message','club_post','run_completed','event_reminder','plan_assigned','achievement','challenge_complete','content_hidden')),
  run_id        uuid references runs(id) on delete cascade,
  comment_id    uuid references run_comments(id) on delete cascade,
  event_id      uuid references events(id) on delete cascade,
  plan_id       uuid references training_plans(id) on delete cascade,
  club_id       uuid references clubs(id) on delete cascade,
  achievement_id uuid references achievements(id) on delete cascade,
  activity_kind text check (activity_kind is null or activity_kind in ('run','lift','meal')),
  activity_id   uuid,
  read_at       timestamptz,
  created_at    timestamptz not null default now()
);
```

The `achievement` kind (migration `20270208_001`) fires from the
`notify_achievement_earned` AFTER-INSERT trigger on `achievements` for each new
award, linked via the dedicated `achievement_id` FK (the `activity_kind` CHECK
was left untouched rather than widened — a badge isn't an `activities`-view
modality). Owner-only, no actor. A new in-app kind stays bell-only unless added
to the email/push allowlists. `plan_assigned` was added by `20270107_001`.

`(activity_kind, activity_id)` is the **polymorphic activity reference** (F15, migration `20261212_001`) added ahead of the Phase 4 social expansion (kudos on a lift, comment on a meal). `activity_kind` matches the `activities`-view modality tag; `activity_id` is a bare uuid (no single FK — it spans `runs` / `gym_workouts` / `food_log`). The run-notification triggers (`notify_run_kudos`, `notify_run_comment`, `notify_run_completed`) populate it as `('run', run_id)`, and existing run-linked rows were backfilled the same way. `run_id` is kept as the referential-integrity bridge for the run path until the social-lift work lands. The kind CHECK is consolidated into one authoritative constraint (F16, `20261211_001`); `event_reminder` was added by `20261130_001`.

The `plan_update` kind (migration `20261024_001`, coach persona #48) fires from an AFTER UPDATE trigger on `plan_workouts` when the editor (`auth.uid()`) is someone other than the plan owner — the coach-edit notification. `plan_workouts` also gained `updated_by` + `updated_at`, stamped by a BEFORE UPDATE trigger. The cross-user edit path itself lands with the coach-athlete roster (persona #46); until then the notify trigger is dormant (owner-only RLS) while the audit columns populate on every edit.

The `club_post` + `run_completed` kinds (migration `20261101_001`, persona #38) are the two community fan-outs. `notify_club_post` fires on `club_posts` insert and fans out to every **active** member of the club except the author (pending join-requests are skipped — which is what makes the club-home "Posts here notify every active member" copy truthful). `notify_run_completed` fires on `runs` insert and fans out to the runner's followers (`user_follows`), but only for a **public** run **started within the last 24 hours** — the recency gate keeps a bulk history import (Strava/Garmin ZIP, parkrun backfill, CSV restore) or a late offline sync from exploding every follower's inbox with old activity; the window is wide enough to cover an ultra-length single session. Device push (FCM/APNs) for these kinds stays deferred per roadmap Phase 4b — the row IS the delivery surface today and the in-app inbox renders it; the future push sender reads the same rows.

Two indexes for the read path: `(user_id, created_at desc)` for the list view, and a **partial** `(user_id, created_at desc) where read_at is null` so the bell-badge count query is O(unread). A partial unique `(user_id, actor_id, event_id) where kind = 'event_rsvp'` de-dupes RSVP-status flips (Going → Maybe → Going re-fires the trigger but `on conflict do nothing` keeps one row), and a partial unique `(user_id, run_id) where kind = 'run_completed'` is the same defensive dedupe for completed-run fan-out. Source FKs use `on delete cascade` so notifications die with their parent (deleted run, deleted comment, deleted event, deleted club), keeping the inbox honest without a cleanup job.

RLS: users SELECT / UPDATE (mark read) / DELETE their own rows. INSERT is closed to regular users — only the SECURITY DEFINER trigger functions write rows. The triggers also defensively skip self-actions (`actor = recipient`) even though the source-table CHECKs already block them. `notify_event_rsvp` fires for the event's `author_id` only and only when `status = 'going'`; Maybe / Declined intentionally produce no inbox row.

#### `direct_messages`

```sql
create table direct_messages (
  id            uuid primary key default gen_random_uuid(),
  sender_id     uuid references auth.users(id) on delete cascade not null,
  recipient_id  uuid references auth.users(id) on delete cascade not null,
  body          text not null check (length(btrim(body)) between 1 and 4000),
  created_at    timestamptz not null default now(),
  read_at       timestamptz,
  check (sender_id <> recipient_id)
);
```

1:1 direct messages (very-social persona #55, migration `20261026_001`). A "thread" is the unordered participant pair — no separate threads table; indexes use `least/greatest(sender_id, recipient_id)` so A→B and B→A share a symmetric thread index. RLS: each participant reads their own threads; **INSERT is gated on `not is_blocked_either_way(sender, recipient)` AND an existing follow in either direction** — a plain `user_blocks` subquery would be hidden from the sender by that table's owner-read RLS, so the SECURITY DEFINER helper is load-bearing here, not a convenience. The recipient marks read (UPDATE); either party deletes. A `message` notification fires to the recipient only on the first unread message of a burst (the trigger checks for an existing unread from the same sender) so an active thread doesn't flood the bell. Deferred: realtime delivery, a non-follower "message requests" inbox, mobile.

#### `segments` / `segment_efforts`

Segments + leaderboards (decisions §37). v1 segments are slices of a *saved route* — `(route_id, start_distance_m, end_distance_m)` — not arbitrary geometry. Visibility on both tables tracks the parent route via EXISTS.

```sql
create table segments (
  id                uuid primary key default gen_random_uuid(),
  route_id          uuid references routes(id) on delete cascade not null,
  name              text not null check (length(name) between 1 and 120),
  start_distance_m  numeric not null check (start_distance_m >= 0),
  end_distance_m    numeric not null,
  length_m          numeric generated always as (end_distance_m - start_distance_m) stored,
  author_id        uuid references auth.users(id) on delete set null,
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

Anyone who can read the parent route can create a segment (Strava-style community contribution); `author_id` is enforced as `auth.uid()`. Effort visibility = segment AND run readability so private runs don't surface on a public segment's leaderboard. **Auto-effort generation is client-side**: there's no trigger because `pg_net` isn't wired and downloading from Postgres is gross. The browser walks the run track via `lib/segments.ts#computeEffortFromTrack` (haversine cumulative distance + timestamp interpolation) on the run-detail page, then INSERTs new efforts via the regular RLS-gated path. The unique constraint makes this idempotent.

---

#### `reports`

User-submitted reports against a profile, club, route, comment, club post, or run. Polymorphic via `(target_kind, target_id)` where `target_kind ∈ {'user', 'club', 'route', 'comment', 'club_post', 'run'}` — the TS union `ReportTargetKind` (`apps/web/src/lib/types.ts`) is kept in lockstep with this CHECK by `apps/web/scripts/check_constraint_unions.mjs`. Reason is constrained to `{'spam', 'harassment', 'inappropriate', 'impersonation', 'other'}`; status is `{'pending', 'reviewed', 'dismissed'}`. A partial-unique index `reports_no_duplicate_pending` enforces one pending report per (reporter, target) pair — once status flips to reviewed/dismissed the same reporter can re-file if the target reoffends.

Inserts go through the `submit_report(p_target_kind, p_target_id, p_reason, p_notes)` SECURITY DEFINER RPC, which validates the target row exists (per kind: `user_profiles` / `clubs` / `routes` / `run_comments` / `club_posts` / `runs`), rejects self-reports on `target_kind='user'` and on a self-authored comment / club post / run (a misclick) with `22023`, rate-limits via the shared `enforce_create_rate_limit` helper at 10/hour per reporter, and surfaces duplicate-pending as a 23505 with a "you already have a pending report" hint. RLS hides others' reports from each user — the only way to *read* `reports` cross-user is via service_role, which is intentional: reports are pending evidence, not public attribution.

Moderation runs through the web admin surface `/admin/reports` (web-only back-office tooling — migration `20270104_001_admin_moderation.sql`). **Auto-hide-after-N + reputation-weighted reports shipped** (migration `20270218_001_auto_hide_reports.sql`, decisions §172) — see "Auto-hide on reports" below. Migrations `20260908_001_user_reports.sql` (user/club/route), `20261117_001_report_comments.sql` (comment), `20270115_001_report_posts_and_runs.sql` (club_post + run). Pinned by `apps/backend/supabase/tests/reports_test.sql` (7 pgtap subtests) + `report_comments_test.sql` (4) + `report_posts_and_runs_test.sql` (8) + `apps/web/tests-e2e/cross-cutting/reports.spec.ts` (2 e2e) + `report-post-and-run.spec.ts` (2 e2e) + `social/comment-report.spec.ts`.

#### `app_admins` + the moderation RPCs

`app_admins (user_id, granted_at, granted_by)` is the moderator allow-list — one row per admin. RLS is enabled with no user-JWT policy, so under RLS a normal caller sees zero rows; grants/revokes happen via service_role (Studio) or `seed.sql` (the seed user is seeded admin for local testing). The oracle `private.is_admin(uid)` (SECURITY DEFINER, `search_path`-pinned, in `private` so PostgREST does not expose it — mirrors the membership oracles of `20261120_001`) backs every gate.

`app_admins` is **deliberately excluded from the DSAR (Art 20) export** — it's an internal access-control allow-list (admin status is controller-assigned, not subject-provided data), and its `granted_by` references another admin's user id, so exporting it to the subject would leak a third party. Admin rows are drained on account deletion (Art 17) instead. The exclusion is recorded in `exportGuardExclusions` (Go worker `personal_data_export_guard_test.go`) with a CISO/counsel-confirm note.

Four RPCs, all SECURITY DEFINER, all (except the chrome gate) hard-denying a non-admin with a `42501` before touching any report data:

- `am_i_admin()` → boolean. The only admin function in `public` (PostgREST-callable); used purely to pick page chrome — never the authorization boundary.
- `fetch_pending_reports()` → one row per reported target with pending reports: `(target_kind, target_id, report_count, reporter_count, reasons jsonb, latest_at, shadow_hidden boolean)`, newest-active first. Drives the queue; `shadow_hidden` reflects the per-kind auto-hide state so the queue can badge it + offer Unhide.
- `fetch_reports_for_target(p_target_kind, p_target_id)` → every individual report (any status) against one target, newest first.
- `resolve_target_reports(p_target_kind, p_target_id, p_status, p_resolution)` → sets all pending reports on the target to `'reviewed'`/`'dismissed'` with `reviewed_by = auth.uid()` + `reviewed_at = now()` + the note; returns the row count. Rejects an invalid status with `22023`. Triage-only.
- `admin_unhide_target(p_target_kind, p_target_id)` → clears `shadow_hidden` on a user/club/route; returns true if a row flipped. The auto-hide revert (decisions §172).

Pinned by `apps/backend/supabase/tests/admin_moderation_test.sql` (22 pgtap subtests; the load-bearing assertions are admin-allowed vs non-admin/anon-DENIED on every RPC) + `apps/web/tests-e2e/admin/reports.spec.ts`.

#### Auto-hide on reports (`shadow_hidden`, migration `20270218_001`, decisions §172)

`clubs.shadow_hidden` / `routes.shadow_hidden` / `user_profiles.shadow_hidden` (each `boolean not null default false`) are a soft, reversible hide. An AFTER INSERT trigger on `reports` calls the SECURITY DEFINER `auto_hide_target(kind, id)`, which counts DISTINCT pending reporters with **≥ 5 public runs** each (the `is_public`-run reputation gate, E3) and flips the target's `shadow_hidden` at **≥ 3** — notifying the owner once on the false→true transition with the new `content_hidden` notification kind. Only `user` / `club` / `route` participate (the function early-returns for `comment` / `club_post` / `run` — no column, manual takedown only). `auto_hide_target` has no anon/authenticated grant; the trigger is the sole caller.

Shadow-hidden rows are filtered out of every public/search/discovery surface with `and not shadow_hidden`: the `public_routes` view (cascades to `search_public_routes` / `nearby_routes` / `routes_within_box`), `discoverable_routes_in_bbox`, `search_clubs` (+ a `grant select (shadow_hidden) on clubs` for its invoker-mode rowtype projection) + `clubs_in_bbox`, `public_profile_by_id`, `search_user_profiles`. Owner + admin reads go through other paths (owner RLS / admin RPCs), so a hidden owner still sees their own row. Admins revert via `admin_unhide_target`. Pinned by `apps/backend/supabase/tests/auto_hide_reports_test.sql` (19 pgtap subtests) + `apps/web/tests-e2e/admin/auto-hide-unhide.spec.ts`.

### Clubs & events

#### `clubs` / `club_members` / `events` / `event_attendees` / `club_posts`

The social layer. See `docs/features/clubs.md` for surfaces and `docs/product/roadmap.md § Clubs and events` for phasing. Added in `20260416_001_clubs_and_events.sql`.

```sql
create table clubs (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid references auth.users not null,
  name          text not null,
  slug          text unique not null,                 -- URL-safe, generated from name
  description   text,
  avatar_url    text,
  location_label text,                                -- freeform "Austin, TX"
  location_point geography(Point, 4326),              -- ClubEditor geocodes location_label via MapTiler;
                                                      -- powers the `search_clubs` ST_DWithin branch so a
                                                      -- query like "Virginia" pulls clubs in VA even when
                                                      -- their label doesn't contain the state name.
                                                      -- Migration 20260905_001 + GIST index.
  member_count  integer not null default 0,           -- denorm of `club_members` where status='active'.
                                                      -- Maintained by trigger `clubs_member_count_trigger`
                                                      -- (migration 20260906_001). Used by `search_clubs`
                                                      -- to rank higher-membership clubs above brand-new
                                                      -- empty ones at the same geographic distance.
  is_public     boolean default true,
  is_verified   boolean default false not null,         -- Manually-verified-as-official flag.
                                                        -- `clubs.name` is intentionally NOT unique
                                                        -- (only `clubs.slug` is) — squatting on a
                                                        -- popular name shouldn't lock out the
                                                        -- official entity (e.g. the Richmond
                                                        -- Marathon). When two clubs share a name
                                                        -- on different slugs, the verified badge
                                                        -- (Icons.verified blue) on the authentic
                                                        -- club is the disambiguator users see in
                                                        -- the UI. Service-role-only flip via the
                                                        -- `clubs_protect_is_verified` trigger
                                                        -- (migration 20260909_001); no admin UI
                                                        -- in v1 — toggled via direct DB access
                                                        -- after manual moderation. Events inherit
                                                        -- verification visually from their parent
                                                        -- club; no `events.is_verified` column.
  join_policy   text not null default 'open',          -- 'open' | 'request' | 'invite' (migration 20260417_001)
  invite_token  text unique,                           -- invite-link token; see join_club_by_token (20260417_001)
  website_url   text,                                  -- "Visit our website" links (migration 20270131_001).
  instagram_url text,                                  -- Each has an http(s)-scheme CHECK (XSS backstop) and
  strava_url    text,                                  -- an explicit `grant select` (the clubs SELECT lockdown
  facebook_url  text,                                  -- 20260801_001 denies new columns by default).
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);
-- Anti-spam phase 2 (migration 20260907_001): BEFORE INSERT trigger
-- `clubs_enforce_create_rate_limit` calls `enforce_create_rate_limit`
-- which delegates to the existing `check_rate_limit` infrastructure.
-- Cap: 5 clubs / hour per owner. service_role + null-auth (migrations,
-- seed) + forged inserts (auth.uid() != owner_id, rejected by RLS
-- with 42501 anyway) all bypass the trigger so the existing RLS
-- pgtap suites still see the right errcode.

create table club_members (
  club_id     uuid references clubs on delete cascade not null,
  user_id     uuid references auth.users on delete cascade not null,
  role        text not null default 'member',         -- 'owner' | 'admin' | 'event_organiser' | 'race_director' | 'member' (CHECK: club_members_role_check)
  status      text not null default 'active',          -- 'active' | 'pending' (request-to-join queue; migration 20260417_001)
  joined_at   timestamptz default now(),
  primary key (club_id, user_id)
);

-- Events. Recurrence shipped (migration 20260417_001) — the
-- recurrence_* columns below drive weekly/biweekly/monthly series;
-- a null recurrence_freq is a one-off event.
create table events (
  id              uuid primary key default gen_random_uuid(),
  club_id         uuid references clubs on delete cascade not null,
  title           text not null,
  description     text,
  starts_at       timestamptz not null,
  duration_min    integer,
  meet_lat        double precision,                   -- SELECT revoked from anon + authenticated (see below)
  meet_lng        double precision,                   -- reachable only via get_event_meet_point() RPC
  meet_label      text,
  route_id        uuid references routes on delete set null,
  distance_m      numeric(10, 2),
  pace_target_sec integer,                            -- seconds per km
  capacity        integer,
  author_id      uuid references auth.users not null,
  recurrence_freq  text,                               -- 'weekly' | 'biweekly' | 'monthly'; null = one-off (migration 20260417_001)
  recurrence_byday text[],                             -- ISO codes 'MO'..'SU' for the weekly pattern
  recurrence_until timestamptz,                        -- series end bound
  recurrence_count integer,                            -- optional occurrence cap; null = no cap besides _until
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
  id                   uuid primary key default gen_random_uuid(),
  club_id              uuid references clubs on delete cascade not null,
  event_id             uuid references events on delete cascade,
  event_instance_start timestamptz,                    -- pins a post to one occurrence of a recurring event (migration 20260417_001)
  parent_post_id       uuid references club_posts on delete cascade,  -- threaded reply (migration 20260417_001)
  author_id            uuid references auth.users not null,
  body                 text not null,
  created_at           timestamptz default now()
);
```

**Helper functions** (RLS readability): `private.is_club_member(club_id)` and `private.is_club_admin(club_id)` — `security definer` functions that encapsulate the `club_members` lookup so every policy below can read cleanly. A trigger auto-enrolls the owner as an `owner`-role member on club insert, so the helpers work uniformly for owners too. They **live in the `private` schema** (migration `20261120_001`), which PostgREST does not expose, so they can't be probed as anon RPC oracles (audit-findings 2026-05-30 Medium); RLS policies reference them by the `private.`-qualified name (the schema move rewrites the dependency automatically).

**`events.meet_lat` / `meet_lng` are column-revoked** from both `anon` and `authenticated` (migrations `20260723_001` / `20260806_001` / `20260818_001`) — a direct `select meet_lat, meet_lng from events` raises `42501`, because precise meeting coordinates would otherwise leak an organiser's home address to any signed-in non-member of a public club. The member-facing map pin + "Get directions" link on the event detail page reads them through `get_event_meet_point(p_event_id uuid) returns table(meet_lat, meet_lng)` (migration `20261027_001`): a `security definer` function that returns the coordinates only when `is_club_member(events.club_id)` and the point is set, and zero rows otherwise. EXECUTE is granted to `anon` + `authenticated` — the in-function membership check is the authorization gate, not the EXECUTE grant. Persona-hunt social-group #10.

**`events.category` / `discipline` / `gym_template` column grants** (the typed-events surface). `events` is column-SELECT-locked (`20260818_001`), so each column added after it is deny-by-default for `anon`/`authenticated`. `20261228_001` grants `SELECT (category, discipline)` (the public category-gating + class discipline label). `20261230_001` grants `SELECT (gym_template)` — the optional `{discipline, duration_min}` jsonb hint a class host sets, read by the attendee-side "Log this as a workout" seam (it carries no PII, so a plain column grant is the right shape, not a SECURITY DEFINER RPC). `host_user_id` (payout recipient) **stays revoked** — it has no client read site. `20270111_001` adds `events.timezone` (IANA, the event's local wall-clock zone captured at create) + `grant select (timezone)` — read by the `search_public_events` discovery RPC to resolve a local time-of-day filter; a non-sensitive string, so a plain grant (not a SECURITY DEFINER RPC) is the right shape. WRITE: `20260818_001` revoked only SELECT, so the event author already writes `category`/`discipline`/`gym_template`/`timezone` through the unrestricted INSERT in `createEvent`. Pinned by pgtap `event_gym_template_grants_test.sql`.

**`search_public_events` RPC** (`20270110_001` + `20270111_001` + `20270112_001`) — the cross-club activity discovery query backing the `/social` Discover tab. `security invoker` + scoped to `clubs.is_public = true` (mirrors `search_clubs`); filters the typed-events model by category / discipline (pg_trgm index `events_discipline_trgm`) / cadence / weekday / free-or-paid / local time-of-day / **proximity**. `20270112_001` adds `p_center_lng/p_center_lat/p_radius_m` (default 50km): when a center is supplied it gates on `ST_DWithin(clubs.location_point, center, radius)` (GiST index `clubs_location_point_gist`), orders nearest-first, and returns `distance_m` for an "X away" label. Proximity filters by the **club's** public `location_point`, never the event's `meet_lat/meet_lng` (revoked to members-only via `get_event_meet_point`, `20261027_001`) — so discovery can't expose a class's exact address; clubs with a null point are excluded under an active near-me but surface on every other filter. No `SECURITY DEFINER` — the events RLS already permits reading a public club's events, so it can only return rows the caller could already see. `20270113_001` adds an explicit `e.is_public = true` filter so a members-only event is never discoverable (even by a member of its club — discovery is for the public surface). Pinned by `search_public_events_test.sql` (13 assertions).

**Event-level visibility — `events.is_public`** (`20270113_001`, decisions §148). Default `true`. The `events` SELECT policy is the single source of truth: `<club gate> AND (events.is_public OR private.is_club_member(club_id))` — so a public club can mark an individual event members-only (committee meeting, private social, draft) and it's hidden from non-members + anon + discovery, while a private club's events stay members-only via the club gate as before. Every event-delegating surface (`event_attendees`, `event_results`, `race_pings`, `run_photos` table + storage, the event photo gallery) **inherits** this automatically because each gates via an `exists (… from events …)` subquery (the caller's RLS on `events` applies inside it). The two that don't inherit were fixed in the same migration: event-tied `club_posts` (its SELECT checked the club only — re-gated to inherit event visibility for event-tied posts) and `is_event_visible` (the `SECURITY DEFINER` helper backing `event_pricing` — definer bypasses the caller's RLS, so it was leaking members-only pricing; recreated to mirror the event-level gate). Column-SELECT-locked table, so a `grant select (is_public)` was added for clients + the security-invoker discovery RPC. Pinned by `rls_events_test.sql` (23 assertions).

**`event_attendees.attendance`** (migration `20270102_001`, instructor_business.md M6) — a nullable column recording whether an attendee actually showed up (`'attended'` | `'no_show'`; NULL until a host marks it), enforced by `event_attendees_attendance_check` and overlaid as `EventAttendance` in `types.ts` (check↔union pair). It is **orthogonal to RSVP `status`** — paid/RSVP'd is not the same as attended. Writes flow ONLY through `mark_attendance(p_event_id, p_user_id, p_instance_start, p_attendance)`, a `security definer` RPC that checks `private.is_event_organiser` and touches the attendance column alone (host-written, attendee-readable via the existing SELECT policy). The `p_instance_start` predicate (migration `20270130_001`) scopes the write to a single occurrence — `event_attendees` is keyed `(event_id, user_id, instance_start)`, so the original `instance_start`-less UPDATE stamped every occurrence of a recurring class at once. The self-only RSVP UPDATE policy is left intact, but column UPDATE on `attendance` is revoked from `authenticated`/`anon` (re-granting UPDATE on `event_id`/`user_id`/`status`/`instance_start` so the RSVP upsert path is unaffected), so the RPC is the sole attendance write path.

**Narrow unions**: `ClubRole = 'owner' | 'admin' | 'event_organiser' | 'race_director' | 'member'` (enforced by the `club_members_role_check` CHECK, migration `20260428_001`, and overlaid in `types.ts`); `RsvpStatus = 'going' | 'maybe' | 'declined' | 'waitlisted'` (client-side only, no DB CHECK — `event_attendees.status` predates the narrow-union convention); `EventAttendance = 'attended' | 'no_show'` (enforced by `event_attendees_attendance_check`, migration `20270102_001`). See `apps/web/src/lib/types.ts`.

---

#### `event_results`

Per-instance event leaderboard. `finisher_status` ∈ `'finished' | 'dnf' | 'dns'`; `rank` is recomputed by `recompute_event_ranks` (called by trigger on insert/update/delete and by the race-mode auto-finalize path). Migration `20260424_001_event_results.sql`; rank tooling and approval grants in `20260428_001_role_permissions.sql`.

The table is **account-optional** (migration `20261028_001_event_results_account_optional.sql`, persona #43): the PK is a surrogate `id` and `user_id` is nullable so an organiser can bulk-import chip-timing results for finishers with no account, identified by `bib` + `finisher_name`. Two plain `UNIQUE` constraints — `(event_id, instance_start, user_id)` and `(event_id, instance_start, bib)` — keep one result per account/bib per instance (SQL NULL-distinctness means account rows never collide on bib and vice-versa) and double as the `onConflict` arbiters for the self-submit and bulk-import upserts. A CHECK forces every row to identify its finisher by an account OR a bib + name. INSERT is permitted to the row owner (`event_results_insert_self`) OR a club event-organiser (`event_results_insert_organiser`); the leaderboard read surface `event_results_redacted` exposes `id` + `bib` + `finisher_name` (public race data) while keeping `run_id` / `age_grade_pct` / `note` owner-only.

#### `event_result_claims`

Lets a registered runner claim a bib-only imported result under organiser approval (migration `20261030_001_event_result_claims.sql`, persona #43; rationale in `decisions.md § 95`). Columns: `id`, `result_id` → `event_results(id)`, `claimant_id` → `auth.users(id)`, `status` ∈ `'pending' | 'approved' | 'rejected'`, `created_at`, `decided_by`, `decided_at`; `unique (result_id, claimant_id)`. RLS SELECT: a claimant sees their own claims, an event-organiser sees claims against results on events they run. There are **no** client write policies — both writes go through SECURITY DEFINER RPCs (EXECUTE granted to `authenticated` only):

- `claim_event_result(p_result_id uuid)` — caller claims a bib-only row. Refuses already-claimed rows, events the caller can't see, and claimants who already hold a result for that `(event, instance)`; re-requesting after a rejection re-opens the claim.
- `decide_event_result_claim(p_claim_id uuid, p_approve boolean)` — organiser-only. Approval sets `event_results.user_id` to the claimant (re-validating that the row is still bib-only and the claimant has no existing result for the instance) and auto-rejects competing pending claims on the same row.

#### `race_sessions` / `race_pings`

Live race mode (Wear OS-led, decisions per roadmap §227). `race_sessions` is the per-instance state machine (`armed → running → finished | cancelled`); `race_pings` is the append-only telemetry stream (lat/lng/distance_m/elapsed_s/bpm) the watch posts during the session. Race-director / event-organiser permissions are checked by `private.is_race_director(uuid)` / `private.is_event_organiser(uuid)` SECURITY DEFINER functions (moved to the `private` schema in `20261120_001`). Migration `20260425_001_race_sessions.sql`. Stale pings are purged by the `cleanup-stale-live-run-pings` cron (see [§ pg_cron schedules](#pg_cron-schedules)).

#### Paid registration — `instructor_payout_accounts` / `event_pricing` / `event_orders` (Slice P1)

The Stripe Connect marketplace ledger (migration `20261229_001`; design in [club_events.md § Slice P](../features/club_events.md#slice-p--paid-registration)). A host (`events.host_user_id`, shipped in `20261227_001`) charges for an **in-person** event via a destination charge; the host is merchant of record, the platform takes an application fee.

- **`instructor_payout_accounts`** — `user_id` PK, `stripe_connect_account_id`, `charges_enabled` / `payouts_enabled` / `details_submitted` (mirrored from Stripe by the `account.updated` webhook), `country`, `default_currency`, `onboarded_at`. **No bank/tax/SSN data** — Stripe holds it. RLS: own-row SELECT only; there is **no client write policy**, so the row is created/maintained exclusively by the `events-connect-onboard` + `stripe-events-webhook` Edge Functions (service role). The **`stripe_connect_account_id` column is revoked** from `anon`/`authenticated` (the `get_event_meet_point` lockdown pattern) — the web UI reads the boolean capability via `host_can_take_payment(p_user_id uuid)` (SECURITY DEFINER, returns true only for a charges-enabled account), never the raw id. The row ships in the **DSAR (Art 15) export** (`instructor_payout_accounts.json`, full `*`) — it's the subject's own connected-account reference + status, and the column-grant revoke above is moot for the export, which runs as service_role over the subject's own row. Wired in both the Go worker `exportPersonalDataSpecs` (live path) and the deprecated `export-data` EF `backup_spec.ts`, pinned by their respective tests.
- **`event_pricing`** — `(event_id, instance_start)` with `instance_start IS NULL` = the series default and a non-null row overriding one occurrence (two partial unique indexes). `price_cents` (>0 CHECK), `currency`, `modality` (CHECK `in ('in_person')` — `virtual` reserved for P4), `platform_fee_bps` (0–10000 CHECK; platform config, not host-set), `refund_policy` (CHECK `in ('full_until_start','full_until_24h','no_refund')`), `sales_close_offset_minutes`. RLS SELECT: readable with the event via `is_event_visible(uuid)` (recreated in `20270113_001` to honour event-level visibility — a members-only event's pricing is hidden from non-members, since this `SECURITY DEFINER` helper bypasses the caller's RLS and would otherwise leak it); write policy: `private.is_event_organiser(club_id)`. A **BEFORE-INSERT/UPDATE trigger** (`enforce_pricing_requires_charges`) rejects the write unless the event host has a charges-enabled payout account — the `charges_enabled` gate is enforced server-side, not just in the disabled UI toggle.
- **`event_orders`** — the order ledger. `id` PK, `event_id`, `instance_start`, `buyer_user_id`, `host_user_id`, `stripe_checkout_session_id` (unique partial index — row-level webhook idempotency), `stripe_payment_intent_id`, `amount_cents`, `currency`, `platform_fee_cents`, `status` (CHECK `in ('pending','paid','refunded','partially_refunded','failed','canceled')`), `created_at`, `paid_at`, `refunded_at`, `reserved_until` (soft-reservation TTL; a sweep index keys on `status='pending'`). RLS SELECT: buyer reads own + an event organiser reads their events' orders. **Writes are service-role-only** — there is no permissive client write policy, and a BEFORE trigger (`lock_event_order_status`, mirroring `lock_subscription_columns`) raises `42501` on any non-service-role INSERT or status change. The `stripe-events-webhook` is the **sole, idempotent writer** of status (deduped on the Stripe event id via the existing `webhook_events` `(provider='stripe', event_id)` table).
- **`event_attendees.order_id`** — nullable FK → `event_orders` (NULL for free events). A BEFORE trigger (`enforce_paid_order_for_priced_event`) requires a `paid` order belonging to the buyer for a `going`/`waitlisted` row on a **priced** event (free events unaffected) — so no one can seat themselves on a paid class without a completed order.

**Narrow unions** (TS ↔ CHECK lockstep, in `check_constraint_unions.mjs` `PAIRS`): `OrderStatus`, `RefundPolicy`, `EventModality` (see `apps/web/src/lib/types.ts`). pgtap coverage: `supabase/tests/paid_events_test.sql` (pricing rejected without/with non-charges-enabled host, buyer reads only own order, organiser reads all, user-JWT cannot insert or flip order status, service role can).

#### Charity fundraising — `fundraisers` / `donations` (fundraising.md, migration `20270213_001`)

Public charity fundraising pages on a run or event, reusing the Slice-P1 Connect rail (the **same** `instructor_payout_accounts` payout account + `host_can_take_payment()`, the **same** `stripe-events-webhook` + secret — see [club_events.md](../features/club_events.md) + [decisions.md § 167](../architecture/decisions.md#167-charity-fundraising-pages-reuse-the-paid-events-stripe-connect-rail-a-fundraiser-is-polymorphic-over-run--event-donation-status-is-service-role-only-live-charges-stay-prod-gated)).

- **`fundraisers`** — `id` PK, `owner_user_id`, a nullable-FK **anchor pair** (`run_id` | `event_id`) with a `(run_id is not null) <> (event_id is not null)` CHECK (exactly one) + a partial unique index per anchor (at most one fundraiser per run/event), `charity_name`, `charity_url` (http/https CHECK), `title`, `story`, `goal_cents` (>0 CHECK), `currency`, `platform_fee_bps` (0 default — a charity donation isn't skimmed; the plumbing exists for a future fee), `status` (`FundraiserStatus` CHECK `in ('open','closed')`), `created_at`/`updated_at`. RLS SELECT: **public when the anchor is publicly visible** (`fundraiser_anchor_visible(run_id, event_id)` SECURITY DEFINER — `is_run_visible_to` for the run case, `is_event_visible` for the event case), else owner-only (fail-closed — a fundraiser on a private run is unreachable by anyone else). INSERT/UPDATE/DELETE: owner-only **and** the caller owns the anchor (owns the run / organises the event's club). A BEFORE trigger (`enforce_fundraiser_requires_charges`, mirroring `enforce_pricing_requires_charges`) rejects opening a fundraiser whose owner has no charges-enabled payout account.
- **`donations`** — the donation ledger, copying the `event_orders` discipline. `id` PK, `fundraiser_id`, `donor_user_id` (NULL = anonymous donor), `owner_user_id` (payout recipient), `display_name`, `message`, `stripe_checkout_session_id` (unique partial index — row-level webhook idempotency), `stripe_payment_intent_id`, `amount_cents` (>0 CHECK), `currency`, `platform_fee_cents`, `status` (`DonationStatus` CHECK `in ('pending','paid','refunded','failed','canceled')`), `is_anonymous`, `created_at`/`paid_at`/`refunded_at`. RLS: **no client SELECT policy** on the base table (a direct read returns zero rows); **writes are service-role-only** (the `lock_donation_status` BEFORE trigger raises `42501` on any non-service-role INSERT or status change — the `stripe-events-webhook` donation branch is the sole, idempotent CAS writer). `donor_user_id` / `owner_user_id` / `stripe_checkout_session_id` / `stripe_payment_intent_id` / `platform_fee_cents` are **revoked from `anon`/`authenticated`** (defence in depth). The public feed + thermometer are served exclusively by two SECURITY DEFINER RPCs, both anchor-visibility-gated: **`fundraiser_feed(p_fundraiser_id, p_limit)`** projects only the public-safe columns (`display_name` nulled when anonymous, `message`, `amount_cents`, `currency`, `is_anonymous`, `paid_at`) of **paid** rows; **`fundraiser_totals(p_fundraiser_id)`** returns `{ raised_cents, donor_count, goal_cents, currency }` as a `sum` (never per-row). Donations is a personal-data table covered by the existing Stripe sub-processor entry — add to the Art 20 export + Art 17 deletion with the same financial-retention caveat as `event_orders`.

**Narrow unions** (TS ↔ CHECK lockstep, in `check_constraint_unions.mjs` `PAIRS`): `FundraiserStatus`, `DonationStatus`. pgtap coverage: `supabase/tests/fundraisers_rls_test.sql` (anon reads a public-anchor fundraiser, cannot read a private-anchor one, non-owner cannot insert/close, donor-identity columns revoked), `donations_status_lock_test.sql` (user-JWT cannot write `donations.status`; feed RPC returns only public-safe columns), `fundraiser_pricing_requires_charges_test.sql` (opening a fundraiser without a charges-enabled account is rejected).

#### Session plans — `session_plans` / `session_plan_blocks` / `session_plan_items` (session_planner.md P1)

Reusable yoga/pilates/class movement sequences (a sibling of the gym routine engine — see [decisions.md § 140](../architecture/decisions.md)). Migration `20270103_001`.

- **`session_plans`** — `id` PK, `author_id` (FK → `auth.users`, the creator), `club_id` (nullable FK → `clubs`, cascade; set when a club owns the plan, mirroring `routes.club_id`), `title`, `discipline` (free text), `equipment` (nullable), `est_duration_min` (nullable cached estimate, recomputed client-side on save), `is_public` (default false), `created_at`, `updated_at`. RLS: author owns own (`auth.uid() = author_id`, all ops); `is_public = true` world-readable; club-owned readable by `private.is_club_member(club_id)` + writable by `private.is_club_admin(club_id)` — the club-owned-routes pattern (`20260520_001`).
- **`session_plan_blocks`** — `id` PK, `plan_id` (FK, cascade), `position` (int), `name` (nullable — a flat plan has no blocks). RLS inherits the parent plan's visibility (a single FOR ALL policy keyed on the parent's author/public/member predicate, with WITH CHECK gating writes to author-or-club-admin).
- **`session_plan_items`** — `id` PK, `plan_id` (FK, cascade), `block_id` (nullable FK → blocks, cascade), `position`, `movement_name`, `kind` (CHECK `in ('hold','reps','flow')` — narrow union `SessionItemKind`, in `check_constraint_unions.mjs`), `duration_s` (nullable, for hold/flow), `reps` (nullable, for reps), `per_side` (default false — split into L/R at expand time by `expandSessionSteps`), `tempo` (nullable), `cue` (nullable). RLS inherits the parent.
- **`events.session_plan_id`** — nullable FK → `session_plans` (`on delete set null`). A `class` event optionally attaches a full sequence (the rich successor to the `gym_template` jsonb hint). Set **only by an event organiser** — the `enforce_event_session_plan_organiser` BEFORE trigger raises `42501` for a non-organiser (defence-in-depth behind the events UPDATE RLS), with a trusted-caller bypass for the service role + direct SQL. The column carries an explicit `grant select (session_plan_id) ... to authenticated, anon` because `events` is under a column-level SELECT lockdown.

**Narrow union**: `SessionItemKind = 'hold' | 'reps' | 'flow'`. pgtap coverage: `supabase/tests/session_plans_rls_test.sql` (author own read/write, public world-read, club member-read / admin-write, the kind CHECK, organiser-only `events.session_plan_id`); `clone_session_template_test.sql` (club-member adopt, copy fidelity, non-member reject).

**Sharing (P3, 2026-06-12)**: `is_public = true` powers the logged-out web share page `/share/session/[id]` — anon SELECT grants on the three tables + the public-plan / inherit-visibility policies already expose a public plan's blocks/items, so no migration was needed beyond the P1 schema. `setSessionPlanPublic` (web + `ApiClient.setSessionPlanPublic` mobile) is the owner-only toggle. A `club_id`-set plan is the club's adoptable "session template"; `clone_session_template` is the adopt path (above).

### Training & coaching

#### `training_plans` / `plan_weeks` / `plan_workouts`

Generated training plans + week phasing + scheduled workouts. Owner-only RLS, deep cascading on plan delete. Plans can be cloned from a club-shared template via `clone_plan_template` (decisions §35) or from the **public plan library** via `clone_public_plan` (migration `20270126_001`); a single week can be repeated via `duplicate_plan_week` (atomic re-index, migration `20261205_001`); workouts link back to the run that completed them via `plan_workouts.completed_run_id`. **`training_plans.is_public_template boolean not null default false`** (migration `20270126_001`) marks a publisher-owned, anyone-can-clone template, orthogonal to the club-scoped `is_template + club_id`; the `training_plans_public_requires_template` CHECK enforces `is_public_template ⇒ is_template`, so a public-library plan reuses the template plumbing (active-status CHECK, one-active index, weeks/workouts visibility). Additive SELECT policies `"anyone reads public plan templates"` (training_plans) + `"anyone reads public template weeks"` (plan_weeks) + `"anyone reads public template workouts"` (plan_workouts) — each gated on `is_public_template = true and auth.role() = 'authenticated'` — let any signed-in user preview a public template for clone, while non-public plans stay owner/club/coach-only; no runs or PII are reachable through these policies. A `plan_workouts.skipped_at timestamptz` (migration `20270125_001`, null = not skipped) records a deliberately skipped session — mutually exclusive with completion, excluded from the progress denominator + the missed-long-run callout (see [training.md § Skipping a workout](../features/training.md)). Migrations `20260419_001_training_plans.sql` (schema), `20260420_001_plan_workouts_workout_kind.sql`, `20260421_001_plan_workouts_structure.sql`, `20260524_001_plan_template_sharing.sql`, `20260510_001_plan_workout_completion.sql`, `20270125_001_plan_workout_skipped.sql`, `20270126_001_public_plan_library.sql`. Engine + week-grid UI: [docs/features/training.md](../features/training.md). Live execution: [docs/features/workout_execution.md](../features/workout_execution.md).

**`training_plans.notes` on club templates** (`is_template = true` AND `club_id` is set): when a member adopts a template via `clone_plan_template`, the template's `notes` field is copied verbatim onto the new plan. On a private (owner-only) plan, `notes` is the runner's own free-text scratchpad. On a club template it becomes member-readable — anyone in the club who can `select * from training_plans where is_template = true and club_id = <X>` sees it. **Public-template-safe** is the documented contract: don't write a runner-private note onto a template. The publish flow (`publishPlanAsTemplate` in `data.ts`) explicitly nulls `vdot` and `current_5k_seconds` per migration `20260721_001`; a future tightening could add `notes` to that null-list, but until a template author writes a private note in production we keep the field carryable for legitimate "warm-up note" content.

#### `user_coach_usage`

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

#### `coach_messages`

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

### Profile, settings & devices

#### `user_profiles`

Supplementary user data not stored in `auth.users`. As of `20260521_001_user_follows.sql` profiles are world-readable to authenticated users (the new `"profiles are readable by anyone authenticated"` policy is additive to the existing self-only `"users own their profile"`). This is required for follow / feed / club-member rendering and was a latent bug fix — pre-migration, all cross-user enrichment queries silently returned empty rows. See `docs/architecture/decisions.md § 31` for the trade-off.

`subscription_tier` and `subscription_at` are write-protected against user-JWT writers. The catch-all `users own their profile` policy was split into per-command policies in `20260624_001_lock_subscription_tier_to_service_role.sql`, and a `BEFORE UPDATE` trigger (`lock_subscription_columns`) raises 42501 (`insufficient_privilege`) on any tier-column change whose JWT role isn't `service_role`. Direct SQL (migrations + seed) bypasses the trigger because no JWT context is set. The only legitimate runtime writer is the `revenuecat-webhook` Edge Function (service-role).

```sql
create table user_profiles (
  id                       uuid primary key references auth.users,
  display_name             text,
  avatar_url               text,
  parkrun_number           text,                                -- e.g. 'A123456' (world-readable)
  preferred_unit           text default 'km',                   -- 'km' | 'mi'
  subscription_tier        text default 'free',                 -- 'free' | 'pro' | 'lifetime' (world-readable)
  subscription_at          timestamptz,
  gender                   text,                                -- 'male' | 'female' | 'nonbinary' | null
  date_of_birth            date,
  height_cm                numeric(5,1),                        -- nutrition BMR (20261216_001); owner-only, off the public-safe grant
  coach_consent_at         timestamptz,                         -- GDPR Art 6(1)(a) — gates /api/coach
  health_data_consent_at   timestamptz,                         -- GDPR Art 9(2)(a) — gates gender + DOB + height + weight persistence
  created_at               timestamptz default now()
);
-- CHECK constraint enforces subscription_tier ∈ ('free','pro','lifetime') —
-- migration 20260429_001_subscription_paywall.sql backfills any pre-existing
-- 'premium' values to 'pro'. Keep this list in lockstep with the
-- SubscriptionTier TS union in apps/web/src/lib/types.ts.
--
-- `coach_consent_at` and `health_data_consent_at` were added in
-- 20260921_001_user_profiles_gdpr_consent_timestamps.sql per
-- audit/gdpr (2026-05-25). Both nullable; NULL = consent not yet
-- given. The /api/coach handler refuses to fan out to Anthropic
-- when coach_consent_at is null; the Preferences page refuses to
-- persist gender / DOB when health_data_consent_at is null and the
-- consent checkbox is unticked. Withdrawal under Art 7(3) nulls
-- the consent timestamp AND clears the associated fields atomically.
--
-- BOTH consent timestamps are server-stamped + tamper-resistant. The
-- GRANT path goes through a SECURITY DEFINER RPC that stamps the
-- server's now() (first-stamp-wins): record_coach_consent()
-- (20261110_001) and grant_health_data_consent() (20261118_001). The
-- shared lock_consent_columns BEFORE-UPDATE trigger blocks a direct
-- end-user write that SETS either timestamp to a non-null value, so a
-- client can't backdate or forge the affirmative act. A direct NULL
-- write (the Art 7(3) withdrawal) stays allowed for health-data
-- consent; coach consent is one-way (cleared only on account deletion).
```

`height_cm` (migration `20261216_001`, nutrition BMR) is **special-category health data** and shares the `gender`/`date_of_birth` posture: it is **owner-only** — not on the `20260707_001` public-safe column grant, so it's read back through `get_my_profile()` and never exposed to other authenticated callers or anon — and its persistence is gated on `health_data_consent_at` at the client layer, exactly like gender/DOB. Same for the `body_metrics` weight series below.

#### `body_metrics`

Weight time-series for the nutrition Mifflin-St Jeor BMR target (migration `20261216_001`). Weight is a **time-series**, not a single mutable column, because a trend matters and a column loses history. **GDPR special-category health data**: owner-only RLS (no public-read policy — unlike `gym_workouts` / `food_log`), cascade-deletes from `auth.users`, gated on `health_data_consent_at` at the client layer, and must be in the DSAR export path (G1/G6).

```sql
create table body_metrics (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade not null,
  recorded_at  timestamptz not null default now(),
  weight_kg    numeric(5,2) not null check (weight_kg > 0 and weight_kg <= 500),
  created_at   timestamptz not null default now()
);
-- index (user_id, recorded_at desc); RLS: owner-only for all four commands.
```

RLS + range CHECK + cascade-delete + the owner-only `height_cm` grant are pinned by `body_metrics_rls_test.sql`.

#### `gym_routines` / `gym_routine_exercises` / `gym_routine_sets`

The gym-programming **P1** reusable-plan tier (migration `20270101_001`, [gym_programming.md](../features/gym_programming.md)). A routine is a named, ordered list of planned exercises, each with planned target sets — **relational, not jsonb** (the deliberate divergence from `plan_workouts.structure jsonb`, justified by per-exercise querying + row-by-row progression). It is **not** a dated activity, so it does **not** feed the `activities` view.

- `gym_routines` — owner column is **`author_id`** (authored content, F17), **author-only RLS** for write + the base read; two additive SELECT branches widen read without replacing it (Postgres ORs permissive policies): a club-member read for club-owned templates (`20270109_001`) and an `is_public_template = true and auth.role() = 'authenticated'` public read for the public library (`20270226_001`). `is_public_template boolean not null default false` (migration `20270226_001`) marks a publisher-owned, anyone-can-adopt template; the `gym_routines_public_not_club` CHECK (`is_public_template ⇒ club_id is null`) keeps public and club visibility strictly separable. `exercise_count` + `last_modified_at` are **client-stamped** (non-authoritative cache, newer-wins; no server trigger). Cascade-deletes from `auth.users` (Art. 17). Indexes `(author_id, last_modified_at desc)` + `(club_id, last_modified_at desc) where club_id not null` + `(last_modified_at desc) where is_public_template` + unique `(author_id, external_id) where external_id not null`.
- `gym_routine_exercises` — `exercise_key` = `normaliseExerciseName(exercise_name)` stamped at write time (binds the plan to logged `gym_sets`); `position` orders the groups; `superset_group`/`superset_order` exist for P2 but P1 leaves them null (paired-null CHECK). RLS via `EXISTS` against the parent routine's `author_id`.
- `gym_routine_sets` — planned targets per set: `target_reps_min`/`_max` (single value = min only), `target_weight_kg` **XOR** `target_percent_1rm` (load-mutex CHECK), `target_rpe`, `rest_s`, `tempo`, `set_type` (default `working`). RLS via `EXISTS` up through `gym_routine_exercises` → `gym_routines.author_id`.
- Four narrow-union ↔ CHECK pairs land here (`periodisation`, `modality`, `progression`, `set_type`); only the columns ship in P1, the engine that reads them is P2-P4.
- The plan→logged-session link lives in `gym_workouts.metadata.routine_id` (a string, **not** an FK), added by the same migration — so deleting a routine leaves prior sessions intact. `gym_workouts.metadata` (jsonb, default `'{}'`) is added here as the prerequisite; the `activities` lift branch enumerates explicit columns so the new column does not change the UNION shape.

Author-only RLS on all three tables + the EXISTS parent gates + the full-tree cascade from `auth.users` are pinned by `gym_routines_rls_test.sql`. The three tables (+ nested embeds) ship in the DSAR export (`export-data` `backup_spec.ts`, pinned by `backup_spec.test.ts`).

**Club templates (migration `20270109_001`, decisions §145).** `gym_routines.club_id` (nullable FK → `clubs`, `on delete cascade`) makes a routine **club-owned** — a publishable template. Added RLS (alongside, not replacing, the author-only policies — Postgres ORs permissive policies): club members read the routine + its exercises/sets children (`club_id is not null and private.is_club_member(club_id)`); club admins may update/delete (unpublish) but **not** insert (publishing is the gated RPC below, so an admin can't inject a foreign `author_id`). Two SECURITY DEFINER RPCs (`search_path = public, private`, revoked from PUBLIC, granted to `authenticated`): `publish_gym_routine_as_template(p_routine_id, p_club_id)` — author + `is_club_admin` gated, rate-limited, deep-copies the routine + exercises + sets into a new club-owned routine (the personal original is untouched); `clone_gym_routine_template(p_template_id)` — author-or-`is_club_member`-or-`is_public_template` gated, rate-limited, deep-copies into a personal, club-less, non-public routine. Pinned by `gym_routine_club_templates_test.sql` (13 tests).

**Public library (migration `20270226_001`, decisions §182).** The anyone-can-adopt counterpart, the gym-routine analogue of the public PLAN library (`clone_public_plan`). `gym_routines.is_public_template` + the `gym_routines_public_not_club` CHECK (public ⇒ not club-owned) + additive public-read SELECT policies `"gym_routines public templates read"` / `"gym_routine_exercises public templates read"` / `"gym_routine_sets public templates read"` (each gated on the parent's `is_public_template = true and auth.role() = 'authenticated'`). `clone_gym_routine_template` gained a third authorisation branch so any signed-in caller adopts a public template (same rate limit + deep-copy; the clone is personal, `club_id` null, `is_public_template` false). `set_gym_routine_public(p_routine_id, p_public)` — SECURITY DEFINER, author-gated, refuses a club-owned routine — flips `is_public_template` on the routine itself (the routine IS the template, no deep-copy). A gym routine carries no private fitness data (targets are the published prescription), so nothing is stripped on publish/clone. Granted to `authenticated`; pinned by `public_gym_routine_library_test.sql` (9 tests). Surfaced as `/gym/routines/library` + the routine-detail publish toggle on web + `RoutinePublicLibraryScreen` + the publish toggle on mobile.

#### `user_settings` / `user_device_settings`

Settings registry. `user_settings.prefs` is a single jsonb bag keyed off `user_id` for **universal** preferences (notification opt-ins, privacy zones, units carry-overs from the legacy `user_profiles` columns). `user_device_settings` keys on `(user_id, device_id)` for **per-device** overrides (push subscription endpoint per browser, sound on/off per watch, etc.). RLS owner-only on both. Migration `20260422_001_user_settings.sql`. The TypeScript helpers `loadSettings()` + `effective<T>()` in `apps/web/src/lib/settings/settings.ts` resolve a per-key value as `device_override ?? user_value ?? default`. See [docs/backend/settings.md](settings.md) for the registered key catalogue.

#### `device_tokens`

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
  is_notifications_enabled  boolean not null default true,
  last_seen_at           timestamptz not null default now(),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (user_id, token)
);
```

Indexes: `device_tokens_active` (partial index on `user_id` where
`is_notifications_enabled`, the fan-out read shape) and
`device_tokens_platform` (for platform-wide audits). RLS scopes reads /
writes to `auth.uid() = user_id`; the push worker reads with the
service-role key to fan out. A trigger touches `updated_at` on update.

#### `safety_contacts`

Opt-in contacts emailed when their owner finishes a run — **even a private
one** — so someone trusted knows the runner got back safely (migration
`20261218_001`, [decisions.md § 131](../architecture/decisions.md)). A distinct
feature from the `run_completed` follower fan-out, which stays gated on
`is_public` by design.

```sql
create table safety_contacts (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id) on delete cascade,
  contact_user_id uuid references auth.users(id) on delete cascade, -- linked on confirm
  contact_email   text not null,        -- the identity; alerts go here
  confirmed_at    timestamptz,          -- the contact's opt-in (NULL = pending)
  confirm_token   uuid not null default gen_random_uuid(), -- email-link capability
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (contact_email ~* '...email...'),
  check (contact_user_id is null or contact_user_id <> owner_id)  -- not_self
);
-- unique (owner_id, lower(contact_email)); index on contact_user_id, confirm_token.
```

**Double opt-in.** The owner's consent is implicit in creating the row; the
contact's is `confirmed_at`. A contact is identified by **email only** at add
time (storing/looking-up a `user_id` then would leak account existence — an
enumeration vector); `contact_user_id` is filled when an app-user contact
confirms in-app, which enables the contact-side cascade-delete and localizes
their alert.

**RLS.** Owner: `select` / `insert` / `delete` on their own rows — **no owner
`UPDATE`** policy, so an owner can never self-confirm a contact. A linked
contact (`contact_user_id = auth.uid()`) gets `select` + `delete` (withdraw).
A BEFORE INSERT trigger forces `confirmed_at` / `contact_user_id` null as
defense in depth.

**RPCs** (all `SECURITY DEFINER`):
- `my_pending_safety_requests()` → pending rows whose `contact_email` matches
  the caller's account email (the email→row match needs an `auth.users` read);
  returns only the caller's own matches, so it leaks nothing.
- `confirm_safety_contact(p_id)` — an app user confirms + links a pending row
  addressed to their email.
- `decline_safety_contact(p_id)` — decline a pending request / withdraw from a
  confirmed one (covers the pre-link case the contact DELETE policy can't).
- `confirm_safety_contact_by_token(p_token)` — unauthenticated email-link
  confirm for external contacts (`anon`-callable; the v4 token is the
  capability).

**Triggers.** AFTER INSERT on `safety_contacts` enqueues a `safety_email`
`confirm` job; AFTER INSERT on `runs` enqueues a `safety_email` `finish` job
per **confirmed** contact regardless of `is_public`, with the same 24h recency
guard `run_completed` uses. See [email.md](../features/email.md).

Pinned by `safety_contacts_test.sql` (RLS isolation, no-owner-UPDATE, the
force-unconfirmed guard, both confirm paths, the finish/confirm enqueues, the
unconfirmed-contact-no-alert + bulk-import-skip cases). Account **deletion**
(Art 17) is covered by the FK cascades; the Art 20 **export** of this table is
a tracked follow-up (the export-guard keys on a literal `user_id` column, which
this table doesn't carry, so it isn't auto-flagged).

---

### Fitness & analytics

#### `personal_records`

Cache table for per-distance PBs (`1_mile` / `5k` / `10k` / `half_marathon` /
`marathon`; the mile bracket was added in `20261021_001`). Backed by triggers on `runs` so reads are a single indexed
lookup instead of the full aggregation that
[`personal_records()`](#personal_records-1) does. Shipped in migration
`20260508_001_personal_records_cache.sql`. The existing
`personal_records()` SQL function stays in place for callers that
haven't migrated.

```sql
create table personal_records (
  user_id       uuid not null references auth.users(id) on delete cascade,
  distance      text not null check (distance in ('1_mile', '5k', '10k', 'half_marathon', 'marathon')),
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

#### `achievements`

Persisted badge awards (one row per `(user_id, badge_key, tier)`; the unique
constraint lets a user accumulate tier history — earning silver later does not
revoke the bronze). Shipped in `20270208_001_achievements.sql`. The badge
*catalogue* (what badges exist + their thresholds) lives in code
(`apps/web/src/lib/social/badges.ts`), not the DB — this table stores only
awards.

```sql
create table achievements (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  badge_key   text not null,            -- matches a catalogue entry id
  tier        text not null default 'bronze'
                check (tier in ('bronze','silver','gold','platinum')),
  source_kind text not null
                check (source_kind in ('pr','segment','streak','distance','plan')),
  source_id   uuid,                     -- the run/effort/plan that triggered it (null for aggregates)
  value_num   double precision,         -- the numeric that earned it (display + dedupe)
  earned_at   timestamptz not null default now(),
  is_public   boolean not null default true,
  constraint achievements_user_badge_uk unique (user_id, badge_key, tier)
);
```

`tier` + `source_kind` are narrow-union CHECK columns kept in lockstep with the
`AchievementTier` / `AchievementSourceKind` TS unions via `check_constraint_unions.mjs`.

**RLS:** `achievements_self_select` (owner reads own, incl. private) +
`achievements_public_select` (`is_public = true` — the share page + a follower's
feed/profile read public badges of others; fail-closed, no public policy = no
leak) + owner-only `achievements_owner_update` (the `is_public` toggle). **No
client INSERT/DELETE** — awards are written only by the award function below
(mirrors `personal_records`). `grant ... to postgres` for the definer-owner.

**Award function:** `award_achievements_for_user(p_user)` — SECURITY DEFINER,
recomputes the full earned set (longest-run + lifetime distance off `runs`,
best streak off run days, PR count off `personal_records`, completed-plan count
off `training_plans`) and `insert ... on conflict do nothing`s the new awards,
**returning only the newly-inserted rows**. Thresholds duplicate the
`badges.ts` catalogue (the lockstep contract; `achievements_test.sql` pins it).
A `pg_advisory_xact_lock` per user serialises concurrent fires. Triggers
`runs_award_achievements` / `personal_records_award_achievements` /
`training_plans_award_achievements` dispatch on the source tables; a
`notify_achievement_earned` AFTER-INSERT trigger on `achievements` writes an
owner notification (`kind = 'achievement'`, linked via the new
`notifications.achievement_id` FK) for each new award. Backfill runs once in the
migration tail over all existing users. See [features/achievements.md](../features/achievements.md)
+ [decisions.md § 164](../architecture/decisions.md).

---

#### `fitness_snapshots`

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

#### `mv_weekly_mileage`

Materialized view that pre-aggregates `runs` into `(user_id, week_start) → (total_distance_m, run_count)` so the `weekly_mileage` RPC and the dashboard's "This Week" card stay sub-millisecond as the runs table grows. Refreshed every five minutes by the `refresh-mv-weekly-mileage` pg_cron job (`refresh materialized view concurrently` — non-blocking thanks to the `mv_weekly_mileage_pk` unique index). Migrations: created in the seed-route + index pass, refresh schedule in `20260602_001_mv_weekly_mileage_refresh.sql`, EXECUTE revoke in `20260517_001_mv_weekly_mileage_revoke.sql` (callers go through the RPC, not direct SELECT).

### Integrations & background jobs

#### `integrations`

OAuth tokens and connection state for each external platform per user.

```sql
create table integrations (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid references auth.users not null,
  provider                 text not null,            -- 'strava' | 'garmin' | 'parkrun' | 'runsignup'
  access_token_secret_id   uuid references vault.secrets(id) on delete set null,
  refresh_token_secret_id  uuid references vault.secrets(id) on delete set null,
  token_expiry             timestamptz,
  external_id              text,                     -- athlete ID on the provider
  scope                    text,                     -- OAuth scopes granted
  last_sync_at             timestamptz,
  sync_cursor              text,                     -- pagination cursor for backfill
  created_at               timestamptz default now(),
  updated_at               timestamptz default now(),
  unique (user_id, provider)
);
```

**Tokens live in Supabase Vault, not on the row.** OAuth access / refresh
tokens are encrypted at rest by Supabase Vault (libsodium, project-managed
master key with built-in rotation). The `integrations` row carries only
UUID references into `vault.secrets`. Never `select access_token from
integrations` — that column was dropped in migration `20260603_001`.

To read or write tokens, call the SECURITY DEFINER helpers:

- `get_integration_tokens(p_user_id, p_provider)` returns
  `(access_token text, refresh_token text, token_expiry timestamptz)`.
  Service role bypasses the owner check; everyone else can only read
  their own.
- `set_integration_tokens(p_user_id, p_provider, p_access, p_refresh, p_expiry)`
  upserts the row + creates / updates the vault secrets in place
  (so `access_token_secret_id` stays stable across token refreshes).

---

#### `jobs`

Generic Postgres-backed job queue. First tenant was map matching (`kind = 'map_match'`); it now also hosts the Strava webhook ingest (`kind = 'strava_event'`) and hourly token rotation (`kind = 'token_refresh'`) that moved off Edge Functions (see `roadmap.md` Phase 2 backend bullets). Data export moved to the Go worker too but as a synchronous HTTP endpoint (`POST /v1/export`), not a job kind, since the user blocks on a signed URL.

```sql
create table jobs (
  id bigint generated always as identity primary key,
  kind text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued',
  attempts smallint not null default 0,
  max_attempts smallint not null default 5,
  scheduled_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  finished_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint jobs_status_check
    check (status in ('queued', 'running', 'done', 'failed', 'cancelled')),
  constraint jobs_attempts_nonneg check (attempts >= 0),
  constraint jobs_max_attempts_pos check (max_attempts > 0)
);

create index jobs_queued
  on jobs (scheduled_at, kind)
  where status = 'queued';

create index jobs_running
  on jobs (locked_at)
  where status = 'running';

-- Idempotency: while a previous map_match for the same run_id is still
-- queued or running, a re-enqueue is a no-op via ON CONFLICT.
create unique index jobs_dedupe_map_match
  on jobs (kind, ((payload->>'run_id')::uuid))
  where kind = 'map_match' and status in ('queued', 'running');
```

- **RLS**: deny everything — no policies, anon/authenticated cannot touch the table. Service role bypasses RLS for direct queries; the SECURITY DEFINER functions below are the typed surface for everything else.
- **Worker API**: `claim_next_job(worker_id, kind_filter)`, `finish_job(job_id, result_status, err)`, `defer_job(job_id, delay_seconds, err)`. PUBLIC EXECUTE is revoked; only `service_role` is granted. See [§ Database functions](#database-functions-rpcs).
- **Concurrency**: `claim_next_job` uses `for update skip locked` so multiple workers can drain in parallel without thrashing each other on the same row.
- **Partial indexes**: the `jobs_queued` and `jobs_running` indexes are partial so queue size scales with the *active* set, not the cumulative job count. The `jobs_dedupe_map_match` index is also partial — once a job finishes, its row is no longer in the unique constraint, so a re-match becomes possible.

#### `live_run_pings`

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

### Billing

#### `monthly_funding`

Monthly funding tracker for the donate page's progress bar. One row per month, keyed by the first of the month (e.g. `'2026-05-01'`). Updated by the project owner when donations land. Publicly readable — the whole point is transparency.

Write path: service role only. RLS is enabled with a single `select` policy (`using (true)`); there are no INSERT/UPDATE/DELETE policies by design. All writes go through direct SQL or a service-role context (e.g. a webhook or admin script). No client-side write policy will be added. A `monthly_funding_updated_at_trigger` BEFORE-UPDATE trigger stamps `updated_at` on every write (`20261129_001`) so the donate page's "last updated" signal stays honest even on a manual amount bump.

```sql
create table monthly_funding (
  month             date primary key,
  amount_received   numeric(10,2) not null default 0,
  donor_count       integer not null default 0,
  updated_at        timestamptz not null default now()
);
```

---

### Infrastructure

#### `rate_limits`

Per-user fixed-window counters that gate Edge Function endpoints. Read/written exclusively through the `check_rate_limit` SECURITY DEFINER function — never direct SELECT/INSERT.

```sql
create table rate_limits (
  user_id        uuid not null,
  bucket         text not null,           -- e.g. 'parkrun-import'
  window_start   timestamptz not null,    -- floor(epoch / window) * window
  count          integer not null default 0,
  primary key (user_id, bucket, window_start)
);
```

`check_rate_limit(p_user_id, p_bucket, p_max, p_window_seconds) returns table(allowed bool, retry_after_seconds int)` — atomic increment-and-check; even denied calls increment, but the user just stays at ceiling+N until the window rolls (no extra punishment). Cron job `cleanup-stale-rate-limits` deletes rows older than 24 h hourly. RLS is enabled with no policies so direct REST access returns zero rows; the EF helper bypasses RLS via the SECURITY DEFINER grant.

---

#### pg_cron schedules

| Job | Schedule | What it does | Migration |
|---|---|---|---|
| `refresh-mv-weekly-mileage` | `*/15 * * * *` | `refresh materialized view concurrently mv_weekly_mileage`. Original schedule was `*/5` (set in `20260602_001`); bumped to `*/15` in `20260706_001` after the cost-controls audit flagged the cadence as the dominant Supabase background-compute draw. | `20260602_001` → `20260706_001` |
| `cleanup-stale-live-run-pings` | `*/15 * * * *` | Calls `cleanup_stale_live_run_pings()` to delete `live_run_pings` rows older than the retention window — keeps the spectator feed table bounded during a multi-hour event. | `20260602_001` |
| `cleanup-stale-rate-limits` | `0 * * * *` (hourly) | Calls `cleanup_stale_rate_limits()` to GC elapsed `rate_limits` rows. | `20260604_001` |
| `cleanup-stale-webhook-events` | `17 4 * * *` | Deletes `webhook_events` rows older than 30 days (RevenueCat/Stripe replay-dedupe table). | `20260623_001` |
| `cleanup-stale-export-blobs` | `23 4 * * *` | Calls `cleanup_stale_export_blobs()` to remove expired data-export artifacts. | `20260720_001` |
| `jobs-stuck-alert` | `*/10 * * * *` | Calls `jobs_stuck_summary()` — surfaces wedged `running` jobs for the observability scraper. | `20260731_001` |
| `enqueue-token-refresh` | `0 * * * *` | Inserts a `token_refresh` job into `jobs` for the Go worker (dedupe-safe: skips if a queued/running one exists). | `20260821_001` |
| `purge-stale-coach-messages` | `17 3 * * *` | Calls `private.purge_stale_coach_messages()` (retention purge). | `20260922_001` |
| `purge-stale-notifications` | `23 3 * * *` | Calls `private.purge_stale_notifications()`. | `20260922_001` |
| `purge-stale-device-tokens` | `29 3 * * *` | Calls `private.purge_stale_device_tokens()`. | `20260922_001` |
| `purge-stale-jobs` | `35 3 * * *` | Calls `private.purge_stale_jobs()` (GDPR DSAR close-out retention). | `20260928_001` |
| `cleanup-stale-app-quota` | `15 4 * * *` | Deletes `app_quota` rows older than 2 days (Strava app-level rate-limit window). | `20261007_001` |
| `purge-stale-direct-messages` | `41 3 * * *` | Calls `private.purge_stale_direct_messages()`. | `20261119_001` |
| `enqueue-event-reminders` | `0 * * * *` | Calls `enqueue_event_reminders()` to fan out upcoming-event reminder emails. | `20261130_001` |
| `jobs-failed-alert` | `*/10 * * * *` | Calls `jobs_failed_summary()` — surfaces terminally-failed jobs for the observability scraper. | `20261201_001` |
| `cleanup-stale-race-pings` | `*/30 * * * *` | Calls `cleanup_stale_race_pings()` (race-mode ping retention). | `20261213_001` |
| `cleanup-stale-user-coach-usage` | `17 * * * *` | Calls `cleanup_stale_user_coach_usage()` (coach-usage counter retention). | `20261215_001` |

The scheduled functions are EXECUTE-revoked from PUBLIC where applicable; the cron extension runs as superuser. The mv-refresh + live-run-ping cleanup live in `20260602_001_pg_cron_schedules.sql` (the mv refresh is re-scheduled in `20260706_001_pg_cron_mv_refresh_15min.sql`); the rate-limit cleanup is in `20260604_001_rate_limits.sql`. Each remaining row's migration is listed in the table.

---

### Race-director checkpoints

#### `event_checkpoints` / `checkpoint_crossings`

Offline aid-station check-in → live results + cutoff projection. Added in `20270201_001_race_director_checkpoints.sql`. See `docs/features/race_director_ops.md` and decisions §154.

```sql
create table event_checkpoints (
  id                uuid primary key default gen_random_uuid(),
  event_id          uuid not null references events(id) on delete cascade,
  name              text not null,                       -- 1..120 chars (CHECK)
  ordinal           integer not null,                    -- course order; UNIQUE (event_id, ordinal)
  route_marker_id   uuid references route_markers(id) on delete set null,
  position_m        numeric(10, 2),                      -- distance along course, optional
  cutoff_elapsed_s  integer,                             -- cutoff as elapsed s from start; >= 0 (CHECK)
  cutoff_clock      text,                                -- 'HH:MM' wall-clock cutoff (CHECK regex)
  requires_weigh_in boolean not null default false,      -- arms the Art 9 health path at this checkpoint
  created_by        uuid references auth.users not null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table checkpoint_crossings (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references events(id) on delete cascade,
  checkpoint_id   uuid not null references event_checkpoints(id) on delete cascade,
  instance_start  timestamptz not null,
  user_id         uuid references auth.users on delete set null,  -- account-optional identity:
  bib             text,                                           --   user_id OR bib+runner_name
  runner_name     text,                                           --   (CHECK requires at least one)
  in_time         timestamptz,
  out_time        timestamptz,
  -- Art 9 health columns — column-SELECT-locked from anon/authenticated:
  body_weight_kg  numeric(5, 2),                          -- 20..400 (CHECK)
  body_weight_pct numeric(5, 2),
  medical_hold    boolean not null default false,
  medical_note    text,
  recorded_by     uuid references auth.users on delete set null,
  recorded_at     timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint checkpoint_crossings_identity_chk
    check (user_id is not null or bib is not null),
  constraint checkpoint_crossings_account_uniq
    unique (event_id, checkpoint_id, instance_start, user_id),   -- NULLs-distinct
  constraint checkpoint_crossings_bib_uniq
    unique (event_id, checkpoint_id, instance_start, bib)        -- NULLs-distinct
);
```

**RLS / grants.**
- `event_checkpoints`: SELECT per `is_event_visible(event_id)`; INSERT/UPDATE/DELETE gated on `private.is_event_organiser(events.club_id)`.
- `checkpoint_crossings`: SELECT per `is_event_visible(event_id)`. There is **no INSERT/UPDATE/DELETE policy — all writes go through `upsert_checkpoint_crossing`** (the single SECURITY DEFINER writer), so the merge logic can't be bypassed by a raw write.
- **Column-SELECT-lock:** the table default is revoked and only the non-health columns (`id, event_id, checkpoint_id, instance_start, user_id, bib, runner_name, in_time, out_time, recorded_at, updated_at`) are re-granted to `anon, authenticated`. The Art 9 columns (`body_weight_kg, body_weight_pct, medical_hold, medical_note`) + `recorded_by` are then deny-by-default; organisers read them only through `fetch_checkpoint_crossings_for_organiser`.

---

### Other shipped tables (summary)

These tables ship in the live schema but don't have a full column-by-column block above. Each is listed with its purpose, defining migration, and a one-line column summary; read the migration for the exact DDL, constraints, and RLS.

| Table | Migration | Purpose / column summary |
|---|---|---|
| `gym_workouts` | `20261204_001` | Phase-4 gym session header. `id, user_id, title, started_at, duration_s, notes, is_public, external_id, last_modified_at, created_at`. |
| `gym_sets` | `20261204_001` | One row per logged set, child of `gym_workouts`. `id, workout_id, set_index, exercise_name, reps, weight_kg, rpe` (`duration_s` added later for timed holds — instructor_business.md M2). Weights canonical kg. |
| `food_log` | `20261204_001` | Phase-4 nutrition entries. `id, user_id, logged_at, item_name, meal_slot ('breakfast'/'lunch'/'dinner'/'snack'), calories, protein_g, carbs_g, fat_g, is_public, external_id, last_modified_at, created_at`. |
| `gear` | `20260827_001` | Shoes / bikes for wear tracking. `id, owner_id, kind ('shoe'/'bike'), name, brand, model, purchased_at, retired_at, target_distance_m, notes, created_at, updated_at`. |
| `run_gear` | `20260827_001` | Many-to-many run↔gear link. `run_id, gear_id, created_at`, PK `(run_id, gear_id)`. |
| `gear_wear_logs` | `20270225_001` | Per-shoe wear-pattern observations (roadmap §7). `id, gear_id, owner_id, logged_on (date, default current_date), area ('outsole'/'midsole'/'upper'/'other', nullable), note, created_at, updated_at`. Owner-only RLS end to end (no public-visibility path — unlike `run_gear`, wear notes never leak via a public run); INSERT gated on owning both the row and the parent `gear`. Cascades on parent-gear delete. Complements the distance-based `gear_wear` classifier (the bar says how far; the log says what you noticed). |
| `event_exceptions` | `20261019_001` | Cancelled occurrences of a recurring event. `event_id, instance_start, cancelled_by, reason, cancelled_at`, PK `(event_id, instance_start)`. |
| `deletion_audit_log` | `20260917_001` | Tamper-evident account-deletion ledger keyed by the SHA-256 of the user id (no PII). `hashed_user_id, deleted_at, result (enum of outcomes), notes`. |
| `app_quota` | `20261007_001` | App-level (not per-user) third-party rate-limit counter. `provider, window_kind ('short'/'day'), window_start, count`, PK `(provider, window_kind, window_start)`. |
| `lifecycle_email_log` | `20261202_001` | Idempotency ledger for one-shot lifecycle emails (welcome, etc.). `user_id, template, sent_at`, PK `(user_id, template)`. |
| `account_deletion_receipts` | `20270217_001` | Non-cascading send-once ledger for the account-deletion receipt email (the user — and so `lifecycle_email_log` — is gone by send time). `email_hash` (hex SHA-256 of the lowercased address, no raw PII), `sent_at`, PK `email_hash`. Service-role only; 30-day cron retention. decisions §121. |
| `email_suppressions` | `20270108_001` | Do-not-send list. `email, reason ('bounce'/'complaint'/'unsubscribe'/'manual'), created_at`, PK `email`. |
| `webhook_events` | `20260623_001` | Replay-dedupe ledger for inbound webhooks (RevenueCat, Stripe). `provider, event_id, received_at`, PK `(provider, event_id)`; GC'd by `cleanup-stale-webhook-events`. |
| `user_blocks` | `20261012_001` | Per-user block list for the social layer. `blocker_id, blocked_id, created_at, reason`, PK `(blocker_id, blocked_id)`, CHECK `blocker_id <> blocked_id`. |
| `coach_athletes` | `20261102_001` | Coach↔athlete roster (invite/accept). `id, coach_id, athlete_id, status ('pending'/'active'/'ended'), invite_token, note, created_at, accepted_at, ended_at`. See `redeem_coach_invite` + the coach-visibility note below. |
| `race_listings` | `20270214_001` | Public race calendar (race_calendar.md). `id, provider ('runsignup'/'parkrun'/'manual'/'chronotrack'/'raceresult'/'ultrasignup' CHECK), provider_race_id, name, race_date, distance_m, location_label, location_point geography(Point,4326), entry_url, results_url (both http(s)-CHECKed), submitted_by (→auth.users on delete set null), is_verified, created_at, updated_at`. Indexes: `(provider, provider_race_id)` partial-unique, `(race_date)`, GiST on `location_point`, GIN trgm on `name`. **RLS: public read** (`using (true)`, anon incl.); authenticated INSERT (`submitted_by = auth.uid()`); submitter UPDATE only while `is_verified=false`. A `before insert or update` trigger (`force_unverified_listing`) forces `is_verified=false` on any non-service-role write — only `service_role` (the import EF / admin) may verify. Read via the `search_race_listings` RPC (below). Also adds `runs.race_listing_id uuid → race_listings on delete set null` (partial index) — links a matched run to its calendar entry; passes through `public_runs` (non-sensitive). |

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
-- club PLUS an event-level gate (20270113_001, §148): an event is readable
-- when the club is readable AND (events.is_public OR member), so a public
-- club can hide an individual event from non-members + discovery. Admin-only
-- inserts for events and posts. Users manage their own RSVP row and leave
-- their own club membership row. See
-- 20260416_001_clubs_and_events.sql for the full set.
```

---

## Edge Functions

All Edge Functions are TypeScript running on the Deno runtime, deployed to Supabase Edge Functions.

Base URL: `https://{project-ref}.supabase.co/functions/v1/`

Authentication: most functions require a valid Supabase JWT in the `Authorization: Bearer {token}` header (the platform default `verify_jwt = true`). Four functions set `verify_jwt = false` in `config.toml` because they authenticate themselves another way: `strava-webhook` (URL-embedded shared secret + timing-safe HMAC — Strava signs nothing), `revenuecat-webhook` (HMAC over the raw body), `stripe-events-webhook` (Stripe-Signature HMAC over the raw body), and `refresh-tokens` (invoked by pg_cron with a shared bearer token). `clip-public-track` keeps `verify_jwt = true` but is anon-callable: it accepts the Supabase **anon** JWT and gates on the `runs.is_public = true` row check rather than the caller's identity.

---

### `POST /strava-import`

Initiates the Strava OAuth flow and backfills the last 90 days of activities.

**Request:**
```json
{ "code": "abc123", "scope": "activity:read_all,read", "redirect_uri": "https://app.example.com/settings/integrations" }
```

`scope` must contain `activity:read_all` (the function 400s otherwise — Strava lets users untick scopes on the consent screen and we can't backfill without it). `redirect_uri` is validated against `STRAVA_ALLOWED_REDIRECTS` (comma-separated env var); when the env var is empty the check is disabled (single-tenant / dev).

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

> **Status: Deprecated.** Superseded by `POST /v1/strava/webhook` on the Go worker (`apps/job_worker/internal/stravahook/`). The Edge Function is kept deployed as the rollback path — production traffic should route to the Go endpoint via `STRAVA_WEBHOOK_URL`. The spec below describes the legacy path.

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

### `POST /race-results-import`

Imports an official race result onto a `source='race'` run, or enriches an existing recorded run via the auto-match-on-record seam (race_calendar.md). Mirrors `parkrun-import` (auth-before-parse, `checkRateLimitTiered`, `readJsonWithLimit` body cap, `withSentry`, `privacy_default`-honouring `is_public`, per-user `external_id` dedup).

**Request:**
```json
{ "provider": "runsignup", "listingId": "<race_listings.id>", "runSignUpUserId": "optional",
  "matchRunId": "optional — enrich THIS run in place",
  "result": { "bib": "128", "chip_time": "1:47:23", "gun_time": "1:48:01", "overall_place": 128, "age_group_place": 4, "age_group": "M40-44" } }
```

**Flow:**
1. Auth (`auth.getUser`) → 401; tiered rate limit; resolve the public `race_listings` row (name/date/distance) for the metadata stamp.
2. `provider='runsignup'`: **fail closed** — if `RUNSIGNUP_API_KEY`/`_SECRET` are unset return `503 {error:'provider_not_configured'}`; else call the RunSignUp results endpoint, map each finisher to a run row (`source='race'`, `external_id=race:{name}:{date}:{bib}`, the owner-only race metadata). Fail-loud on a non-2xx upstream (502).
3. `provider='paste'`: map the single pasted result row.
4. `matchRunId` set → merge the metadata + set `race_listing_id` onto that owner-scoped run (no duplicate). Else dedup per-user against existing `external_id`s and insert the fresh rows.

**Response:** `{ "imported": 1, "skipped": 0, "enriched": 0 }` (the `matchRunId` path returns `enriched: 1`).

### `POST /race-listings-sync`

Pulls upcoming RunSignUp races near a region into `race_listings` (v1 seam — the actual fetch+upsert is a scoped follow-up). **Fail closed**: returns `503 {error:'provider_not_configured'}` when `RUNSIGNUP_API_KEY`/`_SECRET` are unset; the web + mobile UIs probe it to decide whether to show the RunSignUp affordance or the unavailable explainer.

**Env:** `RUNSIGNUP_API_KEY`, `RUNSIGNUP_API_SECRET` (both required for the RunSignUp legs — unset → 503), `RACE_IMPORT_USER_AGENT` (optional, defaults `RunApp/1.0`).

---

### `POST /refresh-tokens`

> **Status: Deprecated.** Superseded by the `token_refresh` job kind on the Go worker — the cron schedule now lives in `apps/backend/supabase/migrations/20260821_001_token_refresh_cron.sql` and enqueues jobs into the `jobs` table for the worker to drain. The Edge Function is kept deployed as the rollback path.

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

> **Status: Deprecated.** Superseded by `POST /v1/export` on the Go worker (`apps/job_worker/internal/dataexport/`). Clients pick transport via `PUBLIC_EXPORT_HUB_URL` (web) / `EXPORT_HUB_URL` (mobile); unset → call the EF; set → call the worker. The EF is kept deployed as the rollback path.

Exports all of a user's runs as a GPX zip or CSV. GDPR data portability.

**Request:**
```json
{ "format": "gpx" }   // or "csv"
```

**Response:**
```json
{ "url": "https://<ref>.supabase.co/storage/v1/object/sign/runs/<user_id>/exports/<ts>.zip?token=...",
  "path": "<user_id>/exports/<ts>.zip",
  "expires_in": 600,
  "count": 142,
  "format": "gpx" }
```

A signed Supabase Storage URL pointing to the generated artifact, valid for 10 minutes. CSV produces a single row-per-run file. GPX produces a zip containing one `runs/<run_id>.gpx` per run that has a track plus a top-level `runs.json` manifest mirroring the CSV column set. Capped at 5000 runs per export. Rate limit: free 2/h, pro 8/h via `check_rate_limit_tiered`.

---

### `POST /revenuecat-webhook`

Receives RevenueCat subscription events (initial purchase, renewal, cancellation, billing issues, expiration, transfer) and updates the corresponding `user_profiles.subscription_tier` + `subscription_at`. Authenticated by an HMAC-SHA256 of the raw body in the `x-revenuecat-hmac` header (constant-time compared against `REVENUECAT_WEBHOOK_SECRET`) — RevenueCat configures the same value in their dashboard. Replay-protected: events are rejected if `event_timestamp_ms` is outside `[now - 5min, now + 1min]`, and `event.id` is recorded in `webhook_events (provider, event_id)` (migration `20260623_001_webhook_event_dedupe.sql`) so a duplicate delivery skips the side effect and returns 200. See [paywall.md](../features/paywall.md) for the tier mapping. Migration ladder: `20260429_001_subscription_paywall.sql` (the column + CHECK constraint), `20260623_001_webhook_event_dedupe.sql` (replay table), then this function as the write path.

---

### `GET /clip-public-track`

Serves the clipped track JSON for a non-owner viewer of a public run. Replaces the dropped bare-table Storage SELECT policy on the `runs` bucket (migration `20260619_001`) — anonymous and signed-in non-owners can no longer read raw track files; they must go through this function, which applies `clip_track_for_user` (decisions §33) before returning.

**Request:**
```
GET /functions/v1/clip-public-track?run_id={uuid}
```

Anon-callable — `config.toml` keeps `verify_jwt = true`, so the platform requires a Supabase **anon** (or user) JWT, but the function authenticates via the `runs.is_public = true` row check, not the caller's identity. If a JWT is present, it's used to apply owner-visibility rules (owner sees their own raw track; non-owner gets the clipped version).

**Response:** track JSON identical in shape to `runs/{user_id}/{run_id}.json.gz`, with privacy-zone segments clipped.

---

### `POST /events-connect-onboard`

Stripe Connect onboarding for an event host (paid in-person events — see [club_events.md](../features/club_events.md), slice P1). JWT-gated (`verify_jwt = true`). Creates (or reuses) a Stripe Express connected account for the host, persists its id on `instructor_payout_accounts`, and returns a hosted Account Link URL; the host completes KYC / bank / tax on Stripe's pages. The `charges_enabled` flag is never written here — it flips later via the `account.updated` webhook (`stripe-events-webhook`). Onboarding is fully Stripe-hosted (SAQ A); no card or banking data touches us. **Test mode only in P1** — fails closed (503) when `STRIPE_SECRET_KEY` is unset, and the key must be an `sk_test_` key.

---

### `POST /events-checkout`

Buyer checkout for a paid in-person event (club_events.md slice P1). JWT-gated (`verify_jwt = true`) — a logged-out caller is 401'd. Opens a Stripe-hosted Checkout Session as a **destination charge** against the host's connected account and inserts a `pending` `event_orders` row holding a soft capacity reservation (~15 min). Validation gates each fail closed: caller signed in, event visible to the caller, `event_pricing` exists for the (event, instance) with modality `in_person`, the instance is not a cancelled occurrence (`event_exceptions`), the sales window is open, the host has a charges-enabled payout account (else 409), and capacity is not full counting `going` + non-expired `pending`. Idempotency: a stable key derived from (buyer, event, instance) makes a double-click reuse the same session. The `stripe-events-webhook` confirms the order and seats the attendee on `checkout.session.completed`; expiry releases the slot. **Test mode only in P1** (`sk_test_` key).

---

### `POST /stripe-events-webhook`

Stripe Connect events webhook — the one idempotent writer of order **and donation** status (club_events.md slice P1 + fundraising.md). `verify_jwt = false` (Stripe presents no Supabase JWT); authenticated by the `Stripe-Signature` HMAC over the **raw** body against `STRIPE_EVENTS_WEBHOOK_SECRET`. **One webhook, one secret** — the donation path is a branch keyed on `session.metadata.kind === 'donation'` (`isDonationSession`), not a second endpoint. Event-seat branch: `checkout.session.completed` (CAS `pending`→`paid`, confirm-time capacity recheck, seat the `going` attendee; oversold → left paid + flagged for manual refund), `checkout.session.expired` (CAS `pending`→`canceled`, releasing the reservation), `account.updated` (mirror `charges_enabled` / `payouts_enabled` / `details_submitted`). Donation branch: `checkout.session.completed` (CAS the `donations` row `pending`→`paid`, set `paid_at` + `stripe_payment_intent_id`), `checkout.session.expired` (`pending`→`canceled`), `charge.refunded` (resolve the donation via `stripe_payment_intent_id`, CAS `paid`→`refunded`). `donationStatusTransition` is the donation analogue of `orderStatusTransition` — a replayed `completed` on an already-`paid` donation no-ops, so it can't double-count. Idempotency, defence in depth: insert-first into `webhook_events (provider='stripe', event_id)` (a duplicate 23505 → 200 ok-skipped) plus the CAS guard. **Test mode only in P1** — fails closed (503) if the secret is unset.

### `POST /donations-checkout`

Donor checkout for a charity fundraiser (fundraising.md). `verify_jwt = false` — the donor **may be anonymous** (a donation has no seat, unlike a paid registration); if a JWT is present the donation is attributed (`donor_user_id`), otherwise it stays anonymous. Opens a Stripe-hosted Checkout Session as a **destination charge** against the fundraiser owner's connected account and inserts a `pending` `donations` row (service role). Validation gates each fail closed: the fundraiser is visible to the caller (RLS — a private-anchor fundraiser reads as not-found) and `status='open'`, the owner has a charges-enabled payout account (`host_can_take_payment`, else 409), and the amount is within sane bounds (100…1,000,000 cents). Idempotency: a stable key derived from the server-generated donation row id. The `stripe-events-webhook` donation branch confirms the donation on `checkout.session.completed`. SAQ A (no card form). **Test mode only in P1** — fails closed (503 `stripe_not_configured`) when `STRIPE_SECRET_KEY` / `STRIPE_EVENTS_ALLOWED_REDIRECTS` are unset; the key must be an `sk_test_` key.

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

**Returns:** `setof public_routes` — the narrowed public-safe view (not the full `routes` columns) — ordered by distance from the center point. Redefined to return the view in migration `20260703_001_public_routes_view.sql`.

---

### `routes_within_box(min_lat, min_lng, max_lat, max_lng, max_results)`

Viewport-shaped companion to `nearby_routes`. Returns public routes whose **full polyline** (`routes.geom`) intersects the bounding box, sorted by distance from the box centre. Requires the LineString geography column from migration `20260607_001_routes_geom_linestring.sql`.

```sql
select * from routes_within_box(-37.83, 144.94, -37.78, 144.99, 50);
```

**Parameters:**
- `min_lat` / `min_lng` / `max_lat` / `max_lng` — bbox corners (WGS84 degrees). Convention is south-west to north-east.
- `max_results` — maximum rows returned (default 50).

**Returns:** `setof public_routes` — the narrowed public-safe view (not the full `routes` columns) — ordered by distance from the box centre. Redefined to return the view in migration `20260703_001_public_routes_view.sql`.

**When to pick which:** `nearby_routes` answers "what's near me", `routes_within_box` answers "what's in this map viewport". A route whose start sits outside the visible viewport but whose body crosses it appears in the bbox query and *not* in the radius query — that's the whole reason both exist.

---

### `routes_intersecting_track(caller_user_id, track_geojson, tolerance_m, max_results)`

Auto-link helper for the run-detail flow. Given a recorded run's track (as a GeoJSON `LineString`), returns the user's saved routes whose `routes.geom` lies within `tolerance_m` of the track. Used on `/runs/[id]` to surface the "Looks like you ran *Richmond Park Loop*?" prompt when a fresh run isn't linked to a route yet.

```sql
select * from routes_intersecting_track(
  caller_user_id := auth.uid(),
  track_geojson := '{"type":"LineString","coordinates":[[lng,lat],...]}'::jsonb,
  tolerance_m := 100,
  max_results := 10
);
```

**Parameters:**
- `caller_user_id` — must equal `auth.uid()` for non-empty results. The function is `SECURITY INVOKER`, so the existing `select_own_routes` RLS policy gates non-owners to no rows even if a malicious client passes a different uuid.
- `track_geojson` — `{ "type": "LineString", "coordinates": [[lng, lat], ...] }`. Matches PostGIS's `ST_GeomFromGeoJSON` input.
- `tolerance_m` — pre-filter buffer (default 100). Drives the `ST_DWithin` that anchors the GIST scan; bigger values widen the candidate net but cost more in the planner.
- `max_results` — defaults to 10.

**Returns:** `(id, name, distance_m, start_offset_m, end_offset_m)` sorted by `start_offset_m + end_offset_m` ascending. The caller does the final ranking — combining the endpoint offsets with `|distance_m − track_length| / track_length` is a strong "definitely the same route" signal; either dimension alone is too noisy.

---

### `search_public_routes(p_query text, p_min_distance_m numeric, p_max_distance_m numeric, p_surface text, p_tags text[], p_featured_only boolean, p_sort text, p_limit int, p_offset int)`

Filtered + sorted search over public routes (`is_public = true`), all parameters optional with defaults (`p_featured_only false`, `p_sort 'newest'`, `p_limit 50`, `p_offset 0`). `p_query` does a case-insensitive `ilike` over `name`; the numeric/surface/tags args narrow the set (`p_tags` uses the `&&` array-overlap operator); `p_sort` ∈ `popular` / `featured` / `newest`. **Returns `setof public_routes`** — the narrowed public-safe view, not the full `routes` columns. SECURITY DEFINER, granted to `anon` + `authenticated` so the `/routes` Explore tab works without sign-in. Latest signature in migration `20261217_001_f17_naming_uniformity.sql`; earlier it was the simpler `(q text, max_results int)`. Used by `RouteExplorer.svelte` via `apps/web/src/lib/core/data.ts:searchPublicRoutes`.

### `popular_route_tags(tag_limit int)`

Returns the top-N most-used tag strings across `routes.tags` for the Explore tab's tag chips. Granted to `anon` + `authenticated`. Migration `20260502_001_popular_route_tags.sql`.

### `search_race_listings(p_query text, p_distance text, p_from date, p_to date, p_center_lng double precision, p_center_lat double precision, p_radius_m double precision, p_limit int)`

Proximity + soonest-first race-calendar discovery over `race_listings` (race_calendar.md). `security invoker` — the table's `for select using (true)` policy already permits anon reads, so this adds no exposure. All args optional: `p_query` ILIKEs `name`; `p_distance` ∈ `5k`/`10k`/`half`/`marathon`/`ultra` buckets `distance_m` into a tolerance window (mirrors the `race_match` bands); `p_from`/`p_to` window the date (default: upcoming, `race_date >= current_date`); when `p_center_lng`/`p_center_lat` are supplied it gates on `ST_DWithin(location_point, center, p_radius_m)` (default 50 km, GiST index) and returns `distance_m_away`, ordering nearest-first then soonest. `p_limit` clamped to 1–200 (default 60). Granted to `anon` + `authenticated`. Migration `20270214_001`. Used by web `searchRaceListings` (`core/data.ts`) + mobile `RaceService.searchRaceListings`.

### `recompute_event_ranks(p_event_id uuid, p_instance_start timestamptz)`

SECURITY DEFINER recompute of `event_results.rank` for the given (event, instance) tuple. Triggered automatically on `event_results` insert/update/delete; also exposed as an RPC for the race-mode auto-finalize path and admin tooling. Originally `20260424_001_event_results.sql`; latest definition (finishers-only ranking) in `20261222_001_event_rank_finishers_only.sql`. EXECUTE revoked from `public, anon`.

### `approve_event_result(p_event_id uuid, p_instance_start timestamptz, p_user_id uuid, p_approve boolean)`

SECURITY DEFINER, returns the affected `event_results` row. Lets a club admin or event organiser flip an `event_results` row between approved + pending visibility. Permission is checked via `is_event_organiser(uuid)`. EXECUTE revoked from `public, anon` and granted only to `authenticated` (migration `20260814_001_definer_grant_hygiene_pt2.sql` — Supabase grants implicit PUBLIC EXECUTE on every new public-schema function, so the original targeted `authenticated` grant didn't actually narrow anything; the body's organiser guard would still reject anon callers but defence-in-depth wants the EXECUTE narrowed too). Created in `20260428_001_role_permissions.sql`; `search_path` moved to `public, private` in `20261120_001_membership_oracles_private_schema.sql`.

### `private.is_event_organiser(uuid)` / `private.is_race_director(uuid)`

SECURITY DEFINER booleans used by RLS policies and other RPCs to check whether `auth.uid()` is allowed to administer a specific event (organiser is broader; race-director is the in-event live-mode start/stop role). **Live in the `private` schema** (migration `20261120_001`) alongside `is_club_member` / `is_club_admin` — PostgREST does not expose `private`, so they are not anon-callable membership/role oracles (audit-findings 2026-05-30 Medium). EXECUTE granted to `anon, authenticated, service_role` so RLS still evaluates; the qualified `private.` call from a policy bypasses search_path. Same private-schema treatment as `is_run_visible_to` (`20260812_001`).

### `upsert_checkpoint_crossing(p_event_id uuid, p_checkpoint_id uuid, p_instance_start timestamptz, p_user_id uuid default null, p_bib text default null, p_runner_name text default null, p_in_time timestamptz default null, p_out_time timestamptz default null, p_health_consent boolean default false, p_body_weight_kg numeric default null, p_body_weight_pct numeric default null, p_medical_hold boolean default null, p_medical_note text default null) → checkpoint_crossings`

SECURITY DEFINER — the **sole writer** of `checkpoint_crossings` (there is no direct-write RLS policy). Authorises the caller as an organiser (`is_event_organiser(events.club_id)`, else `42501`), validates the event (`42704` if missing), that the checkpoint belongs to the event (`23503`), and the identity rule (`23514` if neither `user_id` nor `bib`). Then inserts or **merges in/out**: a second call for the same `(checkpoint_id, instance_start, identity)` UPDATEs the existing row with `in_time = least(existing, new)` and `out_time = greatest(existing, new)` (Postgres `least`/`greatest` ignore NULLs → earliest-in, latest-out, fill-the-gap), so two client-minted UUIDs on two volunteers' phones collapse onto the canonical row. **Fail-closed health gate (decisions §150):** the Art 9 fields persist only when the checkpoint's `requires_weigh_in = true` AND `p_health_consent = true`; otherwise they are dropped to NULL. EXECUTE revoked from `public, anon`, granted to `authenticated`. Migration `20270201_001`; pinned by `checkpoint_crossings_test.sql`. See [decisions.md § 154](../architecture/decisions.md).

### `fetch_checkpoint_crossings_for_organiser(p_event_id uuid, p_instance_start timestamptz) → setof checkpoint_crossings`

SECURITY DEFINER — the organiser read path for the live-results board. Returns every crossing for the event instance **including** the column-locked Art 9 health fields (which anon/authenticated cannot read off the base table). Raises `42501` for a non-organiser, `42704` for a missing event. EXECUTE revoked from `public, anon`, granted to `authenticated`. Migration `20270201_001`.

### `is_pro()`

SECURITY DEFINER boolean — `select user_profiles.subscription_tier in ('pro','lifetime')` for `auth.uid()`. Used by Edge Functions and the `/api/coach` server route to gate paywalled features without a separate column lookup per request. Granted to `authenticated`. Migration `20260429_001_subscription_paywall.sql` (the predecessor `is_user_pro(uuid)` was dropped in `20260516_001`).

### `join_club_by_token(token text)`

SECURITY DEFINER. Validates a `club_invites.token`, checks expiry / max-uses, inserts a `club_members` row for the caller, and bumps the invite's redemption counter. Atomic — partial failures roll back. Granted to `authenticated`. Migration `20260417_001_club_invites.sql`.

### `redeem_coach_invite(token text)`

SECURITY DEFINER. The caller becomes the athlete on a pending `coach_athletes` invite matching `token` (sets `athlete_id = auth.uid()`, `status = 'active'`). Raises if the token is missing/already redeemed, the caller is the coach (no self-coaching), or the caller is already linked to that coach. Backs `redeemCoachInvite` on the web `/coaching/accept/<token>` page. Table `coach_athletes` (migration `20261102_001`): RLS scopes reads/writes to coach + athlete; coach-only insert of pending invites; either party may end (`status='ended'`); a coach may delete an unredeemed invite. See [decisions.md § 97](../architecture/decisions.md#97-coach-athlete-roster-is-a-web-first-inviteaccept-link-model-persona-hunt-coach-46).

**Coach run visibility (migration `20261103_001`, persona #47).** A `status='active'` link is the consent that lets a coach read their athlete's runs. The helper `private.is_active_coach_of(coach, athlete)` (SECURITY DEFINER, mirrors the club-membership EXISTS inside `is_route_visible_to`) feeds two additions: a `runs` SELECT policy (`active coach reads athlete runs`) so the coach reads the athlete's run rows **public and private** directly off the base table (the `public_runs` view is is-public-only), and a coach branch inside `private.is_run_visible_to` so the social rows gated by it (run_kudos / run_comments / segment_efforts / live_run_pings) are visible too. SELECT-only — no coach write path into an athlete's runs; ending the link (`status='ended'`) revokes immediately. **Run photos are NOT shared with the coach** (migration `20261125_001`, audit-storage): both the `run_photos` table SELECT policy and the `run-photos` Storage byte policy use `private.is_run_photo_visible_to` (owner-or-public, no coach branch), so a coach sees private-run photos no more than the raw GPS track — which also stays owner-only (the `runs` bucket Storage policy is unchanged). See [decisions.md § 98](../architecture/decisions.md#98-an-active-coach-reads-an-athletes-runs-private--public-the-raw-gps-track-stays-owner-only).

### `assign_plan_to_athlete(p_source_plan_id uuid, p_athlete_id uuid, p_start_date date) → uuid`

SECURITY DEFINER (migration `20270106_001`, persona #46/#47). Lets an **active** coach give a linked athlete a whole plan, the write counterpart to the read access above. Gates: caller authenticated, caller ≠ athlete, `private.is_active_coach_of(caller, p_athlete_id)` (the active link is the consent), and the caller can read the source plan (their own plan/template, or a club template they're a member of — mirrors `clone_plan_template`). It then **deep-clones** the source plan + its `plan_weeks` + `plan_workouts` into a new `training_plans` row **owned by the athlete** (`user_id = p_athlete_id`, `status='active'`), date-shifted from `p_start_date`, stamping `parent_template_id = source` and `assigned_by_coach_id = caller`. **Raises if the athlete already has an active plan** (never silently abandons the athlete's own plan). Clone-not-subscribe (decisions §35/§143): the athlete owns the result under the unchanged "users own their plans" RLS and the coach's later source edits don't propagate; the coach keeps the `plan_workouts`-edit access from `20261116_001`. New column `training_plans.assigned_by_coach_id` (nullable FK → `auth.users`, `ON DELETE SET NULL`) records provenance and rides the existing `select *` DSAR export of `training_plans`. Backs `assignPlanToAthlete` on `/coaching/athletes/[id]`. Pinned by `assign_plan_to_athlete_test.sql`. See [decisions.md § 143](../architecture/decisions.md#143-a-coach-assigns-a-training-plan-by-deep-cloning-one-of-their-own-into-an-athlete-owned-plan-clone-not-subscribe-gated-on-the-active-link).

### `coach_roster_summary() → setof roster row`

SECURITY DEFINER (migration `20270206_001`, coach_roster.md). The read-only aggregation behind the multi-athlete roster dashboard. Returns one row per **active-linked** athlete: `athlete_id, display_name, avatar_url, last_run_at, runs_7d, distance_7d_m, load_acute, load_chronic, active_plan_id, plan_completion_pct`. Consent is re-checked **inside** the definer body — a `mine` CTE (`coach_athletes where coach_id = auth.uid() and status='active'`) is the only membership gate (SECURITY DEFINER bypasses the caller's RLS, so the runs/plan coach-read policies can't be the gate here), so a non-coach gets zero rows and an unauthenticated caller **raises** (`not authenticated`, fail-closed). `load_acute` = 7-day distance-proxy stress sum (10 pts/km, mirroring `training_load.ts`'s distance fallback); `load_chronic` = the 28-day total / 4 (avg weekly), is_dnf runs excluded; the client computes the ACWR ratio + injury-risk band from those via the shared `coach_load` helper (the risk policy stays out of the SQL). `plan_completion_pct` mirrors `fetchAthletePlanOverview` (done = `completed_run_id is not null OR manually_completed`; denominator excludes `kind='rest'` + `skipped_at is not null`). **Returns no track bytes** — run row stats only; the raw GPS track stays owner-only (decisions §98 unchanged). `grant execute … to authenticated` (never anon). Backs `fetchCoachRosterSummary` on `/coaching` + the mobile `coaching_screen` roster card. Pinned by `coach_roster_summary_test.sql` (the auth boundary: active-only, ended/pending excluded, non-coach empty, unauthenticated raises, revocation immediate). See [decisions.md § 162](../architecture/decisions.md).

### `latest_fitness_snapshot()`

Returns the caller's most recent `fitness_snapshots` row (VDOT, weekly mileage, ATL/CTL, etc.). Cached materialisation of the inputs the dashboard fitness card needs. Granted to `authenticated`. Migration `20260507_001_fitness_snapshots.sql`.

### `get_integration_tokens(p_user_id uuid, p_provider text)` / `set_integration_tokens(p_user_id uuid, p_provider text, p_access_token text, p_refresh_token text, p_token_expiry timestamptz)`

SECURITY DEFINER pair that brokers OAuth tokens through Supabase Vault rather than exposing the encrypted columns directly to the row. `set` writes the access + refresh + expiry into Vault and stores only the secret IDs on the `integrations` row; `get` returns `table(access_token, refresh_token, token_expiry)` for the calling Edge Function. EXECUTE revoked from `public`, granted to `authenticated` + `service_role`. Both take an explicit `p_user_id` (the caller, re-derived in the function body). Decision: [decisions.md § 41](../architecture/decisions.md#41-oauth-tokens-are-stored-in-supabase-vault-not-as-plaintext-columns). Created in `20260603_001_integrations_vault.sql`; current signatures in `20260919_001_get_integration_tokens_modern_claims.sql`. A compare-and-swap variant `set_integration_tokens_cas(p_user_id, p_provider, p_expected_refresh_token, p_access_token, p_refresh_token, p_token_expiry)` (migration `20261006_001_set_integration_tokens_cas.sql`) guards concurrent refreshes.

### `check_rate_limit_tiered(p_user_id uuid, p_bucket text, p_free_max int, p_pro_max int, p_window_seconds int)`

SECURITY DEFINER. Atomic per-bucket per-user counter that picks the ceiling by reading `user_profiles.subscription_tier` **inline** (`pro` / `lifetime` → `p_pro_max`, else `p_free_max`) — it does NOT call `is_pro()`. Returns `table(allowed boolean, retry_after_seconds int, tier text)`. Gates on caller identity: a non-`service_role` caller whose `auth.uid()` ≠ `p_user_id` raises. Used by `/api/coach`, `parkrun-import`, `strava-import`, `export-data` to enforce paywall throttling without each Edge Function hand-rolling the logic. Granted to `authenticated`. Created in `20260605_001_rate_limits_tiered.sql`; current signature (explicit `p_user_id` + window + role-from-JWT-claims check) in `20260726_001_rate_limit_role_jwt_claims.sql`.

### `cleanup_stale_rate_limits()`

SECURITY DEFINER GC for the `rate_limits` table — deletes rows whose window has elapsed. Driven by the hourly `cleanup-stale-rate-limits` pg_cron job. Migration `20260604_001_cleanup_stale_rate_limits.sql`.

---

### `claim_next_job(worker_id, kind_filter)`

SECURITY DEFINER. Atomically marks the next ready job as `running`, increments its `attempts`, and returns the row. Used by the Go service (and any future worker) to drain the [`jobs`](#jobs) queue. PUBLIC EXECUTE is revoked; granted to `service_role` only.

```sql
-- Drain the next map_match job:
select * from claim_next_job('worker-1', 'map_match');

-- Or any kind:
select * from claim_next_job('worker-1', null);
```

**Parameters:**
- `worker_id` — opaque identifier persisted on the row as `locked_by`. Useful for stuck-job debugging.
- `kind_filter` — restrict the claim to one job type, or `null` for any.

**Returns:** zero or one row with `(id, kind, payload, attempts)`. Empty result means the queue is dry; the worker should sleep + retry. The claim uses `for update skip locked` so concurrent workers each get a distinct row instead of contending.

### `finish_job(job_id, result_status, err)`

SECURITY DEFINER. Marks a claimed job as `done` / `failed` / `cancelled`, sets `finished_at = now()`, and stores `err` as `last_error` (worker-supplied diagnostic on the failure path). Bad `result_status` raises `22023`.

### `defer_job(job_id, delay_seconds, err)`

SECURITY DEFINER. Pushes a claimed job back into the queue with a delay — the row's `status` reverts to `queued`, `scheduled_at` is set to `now() + delay_seconds`, and the `locked_at` / `locked_by` are cleared. Use when a transient upstream (the matching engine, a third-party API) is unavailable. `attempts` is NOT decremented — the increment from the original `claim_next_job` stands, so the per-job `max_attempts` ceiling still applies. **When the retry budget is exhausted** (`attempts >= max_attempts`), `defer_job` does NOT re-queue — re-queuing would strand the row in `queued` forever, since `claim_next_job` only claims rows with `attempts < max_attempts`. Instead it lands the row in `status='failed'` with `finished_at = now()` and `last_error = err`, so the failure surfaces in `find_failed_jobs` / `jobs_failed_summary` rather than going invisible. It **returns the resulting status** (`'queued'` on re-queue, `'failed'` on exhaustion, `null` if the row vanished) so the worker can log the outcome accurately without duplicating the threshold in Go. Migration `20261201_001_jobs_failed_alert.sql`.

### `find_failed_jobs(p_failed_within interval default '15 minutes')` / `jobs_failed_summary(...)`

SECURITY DEFINER, `service_role`-only. The observability pair for terminal job failures (migration `20261201_001`). `find_failed_jobs` lists every `status='failed'` row whose `finished_at` is within the window (id, kind, attempts, finished_at, last_error, age). The window matters because `failed` rows are never purged — an unbounded query would alert forever on old failures. `jobs_failed_summary` wraps it as a single JSONB row `{failed_count, by_kind, sample, checked_at}` so the value is readable in `cron.job_run_details.return_message`. A `jobs-failed-alert` pg_cron entry runs the summary every 10 min; a Sentry/Slack scraper routes on `failed_count > 0`. This is the safety net for the async Strava webhook: a `strava_event` job that fails after the synchronous 200 ack surfaces here instead of disappearing. Parallels the earlier `find_stuck_jobs` / `jobs_stuck_summary` pair (migration `20260731_001`), which covers wedged `running` rows rather than terminated ones.

### `enqueue_run_rematch(p_run_id)`

SECURITY DEFINER. Owner-only manual re-match trigger called by the "Re-match" button on `/runs/[id]`. Resets `run_matched_tracks` (status=pending, attempts=0, error_message=null, …) and inserts a fresh `map_match` row into `jobs`. Self-gates on `auth.uid() = run.user_id`; non-owner calls raise `42501`. Idempotent against in-flight jobs via `jobs_dedupe_map_match`. Migration `20260612_001_enqueue_run_rematch.sql`.

### `clone_plan_template(template_id uuid, new_start_date date)`

SECURITY DEFINER RPC for plan-template adoption (decisions §35). Verifies the caller can SELECT the template (own plan or club member of the template's `club_id`), then duplicates `training_plans` + `plan_weeks` + `plan_workouts` into a new user-owned plan anchored at `new_start_date`. All workout `scheduled_date` values are shifted by the date offset between the template's `start_date` and the new start date. The new plan's `parent_template_id` points back at the template; `is_template = false` and `status = 'active'`. Returns the new plan's id. Granted to `authenticated`.

### `clone_public_plan(template_id uuid, new_start_date date)`

SECURITY DEFINER RPC for **public plan library** adoption (migration `20270126_001`). The anyone-can-clone analogue of `clone_plan_template`: authorises on **public visibility** (`is_template = true and is_public_template = true`) instead of club membership, so any authenticated caller may clone any public template. Anti-bulk-clone rate-limited (`enforce_create_rate_limit('clone_public_plan', …, 20, 3600)`). Auto-completes the caller's existing active plan before inserting (so `training_plans_one_active` can't trip), then deep-clones `training_plans` + `plan_weeks` + `plan_workouts` into a new user-owned plan anchored at `new_start_date` (workout dates shifted by the offset), stamping `parent_template_id = template`, `is_template = false`, `is_public_template = false`, `status = 'active'`. Publisher `vdot`/`current_5k_seconds` are stripped (defence-in-depth, mirrors `20260721_001`). Returns the new plan's id. Granted to `authenticated`. pgtap: `clone_public_plan_test.sql`. Surfaced as Clone on the web `/plans/library` + mobile `PlanLibraryPreviewScreen`; the publish direction is the client-side `publishPlanToLibrary` (copies into an `is_public_template` row, original untouched).

### `clone_session_template(template_id uuid)`

SECURITY DEFINER RPC for session-plan template adoption (session_planner.md P3, migration `20270104_001`). The yoga/pilates analogue of `clone_plan_template`: verifies the caller is the template's author or a member of its owning club (`private.is_club_member`, via the `public, private` search_path), then duplicates `session_plans` + `session_plan_blocks` + `session_plan_items` into a new **personal** plan (`author_id = caller`, `club_id = null`, `is_public = false`), preserving block grouping + `per_side` + positions. A session plan carries no private fitness data, so nothing is stripped on clone. Anti-bulk-clone rate-limited (`enforce_create_rate_limit`, 20/hour). Returns the new plan's id. Granted to `authenticated`. pgtap: `clone_session_template_test.sql`. Surfaced as Adopt on the club-detail Templates tab (`cloneSessionTemplate` web / `ApiClient.cloneSessionTemplate` mobile); the publish direction is the client-side `publishSessionAsTemplate` (copies into a `club_id` row, original untouched).

### `duplicate_plan_week(p_plan_id uuid, p_week_index int)`

Owner-only SECURITY DEFINER RPC for the duplicate-a-week bulk op (migration `20261205_001`). Inserts a copy of the week at `p_week_index` immediately after it as the new `p_week_index + 1`; every later week shifts up one index and its workouts move back 7 days, the copied week's workouts land 7 days after their source, and the plan's `end_date` extends by a week. Completion state (`completed_run_id` / `completed_at` / `manually_completed`) is **not** copied. Atomic because the `plan_weeks (plan_id, week_index)` unique constraint makes a client-side multi-update unsafe — the re-index hops through negative index space to avoid a transient per-row collision. Returns the new week's id. Granted to `authenticated`. Mounted as the per-week Duplicate button on `/plans/[id]` (`duplicatePlanWeek` in `data.ts`).

### `clip_track_for_user(target_user_id uuid, points jsonb)`

SECURITY DEFINER RPC for privacy-zone clipping (decisions §33). Reads `user_settings.prefs.privacy_zones` for the target user, walks the input points dropping in-zone leading + trailing entries, and returns the contiguous middle as jsonb. Zones never leave the database. Granted to `anon` + `authenticated` so anonymous `/share/run/[id]` and `/share/route/[id]` viewers also receive clipped output. Input is capped at 50 000 points (raise on overflow) to bound the residual dense-grid probe attack. Returns input unchanged when the target user has no zones configured. Helpers `privacy_distance_m(lat1, lng1, lat2, lng2)` and `privacy_in_any_zone(lat, lng, zones_json)` are exposed in the same migration but used only internally by the RPC.

### `clip_route_for_viewer(p_route_id uuid)`

SECURITY DEFINER RPC for the routes equivalent of `clip_track_for_user` (decisions §33, migration `20260625_001`). Self-contained: caller passes only the route id. Looks up the row internally, applies the same visibility gate as the routes SELECT policies (owner / public / club member; raises `42501` otherwise so private-route reads are loud), and returns either the unclipped `waypoints` (owner) or the clipped output (non-owner, delegated to `clip_track_for_user` so the zone walk has one implementation). Granted to `anon` + `authenticated`. Anon callers can only read `is_public = true` routes — private-route reads from anon raise `42501`. Routes carry waypoints inline (no Storage indirection like runs) so this is a straight RPC rather than an Edge Function.

### `segment_effort_ranks(p_run_id uuid)`

Returns `(effort_id, rank)` for every segment effort on a run in one round-trip — replaces a client-side N+1 count-per-effort loop in `fetchEffortsForRun` (migration `20261223_001`, perf-hunt 2026-06-10). `rank = 1 +` the number of strictly-faster efforts on the same segment **visible to the caller**. SECURITY INVOKER, so the `segment_efforts` RLS (EXISTS-through-route → `routes.is_public`) gates the comparison set identically to the old per-effort client count. Tie semantics = standard competition ranking (tied fastest both rank 1, next ranks 3). Granted to `anon` + `authenticated`. pgTAP `segment_effort_ranks_test.sql`.

### `gym_exercise_records()`

Returns one row per exercise — `(exercise_name, heaviest_weight_kg, heaviest_weight_reps, best_volume_kg, best_est_1rm_kg, last_performed_at, session_count)` — for the `/gym/records` surface (migration `20261224_001`, perf-hunt follow-up). All-time per-exercise bests can't be served by a windowed client read, so the aggregation lives in SQL (mirroring how run PRs are SQL-maintained); the client-side `exercise_records.ts` stopgap was retired. The SQL is the mirror of `gym_prs.ts#computeExercisePrs` + `exercise_records.ts` (normalised name key, Epley e1rm with the rep clamp, bodyweight-only excluded). SECURITY INVOKER (owner-scoped via `gym_workouts`/`gym_sets` RLS + explicit `auth.uid()`). The `gym_prs.ts` badge engine stays client-side for the per-workout temporal badges. pgTAP `gym_exercise_records_test.sql` pins the metrics against the `gym_prs.test.ts` fixture shape.

### `gym_exercise_set_history(p_name text)`

Returns one exercise's sets — `(workout_id, started_at, exercise_name, reps, weight_kg, rpe, duration_s)` — matched on the **normalised** name (trim → lowercase → collapse whitespace, the same key `gym_prs.ts#normaliseExerciseName` uses), for the `/gym/exercise` progression view and `/gym/[id]`'s per-exercise PR badges + vs-last-time (migration `20261225_001`, perf-hunt follow-up; `duration_s` added in `20261231_001` for timed work — planks/holds — instructor_business.md M2). Bounds the read to one exercise instead of pulling the whole history; the normalised match picks up sessions logged under a different capitalisation (an exact `=` would drop them). SECURITY INVOKER, owner-scoped. pgTAP `gym_exercise_set_history_test.sql`.

### `gym_exercise_names()`

Returns `(exercise_name, uses)` — distinct trimmed exercise names + use counts, most-used first — for the gym editor's autocomplete datalist (migration `20261226_001`, perf-hunt follow-up). Bounded to the count of distinct exercises (dozens) so the History page never pulls raw set history just to derive names. Names stay case-preserved (trim only), matching the prior client behaviour. SECURITY INVOKER, owner-scoped. pgTAP `gym_exercise_names_test.sql`.

---

## Challenges & competitions

Migrations `20270209_001_challenges.sql` (schema + RLS) + `20270210_001_challenge_progress_rpc.sql` (RPCs + completion). See [challenges.md](../features/challenges.md).

### Tables

- **`challenges`** — `id, creator_id, club_id (null = open), title, description, metric, scope, goal_value (null = pure-ranking board), activity_type (null = any), starts_at, ends_at, is_public, created_at`. `metric ∈ {distance, duration, activity_count, streak_days}` and `scope ∈ {individual, club_vs_club, group_goal}` are CHECK-constrained and paired with the `ChallengeMetric` / `ChallengeScope` TS unions (in `check_constraint_unions.mjs`). `club_vs_club` forces `club_id = null` (it aggregates across many clubs).
- **`challenge_participants`** — `(challenge_id, user_id)` PK + `team_club_id` (the club a member's total pools into, club_vs_club only), `joined_at`, `completed_at` (column-locked — written only by the completion RPC, mirroring the `event_attendees.attendance` lockdown; clients hold only the `team_club_id` column-UPDATE grant).
- **`challenge_badges`** — durable completion record, `unique(user_id, challenge_id)`. INSERT closed to clients; written only by the SECURITY DEFINER completion path.

### RLS

- `challenges` SELECT: public OR creator OR participant OR active member of `club_id`. INSERT: `auth.uid() = creator_id` AND (open OR `is_club_admin(club_id)`). UPDATE/DELETE: creator OR club admin. The `is_challenge_visible(uuid)` SECURITY DEFINER helper encapsulates the SELECT predicate for the child tables.
- `challenge_participants` SELECT inherits `is_challenge_visible`; INSERT is self-only + visible + (team join requires active membership of `team_club_id`); DELETE self-only.
- `challenge_badges` SELECT: owner OR the badge's challenge is public.

### RPCs

- **`challenge_leaderboard(p_challenge_id uuid, p_by_team boolean default false)`** → `(user_id, display_name, team_club_id, value, rank)`. **SECURITY DEFINER**, gated on `is_challenge_visible`. ONE query joining participants to a per-user (or per-team) aggregate over each runner's `runs` within `[starts_at, ends_at)`, filtered by `activity_type` when set. DEFINER (not invoker) because the public-runs SELECT policy on `runs` was retired — an invoker aggregate would zero every competitor; the board exposes only the per-user SUM, never the run rows. `rank() over (order by value desc)`. N participants → 1 round trip.
- **`my_active_challenges()`** → challenge fields + `my_value, my_rank, participant_count, completed_at`. SECURITY INVOKER. The self-hide driver: only challenges the caller has joined that are live or ended within 7 days. An empty result = render nothing.
- **`recompute_challenge_completion(p_challenge_id, p_user_id)`** — SECURITY DEFINER. Recomputes the user's value; when `goal_value` is met and no badge exists, inserts `challenge_badges` + stamps `completed_at` + inserts a `challenge_complete` notification. Idempotent (the unique badge row guards). Called opportunistically client-side after a run saves + by the daily `sweep_challenge_completions()` pg_cron job (`sweep-challenge-completions`).

pgTAP: `challenges_rls_test.sql`, `challenge_leaderboard_test.sql`, `challenge_completion_test.sql`, `challenge_participants_completed_lockdown_test.sql`.

---

## Supabase Storage

Three buckets in the live schema:

| Bucket | Access | Purpose |
|---|---|---|
| `runs` | Private (RLS, owner-scoped) | **Two content classes** under different path prefixes — see below. The bare-table public-read RLS that used to gate this on `runs.is_public` was dropped in `20260619_001_drop_public_runs_storage_policy.sql`; non-owner reads now go through the `clip-public-track` Edge Function. Owner SELECT on the `exports/` subprefix was removed in `20260816_001_runs_bucket_exports_signed_url_only.sql` — exports are reachable through the EF-issued 10-min signed URL only, never via direct REST GET. |
| `run-photos` | Private (RLS, parent-run-visibility join) | Photos attached to runs at `{owner_id}/{photo_id}.{ext}`. Per-user-folder INSERT/DELETE; storage SELECT joins through `run_photos` → `is_run_visible_to`. Bucket is private (migration `20260712_001`); clients use signed URLs with 1 h TTL. See `decisions.md § 36`. |
| `route-photos` | Private (RLS, parent-route-visibility join) | Photos attached to routes at `{owner_id}/{photo_id}.{ext}` (backlog C1, migration `20270114_001`). Per-user-folder INSERT/DELETE; storage SELECT joins through `route_photos` → `private.is_route_visible_to`. Private from creation; clients use signed URLs with 15-min TTL. `file_size_limit` 10 MB + image-only `allowed_mime_types`, matching `run-photos`. |
| `avatars` | **Public** (CDN read) + owner-scoped writes | Profile pictures at `{user_id}/avatar.{ext}` (bucket created `20260927_001`; in-app upload added later). `public = true` because an avatar renders on the logged-out `/u/[id]` profile + share pages as a bare `<img src={avatar_url}>`, so `user_profiles.avatar_url` holds a plain public URL (the only thing that satisfies the `^https?://` CHECK for anon viewers). Owner-scoped INSERT/UPDATE/DELETE **and** an owner-scoped SELECT (`20270203_001` — the public CDN serves downloads, but authenticated `.list()`/`.remove()` query `storage.objects` under RLS, so an owner needs SELECT to manage their own object). 2 MB cap, `image/jpeg`/`png`/`webp` only (no SVG → no stored-XSS). Web `uploadAvatar`/`removeAvatar` (`data.ts`) + mobile `ApiClient.uploadAvatar`/`removeAvatar` (byte-identical twin) strip EXIF/GPS client-side before upload (no server-side strip worker on this bucket) and remove-then-insert at the stable path (the bucket grants INSERT/DELETE but not the upsert WITH-CHECK). |

The `routes` and `exports` buckets shown in older revisions of this doc were never created — `routes.waypoints` is stored inline (jsonb on the `routes` table) and exports live under the `runs` bucket's `exports/` prefix.

### Path layout under the `runs` bucket

```
{user_id}/{run_id}.json.gz         # gzipped GPS track for run {run_id}
{user_id}/exports/{timestamp}.zip  # user-requested data export bundles
{user_id}/exports/{timestamp}.csv  # ditto, CSV variant
```

Path-prefix discipline is enforced at multiple layers:

- The `runs_track_url_path_shape` CHECK constraint (`20260621_001_runs_track_url_path_check.sql`) rejects any `runs.track_url` value that doesn't match the per-user track shape.
- The `clip-public-track` Edge Function asserts the same shape on read so a forged path can't escalate beyond the runner's own folder.
- `delete-account/index.ts` walks both prefixes when wiping a user's data so neither tracks nor exports orphan.

`allowed_mime_types` on the bucket is set to `[application/gzip, application/octet-stream, text/csv, application/zip]` (migration `20260815_001_runs_bucket_mime_allowlist.sql`) — defence-in-depth so a future writer can't sneak in `image/svg+xml` or `text/html` and turn the bucket into an XSS vector via a thumbnail / share-page Lambda that serves bytes back to a browser. `application/octet-stream` is included because supabase-js historically defaulted to that when a Blob's MIME wasn't set; some older mobile callers may still emit it.

The owner SELECT policy (`Users can read their own run tracks`) was rewritten in `20260816_001_runs_bucket_exports_signed_url_only.sql` to exclude any path whose second `foldername` segment is `exports` — track downloads (`{user_id}/{run_id}.json.gz`) keep working, but export blobs at `{user_id}/exports/<ts>.{csv,zip}` are reachable only through the service-role-signed URL the `export-data` EF returns. Closes the gap where an authenticated owner could replay a CSV directly from the bucket during the 7-day retention window even after the signed URL expired (e.g. via a browser-history entry or a leaked export with embedded paths).

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
// apps/web/src/lib/core/supabase-server.ts
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
