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
  duration_s    integer not null,           -- elapsed seconds; >= 0 (CHECK, 20270704000001)
  distance_m    numeric(10, 2) not null,    -- metres; >= 0 and not NaN (CHECK, 20270704000001)
  route_id      uuid references routes,     -- linked planned route, if any
  event_id      uuid references events,     -- linked club event instance, if any
  source        text not null,              -- see RunSource enum below
  activity_type text not null default 'run' -- run|walk|hike|cycle|stroller (CHECK). Promoted from metadata in 20261207_001 (F3)
                check (activity_type in ('run','walk','hike','cycle','stroller')),
  is_dnf        boolean not null default false, -- did-not-finish; PR engine excludes these. Promoted from metadata in 20261207_001 (F3)
  elevation_gain_m numeric,                 -- total ascent (metres); null or (>= 0, finite, not NaN) (CHECK, 20270704000001). Nullable; backfilled from metadata.elevation_m in 20270302_001 (ADR §186), summed by the vert challenge metric, projected into activities.summary + public_runs. Writers populate both this + metadata.elevation_m.
  fastest_5k_s  integer,                    -- embedded-best seconds (fastest rolling 5 km window in the track); null or > 0 (CHECK, 20270705000004). Promoted from metadata in 20270325_001; PR-candidate read by refresh_personal_records_for_user, exposed on public_runs.
  fastest_10k_s integer,                    -- same, rolling 10 km window (20270325_001)
  fastest_half_marathon_s integer,          -- same, rolling 21.0975 km window (20270325_001)
  fastest_marathon_s integer,               -- same, rolling 42.195 km window (20270325_001); null or > 0 (CHECK, 20270705000004)
  external_id   text unique,                -- deduplication key
  metadata      jsonb,                      -- source-specific extra fields (avg_bpm, steps, elevation_m, provider ids, …)
  track_url     text,                       -- Storage path: {user_id}/{run_id}.json.gz
  hr_series_url text,                        -- Storage path: {user_id}/{run_id}.hr.json.gz (indoor/trackless HR series)
  is_public     boolean default false,      -- visible at /share/run/{id}
  concluded_at  timestamptz,                 -- positive live-broadcast terminal marker; stamped by concludeLiveBroadcast on stop, null while live or never broadcast. Exposed via public_runs so spectators detect finish honestly. 20270427_001 (issue #613)
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

**The three physical quantities are bounded, and the bound names NaN explicitly** (`20270704000001`). `runs_distance_m_check`, `runs_duration_s_check` and `runs_elevation_gain_m_check` were added after a measurement showed an ordinary authenticated account could POST `{"distance_m":"NaN","duration_s":-60,"elevation_gain_m":"Infinity"}` through PostgREST and have it stored verbatim — the self-owned INSERT policy is the only privilege the write needs. `'NaN'::numeric >= 0` is **true**, so a bare `>= 0` would not have closed it; each numeric bound carries an explicit `<> 'NaN'` term, and `elevation_gain_m` carries `<> 'Infinity'` too because its bare `numeric` type accepts one where `distance_m`'s `numeric(10, 2)` scale rejects it with a 22003 before any CHECK runs. The two consequences that motivated it: NaN outranks every real value in numeric ordering and `challenge_leaderboard` ranks on `sum(distance_m)` descending, so one NaN run took rank 1 of every distance challenge its author had joined; and a negative `duration_s` became the account's 5k best, because the whole-run branch of `refresh_personal_records_for_user` orders on `duration_s asc` with no floor of its own where the promoted `fastest_*_s` branches already carry one. Deliberately no upper bound — a 240-mile ultra is 386 km and refusing a real measurement is worse than admitting an absurd one that no longer poisons an aggregate. Pinned by `runs_physical_quantity_bounds_test.sql`.

**Every numeric column in `public` now carries a bound, or an exemption with a reason** (`20270705000001`, `20270705000002`, `20270705000004`; [decisions §§ 1046-1047](../architecture/decisions.md), [§ 1051](../architecture/decisions.md)). `20270704000002` fixed the bounds that existed and admitted NaN; re-derived from the catalogue, **79** numeric columns on base tables carried no single-column CHECK at all — **31** of them in a `numeric` / `double precision` type that can hold a NaN (the set the followup named, matching name for name) and **48** integer-family, where NaN is unreachable at the type and the exposure is a nonsense sign. All are closed except five deliberate exemptions: `deletion_audit_log.id`, `jobs.id`, `live_run_pings.id` and `race_pings.id` (sequence- or identity-backed surrogate keys no client supplies) and `segments.length_m` (`generated always as (end_distance_m - start_distance_m) stored`, both operands already finite). Two columns are not ranges on purpose — `fitness_snapshots.training_stress_bal` takes a pure finiteness term because a mid-build TSB is legitimately negative, and `checkpoint_crossings.body_weight_pct` takes -100..200 because nothing in the repo fixes its sign convention. `vdot` / `vo2_max` cap at 100 on both tables, deliberately WIDER than `vdotFromRun`'s own 90 ceiling, so no shipped writer can be handed a 23514 it cannot act on. Every add is `NOT VALID` with a separate `VALIDATE` per `migration_locks.md`, and each migration header carries the pre-flight query set to run against a populated instance. **Coverage is enforced**: rule 3 of `numeric_bounds_reject_nan_test.sql` fails the PR when a numeric column carries no single-column CHECK and is not named in its `UNBOUNDED_EXEMPT` list with a reason, so a new numeric column is bounded on the day it lands. These are range bounds, not set-shaped ones, so `check_constraint_unions.mjs` deliberately does not cover them — its coverage rule reads `check (col in (…))` only.

**`plan_weeks_plan_id_week_index_key` is `deferrable initially immediate`** (`20270705000003`, [decisions § 1048](../architecture/decisions.md)). `duplicate_plan_week` shifts every later week up one, and a per-row unique check makes a single `week_index = week_index + 1` collide with the row it is about to vacate; the function used to hop the tail through negative index space and back, which is exactly what made `check (week_index >= 0)` unstatable. It now defers the constraint for the span of the renumber and sets it back to `immediate`, so a duplicate raises inside the RPC rather than at COMMIT and every other writer on the table still gets its 23505 at the statement.

**Eleven managed columns discard a client write** (`20270704000003`). `user_profiles.shadow_hidden`, `clubs.shadow_hidden` / `is_verified` / `member_count`, `routes.shadow_hidden` / `is_featured` / `featured_at` / `run_count` / `geom` / `geom_public` / `start_point`, `gym_workouts.set_count` / `volume_kg` and `challenges.participant_count` are each held by a SECURITY **INVOKER** `BEFORE INSERT OR UPDATE` trigger (`freeze_*_managed_columns`) that restores the previous value — or the creation default — whenever `current_user` is `anon` or `authenticated`. Before it, a moderation-hidden account, club or route could unhide itself with one UPDATE (and `user_profiles` a second way, through DELETE + re-INSERT under its own delete-own-profile policy); a club created with `is_verified => true` kept the badge, because `clubs_protect_is_verified_trg` is BEFORE UPDATE only; `member_count` set to 999999 stayed and ranked that club first in `search_clubs`; `run_count` set by the author promoted their route into the `popular` discover lens; and `update routes set geom_public = geom` overwrote the privacy-zone clip `routes_within_box` serves to `anon`. The guard **discards rather than refuses** on purpose — a 42501 on `shadow_hidden` would tell a hidden account that it is hidden, and it would break `backup.dart`'s restore, which upserts a `select()`ed route verbatim. It is SECURITY INVOKER on purpose too: every legitimate writer of these columns is a SECURITY DEFINER function called BY an ordinary user's session, so the JWT role claim and `current_setting('role')` both read `authenticated` inside them and either signal would lock the moderator out; `current_user` follows the definer switch and does not. See [decisions.md § 941](../architecture/decisions.md) and `frozen_managed_columns_test.sql`.

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
- nulls `route_id` / `event_id` when the joined route or event isn't itself public (via SECURITY DEFINER helpers `is_public_route_by_id` / `is_public_event_by_id` — since `20270318_001` all three helpers, incl. `is_public_club_by_id`, also answer false for a `shadow_hidden` target, and the event helper additionally honours the event-level `is_public` gate from `20270113_001`, so an auto-hidden or members-only target can't stay linkable through the public views),
- restricts to `is_public = true`,
- exposes `activity_type` + `is_dnf` as **columns** (public-safe — both were public-safe metadata keys before they were promoted to real columns in `20261207_001`, F3; the view now selects the columns and the keys no longer ride in the `metadata` projection), and likewise the four embedded-best columns `fastest_5k_s` / `fastest_10k_s` / `fastest_half_marathon_s` / `fastest_marathon_s` (public-safe bag keys before their promotion in `20270325_001`),
- exposes `concluded_at` (nullable `timestamptz`, appended to the view by `20270427_001`, issue #613) — the positive live-broadcast finish marker the `/live/{run_id}` spectator surfaces read to flip a run to its conclusion view; null while the run is live or was never broadcast,
- omits `updated_at` — same signal as `metadata.last_modified_at` (already stripped); leaks last-edit / last-sync timestamps to anyone with the share link (`20260807_001`).
- omits `track_url` (the `{user_id}/{run_id}.json.gz` Storage path — dropped `20260924_001` for defence-in-depth so a future Storage-RLS loosening can't re-open direct download from a leaked path) but exposes a derived boolean `has_track` (`track_url IS NOT NULL`, `20261105_001`) so the feed / `/u/[id]` map-thumbnail gate has a safe existence signal without the path. Non-owner thumbnails fetch the clipped trace by `run_id` through the `clip-public-track` Edge Function, which derives the path itself.

**`source` is intentionally kept** in the view: `RunShareView.svelte` renders it as a source badge ("Strava", "Garmin", "parkrun") so a follower can tell where the run came from. The trade-off is provider-context disclosure (a Strava-tagged badge implies the user has a Strava account) vs. UX recognisability — UX wins because the user opted into sharing. If you ever drop the badge, also drop `r.source` from the view.

Granted to `anon` + `authenticated`. Every public-runs reader (`fetchPublicRun`, `fetchPublicRunsByUser`, `fetchPublicRunAttribution`, `fetchFollowingFeed` on web; `fetchPublicRunById`, `fetchPublicRunsByUser`, `fetchFollowingFeed` on mobile) reads the view, not the base table — architecture-guard tests on both platforms enforce this. **The view doubles as an entitlement oracle:** because it runs as its owner and its `where` is `is_public = true`, a returned row *is* the answer to "may this viewer read this run", which is how `/runs/[id]`'s non-owner branch decides whether to render at all (issue #666). `fetchPublicRunAttribution` therefore projects nothing but `user_id` — the run's fields still come from `fetchPublicRun` inside `RunShareView`, so the privacy-zone clip stays single-sourced. Owner-context reads (`select * from runs where user_id = auth.uid()`) keep the bare-table path because they need the unredacted columns. Decisions §33's wire-leak follow-up entry has the full motivation.

**Views grant SELECT only — never rely on the default privileges.** Supabase's default privileges hand anon/authenticated FULL table privileges on every object created in the `public` schema. For tables RLS gates the rows; for VIEWS it silently made every simple (auto-updatable) redacted view a **write path that bypasses RLS** — a write through a view is authorised as the view owner (`postgres`), so an anon `POST /rest/v1/public_race_listings` inserted a base-table row despite the table's authenticated-only INSERT policy. `20270324_001` reset every public-schema view to exactly its documented read audience, and `view_write_privileges_test.sql` pins the invariant with an information_schema catch-all so a future view created without the `revoke all … then grant select` reset fails CI. When you add a view: `revoke all on <view> from public, anon, authenticated;` then `grant select` to the intended audience.

**Base-table grants are now version-controlled too — don't rely on the default privileges for them either.** The flip side of the view lesson bit prod on 2026-07-13: onboarding failed with `42501 permission denied for table user_profiles` / `user_settings` because the `authenticated` role had lost its base `insert/update/delete` (and some table `SELECT`) grants — grants that had **only ever existed via Supabase's implicit default privileges**, never a migration, so nothing restored them once prod drifted. `20270408_001` makes the whole intended matrix explicit + idempotent: one `grant` per (table, grantee) for `select/insert/update/delete` across every public base table, plus the column carve-outs, with `app_quota` + `deletion_audit_log` left service_role-only. It's additive (never tightens, never grants table-SELECT on a column-locked table) so it's a no-op on a healthy DB and safe to replay. When you add a base table, add its grants to a migration — don't assume the default privileges will carry them to every environment. Rationale in [decisions.md §232](../architecture/decisions.md). This broad DML surface is inert only because every granted table's RLS policies are `(select auth.uid())`-scoped; `rls_grant_without_policy_test.sql` is the defence-in-depth backstop that fails CI the moment a permissive policy with a trivially-true (literal `true`) `USING` / `WITH CHECK` lands on a DML-granted table — the future `create policy … to anon using (true)` that would turn the standing grant live and make the table anon-writable.

**Four tables revoke table-level SELECT and re-grant column by column, and the withheld set is a registry.** `user_profiles` (16 columns withheld — billing state, `parkrun_number`, `date_of_birth` / `gender` / `height_cm`, the consent stamps, `shadow_hidden`; `20260707_001` + `20260810_001`), `events` (3 — `meet_lat` / `meet_lng`, and `host_user_id` the Stripe Connect payout recipient), `clubs` (1 — `invite_token`), and `checkpoint_crossings` (5 — the Art 9 weigh-in fields plus `recorded_by`). Each withheld column has a named `SECURITY DEFINER` replacement read path (`get_my_profile()`, `get_event_meet_point()`, `get_club_invite_token()`, `fetch_checkpoint_crossings_for_organiser()`). **Two consequences of that shape, both real and neither a defect.** `has_table_privilege('anon', 'public.events', 'SELECT')` is **false** while `select count(*) from public.events` as `anon` **succeeds** — Postgres checks column privileges for the columns a query *names*, and `count(*)` names none — so anything reasoning about table privileges alone gets a false negative here. And a direct `select xmin` / `ctid` / `tableoid` by `anon` or `authenticated` raises `42501`, because a per-column grant enumerates user columns only. (An RLS **policy** expression referencing `xmin` is unaffected: policy expressions are not column-privilege-checked. That is why the pgtap refusal-mutation operator reads these four tables normally — see [decisions § 759](../architecture/decisions.md).) **The failure mode to actually watch is drift.** A re-grant is cumulative, so a column added to one of these tables after its lockdown is deny-by-default until an explicit `grant select (col)` lands; `clubs.is_verified` (`20260909_001`) shipped without one and took down every non-service-role read of `clubs` with `42501` until `20260913_001` repaired it. When you add a column to any of the four, add its grant in the same migration — or, if it is meant to stay withheld, add it to the registry in `column_grant_lockdown_registry_test.sql` with the reason. That test is the class-level guard: it pins the withheld set per role in both directions, fails when a table outside the registry acquires the per-column shape, and fails when one of the four regains table-level SELECT.

**Four *other* tables do the same for INSERT / UPDATE, and that shape has a second failure mode the read side does not.** `achievements` (UPDATE `is_public` only, `20270506_001`), `challenge_participants` (UPDATE `team_club_id` only + INSERT `(challenge_id, user_id, team_club_id)`, `20270209_001` + `20270616_001`), `coach_messages` (UPDATE `(archived_at, reaction)` + INSERT `(user_id, plan_id, role, content)`, `20260518_001` + `20270616_001`), `event_attendees` (both verbs, `20270102_001` + `20270520_001`). Only `authenticated` holds any of them — `anon` holds **no** column-level write grant at all, so this is not the read side's both-roles-identical shape. **The drift mirrors the read side**: a column added after a lockdown is deny-by-default and silently *unwritable* (`42501` on a PostgREST PATCH or POST), so add its grant in the same migration or register it as withheld. **The second failure mode is worse and has fired.** A column-scoped UPDATE locks nothing while the same client holds a *wider* INSERT on a table it may also DELETE from, because DELETE + re-INSERT reaches every column the UPDATE grant withheld — [decisions § 584](../architecture/decisions.md) found it on `event_attendees` (a buyer self-writing `attendance`), and `challenge_participants` still carried it until `20270616_001`, so `completed_at` was writable in two statements by the participant. `column_grant_write_lockdown_registry_test.sql` is the class guard for both: the withheld write map per role and verb with a reason per column, no unregistered table carrying the shape, no locked verb regaining a table grant, `anon` never wider than `authenticated` on any column (the one live divergence in the schema was `coach_messages` UPDATE, revoked by `20270616_001`), every insertable-but-not-updatable column registered write-once with the reason writing it once is safe, and the append-only exemption (`global_segment_efforts`) checked rather than trusted. See [decisions § 763](../architecture/decisions.md).


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
create index routes_name_trgm on routes using gin (name extensions.gin_trgm_ops);
-- 20270326_001: per-sort-branch partial indexes for search_public_routes
create index routes_public_popular_sort on routes (run_count desc nulls last, created_at desc)
  where is_public = true and shadow_hidden = false;
create index routes_public_featured_sort on routes (featured_at desc nulls last, created_at desc)
  where is_public = true and shadow_hidden = false;
create index routes_public_newest_sort on routes (created_at desc nulls last)
  where is_public = true and shadow_hidden = false;
-- 20270423_001 dropped the superseded routes_featured index
-- (featured_at desc nulls last where is_featured and is_public): the featured
-- branch above orders ALL public rows and is served by routes_public_featured_sort,
-- so the old is_featured=true-only partial index served nothing (issue #407).
```

**`start_point`** is a PostGIS `geography(Point, 4326)` column storing the route's starting coordinates. It is auto-populated by a `BEFORE INSERT OR UPDATE` trigger which, since `20260925_001`, snaps it to the first waypoint that is **not** inside one of the owner's privacy zones (`NULL` when every waypoint is). A GiST spatial index powers the `nearby_routes` RPC for proximity search, which filters `start_point is not null` — so a route built entirely from home drops out of proximity search rather than pinning it.

**`geom`** is the matching `geography(LineString, 4326)` column for the *full* route, populated from `waypoints` by the same kind of `BEFORE INSERT OR UPDATE` trigger (`routes_set_geom`). Backed by `routes_geom_gist`. Unlocks queries that `start_point` can't answer — "routes that pass through this area", "routes that intersect another route", "routes near a run's track" — via `ST_Intersects` / `ST_DWithin` against the line itself. Both client codegens emit it as opaque (`unknown` in TS, `dynamic` in Dart); the binary EWKB never reaches a renderer, so callers should keep using `waypoints` for drawing and reach for `geom` only inside RPC bodies. Routes with fewer than two valid lat/lng waypoints store `null` (a LineString needs at least two points). Because a `select('*')` would ship this binary over the wire for nothing, the "My routes" read (`fetchRoutesWithError`) enumerates an explicit `ROUTE_LIST_COLS` (base table) / `PUBLIC_ROUTE_LIST_COLS` (view) that omits `geom` + `start_point` — mirroring the `CLUB_SELECT_COLS` idiom.

**`geom_public`** is the same LineString **clipped to the owner's privacy zones** — the geometry a non-owner is already served by `clip_route_for_viewer`, materialised so a public spatial predicate has something zone-aware to run against. Maintained by the same trigger pair as `start_point` (folded into `routes_set_geom`, plus the `user_settings` zones trigger for a retroactive re-clip), backed by `routes_geom_public_gist`, and derived through `privacy_aware_route_geom` → `clip_track_for_user` so it can never drift from the read path. `routes_within_box` is its only consumer and **fails closed** on it: `geom_public is not null` with no fallback to `geom`, so a fully-in-zone route is not returned at all. Registered in [`derived_state.md`](derived_state.md); rationale in `docs/architecture/decisions.md § 566`. Opaque to both codegens, same as `geom`.

**`club_id`** makes a route club-owned: any club admin can edit it, any member can read it regardless of `is_public`. Two RLS policies layer on top of the existing user-owned + public-readable policies — `"club members read club routes"` (SELECT where `club_id is not null and is_club_member(club_id)`) and `"club admins write club routes"` (ALL where `club_id is not null and is_club_admin(club_id)`). See `docs/architecture/decisions.md § 30` and `docs/features/clubs.md § Club-owned routes`. The owner policy `"users own their routes"` carries a `with check (auth.uid() = user_id and (club_id is null or private.is_club_admin(club_id)))` (migration `20270123_001`) so the OR'd permissive evaluation can't be used to set `club_id` to a club you don't administer — a non-admin can only ever write personal (`club_id is null`) rows. The same owner-path `club_id` lockdown is applied to `training_plans` (`"users own their plans"`, club branch additionally requires `is_template = true`) and `session_plans` (`"authors own their session plans"`).

**`is_starred`** is the owner's "what I actually run" flag. The watch's route picker fetches `is_starred=eq.true&order=updated_at.desc&limit=30` so a 1.4-inch round screen never has to scroll through every saved route. When the starred query returns nothing (first-launch / un-curated user), the watch falls back to the 10 most-recently-updated owned routes so the picker isn't empty. Toggleable from web (`/routes` cards + `/routes/[id]` header) and mobile (routes list + detail screen); read-only from the watch. Backed by a partial index keyed on `(user_id, updated_at desc)` so the watch fetch is index-only.

**Public reads go through the `public_routes` view, not the base table.** Migration `20260703_001_drop_routes_public_select_policy.sql` drops the bare-table public-read RLS; non-owner reads (anon + authenticated) consume `public_routes` instead. The view is a thin projection over `routes` filtered to `is_public = true` with `geom` cast back to `unknown`/`dynamic` for the row-type generators. Cross-references the same shape used by `public_runs` (decisions §33). Every public-routes reader on web (`fetchPublicRoutes`, `searchPublicRoutes`, `fetchPublicRouteById`) and mobile (`api_client.fetchRouteById` for non-owners) reads the view. Owner-context reads keep the bare-table path because they need the unredacted columns.

**`public_routes.user_id` is intentionally exposed.** Combined with `public_runs.user_id`, it makes `auth.users.id` (UUID) a stable cross-link between a public route, the public runs that ran on it, and the runner's `/u/[id]` profile page. That linkage is the entire point of the social surface — followers click through from a friend's run to the route they used, then to their profile. The trade-off is that a runner can't share a single public route or run without publishing their auth UUID as a durable identifier; if/when handles ship (decisions §31), the UUID will be aliased but the cross-link will still be present at the schema layer.

**`public_profiles` view** (migration `20260824_001_public_profiles_view.sql`) — anon-readable projection of `user_profiles` exposing only `id`, `display_name`, `avatar_url`. The base `user_profiles` table is owner-only by RLS (`auth.uid() = id`), which blocked the prerendered share pages from baking the runner's name into the og:title. The view restores that single read path with the same privacy posture as `/u/[id]` (display_name + avatar are already on every share-page body via RunSocial / kudos / comments for any authed viewer; the only delta is anon crawlers now see the same name on the unfurl card). No way to enumerate "all users" — callers must supply a uuid up-front (typically from a `public_runs` / `public_routes` row). To retract per-user, add a `crawler_visible` flag to `user_profiles` and a `WHERE` clause on the view. Since `20270329_001` the view carries `where shadow_hidden = false` (the auto-hide backstop completion, decisions §206) — a moderation-hidden profile is unresolvable through it. Anon bulk SELECT on the view was separately revoked in `20261011_001` (anon lookups go through `public_profile_by_id`, which filters `shadow_hidden` + blocks).

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
readable when the parent route is visible (`private.is_route_visible_to` —
which since `20270329_001` answers false on the public branch for a
`shadow_hidden` route, so hidden routes' markers/reviews/segments/conditions
and `route-photos` bytes drop out for everyone but the owner + club members).
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

The owner of the parent route attaches photos (INSERT policy: `auth.uid() = owner_id AND owns the route`). Photo owner OR route owner can DELETE (moderation). SELECT gates on `private.is_route_visible_to(route_id, auth.uid())` (own / public / club-member) on both the table and the Storage bytes (joining through `route_photos.storage_path` OR `thumb_512_path`), so a route flipping public→private propagates within the signed-URL TTL. `storage_path` + `thumb_512_path` carry owner-prefix-shape CHECKs; a BEFORE-UPDATE trigger blocks clearing `storage_path` (use DELETE) and another blocks user-side `thumb_512_path` writes (service-role only). **EXIF stripping is two-layered** (matching `run_photos`, migration `20270224_001`): the clients strip location-bearing metadata *before* upload (web `stripExifFromFile`, mobile `stripImageExif` — JPEG APP1, PNG `eXIf`/text chunks, WebP `EXIF`/`XMP` chunks), and the Go `job_worker` `route_photo_process` handler re-strips server-side + generates the 512w gallery thumbnail (`{owner}/{photo_id}_512.jpg`) and PATCHes `thumb_512_path` (service-role). Two enqueue triggers fire the job: an AFTER INSERT (web upload-then-insert) and an AFTER UPDATE OF `storage_path` (mobile insert-placeholder-then-PATCH); the service-role thumb PATCH never re-enqueues. Clients prefer the thumbnail in galleries and fall back to the original while the column is still null. Pinned by `rls_route_photos_test.sql` (13 assertions) + `route_photos_enqueue_process_test.sql` (6 assertions).

#### `club_photos`

Photos attached to a club — a member-contributed gallery (roadmap backlog row 8, the deferred "club-photo features"; migration `20270301_001`, decisions §190). Metadata in Postgres, bytes in the **private** `club-photos` Storage bucket at `{owner_id}/{photo_id}.{ext}` (signed URLs, 15-min TTL).

```sql
create table club_photos (
  id              uuid primary key default gen_random_uuid(),
  club_id         uuid references clubs(id) on delete cascade not null,
  owner_id        uuid references auth.users(id) on delete cascade not null,
  storage_path    text not null,
  thumb_512_path  text,
  caption         text check (caption is null or length(caption) <= 280),
  position_idx    smallint not null default 0,
  created_at      timestamptz not null default now()
);
```

Re-keys the `route_photos` shape to club membership. **INSERT** requires `auth.uid() = owner_id AND private.is_club_member(club_id)` — *any active member* contributes, not just the club owner. **SELECT** gates on club visibility (`clubs.is_public OR clubs.owner_id = auth.uid() OR private.is_club_member`) on both the table and the Storage bytes (joining `club_photos` → `clubs`), so a public club's gallery is readable by anyone (incl. anon) and a private club's only by active members / the owner; flipping a club private propagates within the signed-URL TTL. **DELETE** is photo-owner OR `private.is_club_admin(club_id)` (moderation). **Caption UPDATE** is photo-owner only. `storage_path` + `thumb_512_path` carry the same owner-prefix-shape CHECKs + the no-blank-clear + service-role-only-thumb BEFORE-UPDATE triggers as route_photos. **EXIF stripping** is two-layered: client-side before upload (web `stripExifFromFile`, mobile `stripImageExif`) PLUS the Go worker `club_photo_process` handler (AFTER INSERT trigger + an AFTER UPDATE OF `storage_path` trigger for the mobile insert-then-PATCH path) which re-strips JPEG EXIF + writes the 512w `thumb_512_path` (service-role only). `club_photo_process` is in the `jobs.kind` allowlist. Pinned by `rls_club_photos_test.sql` (17 assertions). Exported in the GDPR Art 20 spec (owner_id-keyed).

#### `notifications`

Inbox rows for the social loop (decisions §38). Materialised by `after insert` (kudos / comments / follows / club posts / completed runs) and `after insert or update` (event RSVPs) SECURITY DEFINER triggers on `run_kudos`, `run_comments`, `user_follows`, `event_attendees`, `club_posts`, and `runs` so the notification lands in the same transaction as the source write. Not every kind comes from a trigger: `data_export_ready` (`20270607_001`, [decisions § 729](../architecture/decisions.md)) is written by the `notify_data_export_ready()` RPC the Go worker calls once a queued Art 20 export is `ready` — the kind carries **no FK**, because the export lives in `data_export_jobs` and the notification's deep link is `/settings/account`, where the signed download URL is minted at read time. `refund_failed` (`20270701000001`, [decisions § 825](../architecture/decisions.md)) comes from a trigger, but from a **money ledger** rather than a social one: one `after update of status ... when (old.status is distinct from new.status and new.status = 'refund_failed')` SECURITY DEFINER trigger on `event_orders` and one on `donations`, so the payer is told once when the bank sends a refund back. The transition IS the dedupe — the `stripe-events-webhook` CASes against the status it read, so a redelivered event updates no row and fires nothing, which is why this kind needs no `notified_at` stamp. The order arm carries `event_id` + `event_instance_start`; the donation arm carries **no FK**, because `donations` has no client SELECT policy and there is no donor-readable row to point at, so both clients render it as plain text and the outbound CTA falls back to the inbox. An anonymous donation (`donor_user_id` null) is skipped in the function rather than left to raise 23502 inside the webhook's own UPDATE, which would roll the ledger move back with it.

**Widening the `kind` CHECK takes the `NOT VALID` + `VALIDATE` two-step** — `notifications` is in the migration-locks guard's `GUARDED_TABLES`, and a single-step drop-and-recreate scans every notification ever written under ACCESS EXCLUSIVE for a widen that cannot invalidate a single existing row. `20270607_001` is the first kind migration to do so; the twelve before it are grandfathered.

```sql
create table notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  actor_id    uuid references auth.users(id) on delete set null,
  kind        text not null check (kind in ('kudos','comment','comment_reply','follow','event_rsvp','event_cancel','plan_update','message','club_post','run_completed','event_reminder','plan_assigned','achievement','challenge_complete','content_hidden','data_export_ready','refund_failed')),
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

**Bulk dismiss goes through `delete_notifications(p_ids uuid[])`** (migration `20270529_001`), not a client-side `in` filter. PostgREST serialises an `in` filter into the request URL, which leaves a large dismiss at the mercy of whatever request-line budget the gateway in front of PostgREST enforces — measured against the local stack the DELETE is refused with a **414** past roughly 200 ids, while decisions § 653 records a gateway that answered 200 with an empty match instead. Either way the rows survive, and which failure you get is a property of the deployment rather than of the code. Chunking the list dodged the bound and bought a partial dismiss instead, since chunk 3 of 5 can fail with the undo offer already spent. The RPC's array argument rides the POST body instead, and one call is one statement in one transaction: every id goes or none does. It is **SECURITY INVOKER** with no owner predicate of its own — the existing `auth.uid() = user_id` DELETE policy is the whole authorisation story, so a caller naming a stranger's id deletes nothing and is told so by the returned count. Arrays past **1000 ids** raise `22023` rather than truncating; a silent cap would re-open the same class of bug in a new place, and both inboxes page at 100 rows so the ceiling is far above any dismiss a surface can assemble. Callers: web `deleteNotifications` in `core/data.ts`, mobile `ApiClient.deleteNotifications`.

#### `direct_messages`

```sql
create table direct_messages (
  id            uuid primary key default gen_random_uuid(),
  sender_id     uuid references auth.users(id) on delete cascade not null,
  recipient_id  uuid references auth.users(id) on delete cascade not null,
  body          text not null check (length(btrim(body)) between 1 and 4000),
  created_at    timestamptz not null default now(),
  read_at       timestamptz,
  route_id      uuid references routes(id) on delete set null,  -- 20270619_001
  check (sender_id <> recipient_id)
);
```

1:1 direct messages (very-social persona #55, migration `20261026_001`). A "thread" is the unordered participant pair — no separate threads table; indexes use `least/greatest(sender_id, recipient_id)` so A→B and B→A share a symmetric thread index. RLS: each participant reads their own threads; **INSERT is gated on `not is_blocked_either_way(sender, recipient)` AND an existing follow in either direction** — a plain `user_blocks` subquery would be hidden from the sender by that table's owner-read RLS, so the SECURITY DEFINER helper is load-bearing here, not a convenience. The recipient marks read (UPDATE); either party deletes. A `message` notification fires to the recipient only on the first unread message of a burst (the trigger checks for an existing unread from the same sender) so an active thread doesn't flood the bell. Deferred: realtime delivery, a non-follower "message requests" inbox, mobile.

**Typed route attachment (migration `20270619_001`, [decisions § 772](../architecture/decisions.md)).** `route_id` carries the optional route a message shares, replacing the raw share URL v1 put in the body as the thing the thread *renders* (the body keeps the URL: `dm_threads()` returns only `last_body` and the Art 20 export selects `*`, so both read the body and neither resolves an attachment). `on delete set null`, not cascade — a message is the sender's own correspondence and must outlive the route it named, so a third party tidying up their routes cannot delete someone's private conversation. The INSERT policy gained `route_id is null or private.is_route_visible_to(route_id, auth.uid())`: **sender-side**, because a recipient-side check would accept or refuse the identical insert depending on the addressee (a club route is visible to a club-mate and to nobody else) and raise a 42501 the sender cannot act on. What the *recipient* may see is decided at read time — the web card resolves through the owner-aware `fetchRouteById`, so a non-owner gets the `public_routes` view plus `clip_route_for_viewer`'s privacy-zone clip, and a route they may not see renders as unavailable rather than as a dead link. Covering partial index `direct_messages_route_id`. pgtap: `direct_message_route_attachment_test.sql`.

**Send throttle (migration `20270608_001`).** The BEFORE INSERT trigger `direct_messages_enforce_send_rate_limit` calls the shared `enforce_create_rate_limit` helper twice per row, against **two** buckets: `send_direct_message` at 250/hour and `send_direct_message_burst` at 30/minute. Two windows because `check_rate_limit` is fixed-window, so one "N per hour" either admits the whole allowance in a single instant or trips a real back-and-forth — the burst bucket bounds how *fast* messages arrive, the hour bucket how *many*. The hour bucket is checked first so a sender who has spent both is told the binding wait rather than a 40-second one. The throttle lives on the table because `direct_messages` has exactly one write path (a PostgREST INSERT — no RPC, no Edge Function, no Go worker), so every entry point inherits it; [decisions § 734](../architecture/decisions.md) declined a per-affordance throttle for that reason and [§ 737](../architecture/decisions.md) records the sizing. Unlike the standalone RPC path, a *refused* send does not spend budget: the raise aborts the statement and rolls the increment back with it, so the counters count sent messages. Web `sendDm` routes the P0001 through the shared parser, which since [decisions § 744](../architecture/decisions.md) returns `{bucket, seconds}` and leaves the sentence to the locale catalogue — both send buckets resolve to the same "sending messages" wording, since which of the two windows refused is our accounting rather than the sender's. pgtap: `direct_message_rate_limit_test.sql`.

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

`segment_leaderboard_tiered(p_segment_id, p_gender, p_age_band, p_limit, p_club_id)` — SECURITY DEFINER, `search_path = public, private`, block-guarded, route-visibility-filtered, own-row-only demographics. Returns **one row per athlete** (each athlete's best VISIBLE effort), not one per effort: a `distinct on (se.user_id)` CTE reduces the efforts *after* every gender / age-band / club / visibility / block filter is applied, then the outer query ranks + limits the deduped set, so `p_limit` counts distinct competitors and no runner can hold multiple ranks (issue #393, migration `20270424000003`). Ranks are assigned client-side (`assignCompetitionRanks`) from the returned order. The run-detail chip's `segment_effort_ranks` counts over the same per-athlete population since migration `20270523_001`, so the two surfaces agree on an athlete's rank. **Route visibility is delegated to `private.is_route_visible_to`, resolved once per call** (migration `20270524_001`, decisions §596) — the body previously inlined a bare `r.is_public = true` and so served a moderation-hidden route's whole board, and every effort on a segment shares one route, so the question is per-call rather than per-row. A **shadow-hidden athlete keeps their row and rank but `display_name` + `avatar_url` are withheld** from everyone but themselves; the row is redacted rather than dropped so the chip and the board still agree. **The age band is gated on `health_data_consent_at`** (migration `20270606_001`, decisions §727): `date_of_birth` is the child-safety age record and carries no consent term of its own, but deriving an age from it is Art 9 processing, so a runner who supplied a date and withheld the Art 9 consent falls out of the age tier entirely — exactly as a runner with no date does — and their own `age` echo is null. Both sites carry the term: the band-membership filter and the caller's own age echo. The gender tier needs no such term (`gender` is only ever populated under consent). pgTAP `segment_leaderboard_tiered_test.sql` + `segment_leaderboard_shadow_hidden_test.sql` + `segment_leaderboard_age_band_consent_test.sql`.

#### `global_segments` / `global_segment_efforts`

Free-standing global/famous-segment catalogue (decisions §232, migration `20270411_001`). Unlike v1 `segments`, a `global_segments` row carries its **own** polyline (`waypoints jsonb`, same `[{lat,lng,ele?}]` shape as `routes.waypoints`) with no `route_id` dependency — so a run can match it without anyone having re-created the road as an in-app route first (the imported-run, `route_id`-null case). `global_segments` is world-readable for `is_active = true` rows; only the `app_admins` allow-list (`private.is_admin`, migration `20270105_001`) may insert / edit / pull, and `is_active` is a soft-delete so pulling a bad entry doesn't cascade away athletes' efforts. `global_segment_efforts` (`unique(global_segment_id, run_id)`) mirrors `segment_efforts`: run-owner-only insert, base-table SELECT gated on `segment active AND private.is_run_visible_to(run_id, caller)` so a private run never leaks onto a catalogue leaderboard.

Two RPCs back the read surfaces:

- `global_segment_leaderboard(p_segment_id, p_gender, p_age_band, p_limit, p_club_id)` — SECURITY DEFINER, block-guarded (`is_blocked_either_way`), the catalogue twin of `segment_leaderboard_tiered` minus the route-visibility branch. Like its sibling it returns **one row per athlete** (each athlete's best VISIBLE effort) via a `distinct on (se.user_id)` CTE applied *after* every gender / age-band / club / visibility / block filter, so `p_limit` counts distinct competitors — an athlete with many efforts on the same catalogue segment can neither hold multiple ranks nor push a slower competitor off a limited board. The catalogue board shipped without that reduction and got it in migration `20270513_001`; the route board got it in `20270424000003` (issue #393). Requires an authenticated caller (raises `42501` in-body; granted to `anon` too only so the call enters the body rather than SEGV-ing on a missing EXECUTE). Demographic columns are disclosed only for the caller's own row, and since `20270524_001` a shadow-hidden athlete's `display_name` + `avatar_url` are withheld from everyone but themselves (decisions §596; the row and its rank survive). Since `20270606_001` its age band carries the same `health_data_consent_at` gate as its sibling, on both the band-membership filter and the caller's own age echo (decisions §727). pgTAP `global_segment_leaderboard_per_athlete_test.sql` + `segment_leaderboard_shadow_hidden_test.sql` + `segment_leaderboard_age_band_consent_test.sql`.
- `global_segment_effort_ranks(p_run_id)` — SECURITY INVOKER, the catalogue twin of `segment_effort_ranks`; `rank = 1 +` the distinct **other athletes** holding a strictly-faster visible, non-blocked effort on the same segment, in one round-trip for the run-detail chips. Same per-athlete population as the board above since migration `20270523_001` — see `segment_effort_ranks` below for the contract, including the `private.viewer_blocks` delegation both bodies now share. Granted to `anon` + `authenticated`: `20270411_001` granted `authenticated` only while `20270512_001` granted `anon` SELECT on both catalogue tables, so a logged-out reader of a public run got the effort rows and no ranks over them (migration `20270609_001`, decisions §746). pgTAP `global_segment_effort_ranks_per_athlete_test.sql` + `global_segment_grants_test.sql`.

Matching stays narrow — end-to-end against curated geometry via `computeGlobalSegmentEffort` (reusing `computeEffortFromTrack`); arbitrary-geometry HMM/Hausdorff matching is deferred. pgTAP `global_segments_test.sql`.

---

#### `reports`

User-submitted reports against a profile, club, route, comment, club post, run, or route review. Polymorphic via `(target_kind, target_id)` where `target_kind ∈ {'user', 'club', 'route', 'comment', 'club_post', 'run', 'route_review'}` — the TS union `ReportTargetKind` (`apps/web/src/lib/types.ts`) is kept in lockstep with this CHECK by `apps/web/scripts/check_constraint_unions.mjs`. (`route_review` added `20270402_001`.) Reason is constrained to `{'spam', 'harassment', 'inappropriate', 'impersonation', 'other'}`; status is `{'pending', 'reviewed', 'dismissed'}`. A partial-unique index `reports_no_duplicate_pending` enforces one pending report per (reporter, target) pair — once status flips to reviewed/dismissed the same reporter can re-file if the target reoffends.

Inserts go through the `submit_report(p_target_kind, p_target_id, p_reason, p_notes)` SECURITY DEFINER RPC, which validates the target row exists (per kind: `user_profiles` / `clubs` / `routes` / `run_comments` / `club_posts` / `runs` / `route_reviews`), rejects self-reports on `target_kind='user'` and on a self-authored comment / club post / run / route review (a misclick — the review's author column is `route_reviews.user_id`) with `22023`, rate-limits via the shared `enforce_create_rate_limit` helper at 10/hour per reporter, and surfaces duplicate-pending as a 23505 with a "you already have a pending report" hint. RLS hides others' reports from each user — the only way to *read* `reports` cross-user is via service_role, which is intentional: reports are pending evidence, not public attribution.

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

Shadow-hidden rows are filtered out of every public/search/discovery surface with `and not shadow_hidden`: the `public_routes` view (cascades to `search_public_routes` / `nearby_routes` / `routes_within_box`), `discoverable_routes_in_bbox`, `search_clubs` (+ a `grant select (shadow_hidden) on clubs` for its invoker-mode rowtype projection) + `clubs_in_bbox`, `public_profile_by_id`, `search_user_profiles`, and — since `20270328_001` — the **base-table SELECT RLS policies for `clubs` + `events`** (the "public clubs are readable by anyone" policy gains `and shadow_hidden = false`; the events policy's club-public branch gains `and clubs.shadow_hidden = false`; events have no column of their own so the parent club's flag governs). `20270329_001` completed the backstop for the two surfaces that first pass missed: the **`user_profiles` base SELECT policy** (now `auth.uid() = id or shadow_hidden = false`) + the `public_profiles` view (`where shadow_hidden = false`), and the routes SECURITY DEFINER visibility helpers **`private.is_route_visible_to`** + **`clip_route_for_viewer`** (shadow_hidden gate on the public branch — being DEFINER they don't inherit `routes` RLS the way the club-photos storage policy's plain join inherits `clubs`', so they needed their own clause; this also covers `route_photos`/`route_reviews`/`segments`/`route_markers`/`route_conditions` and the `route-photos` bucket, which all gate on the helper). The backstop means a direct anon/non-member read can no longer surface a hidden row even if the caller forgets the filter — the gap that let the `/share/*` SEO surfaces leak before it landed (decisions §206). Owner + admin reads go through other paths (owner/member RLS — the club member policy was broadened to cover a hidden-but-public own club — / admin RPCs), so a hidden owner still sees their own row, and an active club member keeps club-scoped visibility of hidden club routes. Admins revert via `admin_unhide_target`. Pinned by `apps/backend/supabase/tests/auto_hide_reports_test.sql` (19 pgtap subtests) + `rls_shadow_hidden_backstop_test.sql` + `rls_shadow_hidden_backstop_pt2_test.sql` + `apps/web/tests-e2e/admin/auto-hide-unhide.spec.ts`.

### Clubs & events

#### `clubs` / `club_members` / `events` / `event_attendees` / `club_posts`

The social layer. See `docs/features/clubs.md` for surfaces and `docs/product/roadmap.md § Clubs and events` for phasing. Added in `20260416_001_clubs_and_events.sql`.

```sql
create table clubs (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid references auth.users not null,
  name          text not null check (char_length(name) <= 80),
  slug          text unique not null,                 -- URL-safe, generated from name
  description   text check (description is null                  -- 20270502_001; the sibling standard
                            or char_length(description) <= 2000),-- (events / challenges descriptions)
  avatar_url    text,
  location_label text check (location_label is null              -- freeform "Austin, TX"
                             or char_length(location_label) <= 80),
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

**Helper functions** (RLS readability): `private.is_club_member(club_id)` and `private.is_club_admin(club_id)` — `security definer` functions that encapsulate the `club_members` lookup so every policy below can read cleanly. A trigger auto-enrolls the owner as an `owner`-role member on club insert, so the helpers work uniformly for owners too. They **live in the `private` schema** (migration `20261120_001`), which PostgREST does not expose, so they can't be probed as anon RPC oracles (audit-findings 2026-05-30 Medium); RLS policies reference them by the `private.`-qualified name (the schema move rewrites the dependency automatically). A migration re-creating one of these policies must therefore write `private.is_club_member(...)` — the bare name no longer resolves at create-time.

The two club SELECT surfaces — the `club_members` roster policies and the `club_posts` feed policy — additionally carry `and not is_blocked_either_way(auth.uid(), <user_id|author_id>)` (migration `20270402_001`, decisions §228), so a blocked user is hidden from the roster and post feed in both directions, matching every other social read path. The self-membership row and the admin pending-request moderation queue are deliberately un-guarded.

**`events.meet_lat` / `meet_lng` are column-revoked** from both `anon` and `authenticated` (migrations `20260723_001` / `20260806_001` / `20260818_001`) — a direct `select meet_lat, meet_lng from events` raises `42501`, because precise meeting coordinates would otherwise leak an organiser's home address to any signed-in non-member of a public club. The member-facing map pin + "Get directions" link on the event detail page reads them through `get_event_meet_point(p_event_id uuid) returns table(meet_lat, meet_lng)` (migration `20261027_001`): a `security definer` function that returns the coordinates only when `is_club_member(events.club_id)` and the point is set, and zero rows otherwise. EXECUTE is granted to `anon` + `authenticated` — the in-function membership check is the authorization gate, not the EXECUTE grant. Persona-hunt social-group #10.

**`events.category` / `discipline` / `gym_template` column grants** (the typed-events surface). `events` is column-SELECT-locked (`20260818_001`), so each column added after it is deny-by-default for `anon`/`authenticated`. `20261228_001` grants `SELECT (category, discipline)` (the public category-gating + class discipline label). `20261230_001` grants `SELECT (gym_template)` — the optional `{discipline, duration_min}` jsonb hint a class host sets, read by the attendee-side "Log this as a workout" seam (it carries no PII, so a plain column grant is the right shape, not a SECURITY DEFINER RPC). `host_user_id` (payout recipient) **stays revoked** — it has no client read site. `20270111_001` adds `events.timezone` (IANA, the event's local wall-clock zone captured at create) + `grant select (timezone)` — read by the `search_public_events` discovery RPC to resolve a local time-of-day filter; a non-sensitive string, so a plain grant (not a SECURITY DEFINER RPC) is the right shape. WRITE: `20260818_001` revoked only SELECT, so the event author already writes `category`/`discipline`/`gym_template`/`timezone` through the unrestricted INSERT in `createEvent`. Pinned by pgtap `event_gym_template_grants_test.sql`.

**`search_public_events` RPC** (`20270110_001` + `20270111_001` + `20270112_001`) — the cross-club activity discovery query backing the `/social` Discover tab. `security invoker` + scoped to `clubs.is_public = true` (mirrors `search_clubs`); filters the typed-events model by category / discipline (`p_query` ILIKEs discipline OR title — pg_trgm indexes `events_discipline_trgm` + `events_title_trgm`, the latter `20270316_001` so both OR branches are indexable) / cadence / weekday / free-or-paid / local time-of-day / **proximity**. `20270112_001` adds `p_center_lng/p_center_lat/p_radius_m` (default 50km): when a center is supplied it gates on `ST_DWithin(clubs.location_point, center, radius)` (GiST index `clubs_location_point_gist`), orders nearest-first, and returns `distance_m` for an "X away" label. Proximity filters by the **club's** public `location_point`, never the event's `meet_lat/meet_lng` (revoked to members-only via `get_event_meet_point`, `20261027_001`) — so discovery can't expose a class's exact address; clubs with a null point are excluded under an active near-me but surface on every other filter. No `SECURITY DEFINER` — the events RLS already permits reading a public club's events, so it can only return rows the caller could already see. `20270113_001` adds an explicit `e.is_public = true` filter so a members-only event is never discoverable (even by a member of its club — discovery is for the public surface). `20270527_002` fixes `p_byday`: the one-off-event weekday branch derived `extract(isodow from e.starts_at)` off the raw timestamptz, which resolves in the CALLER's session timezone (UTC under PostgREST), so a 20:00 New York event was filed under Monday and an east-of-UTC early-morning event under the previous day — it now goes through `at time zone coalesce(e.timezone, 'UTC')` exactly as the sibling `p_time` branch always did. Pinned by `search_public_events_test.sql` (13 assertions) + `search_public_events_byday_timezone_test.sql` (5, straddling UTC in both directions plus a non-UTC session timezone).

**Event-level visibility — `events.is_public`** (`20270113_001`, decisions §148). Default `true`. The `events` SELECT policy is the single source of truth: `<club gate> AND (events.is_public OR private.is_club_member(club_id))` — so a public club can mark an individual event members-only (committee meeting, private social, draft) and it's hidden from non-members + anon + discovery, while a private club's events stay members-only via the club gate as before. Every event-delegating surface (`event_attendees`, `event_results`, `race_pings`, `run_photos` table + storage, the event photo gallery) **inherits** this automatically because each gates via an `exists (… from events …)` subquery (the caller's RLS on `events` applies inside it). The two that don't inherit were fixed in the same migration: event-tied `club_posts` (its SELECT checked the club only — re-gated to inherit event visibility for event-tied posts) and `is_event_visible` (the `SECURITY DEFINER` helper backing `event_pricing` — definer bypasses the caller's RLS, so it was leaking members-only pricing; recreated to mirror the event-level gate). Its club-public branch delegates to `is_public_club_by_id` since `20270524_001` (decisions §596): the pasted `c.is_public = true` never received the shadow-hidden exclusion `20270328_001` gave the clubs + events policies, so a moderation-hidden club's events — and the `event_pricing` / `event_checkpoints` / `checkpoint_crossings` rows this oracle gates — stayed readable. Owner and member branches are untouched. Column-SELECT-locked table, so a `grant select (is_public)` was added for clients + the security-invoker discovery RPC. Pinned by `rls_events_test.sql` (23 assertions).

**`event_attendees.attendance`** (migration `20270102_001`, instructor_business.md M6) — a nullable column recording whether an attendee actually showed up (`'attended'` | `'no_show'`; NULL until a host marks it), enforced by `event_attendees_attendance_check` and overlaid as `EventAttendance` in `types.ts` (check↔union pair). It is **orthogonal to RSVP `status`** — paid/RSVP'd is not the same as attended. Writes flow ONLY through `mark_attendance(p_event_id, p_user_id, p_instance_start, p_attendance)`, a `security definer` RPC that checks `private.is_event_organiser` and touches the attendance column alone (host-written, attendee-readable via the existing SELECT policy). The `p_instance_start` predicate (migration `20270130_001`) scopes the write to a single occurrence — `event_attendees` is keyed `(event_id, user_id, instance_start)`, so the original `instance_start`-less UPDATE stamped every occurrence of a recurring class at once. The self-only RSVP UPDATE policy is left intact, but column UPDATE on `attendance` is revoked from `authenticated`/`anon` (re-granting UPDATE on `event_id`/`user_id`/`status`/`instance_start` so the RSVP upsert path is unaffected), so the RPC is the sole attendance write path. **`20270520_001` closed the INSERT half**: `20270102_001` rewrote only the UPDATE grant, and a table-level INSERT grant implies every column, so `attendance` (and `order_id`) stayed client-writable on the way IN — an attendee could forge their own roster entry, and re-forge it after an organiser correction via DELETE + re-INSERT, both own-row verbs. INSERT is now column-scoped to `event_id`/`user_id`/`status`/`instance_start`/`joined_at`; the paid seat is written by the service role in `stripe-events-webhook`, which keeps the table grant.

**Narrow unions**: `ClubRole = 'owner' | 'admin' | 'event_organiser' | 'race_director' | 'member'` (enforced by the `club_members_role_check` CHECK, migration `20260428_001`, and overlaid in `types.ts`); `RsvpStatus = 'going' | 'maybe' | 'declined' | 'waitlisted'` (client-side only, no DB CHECK — `event_attendees.status` predates the narrow-union convention); `EventAttendance = 'attended' | 'no_show'` (enforced by `event_attendees_attendance_check`, migration `20270102_001`). See `apps/web/src/lib/types.ts`.

---

#### `event_results`

Per-instance event leaderboard. `finisher_status` ∈ `'finished' | 'dnf' | 'dns'`; `rank` is recomputed by `recompute_event_ranks` (called by trigger on insert/update/delete and by the race-mode auto-finalize path). Migration `20260424_001_event_results.sql`; rank tooling and approval grants in `20260428_001_role_permissions.sql`.

The table is **account-optional** (migration `20261028_001_event_results_account_optional.sql`, persona #43): the PK is a surrogate `id` and `user_id` is nullable so an organiser can bulk-import chip-timing results for finishers with no account, identified by `bib` + `finisher_name`. Two plain `UNIQUE` constraints — `(event_id, instance_start, user_id)` and `(event_id, instance_start, bib)` — keep one result per account/bib per instance (SQL NULL-distinctness means account rows never collide on bib and vice-versa) and double as the `onConflict` arbiters for the self-submit and bulk-import upserts. A CHECK forces every row to identify its finisher by an account OR a bib + name. INSERT is permitted to the row owner (`event_results_insert_self`) OR a club event-organiser (`event_results_insert_organiser`); the leaderboard read surface `event_results_redacted` exposes `id` + `bib` + `finisher_name` (public race data) while keeping `run_id` / `age_grade_pct` / `note` owner-only.

#### `event_result_claims`

Lets a registered runner claim a bib-only imported result under organiser approval (migration `20261030_001_event_result_claims.sql`, persona #43; rationale in `decisions.md § 95`). Columns: `id`, `result_id` → `event_results(id)`, `claimant_id` → `auth.users(id)`, `status` ∈ `'pending' | 'approved' | 'rejected'`, `created_at`, `decided_by`, `decided_at`; `unique (result_id, claimant_id)`. RLS SELECT: a claimant sees their own claims, an event-organiser sees claims against results on events they run. There are **no** client write policies — both writes go through SECURITY DEFINER RPCs (EXECUTE granted to `authenticated` only):

- `claim_event_result(p_result_id uuid)` — caller claims a bib-only row. Refuses already-claimed rows, events the caller can't see, and claimants who already hold a result for that `(event, instance)`; re-requesting after a rejection re-opens the claim. Its inline mirror of the event-visibility chain gates the club-public branch on `is_public_club_by_id` since `20270524_001` (decisions §596) — the copy had drifted from the events policy, which has excluded shadow-hidden clubs since `20270328_001`.
- `decide_event_result_claim(p_claim_id uuid, p_approve boolean)` — organiser-only. Approval sets `event_results.user_id` to the claimant (re-validating that the row is still bib-only and the claimant has no existing result for the instance) and auto-rejects competing pending claims on the same row.

#### `race_sessions` / `race_pings`

Live race mode (Wear OS-led, decisions per roadmap §227). `race_sessions` is the per-instance state machine (`armed → running → finished | cancelled`); `race_pings` is the append-only telemetry stream (lat/lng/distance_m/elapsed_s/bpm/**coarse**) the watch posts during the session. Race-director / event-organiser permissions are checked by `private.is_race_director(uuid)` / `private.is_event_organiser(uuid)` SECURITY DEFINER functions (moved to the `private` schema in `20261120_001`). Migration `20260425_001_race_sessions.sql`. Stale pings are purged by the `cleanup-stale-live-run-pings` cron (see [§ pg_cron schedules](#pg_cron-schedules)).

**Privacy-zone handling — the `race_pings_drop_in_zone` BEFORE-INSERT trigger.** A race ping whose coordinates fall inside one of the runner's `user_settings.prefs.privacy_zones` never reaches the spectator/leaderboard feed at full precision. Originally (`20260704_001`) the trigger dropped the row outright; the last-seen carve-out (`20270309_001`, the `race_pings` analogue of `live_run_pings`' `20270121_001`) instead **retains the single most-recent in-zone ping per `(event_id, instance_start, user_id)`, coarsened via `privacy_coarsen_coord` to a ~2-dp (~1.1 km) grid and flagged `coarse boolean not null default false = true`**, deleting any prior coarse last-seen so it never accumulates. `distance_m`/`elapsed_s`/`bpm` are kept (they carry no positional precision and back the leaderboard rank); only lat/lng are coarsened. So a runner who stops inside their own zone still leaves a "last seen near here" cell for a race director / SAR instead of vanishing. `SECURITY DEFINER` (it crosses the owner-only `user_settings` RLS). Pinned by `rls_race_pings_trigger_test.sql` + `race_pings_last_seen_carveout_test.sql`; the web event leaderboard (`/live/event/[id]/[instance]`) renders the coarse flag as an amber approximate chip + hollow map marker.

#### Paid registration — `instructor_payout_accounts` / `event_pricing` / `event_orders` (Slice P1)

The Stripe Connect marketplace ledger (migration `20261229_001`; design in [club_events.md § Slice P](../features/club_events.md#slice-p--paid-registration)). A host (`events.host_user_id`, shipped in `20261227_001`) charges for an **in-person** event via a destination charge; the host is merchant of record, the platform takes an application fee.

- **`instructor_payout_accounts`** — `user_id` PK, `stripe_connect_account_id`, `charges_enabled` / `payouts_enabled` / `details_submitted` (mirrored from Stripe by the `account.updated` webhook), `country`, `default_currency`, `onboarded_at` (**set-once** — stamped on the first `account.updated` with `details_submitted=true` via an `onboarded_at is null`-filtered UPDATE, never rewritten by a later capability/bank/refresh event). **No bank/tax/SSN data** — Stripe holds it. RLS: own-row SELECT only; there is **no client write policy**, so the row is created/maintained exclusively by the `events-connect-onboard` + `stripe-events-webhook` Edge Functions (service role). The **`stripe_connect_account_id` column is revoked** from `anon`/`authenticated` (the `get_event_meet_point` lockdown pattern) — the web UI reads the boolean capability via `host_can_take_payment(p_user_id uuid)` (SECURITY DEFINER, returns true only for a charges-enabled account), never the raw id. `20261229_001` wrote that revoke at COLUMN level, which is a no-op while the role holds table-level SELECT, so the host's own-row policy handed them the raw `acct_…` id until **`20270621_001`** re-cut it to the prescribed shape (revoke table-level SELECT, re-grant the nine display columns per column — see [decisions.md § 781](../architecture/decisions.md)). The row ships in the **DSAR (Art 15) export** (`instructor_payout_accounts.json`, full `*`) — it's the subject's own connected-account reference + status, and the column-grant revoke above is moot for the export, which runs as service_role over the subject's own row. Wired in both the Go worker `exportPersonalDataSpecs` (live path) and the deprecated `export-data` EF `backup_spec.ts`, pinned by their respective tests.
- **`event_pricing`** — `(event_id, instance_start)` with `instance_start IS NULL` = the series default and a non-null row overriding one occurrence, under a single **non-partial** `unique (event_id, instance_start) nulls not distinct` (`event_pricing_event_instance_uniq`, migration `20270518_001`). It replaced the two partial unique indexes the table shipped with, which stated the same invariant but could not be inferred as an `ON CONFLICT` arbiter — PostgREST emits no index predicate, so every `setEventPricing` upsert raised 42P10 and no price could be attached to any event. Keep it non-partial: the write path is an upsert (decisions §580, pinned by `event_pricing_upsert_test.sql`). `price_cents` (>0 CHECK), `currency`, `modality` (CHECK `in ('in_person')` — `virtual` reserved for P4), `platform_fee_bps` (0–10000 CHECK; platform config, not host-set), `refund_policy` (CHECK `in ('full_until_start','full_until_24h','no_refund')`), `sales_close_offset_minutes`. RLS SELECT: readable with the event via `is_event_visible(uuid)` (recreated in `20270113_001` to honour event-level visibility — a members-only event's pricing is hidden from non-members, since this `SECURITY DEFINER` helper bypasses the caller's RLS and would otherwise leak it); write policy: `private.is_event_organiser(club_id)`. A **BEFORE-INSERT/UPDATE trigger** (`enforce_pricing_requires_charges`) rejects the write unless the event host has a charges-enabled payout account — the `charges_enabled` gate is enforced server-side, not just in the disabled UI toggle.
- **`event_orders`** — the order ledger. `id` PK, `event_id`, `instance_start`, `buyer_user_id`, `host_user_id`, `stripe_checkout_session_id` (unique partial index — row-level webhook idempotency), `stripe_payment_intent_id`, `amount_cents`, `currency`, `platform_fee_cents`, `status` (CHECK `in ('pending','paid','refunded','partially_refunded','refund_failed','failed','canceled')` — `refund_failed` added by `20270624000001`: a `refunded` order whose refund the bank reversed, so the seat is gone and the money is still ours, decisions § 789), `created_at`, `paid_at`, `refunded_at`, `reserved_until` (soft-reservation TTL; a sweep index keys on `status='pending'`). There is deliberately **no refunded-amount column**: how much came back, and whether it delivered, lives one row down in `payment_refunds` (`20270630000001`, decisions § 823). RLS SELECT: buyer reads own + an event organiser reads their events' orders. **Writes are service-role-only** — the one exception is the buyer's `refund_initiated_at` stamp (`20270303_001`), and a BEFORE trigger (`lock_event_order_status`, mirroring `lock_subscription_columns`) raises `42501` on any non-service-role INSERT or status change. Since `20270702000001` that trigger is an **allowlist** rather than a column enumeration — it compares the two row images with `refund_initiated_at` removed from each — because the enumeration it replaced omitted `id`, and `event_orders` is the one payment table carrying a permissive client UPDATE policy, so the buyer of a paid order could rewrite its primary key (decisions § 836). A column added to the table later is now locked the moment it exists. The `stripe-events-webhook` is the **sole, idempotent writer** of status (deduped on the Stripe event id via the existing `webhook_events` `(provider='stripe', event_id)` table).
- **`event_attendees.order_id`** — nullable FK → `event_orders` (NULL for free events). A BEFORE trigger (`enforce_paid_order_for_priced_event`) requires a `paid` order belonging to the buyer for a `going`/`waitlisted` row on a **priced** event (free events unaffected) — so no one can seat themselves on a paid class without a completed order.

**Narrow unions** (TS ↔ CHECK lockstep, in `check_constraint_unions.mjs` `PAIRS`): `OrderStatus`, `RefundPolicy`, `EventModality` (see `apps/web/src/lib/types.ts`). pgtap coverage: `supabase/tests/paid_events_test.sql` (pricing rejected without/with non-charges-enabled host, buyer reads only own order, organiser reads all, user-JWT cannot insert or flip order status, service role can) + `supabase/tests/event_pricing_upsert_test.sql` (the PostgREST-shaped `ON CONFLICT` price write, run as the organiser, through the insert and update branch of both the series and the per-instance shape).

#### Charity fundraising — `fundraisers` / `donations` (fundraising.md, migration `20270213_001`)

Public charity fundraising pages on a run or event, reusing the Slice-P1 Connect rail (the **same** `instructor_payout_accounts` payout account + `host_can_take_payment()`, the **same** `stripe-events-webhook` + secret — see [club_events.md](../features/club_events.md) + [decisions.md § 167](../architecture/decisions.md#167-charity-fundraising-pages-reuse-the-paid-events-stripe-connect-rail-a-fundraiser-is-polymorphic-over-run--event-donation-status-is-service-role-only-live-charges-stay-prod-gated)).

- **`fundraisers`** — `id` PK, `owner_user_id`, a nullable-FK **anchor pair** (`run_id` | `event_id`) with a `(run_id is not null) <> (event_id is not null)` CHECK (exactly one) + a partial unique index per anchor (at most one fundraiser per run/event), `charity_name`, `charity_url` (http/https CHECK), `title`, `story`, `goal_cents` (>0 CHECK), `currency`, `platform_fee_bps` (0 default — a charity donation isn't skimmed; the plumbing exists for a future fee), `status` (`FundraiserStatus` CHECK `in ('open','closed')`), `created_at`/`updated_at`. RLS SELECT: **public when the anchor is publicly visible** (`fundraiser_anchor_visible(run_id, event_id)` SECURITY DEFINER — `is_run_visible_to` for the run case, `is_event_visible` for the event case), else owner-only (fail-closed — a fundraiser on a private run is unreachable by anyone else). INSERT/UPDATE/DELETE: owner-only **and** the caller owns the anchor (owns the run / organises the event's club). A BEFORE trigger (`enforce_fundraiser_requires_charges`, mirroring `enforce_pricing_requires_charges`) rejects opening a fundraiser whose owner has no charges-enabled payout account.
- **`donations`** — the donation ledger, copying the `event_orders` discipline. `id` PK, `fundraiser_id`, `donor_user_id` (NULL = anonymous donor), `owner_user_id` (payout recipient), `display_name`, `message`, `client_request_id` (the donor client's per-attempt idempotency key, unique partial index — `20270620000002`), `stripe_checkout_session_id` (unique partial index — row-level webhook idempotency), `stripe_payment_intent_id` (indexed since `20270620_001`; the `charge.refunded` arm resolves the row by it), `amount_cents` (>0 CHECK), `refunded_cents` (NOT NULL default 0, `20270620_001`), `currency`, `platform_fee_cents`, `status` (`DonationStatus` CHECK `in ('pending','paid','partially_refunded','refunded','refund_failed','failed','canceled')` — `refund_failed` added by `20270624000001`, excluded from `fundraiser_totals` exactly as `refunded` is, decisions § 789), `is_anonymous`, `created_at`/`paid_at`/`refunded_at`. Two more CHECKs bind the refunded amount: `refunded_cents between 0 and amount_cents`, and `status = 'partially_refunded'` implies `refunded_cents > 0` (a partial refund by definition returned something). RLS: **no client SELECT policy** on the base table (a direct read returns zero rows); **writes are service-role-only** (the `lock_donation_status` BEFORE trigger raises `42501` on any non-service-role INSERT, status change **or `refunded_cents` change** — the `stripe-events-webhook` donation branch is the sole, idempotent CAS writer; `20270702000001` widened the trigger to an allowlist with **no** permitted column, so `amount_cents`, `paid_at`, `platform_fee_cents` and `client_request_id` are stated rather than left to the absent SELECT policy, decisions § 836). `20270213_001` wrote its defence-in-depth column revoke at COLUMN level, which Postgres ignores while the role holds table-level SELECT — the grant matrix (`20270408_001`) grants it — so the revoke was inert for the life of the table (the actual gate was, and remains, the absent SELECT policy). **`20270621_001`** re-cut it to the prescribed shape: table-level SELECT is revoked from `anon`/`authenticated` and re-granted per column, withholding `donor_user_id`, `owner_user_id`, `display_name`, `stripe_checkout_session_id`, `stripe_payment_intent_id`, `platform_fee_cents`, `refunded_cents` and `client_request_id`. The set is wider than the original five because a per-column re-grant is cumulative (the two `20270620*` columns would have arrived deny-by-default) and because `fundraiser_feed` nulls `display_name` on an anonymous row, which a column grant cannot do conditionally. See [decisions.md § 781](../architecture/decisions.md). The public feed + thermometer are served exclusively by two SECURITY DEFINER RPCs, both anchor-visibility-gated: **`fundraiser_feed(p_fundraiser_id, p_limit)`** projects only the public-safe columns (`display_name` nulled when anonymous, `message`, `amount_cents`, `currency`, `is_anonymous`, `paid_at`) of **paid + partially-refunded** rows, with `amount_cents` **net of refunds**; **`fundraiser_totals(p_fundraiser_id)`** returns `{ raised_cents, donor_count, goal_cents, currency }` as a `sum` (never per-row), where `raised_cents = sum(amount_cents - refunded_cents + least(reversed, refunded_cents))` over the same two statuses — what the charity kept, with `reversed` the sum of that donation's `failed`/`canceled` `payment_refunds` children (`20270630000001`, decisions § 823: a refund the bank sent back is already inside `refunded_cents`, because `charge.refunded` fired when it was created). A fully `refunded` row is excluded rather than netted to zero, because a row written before `20270620_001` carries `refunded_cents = 0` and netting would add its whole amount back. Donations is a personal-data table covered by the existing Stripe sub-processor entry — add to the Art 20 export + Art 17 deletion with the same financial-retention caveat as `event_orders`.
- **`payment_refunds`** — one row per Stripe Refund on **either** money ledger (`20270630000001`, decisions § 823). `id` PK, `stripe_refund_id` (**unique** — the idempotency key: a webhook redelivery is an upsert, never a second row), `donation_id` / `event_order_id` (both nullable FKs, both `on delete cascade`, exactly one non-null by `payment_refunds_one_ledger_check` — two real FKs where an untyped `(entity_type, entity_id)` would keep neither), `amount_cents` (>= 0), `status` (CHECK `in ('pending','requires_action','succeeded','failed','canceled')` — Stripe's own `Refund.status` vocabulary, which the SDK declares as a bare `string | null`, so the CHECK, the `PaymentRefundStatus` union and the webhook's `REFUND_STATUSES` are three rails `check_constraint_unions.mjs` keeps in lockstep), `failure_reason` (<= 120 chars; the webhook truncates rather than risk a 23514 into an endless Stripe retry), `created_at`, `updated_at`. Covering indexes on both FKs, plus a partial index on the reversed set. **RLS on with no policy at all, `revoke all` from `anon`/`authenticated`, and an explicit `grant select, insert, update, delete … to service_role` (`20270702000002`)** — `20270630000001` wrote only the revoke and left the writer's own DML to Supabase's `alter default privileges`, which is not stable across images (on the workstation CLI's current one the table lands with `service_role=Dxtm` and the webhook's upsert raises `42501`, retried by Stripe forever while every refund goes unrecorded and `fundraiser_totals` reverts to counting a bounced refund as money returned); `20270603_001` states the same grant for `data_export_jobs`, decisions § 840. The lockdown is the `20270621_001` shape taken at table level rather than as a column re-grant, because there is no client read path: a payer sees the net figure `fundraiser_feed` already projects and an operator reads the row under the service role. That puts it on `role_grant_matrix_test`'s service-role-only allow-list beside `app_quota`, `deletion_audit_log` and `data_export_jobs`. Writes are service-role-only via `lock_payment_refund_writes`, which also **latches a terminal status**: `succeeded`/`failed`/`canceled` cannot be replaced by `pending`/`requires_action`, so a benign out-of-order `refund.updated` cannot un-say a `refund.failed` that already landed. This is what gives a failed **PARTIAL** refund a representation — § 789 deliberately does not move `partially_refunded` on either ledger, so before this table the discrepancy existed only in a `console.error`. The operator worklist for money owed back by another route is `select * from payment_refunds where status in ('failed','canceled')`, which covers both ledgers and both scopes, with the amount — where `where status = 'refund_failed'` names the order but no figure. Art 17 erasure is by cascade through both parents; it is **not** in the Art 20 export, because neither `donations` nor `fundraisers` is (see `fundraising.md § Deferred`).

**Narrow unions** (TS ↔ CHECK lockstep, in `check_constraint_unions.mjs` `PAIRS`): `FundraiserStatus`, `DonationStatus`. pgtap coverage: `supabase/tests/fundraisers_rls_test.sql` (anon reads a public-anchor fundraiser, cannot read a private-anchor one, non-owner cannot insert/close), `column_grant_lockdown_registry_test.sql` (the withheld donor-identity + Stripe columns, with the reason each is withheld — the registry fails when a later column lands ungranted or a table-wide grant lands on either payment table), `donations_status_lock_test.sql` (user-JWT cannot write `donations.status`; feed RPC returns only public-safe columns), `fundraiser_pricing_requires_charges_test.sql` (opening a fundraiser without a charges-enabled account is rejected).

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

**`training_plans` private columns on templates** (`is_template = true`, both the club-scoped `club_id` form and the `is_public_template` public-library form): **`vdot`, `current_5k_seconds` and `notes` are OWNER-ONLY and are stripped from every template row by a BEFORE INSERT OR UPDATE trigger** (`private.strip_template_private_fields`, migration `20270508_001`). RLS is row-level only, so the `"anyone reads public plan templates"` / `"club members read club templates"` SELECT branches expose *every* column of a published row to every authenticated reader — the strip therefore has to happen at write time, not at read time. This supersedes the earlier note here, which classified template `notes` as merely "public-template-safe by convention" and deferred the tightening "until a template author writes a private note in production": that premise was already false, because both publishers (`publishPlanToLibrary` and `publishPlanAsTemplate` in `data.ts`, and the mobile twins in `training_service.dart`) copied `notes` verbatim off the source plan, so publishing a plan carried the runner's own free text — training constraints, injury history — into the library through the sanctioned button. The clients now write nulls too, guarded by `security_guards.test.ts`, but the trigger is what holds: the insert is reachable by REST without them. Per-workout `plan_workouts.notes` is untouched — that is plan design ("8x400m at 5K pace"), which is the thing being published. An author-written blurb describing a template wants its own column, not the runner's private field.

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

**RLS:** owner SELECT only. The self-INSERT / self-UPDATE policies this table shipped with were removed in migration `20270505_001` (`user_coach_usage_no_insert` / `no_update` / `no_delete`, with INSERT/UPDATE/DELETE revoked from `anon` + `authenticated`): the table is a meter, and a signed-in caller who can `PATCH message_count = 0` — or `INSERT` a future-dated bucket with a negative count, which the rolling-24h sum adds in — re-rolls their whole allowance and uncaps the Anthropic spend the cap exists to bound. Pinned by `rls_user_coach_usage_test.sql`.

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

RLS + GRANTs: standard owner-only on every command. `select`, `insert`, `delete` gated on `auth.uid() = user_id`; the INSERT policy additionally confines a client to `role = 'user'` (assistant turns come from the service-role client in `coach/handler.ts`). UPDATE is also gated by an owner-only policy, but the `authenticated` role only has column-level UPDATE on `(archived_at, reaction)` — `content`, `role`, `plan_id`, `created_at` are immutable to clients, enforced at the GRANT layer (PostgREST rejects mutations that touch other columns). This preserves the audit trail of who-said-what without trusting the client to behave. INSERT is column-scoped to `(user_id, plan_id, role, content)` since `20270616_001`: it was table-wide, so a client could choose its own `id` and backdate `created_at` — and DELETE is an own-row verb here, so an UPDATE lockdown beside a wider INSERT is the [§ 584](../architecture/decisions.md) shape. The same migration revoked `anon`'s leftover **table-level UPDATE** (`20260518_001` revoked it from `authenticated` only; `20270408_001` then version-controlled the drift), which was the only place in the schema where `anon` held a privilege `authenticated` lacked. See [decisions § 763](../architecture/decisions.md).

Realtime: published on `supabase_realtime` so a client that reloads mid-stream picks the assistant reply up via subscription when the in-flight server request finishes.

---

### Profile, settings & devices

#### `user_profiles`

Supplementary user data not stored in `auth.users`. As of `20260521_001_user_follows.sql` profiles are world-readable to authenticated users — required for follow / feed / club-member rendering; pre-migration, all cross-user enrichment queries silently returned empty rows (see `docs/architecture/decisions.md § 31` for the trade-off). Since `20270329_001` that SELECT policy is `"authenticated read profiles except shadow-hidden"` (`auth.uid() = id or shadow_hidden = false`): a moderation auto-hidden profile (§172/§206) drops out of every cross-user read — kudos/comment/follower enrichment included — while the hidden owner keeps their own row. Anon has no base-table read path (lookups go through `public_profile_by_id`).

`handle` (migration `20270424000002_user_profiles_handle.sql`, issue #465) is the public, user-chosen **@username** — the stable, shareable search key that closes the deferred handle item in decisions §31. Distinct from `runner_handle.ts`'s `Runner #ABCD` anonymizer. Nullable (un-claimed), format-CHECKed to lowercase `[a-z0-9_]{3,30}`, and case-insensitively unique via a `lower(handle)` partial unique index; it's on the cross-user public-safe grant so People-search can render it. The **only** owner write path is the `set_my_handle(p_handle)` SECURITY DEFINER RPC (lowercases, validates format, checks uniqueness, `''`/null clears; raises `handle_invalid` / `handle_taken`). `search_user_profiles` now matches a handle prefix (leading `@` stripped) in addition to `display_name`, and ranks an exact-handle match first — under the *same* `discoverable_in_search` opt-out + minor + shadow filters, so an opted-out runner stays unfindable by handle too. Pinned by `search_user_profiles_handle_test.sql`.

`subscription_tier`, `subscription_at`, and `tier_updated_event_ts` are write-protected against user-JWT writers. The catch-all `users own their profile` policy was split into per-command policies in `20260624_001_lock_subscription_tier_to_service_role.sql`, and a `BEFORE UPDATE` trigger (`lock_subscription_columns`) raises 42501 (`insufficient_privilege`) on any change to those columns whose JWT role isn't `service_role`. Direct SQL (migrations + seed) bypasses the trigger because no JWT context is set. The only legitimate runtime writer is the `revenuecat-webhook` Edge Function (service-role). `tier_updated_event_ts` (epoch-ms, `20270403_001`) is the driving event's timestamp; the webhook makes every tier write monotonic (`… where tier_updated_event_ts is null or tier_updated_event_ts <= incoming`) so an out-of-order `EXPIRATION` delivered after a newer `RENEWAL` can't downgrade a paying user (decisions §229). It is inside the same service-role lock precisely so a user can't stamp a future ts to pin `pro`.

```sql
create table user_profiles (
  id                       uuid primary key references auth.users,
  display_name             text,                                -- <= 60 chars (20270502_001) + rejects control chars (20270423_001)
  avatar_url               text,
  handle                   text,                                -- public @username (issue #465, 20270424000002); lowercase [a-z0-9_]{3,30}, case-insensitively unique, world-readable
  parkrun_number           text,                                -- e.g. 'A123456' (world-readable)
  preferred_unit           text default 'km',                   -- 'km' | 'mi'
  subscription_tier        text default 'free',                 -- 'free' | 'pro' | 'lifetime' (world-readable)
  subscription_at          timestamptz,
  gender                   text,                                -- 'male' | 'female' | 'prefer_not_to_say' | null (CHECK, 20270422_001)
  date_of_birth            date,
  height_cm                numeric(5,1),                        -- nutrition BMR (20261216_001); owner-only, off the public-safe grant
  coach_consent_at         timestamptz,                         -- GDPR Art 6(1)(a) — WHEN the AI disclosure was accepted
  ai_disclosure_version    smallint,                            -- 20270511_001 — WHICH disclosure version; paired with coach_consent_at
  health_data_consent_at   timestamptz,                         -- GDPR Art 9(2)(a) — gates gender + DOB + height + weight persistence
  created_at               timestamptz default now()
);
-- CHECK constraint enforces subscription_tier ∈ ('free','pro','lifetime') —
-- migration 20260429_001_subscription_paywall.sql backfills any pre-existing
-- 'premium' values to 'pro'. Keep this list in lockstep with the
-- SubscriptionTier TS union in apps/web/src/lib/types.ts.
--
-- `user_profiles_display_name_no_control_chars` (20270423_001) rejects any
-- control character (CR/LF/other C0/DEL) in display_name. display_name is
-- interpolated into the Subject of safety-contact emails the app relays to
-- third parties; a raw CR/LF is an SMTP/MIME header injection (issue #375).
-- The Go mailer (job_worker) also strips control chars from every header by
-- construction; this CHECK is the defence-in-depth write boundary. NULL stays
-- allowed. Added NOT VALID + VALIDATE (existing rows scrubbed first) so the
-- DDL doesn't take a long blocking lock on the populated table.
--
-- `user_profiles_display_name_len_chk` (20270502_001, decisions §545) caps it at
-- **60** — the number both setup wizards already stated while the two settings
-- screens capped at nothing and the column at nothing. The four caps that
-- migration adds (this one plus `clubs.name` 80 / `clubs.description` 2000 /
-- `clubs.location_label` 80) are restated once per client in
-- `apps/web/src/lib/core/text_limits.ts` + `apps/mobile_android/lib/text_limits.dart`,
-- and `text_limits_test` on each side PARSES the migration to prove they match —
-- a composer capped above the constraint hands the user a 23514 it cannot
-- explain. Unlike `20261124_001` (which added three NOT VALID caps and never
-- validated any of them, so those rows are permanently unchecked) it emits the
-- VALIDATE, pinned by `club_profile_text_caps_test.sql`.
--
-- **Nothing is uncapped any more** (`20270503_001`, decisions §548). The "40
-- remain" this comment used to carry was derived by reading the migration files
-- and was low by twelve; re-derived from the CATALOGUE the real population was
-- **52**, and that migration caps all of them. Three things defeated the static
-- read, and they are the reason the guard is catalogue-based:
--
--   * the schema spells the predicate BOTH `length(...)` (the older tables —
--     `gear`, `run_photos`, `gym_*`) and `char_length(...)` (the newer ones),
--     so a derivation keyed on one spelling mis-sees the other in both
--     directions;
--   * `alter table … add column a text, add column b text;` is ONE statement
--     with two clauses, which is why `event_results.finisher_name` never showed
--     up in a count while its sibling `bib` did;
--   * a column named inside any CHECK was read as bounded — true of enum
--     membership, false of `event_results`' `user_id is not null or (bib is not
--     null and finisher_name is not null)`, which bounds nothing.
--
-- `20270503_001` also emits the three VALIDATEs `20261124_001` never did
-- (`club_posts.body`, `coach_messages.content`, `events.description`): both
-- §545 and §546 named that defect and fixed it only for their own constraints.
-- The one column deliberately left without a length cap is
-- `event_checkpoints.cutoff_clock`, pinned to five characters by its own
-- `^[0-2][0-9]:[0-5][0-9]$`. The ladder is 60/80/120 for a name, 280–600 for a
-- note, 2000 for prose. `free_text_caps_test.sql` re-derives the population at
-- run time rather than listing it, so a new unbounded text column fails there.
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
-- (20261110_001) and grant_health_data_consent() (20261118_001,
-- insert-or-update since 20270418_001 so a grant that runs before the
-- client-provisioned profile row exists still lands instead of 0-row
-- no-oping). The shared lock_consent_columns BEFORE-UPDATE trigger
-- blocks a direct end-user write that SETS either timestamp to a
-- non-null value, so a client can't backdate or forge the affirmative
-- act. WITHDRAWAL is also RPC-shaped on both consents:
-- withdraw_coach_consent() (20261128_001) and
-- withdraw_health_data_consent() (20270418_001, issue #233) — the
-- latter nulls the consent stamp + the Art 9 profile columns
-- (height_cm, gender) AND erases the body_metrics series in one
-- transaction, insert-or-update so a missing profile row can't turn
-- the withdrawal into a silent no-op. (A direct NULL write of
-- health_data_consent_at remains trigger-permitted, but clients use
-- the RPC.) Pinned by withdraw_coach_consent_test.sql +
-- withdraw_health_data_consent_test.sql.
--
-- date_of_birth is NOT among them (20270605_001, decisions § 721).
-- The column is the child-safety age record the under-18 exclusions
-- in search_user_profiles / discoverable_runners_near read; the Art 9
-- health use reads the user_settings.prefs mirror, which every client
-- clears on withdrawal. Art 7(3) ends the processing the consent
-- authorised, not the discoverability floor — Art 17 erasure is the
-- separate right that does clear the column, via delete-account's
-- auth.users cascade. See decisions § 718 for the two-store rule.
```

**The AI consent record is VERSIONED** (migration `20270511_001`, issue #734, decisions § 571).
`coach_consent_at` alone could only answer *whether* someone consented, never *to what* — so
`/api/coach/route-describe` and `/api/coach/route-request`, which ship a different payload (the
typed request plus a coarse `location_label`) for a different purpose, had no gate they could
honestly use. Reusing the Coach stamp would have retroactively widened what an existing user
agreed to; a second boolean would have repeated the problem on the next AI feature. The record
is now the pair **`ai_disclosure_version` (which disclosure) + `coach_consent_at` (when)**,
kept whole by `user_profiles_ai_disclosure_chk` — either both are set or neither is.

| Version | Scope | Minimum required by |
|---|---|---|
| 1 | AI Coach only — profile slice, recent runs, active plan, chat text | `/api/coach` |
| 2 | All AI features — v1 plus the AI route assistant (route stats + name, the typed request, a coarse place label) | `/api/coach/route-describe`, `/api/coach/route-request` |

The ladder is **monotone by construction** — each version is a strict superset of the one below,
which is what makes `accepted >= required` sound. A future disclosure that *narrows* could not
join it; it would need a scope set instead.

- `ai_disclosure_current_version()` — the highest version the DB knows. Its TS mirror is
  `AI_DISCLOSURE_CURRENT_VERSION` in `apps/web/src/lib/core/ai_disclosure.ts`, and
  `ai_disclosure.test.ts` parses the migration to fail the build on drift.
- `record_ai_disclosure_consent(p_version smallint)` → `(version, accepted_at)` — the canonical
  recorder. **Monotone**: accepting a version at or below the one on record is a no-op returning
  the original stamp, so a Coach re-prompt can never walk a v2 acceptance back to v1. An unknown
  version **raises** (`22023`) rather than being stored — a disclosure the deployment cannot
  describe is one it cannot prove was made.
- `withdraw_ai_disclosure_consent()` — Art 7(3). Clears **both** columns: there is one
  acceptance of one disclosure, so withdrawal is all of it.
- `record_coach_consent()` / `withdraw_coach_consent()` remain as **v1 entry points** in SQL,
  but **no client calls them**: mobile now presents the same widened disclosure web does, so
  the honest record is v2 and `packages/api_client` writes it through
  `record_ai_disclosure_consent()` directly (decisions § 573). Two client paths writing one
  consent record is the defect the versioning exists to prevent, one layer down.
- `lock_consent_columns` now also blocks a direct write to `ai_disclosure_version`; without that
  a PostgREST PATCH could self-grant the widened scope.

Existing acceptances backfill to **v1**, so a Coach user keeps the Coach and is refused (403,
body `code: "ai_disclosure_required"`) by the route endpoints until they accept the widened
disclosure in Settings → Account. Every gate fails closed: no record, a half-written record, an
unreadable lookup, or an unknown version all deny. Pinned by `ai_disclosure_consent_test.sql`.

**Pre-deploy checklist item (not a code blocker):** counsel / CISO sign-off on the v2
disclosure copy (`coachPage.consent*` in the every web locale) before it is presented in
production. The code, the gate, and the record ship now.

`height_cm` (migration `20261216_001`, nutrition BMR) is **special-category health data** and shares the `gender`/`date_of_birth` posture: it is **owner-only** — not on the `20260707_001` public-safe column grant, so it's read back through `get_my_profile()` and never exposed to other authenticated callers or anon — and its persistence is gated on `health_data_consent_at` at the client layer, exactly like gender/DOB. Same for the `body_metrics` weight series below.

**`age_confirmed_at` / `terms_accepted_at`** (migration `20260929_001`, GDPR Art 8) are the affirmative age/ToS-consent timestamps, stamped server-side by the `confirm_age_and_terms()` SECURITY DEFINER RPC (first-stamp-wins). NULL means consent never landed (the client gate was bypassed — a direct `curl` to GoTrue `/auth/v1/signup`, or an OAuth callback that dropped the `sessionStorage` tick). Originally these were enforced **only** by a client-side redirect to `/auth/confirm-age`, so an unconsented `authenticated` account had full functional use of the app. **`20270424000004` adds the server-side enforcement**: a fail-closed `BEFORE INSERT` trigger (`private.enforce_consent()`) on the core personal-data content tables — `runs`, `gym_workouts`, `food_log`, `body_metrics`, `routes` — raises `42501` when the caller (`auth.uid()`) has no `age_confirmed_at` stamp. The reusable trigger keys on `auth.uid()` (the RLS insert check already forces `new.user_id = auth.uid()`); a null `auth.uid()` (service_role / backend jobs) and the never-gated `user_profiles` consent-stamping path both pass through, so legitimate signup and async ingestion are unaffected. **Prod deploy gated on CISO/legal sign-off** per the compliance rule. Pinned by `consent_write_gate_test.sql`; see [web_app_auth.md § Consent is enforced server-side](../features/web_app_auth.md).

#### `body_metrics`

Weight time-series for the nutrition Mifflin-St Jeor BMR target (migration `20261216_001`). Weight is a **time-series**, not a single mutable column, because a trend matters and a column loses history. **GDPR special-category health data**: owner-only RLS (no public read at all — `gym_workouts` / `food_log` are also owner-only on the base table since `20270313_001`, but each has a redacted `public_*` view for its `is_public` rows; `body_metrics` has neither), cascade-deletes from `auth.users`, gated on `health_data_consent_at` at the client layer, and must be in the DSAR export path (G1/G6).

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

RLS + range CHECK + cascade-delete + the owner-only `height_cm` grant are pinned by `body_metrics_rls_test.sql`. The client-side bound both platforms put on the field — narrower than the column, and stated in the unit the runner types in — lives in `core/column_limits.ts` / `column_limits.dart`, and `scripts/check_shared_constants.mjs` proves it sits inside this CHECK and inside `numeric(5,2)` ([decisions § 792](../architecture/decisions.md)). Same for `user_profiles.height_cm` and `checkpoint_crossings.body_weight_kg`.

#### `gym_routines` / `gym_routine_exercises` / `gym_routine_sets`

The gym-programming **P1** reusable-plan tier (migration `20270101_001`, [gym_programming.md](../features/gym_programming.md)). A routine is a named, ordered list of planned exercises, each with planned target sets — **relational, not jsonb** (the deliberate divergence from `plan_workouts.structure jsonb`, justified by per-exercise querying + row-by-row progression). It is **not** a dated activity, so it does **not** feed the `activities` view.

- `gym_routines` — owner column is **`author_id`** (authored content, F17), **author-only RLS** for write + the base read; a club-member SELECT branch widens read for club-owned templates (`20270109_001`). The public-library read moved OFF the base table in `20270319_001`: non-author reads of public templates go through the redacted **`public_gym_routines` view** (no `external_id` / `last_modified_at`, granted to authenticated only), and the exercises/sets child policies answer via the `private.is_public_gym_routine(routine_id)` SECURITY DEFINER oracle. `is_public_template boolean not null default false` (migration `20270226_001`) marks a publisher-owned, anyone-can-adopt template; the `gym_routines_public_not_club` CHECK (`is_public_template ⇒ club_id is null`) keeps public and club visibility strictly separable. `exercise_count` + `last_modified_at` are **client-stamped** (non-authoritative cache, newer-wins; no server trigger). Cascade-deletes from `auth.users` (Art. 17). Indexes `(author_id, last_modified_at desc)` + `(club_id, last_modified_at desc) where club_id not null` + `(created_at desc) where is_public_template` (re-pointed off the redacted `last_modified_at` in `20270319_001`) + unique `(author_id, external_id) where external_id not null`.
- `gym_routine_exercises` — **`exercise_key` is server-stamped** (binds the plan to logged `gym_sets`): the `gym_routine_exercises_stamp_exercise_key_trigger` BEFORE INSERT OR UPDATE trigger sets it to `normalise_exercise_name(exercise_name)` unconditionally, so a client-supplied value is **overwritten, never refused**, and the column carries a constant `''` default so no client is obliged to compute it (`20270711000001`, decisions § 1284 — the same shape `gym_sets.exercise_key` has had since `20270706000001`). It stays held to the derivation by the validated CHECK `gym_routine_exercises_exercise_key_canonical` since `20270623000001` (decisions § 790), which the trigger now makes unviolatable rather than redundant — a disabled or dropped trigger fails loudly instead of silently splitting a lifter's history. `position` orders the groups; `superset_group`/`superset_order` exist for P2 but P1 leaves them null (paired-null CHECK). RLS via `EXISTS` against the parent routine's `author_id`.
- `gym_routine_sets` — planned targets per set: `target_reps_min`/`_max` (single value = min only), `target_weight_kg` **XOR** `target_percent_1rm` (load-mutex CHECK), `target_rpe`, `rest_s`, `tempo`, `set_type` (default `working`). RLS via `EXISTS` up through `gym_routine_exercises` → `gym_routines.author_id`.
- Four narrow-union ↔ CHECK pairs land here (`periodisation`, `modality`, `progression`, `set_type`); only the columns ship in P1, the engine that reads them is P2-P4.
- The plan→logged-session link lives in `gym_workouts.metadata.routine_id` (a string, **not** an FK), added by the same migration — so deleting a routine leaves prior sessions intact. `gym_workouts.metadata` (jsonb, default `'{}'`) is added here as the prerequisite; the `activities` lift branch enumerates explicit columns so the new column does not change the UNION shape. The lift branch's `summary` carries `title` / `set_count` / `volume_kg` / `duration_s` (`duration_s` added by `20270429_001` — it had existed on the table since the Phase 4 foundation but was never projected, so every consumer reading a strength session through the view saw a null duration and the mobile nutrition exercise add-on scored it as zero). `duration_s` is nullable, so a consumer must read a null as "no timer", never as zero.

Author-only RLS on all three tables + the EXISTS parent gates + the full-tree cascade from `auth.users` are pinned by `gym_routines_rls_test.sql`. The three tables (+ nested embeds) ship in the DSAR export (`export-data` `backup_spec.ts`, pinned by `backup_spec.test.ts`).

**Club templates (migration `20270109_001`, decisions §145).** `gym_routines.club_id` (nullable FK → `clubs`, `on delete cascade`) makes a routine **club-owned** — a publishable template. Added RLS (alongside, not replacing, the author-only policies — Postgres ORs permissive policies): club members read the routine + its exercises/sets children (`club_id is not null and private.is_club_member(club_id)`); club admins may update/delete (unpublish) but **not** insert (publishing is the gated RPC below, so an admin can't inject a foreign `author_id`). Two SECURITY DEFINER RPCs (`search_path = public, private`, revoked from `public, anon` since `20270626000001`, granted to `authenticated`): `publish_gym_routine_as_template(p_routine_id, p_club_id)` — author + `is_club_admin` gated, rate-limited, deep-copies the routine + exercises + sets into a new club-owned routine (the personal original is untouched); `clone_gym_routine_template(p_template_id)` — author-or-`is_club_member`-or-`is_public_template` gated, rate-limited, deep-copies into a personal, club-less, non-public routine. Pinned by `gym_routine_club_templates_test.sql` (13 tests).

**Public library (migration `20270226_001`, redaction `20270319_001`, decisions §182).** The anyone-can-adopt counterpart, the gym-routine analogue of the public PLAN library (`clone_public_plan`). `gym_routines.is_public_template` + the `gym_routines_public_not_club` CHECK (public ⇒ not club-owned). The original additive base-table public-read branch leaked `external_id` (import crosswalk) + `last_modified_at` (edit-cadence clock), so `20270319_001` replaced it with the 20270313 medicine: the parent's public read goes through the redacted **`public_gym_routines` view** (template-safe columns only, granted to authenticated — the library stays a signed-in surface), and the `"gym_routine_exercises/sets public templates read"` child policies answer via `private.is_public_gym_routine(routine_id)` (SECURITY DEFINER oracle) since the parent row is now RLS-hidden from non-authors. `clone_gym_routine_template` carries the public-template authorisation branch (any signed-in caller; the clone is personal, `club_id` null, `is_public_template` false). `set_gym_routine_public(p_routine_id, p_public)` — SECURITY DEFINER, author-gated, refuses a club-owned routine — flips `is_public_template` on the routine itself (the routine IS the template, no deep-copy). Nothing else is stripped on publish/clone (targets are the published prescription). Pinned by `public_gym_routine_library_test.sql` (13 tests). Surfaced as `/gym/routines/library` + the routine-detail publish toggle on web + `RoutinePublicLibraryScreen` + the publish toggle on mobile; library ordering is `created_at desc` (the sync clock is redacted).

#### `user_settings` / `user_device_settings`

Settings registry. `user_settings.prefs` is a single jsonb bag keyed off `user_id` for **universal** preferences (notification opt-ins, privacy zones, units carry-overs from the legacy `user_profiles` columns). `user_device_settings` keys on `(user_id, device_id)` for **per-device** overrides (push subscription endpoint per browser, sound on/off per watch, etc.). RLS owner-only on both. Migration `20260422_001_user_settings.sql`. The TypeScript helpers `loadSettings()` + `effective<T>()` in `apps/web/src/lib/settings/settings.ts` resolve a per-key value as `device_override ?? user_value ?? default`. See [docs/backend/settings.md](settings.md) for the registered key catalogue.

Two key-targeted RPCs write the `push_subscription` device pref atomically (PostgREST can't express a jsonb key write in a PATCH, and a whole-bag read-merge-write can clobber the row's other prefs — issue #235): **`set_push_subscription(p_device_id, p_subscription, p_platform default 'web', p_label default null)`** — SECURITY INVOKER, `authenticated`-only, `auth.uid()`-scoped; a single `jsonb_set` (or `- 'push_subscription'` when `p_subscription` is NULL / jsonb `'null'`) with an insert arm for a not-yet-provisioned device row (migration `20270419_001`, the web subscribe/unsubscribe path in `apps/web/src/lib/util/push.ts`); and **`clear_push_subscription(p_user_id, p_device_id)`** — SECURITY DEFINER, `service_role`-only; the Go worker's dead-endpoint prune (migration `20261219_001`). Pinned by `set_push_subscription_test.sql` + `web_push_channel_test.sql`.

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

Cache table for per-distance PBs (`1_mile` / `5k` / `8k` / `10k` / `12k` /
`half_marathon` / `marathon`; the mile bracket was added in `20261021_001`,
8k + 12k in `20270330_001` — all whole-run brackets are ±2% of the canonical
distance). Backed by triggers on `runs` so reads are a single indexed
lookup instead of the full aggregation that
[`personal_records()`](#personal_records-1) does. Shipped in migration
`20260508_001_personal_records_cache.sql`. The existing
`personal_records()` SQL function stays in place for callers that
haven't migrated.

```sql
create table personal_records (
  user_id       uuid not null references auth.users(id) on delete cascade,
  distance      text not null check (distance in ('1_mile', '5k', '8k', '10k', '12k', 'half_marathon', 'marathon')),
  best_time_s   integer not null,
  run_id        uuid references runs(id) on delete set null,
  achieved_at   timestamptz not null,
  updated_at    timestamptz not null default now(),
  primary key (user_id, distance)
);
```

Triggers: `runs_personal_records_insert / update / delete` — statement-level
AFTER triggers with transition tables since `20270315_001` (per-row before
that) — call `refresh_personal_records_for_user(uid)` once per statement per
affected user, a `security definer` helper that deletes + re-inserts the
caller's rows (full rebuild per user on any run change — simpler to reason
about than incremental; batching per statement keeps a bulk import at one
rebuild per chunk instead of one per row). The UPDATE trigger's old OF
column list lives in the trigger function as a changed-value filter, and
`activity_type` is one of the watched columns since `20270514_001`.
Candidates are **run-family only** — every `activity_type` except `cycle`
(`20270514_001`), matching the client's `isRunFamily` rule in `recap.ts`;
a bicycle otherwise covers a PR bracket at a speed no runner reaches and
takes the bracket permanently. See
[derived_state.md](derived_state.md#personal_records).
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
(mirrors `personal_records`), and since `20270616_001` neither verb is granted to
`anon`/`authenticated` either, so the refusal comes from the privilege layer
rather than only from the absence of a policy. `grant ... to postgres` for the
definer-owner.
The toggle is scoped at the **column** layer, not just the row layer: migration
`20270506_001` revokes table-wide UPDATE from `anon` + `authenticated` and grants
only `update (is_public)`, because the ownership policy alone let the owner of a
bronze award rewrite its `badge_key` / `tier` / `value_num` / `earned_at` and
publish a badge they never earned (the `(user_id, badge_key, tier)` unique
constraint does not stop a rename). Same idiom as `coach_messages`,
`challenge_participants`, `event_attendees`.

**Award function:** `award_achievements_for_user(p_user)` — SECURITY DEFINER,
recomputes the full earned set (longest-run + lifetime distance off `runs`,
best streak off run days, PR count off `personal_records`, completed-plan count
off `training_plans`) and `insert ... on conflict do nothing`s the new awards,
**returning only the newly-inserted rows**. Longest-run is **run-family only**
(`activity_type <> 'cycle'`, `20270514_001`) while lifetime distance and the
streak stay cross-modal — the same split `recap.ts` makes; the UPDATE dispatch
trigger watches `activity_type` to match. Thresholds duplicate the
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

#### `mv_weekly_mileage` — dropped in `20270530_001`

**This materialized view no longer exists**, and the repo now has no materialized view at all. It was created ahead of need in `20260407_001`, revoked from `anon`/`authenticated` in `20260517_001`, refreshed every 15 min by pg_cron since `20260602_001`/`20260706_001` — and never acquired a reader on any tier. Dropped along with its `mv_weekly_mileage_pk` index and its cron entry; the pgtap guard is `mv_weekly_mileage_dropped_test.sql`. Rationale and the alternatives weighed are in [decisions.md § 690](../architecture/decisions.md).

An earlier revision of this section claimed the view backed "the `weekly_mileage` RPC and the dashboard's 'This Week' card". **Neither was ever true.** For the record, so nobody re-derives the same wrong picture:

- `weekly_mileage(weeks_back)` aggregates `runs` directly under `user_id = auth.uid()` (`20260406_001`, re-emitted with a pinned `search_path` in `20260710_001`). It never referenced the view — and has no caller of its own on any client.
- The dashboard's weekly chart calls `fetchWeeklyMileage`, which selects a bounded 14-week `(started_at, distance_m)` window off `runs_user_started_at` and buckets it in TypeScript (`bucketWeeklyMileage`). The `ThisWeekStrip` ribbon is fed runs already in memory. Both bucket at the runner's **local** midnight and honour the `week_start_day` preference, which is precisely what the view's `date_trunc('week', ...)` could not do.

If a genuinely hot weekly aggregate ever appears, it wants a view keyed per user timezone and week-start preference — a different object, not this one revived.

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
  last_sync_at             timestamptz,              -- last COMPLETE walk of the lookback window; a truncated backfill leaves it alone (decisions § 766)
  sync_cursor              text,                     -- resume point for a truncated `strava-import` walk: {"v":1,"from","after","before"} epoch seconds. Written on a truncation that made progress, cleared on a finished window / connect / disconnect (decisions § 768)
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

Generic Postgres-backed job queue. First tenant was map matching (`kind = 'map_match'`); it now also hosts the Strava webhook ingest (`kind = 'strava_event'`), hourly token rotation (`kind = 'token_refresh'`), the run-photo EXIF-strip + thumbnail (`kind = 'photo_process'`), and the club-photo EXIF-strip + thumbnail (`kind = 'club_photo_process'`, migration `20270301_001`) that moved off / never lived in Edge Functions (see `roadmap.md` Phase 2 backend bullets). The `kind` CHECK allowlist is maintained by ALTER migrations (latest adds `data_export`, `20270603_001`); a new kind must extend the CHECK + the Go dispatch switch + the pgtap kind test together. Data export is a job kind as of [decisions § 717](../architecture/decisions.md) — `kind = 'data_export'`, enqueued by `enqueue_data_export` alongside its `data_export_jobs` state row, with `max_attempts = 2` (every attempt past the tus Finish uploads a whole archive) and a 15-minute per-attempt worker clock instead of the generic five. The subject no longer blocks on the signed URL: they poll `GET /v1/export/jobs/latest`, which mints it at read time.

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

-- Matches claim_next_job's `order by scheduled_at, id`: the `id`
-- tie-break resolves same-scheduled_at bursts from the index with no
-- in-memory sort. (Was `(scheduled_at, kind)`; `kind` bought nothing —
-- the worker always claims with an empty kind_filter. Migration
-- 20270423_001.)
create index jobs_queued_v2
  on jobs (scheduled_at, id)
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
- **Worker API**: `claim_next_job(worker_id, kind_filter)`, `finish_job(job_id, result_status, err)`, `defer_job(job_id, delay_seconds, err)`. `service_role` only. None of the three carries an in-body auth check, and until `20270626000001` each was revoked `from public` alone — which removes nothing on an image that grants `anon` by name at create time (Cloud and CI, see § Who may EXECUTE one at the head of [Database functions (RPCs)](#database-functions-rpcs)), so both `anon` **and** `authenticated` could drain the queue there: claim a job's payload and burn an attempt, mark it succeeded, or defer it. Both are now revoked; `anon_execute_contract_test.sql` pins it. See [decisions.md § 799](../architecture/decisions.md).
- **Concurrency**: `claim_next_job` uses `for update skip locked` so multiple workers can drain in parallel without thrashing each other on the same row.
- **Partial indexes**: the `jobs_queued_v2` and `jobs_running` indexes are partial so queue size scales with the *active* set, not the cumulative job count. The `jobs_dedupe_map_match` index is also partial — once a job finishes, its row is no longer in the unique constraint, so a re-match becomes possible.

#### `live_run_pings`

Ephemeral per-sample GPS feed for the `/live/{run_id}` spectator page.
Shipped in migration `20260509_001_live_run_pings.sql`.

```sql
create table live_run_pings (
  id            bigserial primary key,
  run_id        uuid not null references runs(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  at            timestamptz not null default now(),
  lat           double precision not null,  -- -90..90 (CHECK, 20270705000001)
  lng           double precision not null,  -- -180..180 (CHECK, 20270705000001)
  ele           double precision,           -- null or -500..9000 m (CHECK, 20270705000001)
  elapsed_s     integer,                    -- null or >= 0 (CHECK, 20270705000001)
  distance_m    double precision,           -- null or (>= 0, finite, not NaN) (CHECK, 20270705000001)
  bpm           integer                     -- null or 0..300 (CHECK, 20270705000001)
);
```

- **Every column is bounded, and the bound is the reason a spectator sees a
  map** (`20270705000001`, [decisions § 1046](../architecture/decisions.md)).
  Until then the table carried no numeric CHECK at all, and from an ordinary
  account's own session one INSERT landed `lat = 'NaN'`, `lng = 'Infinity'`,
  `ele = 'NaN'`, `distance_m = 'NaN'`, `elapsed_s = -5` and `bpm = -40` on the
  account's own public run — every value read straight back by `anon` through
  `live_run_pings_visible_when_run_is`. Not an escalation (the runner owns the
  row); the exposure is the READER, since a NaN coordinate draws nothing on
  `/live/[id]` and an infinite longitude fits the viewport to the world. The
  PostGIS derivation did raise `NOTICE: Coordinate values were coerced into
  range …`, but it clamped only its own derived point and left these two
  `float8` columns untouched. `lat` / `lng` / `ele` / `bpm` are two-sided so
  they exclude NaN and both infinities for free; the one-sided `distance_m`
  names them explicitly. `race_pings` carries the identical set on its own
  `lat` / `lng` / `distance_m` / `elapsed_s` / `bpm`. Pinned by
  `unbounded_numeric_column_bounds_test.sql`.
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

**Create rate-limit buckets.** Every live `enforce_create_rate_limit(bucket, user, max, window_s)` call site, which is the wrapper the write paths use over `check_rate_limit`. The counter is keyed by **bucket**, so one bucket debited with two different ceilings would give a caller a limit that depends on which path they took — `scripts/check_shared_constants.mjs` resolves the call sites by replaying every migration, refuses that case, and fails the PR when this table and the SQL disagree ([decisions § 792](../architecture/decisions.md)). The bucket → sentence mapping a throttled caller reads is a separate registry, [§ 744](../architecture/decisions.md).

| Bucket | Max | Window (s) | Raised by |
|---|---|---|---|
| `clone_gym_routine_template` | 20 | 3600 | `clone_gym_routine_template()` |
| `clone_plan_template` | 20 | 3600 | `clone_plan_template()` |
| `clone_public_plan` | 20 | 3600 | `clone_public_plan()` |
| `clone_session_template` | 20 | 3600 | `clone_session_template()` |
| `create_challenge` | 30 | 3600 | `enforce_challenge_create_rate_limit()` (before-insert trigger) |
| `create_club` | 5 | 3600 | `clubs_create_rate_limit_trigger()` |
| `create_report` | 10 | 3600 | `submit_report()` |
| `create_route` | 30 | 3600 | `routes_create_rate_limit_trigger()` |
| `publish_gym_routine_as_template` | 20 | 3600 | `publish_gym_routine_as_template()` |
| `send_direct_message` | 250 | 3600 | `direct_messages_rate_limit_trigger()` |
| `send_direct_message_burst` | 30 | 60 | `direct_messages_rate_limit_trigger()` |

---

#### `data_export_jobs`

Durable state of one Art 20 export request (`20270603_001`, [decisions § 717](../architecture/decisions.md)). The sibling of the generic `jobs` queue entry, the same split `run_matched_tracks` uses: the `jobs` row is what the worker claims, this row is what the subject's status read sees.

```sql
create table data_export_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  format text not null,          -- csv | gpx | backup
  status text not null default 'queued',
                                 -- queued | running | ready | failed | expired
  object_path text,              -- key in the `exports` bucket; never a signed URL
  run_count integer,
  total_runs integer,
  complete boolean,
  error_code text,               -- machine token, <= 64 chars
  started_at timestamptz,
  finished_at timestamptz,
  notified_at timestamptz,       -- 20270607_001: the subject has been told
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index data_export_jobs_one_in_flight
  on data_export_jobs (user_id) where status in ('queued', 'running');
```

**RLS on, zero policies, and no `authenticated` grant either.** The row is useless to a client without a signed URL, which only the service role can mint (the `exports` bucket carries no `storage.objects` policies at all, § 703), so the whole read goes through the worker's JWT-authed `GET /v1/export/jobs/latest`. It sits beside `app_quota` and `deletion_audit_log` on `role_grant_matrix_test.sql`'s service-role-only allow-list; denying at the grant level as well as through RLS means a policy added by mistake later still opens nothing. It is deliberately **excluded** from the Art 20 export itself (`exportGuardExclusions`): it is fulfilment metadata about the subject's own requests, not data they provided, and shipping it inside the archive it describes would be circular. It cascades away with the account (Art 17).

**`object_path`, never a URL.** A 10-minute signed URL minted when the build finished is already spent by the time a subject who closed the tab comes back; the path is inert on its own and the status endpoint signs at read time.

**RPCs** (both `service_role` only):
- `enqueue_data_export(p_user_id uuid, p_format text)` → `(id, status, format, created_at, reused)`. Inserts the state row **and** its `jobs` entry in one statement — two round-trips from the HTTP handler could leave a state row nothing will ever build. Returns the export already in flight with `reused = true` rather than starting a second one; a race past that check is caught by the unique index and resolved to the same row. Stamps `max_attempts = 2` on the queue entry, not the table default of 5, because every attempt that reaches the tus Finish uploads a whole archive.
- `expire_stale_export_jobs()` → count. Flips `ready` rows past the 7-day artifact-retention window to `expired` so a row cannot outlive its own object and keep offering a download that 404s. Called by `enqueue_export_blob_reap()` — the scheduled half, and the one that runs whether or not a worker ever claims the reap ([§ 1144](../architecture/decisions.md)) — and still by the now-unscheduled `cleanup_stale_export_blobs` break-glass. Split out because `storage.objects` refuses a direct DELETE unless `storage.allow_delete_query` is set for the transaction — storage-api's own `protect_delete()` trigger, present in the image both the CI-pinned and the workstation CLI start. Since `20270703000002` the blob sweep sets that GUC itself, so it is no longer out of pgtap's reach and `export_surface_contract_test` drives it.
- `export_retention_overrun(p_grace interval default '1 day')` → jsonb `{overrun_count, oldest_age_s, by_bucket, retention_days, grace_s, checked_at}` (`20270710000004`, [decisions § 1234](../architecture/decisions.md)). Counts export artifacts past retention across both the `exports` bucket and the legacy `runs/{uid}/exports/` prefix, using `cleanup_stale_export_blobs`' own predicate so the alert and the reaper cannot disagree about what an export artifact is. **Returns rather than raising**, unlike the sweep: that raise is a post-condition on a DELETE the sweep just performed, and a standing check that raised would put a failed row in `cron.job_run_details` every day for as long as a recoverable overrun lasted. The grace day is load-bearing — objects cross the 7-day line continuously and the reap runs once a night, so without it the check would fire every day forever. `service_role` only.
- `notify_data_export_ready(p_export_job_id uuid)` → boolean (`20270607_001`, [decisions § 729](../architecture/decisions.md)). Announces a finished export: one `notifications` row of kind `data_export_ready`, and `notified_at` stamped in the **same statement** under a `for update` lock — so an at-least-once redelivery of the `data_export` job cannot announce the same archive twice, while the handler's already-built early-return can safely re-ask and thereby repair a crash between the finish write and the announcement. Refuses (returns false) unless the row is `ready`, carries an `object_path`, and is not already stamped; an expired row is refused for the same reason its artifact is gone. The stamp is a column rather than a "does a notification row exist" check because the subject may delete the row from their own inbox, and a deleted row must not read as never-notified. `service_role` only — the notifications AFTER INSERT fan-out turns the row into an email job and a push job, so a client-reachable version would be a mail cannon. Carries **no FK and no URL**: the deep link is `/settings/account`, where the signed download URL is minted at read time.

Pinned by `data_export_jobs_test.sql` (19 assertions) + `data_export_ready_notification_test.sql` (14) + `jobs_kind_allowlist_test.sql`.

---

#### pg_cron schedules

| Job | Schedule | What it does | Migration |
|---|---|---|---|
| `cleanup-stale-live-run-pings` | `*/15 * * * *` | Calls `cleanup_stale_live_run_pings()` to delete `live_run_pings` rows older than the retention window — keeps the spectator feed table bounded during a multi-hour event. | `20260602_001` |
| `cleanup-stale-rate-limits` | `0 * * * *` (hourly) | Calls `cleanup_stale_rate_limits()` to GC elapsed `rate_limits` rows. | `20260604_001` |
| `cleanup-stale-webhook-events` | `17 4 * * *` | Deletes `webhook_events` rows older than 30 days (RevenueCat/Stripe replay-dedupe table). | `20260623_001` |
| `enqueue-export-blob-reap` | `13 4 * * *` | Calls `enqueue_export_blob_reap()`: expires the `data_export_jobs` rows whose artifacts are about to go (`expire_stale_export_jobs()`, unconditionally — reachability first), then queues the Go worker's `export_blob_reap` job(s) that actually erase the bytes through the Storage API. One job for the `exports` bucket plus one per user still holding a legacy `runs/{uid}/exports/*` archive, the worklist derived from `storage.objects` so it empties itself; singleton per payload, so a night the worker was down cannot stack identical sweeps. **This is the only scheduled half of export retention.** `cleanup-stale-export-blobs` (`23 4 * * *`, `20260720_001`) was **unscheduled** in `20270709000001` ([§ 1172](../architecture/decisions.md)): its `storage.objects` row delete erases nothing and, once the row is gone, puts the bytes beyond the reach of the reaper that does. `cleanup_stale_export_blobs()` itself is kept as a `service_role` break-glass. | `20270708000010` |
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
| `purge-stale-checkpoint-health-data` | `47 3 * * *` | Calls `private.purge_stale_checkpoint_health_data()` — scrubs (nulls) the Art 9 weigh-in / medical columns on `checkpoint_crossings` older than 90 days (`recorded_at`); the in/out split times survive (they are race results). | `20270317_001` |
| `cleanup-account-deletion-receipts` | `17 * * * *` | Calls `cleanup_account_deletion_receipts()` (Art 17 deletion-receipt retention). | `20270217_001` |
| `sweep-challenge-completions` | `17 2 * * *` | Calls `sweep_challenge_completions()` — awards completion for goal-bearing challenges whose window has closed. | `20270210_001` |
| `enqueue-weekly-digest` | `0 8 * * 1` | Calls `enqueue_weekly_digests()` to fan out the Monday-morning digest emails. | `20270220_001` |
| `enqueue-lifecycle-drip` | `0 9 * * *` | Calls `enqueue_lifecycle_drip()` to fan out the onboarding drip sequence. | `20270223_001` |
| `enqueue-safety-overdue-emails` | `*/5 * * * *` | Calls `enqueue_safety_overdue_emails()` — the overdue-runner escalation to a trusted contact. | `20270401_001` |
| `jobs-backlog-alert` | `*/10 * * * *` | Calls `jobs_backlog_summary()` — queued jobs nobody has claimed, for the observability scraper. The third alert beside the stuck and failed ones, covering what neither can see: `find_stuck_jobs` selects `status = 'running'` and `find_failed_jobs` selects `status = 'failed'`, so a worker that is not running at all leaves every job `queued` with a null `locked_at` and both report a healthy queue ([§ 1234](../architecture/decisions.md)). Route the scraper on `backlogged_count > 0`. | `20270710000004` |
| `export-retention-overrun-alert` | `43 4 * * *` | Calls `export_retention_overrun()` — Art 20 archives still on Storage past the 7-day window plus a grace day. The CONDITION half of export retention, where `jobs-backlog-alert` is the cause half: a reap that was claimed, ran, and erased nothing is `done` and drains the queue while the bytes stay. Thirty minutes after the reap; the grace day means the lag cannot false-positive. Route the scraper on `overrun_count > 0`. | `20270710000004` |

The table above is the whole schedule, not a selection: re-derive it with
`psql "$DB_URL" -c "select jobname, schedule from cron.job order by jobname"` against a
reset local stack, and the row count must match. The scheduled functions are EXECUTE-revoked from `public, anon, authenticated` and granted to `service_role` only (`20270625000001` + `20270626000001`; before those, a single-grantee revoke left both client roles holding the create-time grant on Cloud). pg_cron itself runs them as `postgres` and needs no grant. The live-run-ping cleanup lives in `20260602_001_pg_cron_schedules.sql` alongside what used to be a `refresh-mv-weekly-mileage` entry — that job is **gone** (unscheduled in `20270530_001` when the unread matview it refreshed was dropped, see above), so the table above lists no matview refresh and the repo now schedules no `refresh materialized view` anywhere. The rate-limit cleanup is in `20260604_001_rate_limits.sql`. Each remaining row's migration is listed in the table.

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
  created_by        uuid references auth.users on delete set null,  -- nullable + SET NULL (20270311_001) so the organiser can delete their account; the checkpoint survives
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
- **Retention (Art 5(1)(e)):** the Art 9 health columns are scrubbed (nulled, `medical_hold` reset to false) 90 days after `recorded_at` by the `purge-stale-checkpoint-health-data` cron (`20270317_001`); the crossing rows and their in/out split times are kept — they are the race's results, same permanence as `event_results`. Pinned by `checkpoint_health_retention_test.sql`.

---

### Other shipped tables (summary)

These tables ship in the live schema but don't have a full column-by-column block above. Each is listed with its purpose, defining migration, and a one-line column summary; read the migration for the exact DDL, constraints, and RLS.

| Table | Migration | Purpose / column summary |
|---|---|---|
| `gym_workouts` | `20261204_001` | Phase-4 gym session header. `id, user_id, title, started_at, duration_s, notes, is_public, external_id, last_modified_at, created_at` (+ `set_count`/`volume_kg` trigger cache `20261214_001`; `metadata` jsonb `20270101_001`). **Public reads go through the redacted `public_gym_workouts` view, not the base table** (`20270313_001`): the base table is owner-only (`user_id = auth.uid()`), and the view projects only `id, user_id, started_at, title, duration_s, is_public, set_count, volume_kg, created_at` for `is_public` rows. `external_id`, `last_modified_at`, `notes`, and `metadata` are **owner-only** (import crosswalk / sync clock / free text / internal plan-link — none classified public-safe). Mirrors the `public_runs` pattern. A non-owner query against the base table returns `[]` rather than a 42501, so a client that misses the view **under-reports silently** — the cross-modal following feed's lift branch (web `fetchFollowingLifts`, mobile `_fetchFollowingLifts`) did exactly that until #527. `following_lifts_visibility_test.sql` pins the follower contract; the mobile `architecture_guards_test.dart` pins the reader. |
| `gym_sets` | `20261204_001` | One row per logged set, child of `gym_workouts`. `id, workout_id, set_index, exercise_name, reps, weight_kg, rpe` (`duration_s` added later for timed holds — instructor_business.md M2; `exercise_id` nullable catalogue FK — `20270222_001`; `set_type` NOT NULL default `working`, CHECK over the routine vocabulary warmup/working/dropset/amrap/failure/backoff — `20270228_001`, decisions §189; **`exercise_key` NOT NULL default `''`, the server-stamped grouping key** — `20270706000001`/`20270706000002`, decisions § 1076, maintained by the `gym_sets_stamp_exercise_key_trigger` BEFORE INSERT OR UPDATE trigger and held to `normalise_exercise_name(exercise_name)` by the validated CHECK `gym_sets_exercise_key_canonical`, with `gym_sets_exercise_key_len_chk` bounding it at the name's own 120; a client-supplied value is overwritten, never refused, so no client computes it — see `derived_state.md`). Weights canonical kg. **Non-owner reads of a PUBLIC workout's sets go through the redacted `public_gym_sets` view** (`20270327_001`): the base "visible via parent workout" policy became owner-only-effective when `20270313_001` dropped the parent's public branch (which broke the /share/workout page — CI run 28707481878), and the view projects only `id, workout_id, set_index, exercise_name, reps, weight_kg, duration_s` for sets of `is_public` workouts. `rpe` is **owner-only**. |
| `food_log` | `20261204_001` | Phase-4 nutrition entries. `id, user_id, started_at` (renamed from `logged_at` in `20261208_001`)`, item_name, meal_slot ('breakfast'/'lunch'/'dinner'/'snack'), calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, saturated_fat_g, cholesterol_mg, is_public, external_id, last_modified_at, created_at`. The five extended nutrients (`fiber_g / sugar_g / sodium_mg / saturated_fat_g / cholesterol_mg`) were added by `20270426_001` (issue #492) — all nullable with a `>= 0` CHECK; grams for fibre/sugar/saturated fat, milligrams for sodium/cholesterol. **Public reads go through the redacted `public_food_log` view, not the base table** (`20270313_001`): the base table is owner-only, and the view projects only `id, user_id, started_at, item_name, meal_slot, calories, protein_g, carbs_g, fat_g, is_public, created_at` for `is_public` rows (the extended nutrients are **not** projected into the public view — owner-only, like `external_id` + `last_modified_at`). Mirrors the `public_runs` pattern. |
| `gear` | `20260827_001` | Shoes / bikes for wear tracking. `id, owner_id, kind ('shoe'/'bike'), name, brand, model, purchased_at, retired_at, target_distance_m, notes, created_at, updated_at`. |
| `run_gear` | `20260827_001` | Many-to-many run↔gear link. `run_id, gear_id, created_at`, PK `(run_id, gear_id)`. |
| `gear_wear_logs` | `20270225_001` | Per-shoe wear-pattern observations (roadmap §7). `id, gear_id, owner_id, logged_on (date, default current_date), area ('outsole'/'midsole'/'upper'/'other', nullable), note, created_at, updated_at`. Owner-only RLS end to end (no public-visibility path — unlike `run_gear`, wear notes never leak via a public run); INSERT gated on owning both the row and the parent `gear`. Cascades on parent-gear delete. Complements the distance-based `gear_wear` classifier (the bar says how far; the log says what you noticed). |
| `gear_rotations` | `20270227_001` | Named multi-pair gear groupings (roadmap §7; decisions §183). `id, owner_id, name, created_at, updated_at`. Owner-only RLS (4 policies, like `gear`). A rotation is a many-to-many named group ("Daily trainers"), distinct from and additive to the single `is_default` current pair — assigning a rotation never changes run auto-tagging. No public-visibility path. |
| `gear_rotation_members` | `20270227_001` | Many-to-many rotation↔gear link. `rotation_id, gear_id, created_at`, PK `(rotation_id, gear_id)`. Owner-only RLS; INSERT gated on owning BOTH the parent rotation AND the parent `gear` (the `run_gear` double-gate). Cascades on either parent delete (a deleted gear leaves its other rotations intact). |
| `event_exceptions` | `20261019_001` | Cancelled occurrences of a recurring event. `event_id, instance_start, cancelled_by, reason, cancelled_at`, PK `(event_id, instance_start)`. |
| `deletion_audit_log` | `20260917_001` | Tamper-evident account-deletion ledger keyed by the SHA-256 of the user id (no PII). `hashed_user_id, deleted_at, result (enum of outcomes), notes`. |
| `app_quota` | `20261007_001` | App-level (not per-user) third-party rate-limit counter. `provider, window_kind ('short'/'day'), window_start, count`, PK `(provider, window_kind, window_start)`. |
| `lifecycle_email_log` | `20261202_001` | Idempotency ledger for one-shot lifecycle emails (welcome, etc.). `user_id, template, sent_at`, PK `(user_id, template)`. |
| `account_deletion_receipts` | `20270217_001` | Non-cascading send-once ledger for the account-deletion receipt email (the user — and so `lifecycle_email_log` — is gone by send time). `email_hash` (hex SHA-256 of the lowercased address, no raw PII), `sent_at`, PK `email_hash`. Service-role only; 30-day cron retention. decisions §121. |
| `email_suppressions` | `20270108_001` | Do-not-send list. `email, reason ('bounce'/'complaint'/'unsubscribe'/'manual'), created_at`, PK `email`. |
| `webhook_events` | `20260623_001` | Replay-dedupe ledger for inbound webhooks (RevenueCat, Stripe). `provider, event_id, received_at`, PK `(provider, event_id)`; GC'd by `cleanup-stale-webhook-events`. |
| `user_blocks` | `20261012_001` | Per-user block list for the social layer. `blocker_id, blocked_id, created_at, reason`, PK `(blocker_id, blocked_id)`, CHECK `blocker_id <> blocked_id`. |
| `coach_athletes` | `20261102_001` | Coach↔athlete roster (invite/accept). `id, coach_id, athlete_id, status ('pending'/'active'/'ended'), invite_token, note, created_at, accepted_at, ended_at`. See `redeem_coach_invite` + the coach-visibility note below. |
| `race_listings` | `20270214_001` | Public race calendar (race_calendar.md). `id, provider ('runsignup'/'parkrun'/'manual'/'chronotrack'/'raceresult'/'ultrasignup' CHECK), provider_race_id, name, race_date, distance_m, location_label, location_point geography(Point,4326), entry_url, results_url (both http(s)-CHECKed), submitted_by (→auth.users on delete set null), is_verified, created_at, updated_at`. Indexes: `(provider, provider_race_id)` partial-unique, `(race_date)`, GiST on `location_point`, GIN trgm on `name`. **RLS (since `20270320_001`): base-table SELECT is submitter-own-rows only** (`submitted_by = auth.uid()`) — the public calendar is served by the redacted **`public_race_listings` view** (every column except `submitted_by`, granted to anon + authenticated), closing the audit/rls submitter-crosswalk leak the original `using (true)` policy carried. Authenticated INSERT (`submitted_by = auth.uid()`); submitter UPDATE only while `is_verified=false`. A `before insert or update` trigger (`force_unverified_listing`) forces `is_verified=false` on any non-service-role write — only `service_role` (the import EF / admin) may verify. Read via the `search_race_listings` RPC (below, re-pointed at the view) or the view directly (web/mobile `fetchRaceResultForRun`, the `race-results-import` EF's listing resolve). Also adds `runs.race_listing_id uuid → race_listings on delete set null` (partial index) — links a matched run to its calendar entry; passes through `public_runs` (non-sensitive). |

---

## Row-level security

RLS is enabled on every table. The authoritative policy set lives in the migrations (grep `create policy` / `alter policy`, latest touch wins) and in live `pg_policies`; behaviour is pinned by the pgtap suite under `supabase/tests/`. This section documents the access *model* — do not paste policy SQL from here; it will drift.

House patterns:

- **Owner-scoped by default.** The baseline for user-data tables is an owner policy over `user_id` (per-command on newer tables, `for all` on the early ones), e.g.:

  ```sql
  create policy "users own their runs"
    on runs for all
    using ((select auth.uid()) = user_id);
  ```

  `auth.uid()` / `auth.jwt()` / `auth.role()` / `current_setting()` are always wrapped in a scalar subselect so they hoist into a once-per-statement InitPlan instead of re-evaluating per row; `rls_initplan_test.sql` fails the suite on any bare call.
- **Public reads go through the eight `public_*` SECURITY DEFINER views** (`public_runs`, `public_routes`, `public_profiles`, `public_race_listings`, `public_gym_workouts`, `public_gym_sets`, `public_gym_routines`, `public_food_log`) — NOT through base-table policies. The early `is_public = true` SELECT policies on `runs`/`routes` were dropped when clients switched to the views, which redact columns and metadata keys the row-level flag would otherwise leak (decisions §33). Views are read-only to `anon`/`authenticated` (revoke-then-grant, §201, pinned by `view_write_privileges_test.sql`).
- **Named carve-outs widen the baseline** where a feature needs it — each is its own policy so intent stays readable, which is also why the Supabase advisor's "multiple permissive policies" warnings are accepted. The load-bearing ones on the core tables:
  - `runs`: owner ALL + `active coach reads athlete runs` (SELECT via the coach link).
  - `routes`: owner ALL + club-scoped branches (`club members read club routes`, admin insert/update/delete). No public-read base policy — `public_routes` serves that.
  - `user_profiles`: per-command owner policies (the INSERT gate also blocks self-granting a paid `subscription_tier`; UPDATE columns are locked by `lock_subscription_columns()`), and SELECT for authenticated readers excludes shadow-hidden profiles. Anonymous readers use `public_profiles`.
  - `route_reviews`: own-row per-command writes + `reviews on visible routes are readable` (visibility follows the route, including the club branches).
  - `integrations`: owner ALL (tokens themselves live in Vault, not in the row).
  - `user_coach_usage`: own-row SELECT only. INSERT/UPDATE/DELETE are denied to anon + authenticated (explicit deny policies **and** revoked grants, migration `20270505_001`) — it is a server-maintained meter whose only writers are the `auth.uid()`-guarded definer RPCs and the retention cron. A client-writable counter is a client-resettable spend cap.
  - `monthly_funding`: public SELECT, service-role writes.
- **Clubs & the social graph**: public clubs readable by anyone, private clubs by members + owner; `events`, `event_attendees`, `club_posts` inherit the parent club's visibility PLUS an event-level gate (`20270113_001`, §148) so a public club can hide an individual event; admin-gated writes via `private.is_club_admin`. Social reads additionally carry the `is_blocked_either_way` / `private.viewer_blocks` predicate (§228) so a block hides each party from the other everywhere, including shared-club surfaces.
- **Service-role-only tables** (`app_quota`, `deletion_audit_log`, ledgers like `webhook_events`) have RLS enabled with no anon/authenticated policies at all — fail closed.

---

## Edge Functions

All Edge Functions are TypeScript running on the Deno runtime, deployed to Supabase Edge Functions.

Base URL: `https://{project-ref}.supabase.co/functions/v1/`

Authentication: most functions require a valid Supabase JWT in the `Authorization: Bearer {token}` header (the platform default `verify_jwt = true`). Four functions set `verify_jwt = false` in `config.toml` because they authenticate themselves another way: `strava-webhook` (URL-embedded shared secret + timing-safe HMAC — Strava signs nothing), `revenuecat-webhook` (HMAC over the raw body), `stripe-events-webhook` (Stripe-Signature HMAC over the raw body), and `refresh-tokens` (invoked by pg_cron with a shared bearer token). `clip-public-track` keeps `verify_jwt = true` but is anon-callable: it accepts the Supabase **anon** JWT and gates on the `runs.is_public = true` row check rather than the caller's identity.

---

### `POST /strava-import`

Initiates the Strava OAuth flow and backfills the last 90 days of activities.
A subsequent `{ "action": "sync", "lookbackDays": n }` walks the last `n` days
instead — `n` must be an integer in `1..365` or the function answers 400
`invalid_lookback_days`. Both clients offer 90 / 180 / 365; the maximum is
pinned to this bound by a guard in `strava_sync_result.test.ts`.

**Request:**
```json
{ "code": "abc123", "scope": "activity:read_all,read", "redirect_uri": "https://app.example.com/settings/integrations" }
```

`scope` must contain `activity:read_all` (the function 400s otherwise — Strava lets users untick scopes on the consent screen and we can't backfill without it). `redirect_uri` is compared **whole** against `STRAVA_ALLOWED_REDIRECTS` (comma-separated env var) — not by origin, because Strava's own callback-domain check is already path-prefix loose and that is the window this gate closes. An **empty or unset** env var **fails closed**: the function returns 503 `strava_not_configured` and exchanges nothing. (An earlier revision of this page said the check was disabled when empty — it never was.) A claim outside the list returns 400 `invalid_redirect_uri`. Both branches plus the parse live in `_shared/redirect_allowlist.ts` and are covered by `_shared/redirect_allowlist.test.ts`.

**Flow:**
1. Exchange `code` for access + refresh tokens via Strava
2. Fetch athlete profile to get Strava athlete ID
3. Store tokens in `integrations` table
4. Register Strava webhook subscription (if not already registered)
5. Backfill: fetch paginated activities from past 90 days
6. For each activity: fetch GPS stream, map to `Run`, upsert
7. Report `complete` (the window was walked to its end) and `resumable` (a
   resume point was recorded on `sync_cursor`, so a re-sync continues rather
   than restarting). `last_sync_at` is stamped, and `sync_cursor` cleared,
   only on a `complete` walk — see [decisions § 766 + § 768](../architecture/decisions.md).

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
{ "imported": 23, "skipped": 0, "total": 23, "complete": true }
```

`total` is every usable result the page carried; `imported + skipped` stops at
`MAX_PARKRUN_ROWS` (5000). `complete` is the explicit claim in the shape
`parseStravaSyncResult` established — **a client must treat an absent `complete`
as PARTIAL**, never as whole (decisions § 976).

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
1. Auth (`auth.getUser`) → 401; tiered rate limit — **two buckets**, `race-results-import` at 8/32 per hour for a real import and `race-results-import:probe` at 60/240 for a `probe=true` call, both fail-closed. A probe reads env vars and returns where an import spends a shared per-application provider credential, and charging both to the import bucket meant a few settings-screen loads cost a free runner the ability to import at all — silently, because an exhausted bucket answers 429 and both clients grade a 429 as "provider unavailable" (decisions § 1041, § 1007). Then resolve the public `race_listings` row (name/date/distance) for the metadata stamp.
2. `provider='runsignup'`: **fail closed** — if `RUNSIGNUP_API_KEY`/`_SECRET` are unset return `503 {error:'provider_not_configured'}`; else call the RunSignUp results endpoint, map each finisher to a run row (`source='race'`, `external_id=race:{name}:{date}:{bib}`, the owner-only race metadata). Fail-loud on a non-2xx upstream (502).
3. `provider='chronotrack'`: **fail closed** — if `CHRONOTRACK_CLIENT_ID`/`CHRONOTRACK_USER_ID`/`CHRONOTRACK_PASSWORD` are unset return `503 {error:'provider_not_configured'}`; else call the ChronoTrack Live results endpoint (event id = the listing's `provider_race_id`), map each finisher with the same shaping as RunSignUp. Fail-loud on a non-2xx upstream (502).
4. `provider='paste'`: map the single pasted result row.
5. `provider='ultrasignup'`: **refuses unconditionally** — `503 {error:'provider_not_configured', reason:'results_unattributable'}`, before the credential read and before the fetch. The endpoint is an athlete history feed with no race identifier on a row, so every result would be stamped with the listing's race (decisions § 975).
6. `probe=true`: report provider availability without a listing — `503 provider_not_configured` when `provider='chronotrack'` or `provider='runsignup'` is unconfigured, or `provider='ultrasignup'` (always), else `{configured:true}`. Drives every race-import Settings card: mobile probes all three legs here since decisions § 1041, web ChronoTrack + UltraSignup (its RunSignUp check still asks `race-listings-sync`).
7. `matchRunId` set → merge the metadata + set `race_listing_id` onto that owner-scoped run (no duplicate). Else dedup per-user against existing `external_id`s and insert the fresh rows.

**Response:** `{ "imported": 1, "skipped": 0, "enriched": 0, "complete": true }` (the `matchRunId` path returns `enriched: 1`).

`complete` is false when the provider fetch may have been cut off at
`MAX_RESULTS_ROWS` (2000). It is reachable rather than theoretical:
`runSignUpResultsUrl` narrows upstream by **user id only**, so a request scoped
by bib alone fetches the whole finisher field and the bib filter runs afterwards
— a major with 30,000 finishers truncates before it. A truncated fetch that
matched nothing answers `502 {error:'upstream_results_truncated', complete:false}`
rather than a successful import of nothing, because "we read the whole field and
you are not in it" and "we read the first 2,000 and you were not among them" are
different sentences (decisions § 976).

### `POST /race-listings-sync`

Pulls a provider's upcoming races into `race_listings`. **Fail closed**: returns `503 {error:'provider_not_configured'}` when the chosen provider's key/secret are unset (`RUNSIGNUP_API_KEY`/`_SECRET`, or `ULTRASIGNUP_API_KEY`/`_SECRET` for `provider:'ultrasignup'`). **No client probes it any more** — every Settings card gates an *import*, so all six probes (three legs x two platforms) ask `race-results-import` instead (decisions § 1041 for mobile, § 1064 for web). The no-`sync` branch stays: it is what makes a sync opt-in, not a probe affordance. An unrecognised `provider` is `400 unknown_provider`, never coerced to the default.

**Request:** `{ "sync": true, "provider": "runsignup" | "ultrasignup", "near": { "lng": -106.9, "lat": 37.8, "radius_m": 50000 } }` — `near` is optional; present-but-unusable is a `400`, never a silent fall back to no hint. **Without `sync: true` this is a credential probe**: it answers `{"configured": true}` behind the same gate and performs no fetch and no write. A sync has to be asked for or a page load would walk the provider feed and spend the 2/hour bucket (decisions § 977). Since decisions § 1041 the only caller left is web's `isRunSignUpConfigured`: every mobile probe and web's UltraSignup one ask `race-results-import`, which owns the results leg those cards are a claim about.

**Flow:** auth → tiered rate limit (fail-closed) → provider gate → credential gate → fetch the provider feed → read each row through that provider's reader → reconcile against the stored `(provider, provider_race_id)` rows → insert the new ones and update only the changed ones, **as the service role** (`race_listings_force_unverified` forces `is_verified` false for every other role, and the INSERT policy requires `submitted_by = auth.uid()`). There is no upsert: `race_listings_provider_uniq` is a PARTIAL unique index and PostgREST cannot supply its predicate as an `ON CONFLICT` arbiter (42P10).

**Response:** `{ "synced": 4, "updated": 1, "skipped": 0, "unusable": 0, "total": 5, "complete": true }`. `unusable` is rows the provider returned that could not yield the name and date `race_listings` requires — the field names in `lib.ts` are **unverified against a live payload** (no credential exists), so a differently-shaped feed answers `synced: 0` with `unusable` equal to the row count rather than writing junk into a public calendar (decisions § 977). A non-2xx or unparseable upstream is `502` and writes nothing.

**Env:** `RUNSIGNUP_API_KEY`, `RUNSIGNUP_API_SECRET` (both required for the RunSignUp legs — unset → 503), `CHRONOTRACK_CLIENT_ID`, `CHRONOTRACK_USER_ID`, `CHRONOTRACK_PASSWORD` (all three required for the ChronoTrack leg — any unset → 503), `RACE_IMPORT_USER_AGENT` (optional, defaults `RunApp/1.0`).

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
1. Authenticate user via JWT; rate-limit 3/hour (fail-closed)
2. Best-effort third-party revocations — each outcome (`ok`/`skipped`/`failed`) recorded to `deletion_audit_log.third_party_outcomes`, failures logged for operator replay but never abort the erasure: Strava OAuth deauthorize, Garmin (fail-closed placeholder until OAuth ships), RevenueCat subscriber DELETE, FCM push-token batchRemove, Stripe Connect Express account DELETE (`/v1/accounts/{id}` — closes the host's live payout account before the `instructor_payout_accounts` row cascades away with its id)
3. Mandatory pre-cascade cleanups — any failure aborts with 500 and leaves the auth row intact for retry: `vault.secrets` (integration tokens), `reports` rows targeting the user, `jobs` queue payloads carrying the user id, `rate_limits` rows, `segments` anonymisation
4. Mandatory Storage drain: recursive `{user_id}/` prefix walk of the `runs` (tracks + legacy exports), `exports`, `run-photos`, `route-photos`, and `club-photos` buckets — abort on failure; plus a best-effort `avatars` drain
5. Delete the auth user via `admin.deleteUser()` — row data in `runs`, `routes`, `user_profiles`, `user_settings`, etc. cascades automatically via `ON DELETE CASCADE` foreign keys
6. Enqueue the deletion-receipt email (no `user_id` in the payload) and write the `ok` audit row with per-table deleted counts

**Response:**
```json
{ "ok": true }
```

No request body required. Irreversible.

---

### `POST /v1/export/jobs` + `GET /v1/export/jobs/latest` (Go worker)

The queued Art 20 rail ([decisions § 717](../architecture/decisions.md)), and since [§ 724](../architecture/decisions.md) the **only** rail on the Go worker — the synchronous `POST /v1/export` is deleted, and both clients enqueue. Both endpoints take an `Authorization: Bearer <supabase access token>` and refuse with 503 when the worker has no JWT verification configured.

**`POST /v1/export/jobs`** — body `{ "format": "csv" | "gpx" | "backup" }` (default `csv`). Answers **202** with `{ "job_id", "status", "format", "reused" }` and builds nothing on the caller's connection. An export already `queued` or `running` for the subject is returned with `reused: true` and **spends no rate-limit token** — a client retrying through a flaky connection would otherwise burn its whole hour's quota re-requesting the export it already has building. Rate limit otherwise unchanged: free 2/h, pro 8/h via `check_rate_limit_tiered`, fail-closed on an RPC error.

**`GET /v1/export/jobs/latest`** — the subject's most recent export, so a page reloading mid-build needs nothing stored locally. Answers 200 with `{ "status", "job_id", "format", "requested_at" }` plus, when `status = "ready"`, `{ "url", "expires_in", "count", "total", "complete" }`. `status` is one of `none` (never asked), `queued`, `running`, `ready`, `failed` (with `error_code`), `expired` (the 7-day sweep collected the artifact), or `stalled` — a **read-time derivation**, never a stored state, for a row nothing has touched for longer than the worker's whole retry budget, which is what a crash between claim and result write looks like. The signed URL is minted **here**, not at build time, so its 10-minute clock starts when the subject asks. The two clients spend that differently and both are right for their surface: web holds a real `href` on the page and therefore re-reads at half the URL's lifetime so the link cannot expire under someone looking at it; mobile holds no link at all — its card carries a Download action that re-reads this endpoint at the tap, so the ten minutes start when the runner acts and a ready job needs no polling (§ 724).

### `POST /export-data`

> **Status: Deprecated.** Superseded by the Go worker's **queued** export rail — `POST /v1/export/jobs` + `GET /v1/export/jobs/latest` (`apps/job_worker/internal/dataexport/`, [decisions § 717](../architecture/decisions.md)). Web picks transport via `PUBLIC_EXPORT_HUB_URL`: unset → call the EF, set → call the worker. Mobile has no EF path at all and always enqueues ([§ 724](../architecture/decisions.md)). The EF is kept deployed as the rollback path and still builds **synchronously** — it is now the **only** synchronous export rail anywhere, which is why the web client keeps a synchronous branch for it and nothing else does.

Exports a user's data as a CSV, a GPX zip, or the full `run-app-backup` zip. GDPR data portability.

**Request:**
```json
{ "format": "gpx" }   // or "csv" or "backup"
```

**Response:**
```json
{ "url": "https://<ref>.supabase.co/storage/v1/object/sign/exports/<user_id>/exports/<ts>.zip?token=...",
  "expires_in": 600,
  "count": 142,
  "total": 142,
  "complete": true,
  "format": "gpx" }
```

A signed Supabase Storage URL pointing to the generated artifact, valid for 10 minutes (the Storage `path` is deliberately not echoed — see the function's header comment). CSV produces a single row-per-run file. GPX produces a zip containing one `runs/<run_id>.gpx` per run that has a track plus a top-level `runs.json` manifest mirroring the CSV column set. `backup` produces the same `run-app-backup` v1 archive layout as the Go worker's canonical export — `manifest.json` + `runs.json` + `routes.json` + `profile.json` (incl. `subscription_tier` / `subscription_at` / `billing_issue_at`) + raw `tracks/` and `hr/` gzips + `photos/` bytes + one `.json` per personal-data table via `backup_spec.ts` (incl. `route_markers` + `checkpoint_crossings`) — see [backup_restore.md](../ops/backup_restore.md). **No run cap and no per-section row ceiling** on this rail since 2026-08-21 ([decisions § 703](../architecture/decisions.md)): the archive is streamed into Storage through a chunked tus upload (`/storage/v1/upload/resumable`, 6 MiB chunks) and each section is serialised page by page, so nothing is resident. The bound that remains is the function's 150 s request clock, enforced as an explicit 120 s budget — a section it cuts short is named in `manifest.json`'s `incomplete`. (The Go worker's queued rail, which production actually calls, streams the same way since [decisions § 708](../architecture/decisions.md) and carries neither cap either. The two rails differ only in what bounds them: the function has a request clock and the worker does not, so there is no budget on the Go rail — its remaining bound is the Storage object-size ceiling, effectively the project-level upload limit, and it fails the upload rather than shortening the archive.) `count` is what the archive carries, `total` what the database holds, and `complete` whether the two agree and no section was cut short — a runner whose export ran out of wall clock (or was hit by a page that failed to read) gets a short archive, and both clients disclose it: web swaps the success toast for a partial one and leaves a persistent notice under the export buttons on `/settings/account`, mobile discloses it on the account-export card and banners it after the share sheet closes. Only an explicit `complete: false` claims a shortfall — a response without the field (an older deployment of either transport) is not evidence of truncation. The `backup` format says the same thing in more detail inside `manifest.json` (`complete` + the `incomplete` section list). Rate limit: free 2/h, pro 8/h via `check_rate_limit_tiered`.

---

### `POST /revenuecat-webhook`

Receives RevenueCat subscription events (initial purchase, renewal, cancellation, billing issues, expiration, transfer) and updates the corresponding `user_profiles.subscription_tier` + `subscription_at`. Authenticated by an HMAC-SHA256 of the raw body in the `x-revenuecat-hmac` header (constant-time compared against `REVENUECAT_WEBHOOK_SECRET`) — RevenueCat configures the same value in their dashboard. Replay-protected: events are rejected if `event_timestamp_ms` is outside `[now - 5min, now + 1min]`, and `event.id` is recorded in `webhook_events (provider, event_id)` (migration `20260623_001_webhook_event_dedupe.sql`) so a duplicate delivery skips the side effect and returns 200. Event-id dedupe stops *replays* but not two *distinct* events arriving out of order, so the tier write is additionally made **monotonic** on `tier_updated_event_ts` (`20270403_001`, decisions §229): a deactivation applies only when its `event_timestamp_ms` is newer than the last event that set the tier. See [paywall.md](../features/paywall.md) for the tier mapping. Migration ladder: `20260429_001_subscription_paywall.sql` (the column + CHECK constraint), `20260623_001_webhook_event_dedupe.sql` (replay table), then this function as the write path.

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

Stripe Connect events webhook — the one idempotent writer of order **and donation** status (club_events.md slice P1 + fundraising.md). `verify_jwt = false` (Stripe presents no Supabase JWT); authenticated by the `Stripe-Signature` HMAC over the **raw** body against `STRIPE_EVENTS_WEBHOOK_SECRET`. **One webhook, one secret** — the donation path is a branch keyed on `session.metadata.kind === 'donation'` (`isDonationSession`), not a second endpoint. Every `data.object` is narrowed once through the typed readers in `lib.ts`, whose source shapes are pinned to the SDK's own `Stripe.Checkout.Session` / `Stripe.Charge` / `Stripe.Account` by compile-time assertions over a type-only import (decisions § 785). **A completed Session is not a payment**: for a delayed-notification method (SEPA debit, Bacs, boleto, a bank redirect) `checkout.session.completed` arrives with `payment_status: 'unpaid'` and the outcome lands days later, so both confirm arms gate on `isPaymentSettled` before any write and the two async outcomes are dispatched — the Stripe endpoint must subscribe to them. Event-seat branch: `checkout.session.completed` / `checkout.session.async_payment_succeeded` (CAS `pending`→`paid`, confirm-time capacity recheck, seat the `going` attendee; oversold → left paid + flagged for manual refund), `checkout.session.expired` (CAS `pending`→`canceled`, releasing the reservation), `checkout.session.async_payment_failed` (CAS `pending`→`failed`, releasing it the same way), `account.updated` (mirror `charges_enabled` / `payouts_enabled` / `details_submitted`). Donation branch: `checkout.session.completed` / `checkout.session.async_payment_succeeded` (CAS the `donations` row `pending`→`paid`, set `paid_at` + `stripe_payment_intent_id`), `checkout.session.expired` / `checkout.session.async_payment_failed` (`pending`→`canceled` / `failed`), `charge.refunded` (resolve the donation via `stripe_payment_intent_id`, then CAS `paid`/`partially_refunded` → `refunded` on a full refund or `partially_refunded` on a partial one, writing `refunded_cents` from the charge's **cumulative** `amount_refunded`). The refund CAS is compound — the status it read **and** `refunded_cents <= the reported total` — so two instalments delivered out of order cannot walk the figure back (`20270620_001`, decisions § 776). **A refund that FAILS is a fourth outcome on both ledgers** (`20270624000001`, decisions § 789): `charge.refunded` fires when a refund is *created*, so the seat is released before the money settles, and a bank rejection arrives later as `refund.failed` / `refund.updated` / the deprecated `charge.refund.updated` (all three handled — which one an endpoint receives depends on its pinned API version relative to `2024-10-28.acacia`, which is dashboard configuration; the Stripe endpoint must subscribe to them). The arm is gated on the **Refund object's own status** (`failed` / `canceled`; `pending` and `requires_action` are still in flight) via `refundReversed`, never on the event type — `refund.updated` also fires when Stripe attaches an acquirer reference number. It CASes `refunded -> refund_failed` on whichever ledger owns the payment intent, **touches no seat**, and is reachable only from `refunded`: `partially_refunded` is seat-bearing on orders and is the only donation state whose `refunded_cents` still nets into the thermometer, so a failed *partial* refund does not move a status. Since `20270630000001` (decisions § 823) it is nonetheless RECORDED: every refund-lifecycle delivery upserts a `payment_refunds` row keyed on the Stripe Refund id — before the reversal gate and whatever the status, so a reversal has its sibling instalments to be read against — and `fundraiser_totals` / `fundraiser_feed` add back any part of `refunded_cents` whose refund is recorded `failed` or `canceled`. The correction is strictly additive and clamped to `refunded_cents`, because the child set is only as complete as the endpoint's `enabled_events`: `charge.refunded` carries a Charge and no refund id, so deriving `refunded_cents` itself from these rows would count an unheard-of succeeded refund as money kept. `refund_failed + charge.refunded (full) -> refunded` is the one way out, for a refund paid another way that landed. `donationStatusTransition` is the donation analogue of `orderStatusTransition` — a replayed `completed` on an already-`paid` donation no-ops, so it can't double-count. Idempotency, defence in depth: insert-first into `webhook_events (provider='stripe', event_id)` (a duplicate 23505 → 200 ok-skipped) plus the CAS guard. **Test mode only in P1** — fails closed (503) if the secret is unset. Since `20270701000001` the reversal also **tells the payer**: an `after update of status` trigger on each ledger writes a `refund_failed` notification on the transition, which the fan-out turns into the inbox row, the email and both pushes ([decisions § 825](../architecture/decisions.md)). The dispatcher additionally logs which refund-event **era** the delivery belongs to — `refundEventsApiEra(event.apiVersion)` graded against `2024-10-28.acacia`, on the ISO date prefix, `unknown` for anything unparseable — so an operator can tell from the logs whether the endpoint is receiving `refund.failed` / `refund.updated` or only the deprecated `charge.refund.updated`, which is otherwise unreadable from this repo ([decisions § 826](../architecture/decisions.md)).

### `POST /donations-checkout`

Donor checkout for a charity fundraiser (fundraising.md). `verify_jwt = false` — the donor **may be anonymous** (a donation has no seat, unlike a paid registration); if a JWT is present the donation is attributed (`donor_user_id`), otherwise it stays anonymous. Opens a Stripe-hosted Checkout Session as a **destination charge** against the fundraiser owner's connected account and inserts a `pending` `donations` row (service role). Validation gates each fail closed: the fundraiser is visible to the caller (RLS — a private-anchor fundraiser reads as not-found) and `status='open'`, the owner has a charges-enabled payout account (`host_can_take_payment`, else 409), and the amount is within sane bounds (100…1,000,000 cents). Idempotency: the caller **must** send `idempotency_key` (a UUID minted once per donation attempt and re-sent on a retry; a missing or malformed one is a 400). It is persisted as `donations.client_request_id` under a unique index, the pending donation is resolved from it **before** the Stripe call, and the same donation id then rebuilds byte-identical Stripe params so Stripe replays the session already open. A key presented against a different fundraiser/amount/donor, or one whose row is no longer `pending`, is a 409 rather than a replay. The row is written **before** the Stripe call so a crash between the two is repairable. The key cannot be derived server-side: a donor may be anonymous, so there is no identity to key on, and repeat giving is legitimate (decisions § 776). The `stripe-events-webhook` donation branch confirms the donation on `checkout.session.completed`. SAQ A (no card form). **Test mode only in P1** — fails closed (503 `stripe_not_configured`) when `STRIPE_SECRET_KEY` / `STRIPE_EVENTS_ALLOWED_REDIRECTS` are unset; the key must be an `sk_test_` key.

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

### Who may EXECUTE one — and why `revoke ... from public` is not enough

Every function in `public` is owned by `postgres`, and what a freshly created
one's ACL says depends on the Postgres image the schema is running on:

- **Supabase Cloud and CI** (`supabase/setup-cli` is pinned to `2.84.2` in
  `ci.yml`) carry an `alter default privileges` for `postgres` that grants
  EXECUTE to `anon`, `authenticated` and `service_role`. A new function arrives
  with those three **by name**, so `revoke execute ... from public` removes
  nothing — there is no PUBLIC entry to remove.
- **A current workstation CLI** (2.109.1) ships an image whose `postgres`
  default ACL is `{postgres=X/postgres}`, and a new function comes up with
  `proacl` NULL — Postgres's built-in owner+PUBLIC default. There
  `revoke ... from public` *does* withhold from `anon`, and
  `revoke ... from anon` is the statement that withholds nothing.

Two shipped pgtap suites are the evidence that the two differ, and both fail on
a current workstation while passing on CI: `coach_roster_summary_test` expects
an anon caller to enter the body of a function revoked only `from public` and be
refused **by the body**, and `donations_status_lock_test` calls
`fundraiser_totals` as `service_role`, which no migration ever granted it.

**So the only portable withholding names both grantees:**

```sql
revoke execute on function public.<fn>(<args>) from public, anon;
grant  execute on function public.<fn>(<args>) to authenticated;   -- and/or service_role
```

Add `authenticated` to the revoke list when no client role should hold it at all
(the `cleanup_*` / `enqueue_*` cron family, and helpers only a SECURITY DEFINER
trigger calls). 57 migrations write a function-level `from public, anon` revoke
today (45 as `revoke execute`, 12 as `revoke all`); it is the house form for
exactly this reason, and `check_migration_function_revoke_noop.mjs` is what
keeps it — it replays all 478 migrations in version order and fails the PR on
any EXECUTE revoke that leaves the other channel at its image-dependent
default, in either direction. **Those four figures are derived, not typed**: the
guard prints them and `check_migration_function_revoke_noop.test.mjs` asserts
this paragraph against its output, because they had gone stale on every
migration-bearing PR and been hand-corrected twice — the second time to a total
that did not agree with its own parenthesis ([decisions § 1181](../architecture/decisions.md)).

**The same replay runs in the positive direction**, and that half is
`check_stated_function_grants.mjs` ([decisions § 1139](../architecture/decisions.md)).
A catalogue assertion cannot tell a stated grant from an inherited one on the
image the PR gate runs, so this one reads the migration text and derives the ACL
the repo *states* — PUBLIC discounted, since PUBLIC is exactly the channel the
two images disagree about. The obligation is **derived from the call sites**:
every RPC name the web, Lambda, `api_client` and mobile trees call must carry a
stated `authenticated` grant, and every one the Edge Functions and the Go worker
call must carry a stated `service_role` one, so a PR that adds a caller whose
grant no migration states fails on that PR. The `stated` table in
`anon_execute_registry_test.sql` is the second, much smaller source, for a pair
no source tree names; the guard parses its rows out of that file so the two read
one registry. It runs as a step in the `pgtap RLS suite` job and needs no stack.
It found three violations on its first run: `host_can_take_payment` (called as
service_role by both checkout functions, granted by `20270708000001`,
[§ 1140](../architecture/decisions.md)) and `api_client`'s two dead callers
([§ 1142](../architecture/decisions.md)).

Two further rules follow from the same mechanism:

- **`drop function` takes the privileges with it**, so a signature change
  re-issues the image default. Any migration that drops and recreates a function
  must re-emit its `revoke` / `grant` pair, or a withholding decision is
  silently reverted. `20260830_001` withheld `segment_leaderboard_tiered` from
  `anon` as an audit fix and `20261022_001` handed it straight back that way
  (repaired in `20270625000001`; see [decisions.md § 799](../architecture/decisions.md)).
- **The grant is the only control a SECURITY DEFINER function has** unless its
  body checks `auth.uid()` itself. `anon_execute_registry_test.sql` pins the
  rule and the four functions `20270625000001` withheld, plus — in assertions
  (7)-(9) — the routines a named role must be able to CALL. Those three joined
  the registry on `pg_get_function_identity_arguments`, which carries parameter
  NAMES, against an `args` column that carries the type list, so they matched
  nothing on either image and asserted over an empty set until
  [§ 1141](../architecture/decisions.md) moved them to
  `oidvectortypes(p.proargtypes)` and added (9) as the control.

**The set of anon-executable functions is closed, and pinned.**
`20270626000001` swept the remaining 71 and
`anon_execute_contract_test.sql` holds the contract for the whole schema: no
`public` non-trigger function outside a 34-row allowlist may be executable by
`anon` or carry a PUBLIC / `anon` EXECUTE entry, every function *on* the
allowlist still must be (so a blanket revoke that 42501s the logged-out pages
fails there rather than in production), and the cron / job-queue family must
stay closed to `authenticated` while `service_role` keeps it. Adding an RPC that
a logged-out visitor needs therefore means adding a row to that list with the
surface that justifies it; adding one they do not need means writing the revoke,
or the test names your function. The 34 are the `/share/*` and `/live/[id]`
lookups, the logged-out map / search / discovery readers, the public fundraiser
and segment and challenge boards, the three visibility oracles named inside the
`public_runs` and `public_routes` view definitions, `is_event_visible` and
`is_challenge_visible` (named by policies `to public` on tables `anon` can
read — withholding either turns an anonymous read into `42501`), and
`confirm_safety_contact_by_token`, which a trusted contact calls from an emailed
link with no account at all.

Trigger-returning functions are outside that contract on purpose: Postgres
raises `0A000` for a direct call before privileges are consulted, so no grant
makes one reachable. Extension-owned functions are outside it too — several
hundred arrive with the image default and are the extension's business.

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

Viewport-shaped companion to `nearby_routes`. Returns public routes whose **privacy-clipped polyline** (`routes.geom_public`) intersects the bounding box, sorted by distance from the box centre. Requires the clipped LineString column from migration `20270509_001_routes_geom_public.sql`.

The predicate deliberately does **not** read `routes.geom`. Running it over the raw line while returning `id` made this RPC — which is granted to `anon` — a membership oracle: a grid sweep of small boxes traced the in-zone tail of a public route at box resolution, recovering exactly the coordinate privacy zones exist to withhold (decisions §566). It also **fails closed**: a route with no `geom_public` (fully inside a zone, or fewer than two valid waypoints) is not returned, rather than falling back to the unclipped column.

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

Filtered + sorted search over public routes (`is_public = true`), all parameters optional with defaults (`p_featured_only false`, `p_sort 'newest'`, `p_limit 50`, `p_offset 0`). `p_query` does a case-insensitive `ilike` over `name` (pg_trgm GIN index `routes_name_trgm`, migration `20270316_001` — which also dropped the tsvector `routes_name_search` index, since a `to_tsvector` GIN can never serve `ilike`); the numeric/surface/tags args narrow the set (`p_tags` uses the `&&` array-overlap operator); `p_sort` ∈ `popular` / `featured` / `newest`. **Returns `setof public_routes`** — the narrowed public-safe view, not the full `routes` columns. SECURITY DEFINER, granted to `anon` + `authenticated` so the `/routes` Explore tab works without sign-in. Latest signature in migration `20261217_001_f17_naming_uniformity.sql`; earlier it was the simpler `(q text, max_results int)`. **Live body in `20270326_001`** (db-performance High): plpgsql with one CASE-free `ORDER BY` branch per sort mode instead of the original three CASE-wrapped arms — a CASE sort key can never match a b-tree, so every call used to sort the whole public set. Each branch is served by a matching partial index (`routes_public_popular_sort` (`run_count desc nulls last, created_at desc`), `routes_public_featured_sort` (`featured_at desc nulls last, created_at desc`), `routes_public_newest_sort` (`created_at desc nulls last`), all `where is_public and not shadow_hidden`; an unrecognised `p_sort` keeps the old trailing `created_at desc` arm via the pre-existing `routes_public` index). Ordering semantics are unchanged, including nulls placement; pinned old-vs-new by `search_public_routes_sort_test.sql`. Used by `RouteExplorer.svelte` via `apps/web/src/lib/core/data.ts:searchPublicRoutes`.

### `popular_route_tags(tag_limit int)`

Returns the top-N most-used tag strings across `routes.tags` for the Explore tab's tag chips. Granted to `anon` + `authenticated`. Migration `20260502_001_popular_route_tags.sql`.

### `search_race_listings(p_query text, p_distance text, p_from date, p_to date, p_center_lng double precision, p_center_lat double precision, p_radius_m double precision, p_limit int)`

Proximity + soonest-first race-calendar discovery over the redacted `public_race_listings` view (race_calendar.md; re-pointed at the view in `20270320_001` when the base table became submitter-own-rows only). `security invoker` — the view is granted to anon + authenticated and never carries `submitted_by`, so this adds no exposure. All args optional: `p_query` ILIKEs `name`; `p_distance` ∈ `5k`/`10k`/`half`/`marathon`/`ultra` buckets `distance_m` into a tolerance window (mirrors the `race_match` bands); `p_from`/`p_to` window the date (default: upcoming, `race_date >= current_date`); when `p_center_lng`/`p_center_lat` are supplied it gates on `ST_DWithin(location_point, center, p_radius_m)` (default 50 km, GiST index) and returns `distance_m_away`, ordering nearest-first then soonest. `p_limit` clamped to 1–200 (default 60). Granted to `anon` + `authenticated`. Migration `20270214_001`. Used by web `searchRaceListings` (`core/data.ts`) + mobile `RaceService.searchRaceListings`.

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

SECURITY DEFINER boolean — `select user_profiles.subscription_tier in ('pro','lifetime')` for `auth.uid()`. Used by Edge Functions and the `/api/coach` server route to gate paywalled features without a separate column lookup per request. Granted to `authenticated` + `service_role`, and revoked from `public, anon` in `20270626000001` — no RLS policy names it, so the grant narrows freely. Migration `20260429_001_subscription_paywall.sql` (the predecessor `is_user_pro(uuid)` was dropped in `20260516_001`).

### `join_club_by_token(token text)`

SECURITY DEFINER. Validates a `club_invites.token`, checks expiry / max-uses, inserts a `club_members` row for the caller, and bumps the invite's redemption counter. Atomic — partial failures roll back. Granted to `authenticated`. Migration `20260417_001_club_invites.sql`.

### `redeem_coach_invite(token text)`

SECURITY DEFINER. The caller becomes the athlete on a pending `coach_athletes` invite matching `token` (sets `athlete_id = auth.uid()`, `status = 'active'`). Raises if the token is missing/already redeemed, the caller is the coach (no self-coaching), or the caller is already linked to that coach. Backs `redeemCoachInvite` on the web `/coaching/accept/<token>` page. Table `coach_athletes` (migration `20261102_001`): RLS scopes reads/writes to coach + athlete; coach-only insert of pending invites; either party may end (`status='ended'`); a coach may delete an unredeemed invite. See [decisions.md § 97](../architecture/decisions.md#97-coach-athlete-roster-is-a-web-first-inviteaccept-link-model-persona-hunt-coach-46).

**Coach run visibility (migration `20261103_001`, persona #47).** A `status='active'` link is the consent that lets a coach read their athlete's runs. The helper `private.is_active_coach_of(coach, athlete)` (SECURITY DEFINER, mirrors the club-membership EXISTS inside `is_route_visible_to`) feeds two additions: a `runs` SELECT policy (`active coach reads athlete runs`) so the coach reads the athlete's run rows **public and private** directly off the base table (the `public_runs` view is is-public-only), and a coach branch inside `private.is_run_visible_to` so the social rows gated by it (run_kudos / run_comments / segment_efforts / live_run_pings) are visible too. SELECT-only — no coach write path into an athlete's runs; ending the link (`status='ended'`) revokes immediately. **Run photos are NOT shared with the coach** (migration `20261125_001`, audit-storage): both the `run_photos` table SELECT policy and the `run-photos` Storage byte policy use `private.is_run_photo_visible_to` (owner-or-public, no coach branch), so a coach sees private-run photos no more than the raw GPS track — which also stays owner-only (the `runs` bucket Storage policy is unchanged). See [decisions.md § 98](../architecture/decisions.md#98-an-active-coach-reads-an-athletes-runs-private--public-the-raw-gps-track-stays-owner-only).

### `assign_plan_to_athlete(p_source_plan_id uuid, p_athlete_id uuid, p_start_date date) → uuid`

SECURITY DEFINER (migration `20270106_001`, persona #46/#47). Lets an **active** coach give a linked athlete a whole plan, the write counterpart to the read access above. Gates: caller authenticated, caller ≠ athlete, `private.is_active_coach_of(caller, p_athlete_id)` (the active link is the consent), and the caller can read the source plan (their own plan/template, or a club template they're a member of — mirrors `clone_plan_template`). It then **deep-clones** the source plan + its `plan_weeks` + `plan_workouts` into a new `training_plans` row **owned by the athlete** (`user_id = p_athlete_id`, `status='active'`), date-shifted from `p_start_date`, stamping `parent_template_id = source` and `assigned_by_coach_id = caller`. **The copy carries the plan, not the coach**: `vdot`, `current_5k_seconds` and plan-level `notes` are written as literal nulls (`20270711000002`, decisions § 1285), the same three columns `private.strip_template_private_fields` nulls on a template (`20270508_001`) and the two clone RPCs already refused to propagate. Unlike a template, the source here is usually the coach's own personal plan, which **can** hold all three — so until that migration a coach's own VDOT rendered as a header stat on the athlete's plan and the coach's private plan notes landed on a row the athlete owns. The prescription itself is unaffected: `plan_workouts` (all eleven columns) plus `source` and `rules` are carried, and `rules` is the sanctioned plan-wide prose channel (`20270710000003`). Deliberately **not** a trigger — the "users own their plans" policy's `with check (auth.uid() = user_id …)` makes this RPC the only path that can create a row owned by somebody else, and a trigger keyed on `assigned_by_coach_id` would fire on every later update and delete the ATHLETE's own notes. No backfill: nulling a column on a row another user now owns is a second unilateral write on their data, and it would not undo a disclosure that has already happened. **Raises if the athlete already has an active plan** (never silently abandons the athlete's own plan). Clone-not-subscribe (decisions §35/§143): the athlete owns the result under the unchanged "users own their plans" RLS and the coach's later source edits don't propagate; the coach keeps the `plan_workouts`-edit access from `20261116_001`. New column `training_plans.assigned_by_coach_id` (nullable FK → `auth.users`, `ON DELETE SET NULL`) records provenance and rides the existing `select *` DSAR export of `training_plans`. Backs `assignPlanToAthlete` on `/coaching/athletes/[id]`. Pinned by `assign_plan_to_athlete_test.sql`. See [decisions.md § 143](../architecture/decisions.md#143-a-coach-assigns-a-training-plan-by-deep-cloning-one-of-their-own-into-an-athlete-owned-plan-clone-not-subscribe-gated-on-the-active-link).

### `coach_roster_summary() → setof roster row`

SECURITY DEFINER (migration `20270206_001`; latest body `20270314_001`, coach_roster.md). The read-only aggregation behind the multi-athlete roster dashboard. Returns one row per **active-linked** athlete: `athlete_id, display_name, avatar_url, last_run_at, runs_7d, distance_7d_m, load_acute, load_chronic, active_plan_id, plan_completion_pct`. Consent is re-checked **inside** the definer body — a `mine` CTE (`coach_athletes where coach_id = auth.uid() and status='active'`) is the only membership gate (SECURITY DEFINER bypasses the caller's RLS, so the runs/plan coach-read policies can't be the gate here), so a non-coach gets zero rows and an unauthenticated caller **raises** (`not authenticated`, fail-closed). `load_acute` = 7-day distance-proxy stress sum (10 pts/km, mirroring `training_load.ts`'s distance fallback); `load_chronic` = the 28-day total / 4 (avg weekly), is_dnf runs excluded via the `runs.is_dnf` column (`20270314_001` — the `20270206_001` body read the promoted-away `metadata->>'is_dnf'` key, a silent no-op that let DNFs inflate every load); the client computes the ACWR ratio + injury-risk band from those via the shared `coach_load` helper (the risk policy stays out of the SQL). `plan_completion_pct` mirrors `fetchAthletePlanOverview` (done = `completed_run_id is not null OR manually_completed`; denominator excludes `kind='rest'` + `skipped_at is not null`). **Returns no track bytes** — run row stats only; the raw GPS track stays owner-only (decisions §98 unchanged). `grant execute … to authenticated` (never anon). Backs `fetchCoachRosterSummary` on `/coaching` + the mobile `coaching_screen` roster card. Pinned by `coach_roster_summary_test.sql` (the auth boundary: active-only, ended/pending excluded, non-coach empty, unauthenticated raises, revocation immediate). See [decisions.md § 162](../architecture/decisions.md).

### `latest_fitness_snapshot()`

Returns the caller's most recent `fitness_snapshots` row (VDOT, weekly mileage, ATL/CTL, etc.). Cached materialisation of the inputs the dashboard fitness card needs. Granted to `authenticated`. Migration `20260507_001_fitness_snapshots.sql`.

### `get_integration_tokens(p_user_id uuid, p_provider text)` / `set_integration_tokens(p_user_id uuid, p_provider text, p_access_token text, p_refresh_token text, p_token_expiry timestamptz)`

SECURITY DEFINER pair that brokers OAuth tokens through Supabase Vault rather than exposing the encrypted columns directly to the row. `set` writes the access + refresh + expiry into Vault and stores only the secret IDs on the `integrations` row; `get` returns `table(access_token, refresh_token, token_expiry)` for the calling Edge Function. EXECUTE revoked from `public, anon` (`20270626000001` added the `anon` half; the original `from public` alone withheld nothing on Cloud), granted to `authenticated` + `service_role`. Both take an explicit `p_user_id`, and the body raises unless the caller is that user or `service_role`. Decision: [decisions.md § 41](../architecture/decisions.md#41-oauth-tokens-are-stored-in-supabase-vault-not-as-plaintext-columns). Created in `20260603_001_integrations_vault.sql`; current signatures in `20260919_001_get_integration_tokens_modern_claims.sql`. A compare-and-swap variant `set_integration_tokens_cas(p_user_id, p_provider, p_expected_refresh_token, p_access_token, p_refresh_token, p_token_expiry)` (migration `20261006_001_set_integration_tokens_cas.sql`) guards concurrent refreshes.

### `check_rate_limit_tiered(p_user_id uuid, p_bucket text, p_free_max int, p_pro_max int, p_window_seconds int)`

SECURITY DEFINER. Atomic per-bucket per-user counter that picks the ceiling by reading `user_profiles.subscription_tier` **inline** (`pro` / `lifetime` → `p_pro_max`, else `p_free_max`) — it does NOT call `is_pro()`. Returns `table(allowed boolean, retry_after_seconds int, tier text)`. Gates on caller identity: a non-`service_role` caller whose `auth.uid()` ≠ `p_user_id` raises. Used by `/api/coach`, `parkrun-import`, `strava-import`, `export-data` to enforce paywall throttling without each Edge Function hand-rolling the logic. Granted to `authenticated`. Created in `20260605_001_rate_limits_tiered.sql`; current signature (explicit `p_user_id` + window + role-from-JWT-claims check) in `20260726_001_rate_limit_role_jwt_claims.sql`.

### `cleanup_stale_rate_limits()`

SECURITY DEFINER GC for the `rate_limits` table — deletes rows whose window has elapsed. Driven by the hourly `cleanup-stale-rate-limits` pg_cron job. Migration `20260604_001_cleanup_stale_rate_limits.sql`. The body is an unqualified `delete` with no auth check, and until `20270625000001` nothing had revoked EXECUTE from it at all: an anonymous `POST /rest/v1/rpc/cleanup_stale_rate_limits` cleared every elapsed rate-limit window. It is now `from public, anon, authenticated` with `service_role` granted, matching its three siblings.

---

### `claim_next_job(worker_id, kind_filter)`

SECURITY DEFINER. Atomically marks the next ready job as `running`, increments its `attempts`, and returns the row. Used by the Go service (and any future worker) to drain the [`jobs`](#jobs) queue. Revoked from `public, anon, authenticated` and granted to `service_role` only — the body has no auth check, so the grant is the whole control; see the caveat on the [`jobs`](#jobs) table.

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

SECURITY DEFINER RPC for privacy-zone clipping (decisions §33). Reads `user_settings.prefs.privacy_zones` for the target user, walks the input points dropping in-zone leading + trailing entries, and returns the contiguous middle as jsonb. Zones never leave the database. **Granted to no client role.** `20260915_001` revoked `anon` because the RPC is a probe oracle — it trims LEADING in-zone points, so a 3-point probe returning 2 means "inside a zone" and 3 means "outside", and ~40 calls binary-search a victim's home to metre precision with no Edge Function rate limit in the way (it is a PostgREST RPC). `20270521_001` revoked `authenticated` for the same reason: signup is free and unthrottled, so the role is not a trust boundary. Anonymous and signed-in viewers still receive clipped output — every consumer (`clip_route_for_viewer`, `privacy_aware_route_geom`, `route_markers_for_viewer`, the `clip-public-track` Edge Function) is SECURITY DEFINER or service-role and does not need the caller to hold the grant. Web's `clipTrackForUser` helper was deleted in the same change; `api_client`'s twin of it was missed and survived, unreachable and returning `[]` through its own fail-closed catch, until [decisions § 1142](../architecture/decisions.md) deleted it too. **There is no client caller now** — the only clipping path a client has for a run is `fetchClippedTrackForRun` / the `clip-public-track` Edge Function. Input is capped at 50 000 points (raise on overflow) to bound the residual dense-grid probe attack. Returns input unchanged when the target user has no zones configured. Helpers `privacy_distance_m(lat1, lng1, lat2, lng2)` and `privacy_in_any_zone(lat, lng, zones_json)` are exposed in the same migration but used only internally by the RPC.

### `clip_route_for_viewer(p_route_id uuid)`

SECURITY DEFINER RPC for the routes equivalent of `clip_track_for_user` (decisions §33, migration `20260625_001`). Self-contained: caller passes only the route id. Looks up the row internally, applies the same visibility gate as `private.is_route_visible_to` (owner / public-and-not-`shadow_hidden` / club member — the shadow-hidden exclusion landed in `20270329_001`, decisions §206; raises `42501` otherwise so private- or hidden-route reads are loud), and returns either the unclipped `waypoints` (owner) or the clipped output (non-owner, delegated to `clip_track_for_user` so the zone walk has one implementation). Granted to `anon` + `authenticated`. Anon callers can only read non-hidden `is_public = true` routes. Routes carry waypoints inline (no Storage indirection like runs) so this is a straight RPC rather than an Edge Function.

### `segment_effort_ranks(p_run_id uuid)`

Returns `(effort_id, rank)` for every segment effort on a run in one round-trip — replaces a client-side N+1 count-per-effort loop in `fetchEffortsForRun` (migration `20261223_001`, perf-hunt 2026-06-10). `rank = 1 +` the number of **distinct other athletes** holding at least one strictly-faster effort on the same segment that is visible to the caller and not blocked either way — the same one-row-per-athlete population `segment_leaderboard_tiered` ranks over, so the chip and the board the chip links to can't disagree (migration `20270523_001`, decisions §594). Counting distinct rival `user_id`s *is* the boards' `distinct on (se.user_id)` best-effort reduction (an athlete's best is under `t` exactly when they hold some effort under `t`), so the covering `segment_efforts (segment_id, time_seconds)` range scan still serves it with no extra index. The effort's own athlete is excluded: on a per-athlete board you are not your own competitor, so a repeat effort never ranks against your own faster one. SECURITY INVOKER, so `segment_efforts` RLS (segments EXISTS → `private.is_route_visible_to`, plus `private.is_run_visible_to`) bounds the population; the block filter is the one predicate RLS can't supply and is applied to the comparison set only — never to the run's own efforts, so a caller reading a blocked athlete's public run still gets a rank row. It is applied through `private.viewer_blocks` rather than by naming `is_blocked_either_way` (migration `20270609_001`, decisions §746): a SECURITY INVOKER body ACL-checks every function it names against the CALLING role, and `20261108_001` revoked anon's EXECUTE on `is_blocked_either_way`, so from `20270523_001` until `20270609_001` an anonymous reader of a public run was admitted into the body and then 42501'd inside it — and only once the rival subquery yielded a row, i.e. on exactly the efforts the runner had not won. Neither client degrades a missing row to `#1` any more; an unanswered rank is null and the chip says the standing is unknown. Tie semantics = standard competition ranking (tied fastest both rank 1, next ranks 3). The boards' `p_gender` / `p_age_band` / `p_club_id` tiers are deliberately not mirrored — the chip states a standing on the default all-comers board. Granted to `anon` + `authenticated`. **Both clients call it** — web `fetchEffortsForRun` (`core/data.ts`) and mobile `ApiClient.fetchEffortsForRunWithSegments`; mobile counted strictly-faster effort rows client-side until 2026-08-19 (decisions §696), which is the same divergence one layer out where no migration reaches it, so the mobile call site is pinned by the source guard `packages/api_client/test/segment_effort_ranks_source_test.dart`. pgTAP `segment_effort_ranks_test.sql` + `segment_effort_ranks_per_athlete_test.sql`.

### `normalise_exercise_name(p_name text)`

The exercise grouping key, and the only SQL definition of it (migration `20270623000001`, decisions § 790). Lower-cases, collapses every run of whitespace to one space, trims. `IMMUTABLE` / `parallel safe` / `returns null on null input`, `search_path = ''`, granted to `authenticated` **and `service_role`** — the two CHECK constraints below name it, and a CHECK ACL-checks the function it names against the role performing the INSERT, so the grant list is decided by who writes those tables rather than by who calls the RPCs (`anon` writes neither and a CHECK only runs on a write). Five RPCs group on the key it defines — `gym_exercise_names`, `gym_exercise_records`, `gym_exercise_set_history`, `gym_exercise_set_history_batch` and `gym_workout_summaries` — but since `20270706000002` none of them derives it per row: they read the persisted `gym_sets.exercise_key`, and the two history RPCs call this function only on their own ARGUMENT. The blank-name filter moved with the key (`s.exercise_key <> ''` — a name that is nothing but whitespace is not an exercise). **The whitespace class is written by explicit code point, not as `\s`, and that is the point of the function.** `\s` is `[[:space:]]`, whose membership past ASCII is decided by the collation rather than by Unicode: on PG 17.6 under the ICU provider it matches U+00A0 / U+2007 / U+202F / U+001C-U+001F and under `en_US.utf8` it matches none of them, so the four hand-written copies this replaced produced different keys on different deployments of the same migration set. The class is Unicode `White_Space` plus U+FEFF, identical to `EXERCISE_WS` in `gym_prs.ts` and `kExerciseWhitespace` in `gym_prs.dart`; `scripts/check_shared_constants.mjs` compares all three. All three persisted keys are stamped **in SQL**, by a BEFORE INSERT OR UPDATE trigger per table — `gym_sets_stamp_exercise_key_trigger` (`20270706000001`), `gym_routine_exercises_stamp_exercise_key_trigger` and `exercises_stamp_name_key_trigger` (both `20270711000001`, decisions § 1284). No client computes any of them, and a client that sends one has it overwritten rather than refused: the refusal was a client-VERSION coupling, since a build whose frozen fold table predates the server's derives a different key and got a 23514 on a legitimate save (decisions § 830, § 1252). All three columns are still held to the derivation by a validated CHECK (`gym_sets_exercise_key_canonical`, `gym_routine_exercises_exercise_key_canonical`, `exercises_name_key_canonical`), which nothing can now violate — they are what turns a lost trigger into a loud refusal. The clients remain the anchor for the whitespace CLASS itself, which is what `check_shared_constants.mjs` compares.

**The CASE fold names its collation for the same reason** (migration `20270630000003`, decisions § 830). `lower()` answers with the collation of its argument, so the derivation opened on the database's opinion until it was pinned to `collate "und-x-icu"`, the ICU root locale. Measured over all 1,112,063 assignable code points, the old expression disagreed with itself at 1 code point between the ICU and libc providers (U+0130), at 2 between ICU `en-US` and `tr-TR` — one of them ASCII `I`, so every "Incline Press" re-keyed on a Turkish database — at 3 under `lt-LT`, and at 1,406 under `C` / `C.utf8`; it also applied Unicode's contextual Final_Sigma rule under ICU and not under libc. Under the pin, zero. Two folds are additionally named by code point because the CLIENTS' own case tables are not each other's (JS and Dart `toLowerCase()` disagree at 466 code points): U+0130 folds to a bare `i` before the lowercase, and U+03C2 to U+03C3 after. Both are registered in `check_shared_constants.mjs` alongside the whitespace class. A named 1,488-pair mapping table — the fully runtime-independent fix — was measured at 60 µs per call against 0.34 µs for `lower()` and deferred behind persisting the key, because the RPCs re-derived it once per `gym_sets` row and a 15,000-set history would have paid ~0.9 s of pure folding per call. That prerequisite landed in `20270706000001`/`20270706000002` (decisions § 1076): the fold is now paid once per WRITE, so the table's cost is bounded by how often a lifter logs a set rather than by how much history they have. The table itself is still filed. pgTAP `normalise_exercise_name_test.sql` (21 tests).

### `gym_exercise_records()`

Returns one row per exercise — `(exercise_name, heaviest_weight_kg, heaviest_weight_reps, best_volume_kg, best_est_1rm_kg, last_performed_at, session_count)` — for the `/gym/records` surface (migration `20261224_001`, perf-hunt follow-up). All-time per-exercise bests can't be served by a windowed client read, so the aggregation lives in SQL (mirroring how run PRs are SQL-maintained); the client-side `exercise_records.ts` stopgap was retired. The SQL is the mirror of `gym_prs.ts#computeExercisePrs` + `exercise_records.ts` (normalised name key, Epley e1rm with the rep clamp, bodyweight-only excluded). SECURITY INVOKER (owner-scoped via `gym_workouts`/`gym_sets` RLS + explicit `auth.uid()`). The display spelling for a key is the caller's most-recent one — see `gym_exercise_names()` below for the rule, which `20270705000005` unified across the two and whose tiebreak it made collation-independent here. The `gym_prs.ts` badge engine stays client-side for the per-workout temporal badges. pgTAP `gym_exercise_records_test.sql` pins the metrics against the `gym_prs.test.ts` fixture shape, plus the display-spelling rule.

### `run_streaks_for_user(p_tz text, p_source text)`

Returns one row — `(current_streak, best_streak)` — for the `/dashboard` streak card's all-time sub-label (migration `20270501_001`, decisions §471). A gaps-and-islands aggregate over the caller's distinct run days on the `(user_id, started_at)` index: an all-time best streak can't be served by the ~2-year windowed dashboard fetch, so the aggregation lives in SQL (the `gym_exercise_records` pattern). Days bucket by the runner's **local** day — `p_tz` is the client's IANA zone (`Intl.DateTimeFormat().resolvedOptions().timeZone`), matching the display-side `computeRunStreaks` helper rather than the UTC shortcut inside `award_achievements_for_user`; an unrecognized zone raises (the client fails closed). Mirrors the helper's other semantics: same-day dedupe, future-day clamp against `now()` in `p_tz`, the Strava grace day for `current_streak`, and no DNF/source-family exclusion. `p_source` (nullable) scopes both figures to one source, matching the dashboard's source-filter chips. SECURITY INVOKER with a **load-bearing** explicit `auth.uid()` filter (runs RLS admits other users' public rows), granted to `authenticated` only. Web `fetchRunStreaks` (`core/data.ts`) returns null — never zeros — on failure so the card suppresses the all-time claim. pgTAP `run_streaks_for_user_test.sql` (12 tests incl. the pre-window island and the 23:30-local/UTC-date edge).

### `gym_exercise_set_history(p_name text)`

Returns one exercise's sets — `(workout_id, started_at, exercise_name, reps, weight_kg, rpe, duration_s, set_type)` — matched on the **normalised** name (trim → lowercase → collapse whitespace, the same key `gym_prs.ts#normaliseExerciseName` uses), for the `/gym/exercise` progression view (migration `20261225_001`, perf-hunt follow-up; `duration_s` added in `20261231_001` for timed work — planks/holds — instructor_business.md M2; `set_type` in `20270525_001`). Bounds the read to one exercise instead of pulling the whole history; the normalised match picks up sessions logged under a different capitalisation (an exact `=` would drop them). Since `20270706000002` the row side of that match is the persisted `gym_sets.exercise_key` and only `p_name` is folded, once per call. SECURITY INVOKER, owner-scoped. pgTAP `gym_exercise_set_history_test.sql` (6 tests).

### `gym_exercise_set_history_batch(p_names text[])`

The batched sibling (migration `20270323_001`): the same row shape plus a leading `normalised_name` grouping key, serving N exercises in ONE call — `/gym/[id]`'s PR badges + vs-last-time and `/gym/session/[routineId]`'s progression prefill previously invoked the singular RPC once per exercise (an N+1 of round-trips per rendered workout). A client-side `.in('exercise_name', …)` batch would be wrong — the match must be on the normalised key. Duplicate/blank/null input names are collapsed/ignored. SECURITY INVOKER, owner-scoped (`gw.user_id = auth.uid()`), granted to `authenticated`. Web `fetchExerciseSetHistoryBatch` (`core/data.ts`). pgTAP `gym_exercise_set_history_batch_test.sql` (8 tests).

Both RPCs return `set_type` since migration `20270525_001` (decisions §605). The progression prescriber excludes a warmup by reading exactly that column, and until then neither RPC surfaced it, so every ramp-up reached the web prescriber looking like a working set. Adding a column to a `returns table` changes the return type — `create or replace` refuses it (42P13) — so both were dropped and recreated with their bodies re-emitted verbatim and their `revoke … from public` / `grant execute … to authenticated` pair re-issued (a `drop function` takes the privileges with it).

### `gym_routine_history(p_routine_id uuid, p_recent_limit integer default 5)`

Returns exactly one row — `(session_count, last_performed_at, graded_count, completed_count, recent_sessions jsonb)` — for the routine-history panel on `/gym/routines/[id]` and `routine_detail_screen.dart` (migration `20270528_001`). A count is an aggregate, so no windowed client read can serve it honestly: both platforms previously read up to 500 `gym_workouts` rows carrying `metadata.routine_id` just to reduce them client-side, and an unbounded PostgREST select truncates silently at `db.max-rows` with a 200 — a lifter running one routine weekly for a decade saw a capped figure. The RPC returns the complete tallies plus an explicitly bounded page of the most recent sessions (`recent_sessions`, each `{id, started_at, title, metadata}`, newest first, `p_recent_limit` clamped to `[0, 50]`) in one snapshot, so the listed rows can never disagree with the count above them.

The two exclusions are the contract and mirror `gym/routine_history.ts` ↔ `routine_history.dart` (decisions §617): a row still carrying a `gym_session_draft` **object** is an in-flight session, not a session performed, and is dropped from both the tallies and the page (a resume must not inflate the routine's usage); a "save as is" row keeps `routine_id` and claims no adherence verdict, so it counts as a session but sits **outside** `graded_count` rather than counting as a miss. Days-since-last stays client-side — it is floored against the *reader's* clock and clamped so a row stamped ahead of it reads as today.

SECURITY INVOKER with a **load-bearing** explicit `auth.uid()` filter: the `gym_workouts` select policy also admits other users' `is_public` rows, so without it a caller could aggregate a stranger's sessions. Granted to `authenticated` only. Web `fetchGymRoutineHistory` (`core/data.ts`), mobile `ApiClient.fetchGymRoutineHistory`. pgTAP `gym_routine_history_test.sql` (12 tests, incl. a 1200-session routine past the PostgREST cap and the cross-user RLS case against a public row).

**It reads on `gym_workouts_user (user_id, started_at desc)`, and an index on `metadata->>'routine_id'` was measured and rejected** (verified by EXPLAIN, same method as the `runs_user_started_at` note above). Because this RPC is `security invoker`, the query runs under RLS, and the planner may not push a **non-leakproof** qual below an RLS security qual — `jsonb_object_field_text` is not `LEAKPROOF`, so `(metadata ->> 'routine_id') = $1` stays a heap `Filter` and only `user_id` reaches `Index Cond` no matter what the index is on. Over 60 000 synthetic rows (one account holding 2 008 sessions, 153 on the target routine) the existing index reads 1 278 heap blocks / 1 296 buffers in 1.7 ms; adding `(user_id, (metadata ->> 'routine_id'), started_at desc) where (metadata ->> 'routine_id') is not null` reads 1 277 heap blocks / 1 300 buffers in **2.5 ms** — strictly worse, since the heap work is unchanged and a 2.5 MB index is added to walk and to maintain on every gym-workout write. A GIN index queried with `@>` fares no better (`jsonb_contains` is likewise not leakproof; the planner ignored it entirely). The only shape the planner will use here is a **promoted plain column** (`routine_id uuid` + `(user_id, routine_id, started_at desc) where routine_id is not null` → 154 heap blocks / 158 buffers / 0.37 ms, `Index Cond` on both columns, because `uuid_eq` is leakproof) — i.e. the fix is a column promotion under the [column-vs-bag checklist](../architecture/conventions.md#activity-table-column-checklist--column-vs-jsonb-bag-f6--decision-d4), not an index. Not done yet: at 2 000 sessions the query is 1.7 ms on a page-open path, so it does not yet earn a `runs`-style promotion (`20261207_001`) plus its batched backfill. `fetchGymSessionDraft` (`core/data.ts`) filters the same bag key under the same constraint and would be promoted with it.

### `delete_notifications(p_ids uuid[])`

Deletes the caller's notifications by id and returns how many rows went (migration `20270529_001`). It exists so a bulk dismiss is **one transaction**. The clients used to hand the id list to a PostgREST `in` filter, which is serialised into the request URL — so a large dismiss depended on the request-line budget of whatever gateway sits in front of PostgREST. Measured against the local stack that DELETE is refused with a **414** past roughly 200 ids; decisions §653 records a gateway that answered 200 with an empty match instead. Either failure loses the whole dismiss, and which one you get is a property of the deployment, not of the code. Chunking the list dodged the bound and opened a partial dismiss — chunk 3 of 5 can fail and leave the inbox half-dismissed, with the undo offer already spent and the rows already gone from the list. An array argument travels in the RPC's POST body, which carries no such bound, so there is nothing left to chunk.

**SECURITY INVOKER with no owner predicate of its own** — deliberately unlike the two RPCs above. The `notifications` DELETE policy is already exactly `auth.uid() = user_id` (nothing else is visible to a caller, no public-row leg to close), so re-deriving that filter inside the body would be a second copy with nothing left to catch a drift between them. A caller naming a stranger's id deletes nothing and learns so from the returned count. Granted to `authenticated`; `public` **and `anon`** are revoked — Supabase's default privileges hand every new public function to `anon`, and a mutation has no business being reachable without a session even though RLS would match zero rows for one.

**Past 1000 ids the call raises `22023` rather than truncating.** An unbounded array is row locks held for the length of one statement, but a silent cap would re-open, in a new place, exactly the bug the RPC closes — so the refusal is explicit and deletes no prefix. Both inboxes page at 100 rows, so the ceiling sits far above any dismiss a surface can assemble. A null or empty array is a no-op returning 0, not an error.

Web `deleteNotifications` (`core/data.ts`), mobile `ApiClient.deleteNotifications` — neither chunks. pgTAP `delete_notifications_rpc_test.sql` (14 tests, incl. the 150-id dismiss, the cross-user RLS case, and an all-or-nothing check under a row trigger that fails mid-batch).

### `gym_exercise_names()`

Returns `(exercise_name, uses)` — one row per exercise + use count, most-used first — for the gym editor's autocomplete datalist (migration `20261226_001`, perf-hunt follow-up). Bounded to the count of distinct exercises (dozens) so the History page never pulls raw set history just to derive names. SECURITY INVOKER, owner-scoped. pgTAP `gym_exercise_names_test.sql` (7 tests).

**One row per exercise, not per spelling of it** (migration `20270630000004`, decisions § 831). Grouping was a bare `btrim`, which strips U+0020 and nothing else, so a name pasted with a leading tab was its own suggestion beside the clean spelling of the same lift, and a case variant was a third. It groups on `normalise_exercise_name` now, and `uses` counts the whole group. Display stays case- and spelling-preserving — this feeds a datalist, not a key. **The spelling shown is the caller's most-RECENT one, the same rule the sibling `gym_exercise_records` applies to the same question** (migration `20270705000005`, decisions § 1050). It used to be the most-USED one, which is self-reinforcing on an autocomplete: it offers the old capitalisation, the lifter accepts it, and the counts never cross, so a re-capitalisation can never take effect. Ties — two of a key's spellings logged at the same instant — break on `length(display)` first, so a paste carrying a leading tab loses to its clean sibling, then on the spelling under `collate "und-x-icu"`; a bare comparison is resolved by the argument's own collation, the dependence § 830 closed for the key itself. Both RPCs' final `order by` on the returned list is pinned to the same collation. `uses` still counts the whole group and the list is still ordered most-used first.

### `gym_workout_summaries(p_limit integer default 100)`

Returns `(workout_id, exercise_count, is_pr)` — one row per workout the `/gym` list shows (migration `20270510_001`, decisions §568). Closes the residual §138 left open: the list's per-workout PR badge is an all-time question ("did this workout beat everything logged before it?"), so the client read the user's whole `gym_sets` history unwindowed — and PostgREST caps an unbounded SELECT at **1000 rows**, so past ~40 sessions of 25 sets the badges were computed from a truncated, unordered slice. `p_limit` bounds the rows returned; the PR judgement always runs over the caller's **entire** history, which also fixes a second bug — the client walked only the 100 workouts it had fetched, so a lift set 101 workouts ago failed to suppress a badge and `/gym` disagreed with `/gym/[id]`.

`is_pr` mirrors `gym_prs.ts#RunningPrTracker`: walking oldest → newest (ties broken by id), a workout is flagged when any one exercise's best single-set weight, best single-set volume, or best Epley e1rm strictly beats every earlier workout's — an exercise with no earlier set counting as a PR. Volume and e1rm round to 1 dp on both sides of the comparison, as `round1()` does. `exercise_count` is the distinct **normalised** names (a whitespace-only name passes the `length(1..120)` CHECK; it counts toward the workout's stored `set_count` / `volume_kg` but is not an exercise). Recompute-on-read, so it can't drift from `gym_sets` — off the persisted `exercise_key` since `20270706000002`, which is the same key by construction. SECURITY INVOKER, owner-scoped, granted to `authenticated`. Web `fetchGymWorkoutSummariesWithError` (`core/data.ts`). pgTAP `gym_workout_summaries_test.sql` (14 tests) and web `gym_workout_summaries.test.ts` build the **same fixture** and assert the same four PR workouts, one through the RPC and one through the real `RunningPrTracker`, so the SQL and TS definitions can't drift apart.

The list's other two row stats need no RPC: `gym_workouts.set_count` / `volume_kg` are trigger-maintained columns ([derived_state.md](derived_state.md)) the page was re-deriving from raw sets.

### `gym_has_weighted_sets()`

Returns a boolean: has the caller ever logged a set with a positive `weight_kg`? Gates the Records link on `/gym`, since `/gym/records` only surfaces weighted exercises (migration `20270510_001`). All-time and `exists`-early-exit, so it stays honest for a lifter whose last weighted session is further back than the list page reaches — the case a per-page flag would get wrong. SECURITY INVOKER, owner-scoped. Web `fetchGymHasWeightedSets`. Covered by `gym_workout_summaries_test.sql`.

---

## Challenges & competitions

Migrations `20270209_001_challenges.sql` (schema + RLS) + `20270210_001_challenge_progress_rpc.sql` (RPCs + completion). See [challenges.md](../features/challenges.md).

### Tables

- **`challenges`** — `id, creator_id, club_id (null = open), title, description, metric, scope, goal_value (null = pure-ranking board), activity_type (null = any), starts_at, ends_at, is_public, created_at, participant_count`. `metric ∈ {distance, duration, vert, activity_count, streak_days}` and `scope ∈ {individual, club_vs_club, group_goal}` are CHECK-constrained and paired with the `ChallengeMetric` / `ChallengeScope` TS unions (in `check_constraint_unions.mjs`). `club_vs_club` forces `club_id = null` (it aggregates across many clubs). `challenges_goal_ck` (`20270615_001`) requires a non-null `goal_value` to be **positive** and, for `streak_days` only, no larger than `floor(extract(epoch from (ends_at - starts_at)) / 86400) + 1` — the count of UTC dates the window can touch, which is what `count(distinct (started_at at time zone 'UTC')::date)` is bounded by. A stored `0` is not an inert "no goal": `recompute_challenge_completion` returns early only on NULL and then compares `value >= goal`, so it completes for every participant. `duration` is deliberately NOT bounded — the aggregate sums `duration_s` over runs whose START is inside the window, so a run begun just before it closes carries its whole duration. Mirrored client-side by `checkChallengeGoal` / `maxStreakDaysInWindow` (`social/challenge_goal.ts` ↔ `challenge_goal.dart`) so the refusal is named inline instead of arriving as a 23514 ([decisions § 758](../architecture/decisions.md)). `participant_count` is a trigger-maintained cache (`sync_challenge_participant_count()`, `20270308_001`; see [derived_state.md](derived_state.md)). A `before insert` trigger rate-limits authenticated creation to 30/hour (`enforce_challenge_create_rate_limit`, fail-open, skips auth-less inserts).
- **`challenge_participants`** — `(challenge_id, user_id)` PK + `team_club_id` (the club a member's total pools into, club_vs_club only), `joined_at`, `completed_at` (column-locked — written only by the completion RPC, mirroring the `event_attendees.attendance` lockdown; clients hold only the `team_club_id` column-UPDATE grant). **INSERT is column-scoped to `(challenge_id, user_id, team_club_id)` since `20270616_001`** — exactly what both clients post. It was table-wide, and joining and leaving are both own-row verbs, so `delete` + re-`insert` with `completed_at` already set forged a completion and backdated `joined_at` in two statements; leaving and rejoining now resets both. Same [§ 584](../architecture/decisions.md) shape `20270520_001` closed on `event_attendees`, pinned schema-wide by `column_grant_write_lockdown_registry_test.sql` ([decisions § 763](../architecture/decisions.md)).
- **`challenge_badges`** — durable completion record, `unique(user_id, challenge_id)`. INSERT closed to clients; written only by the SECURITY DEFINER completion path.

### RLS

- `challenges` SELECT: public OR creator OR participant OR active member of `club_id`. INSERT: `auth.uid() = creator_id` AND (open OR `is_club_admin(club_id)`). UPDATE/DELETE: creator OR club admin. The `is_challenge_visible(uuid)` SECURITY DEFINER helper encapsulates the SELECT predicate for the child tables.
- `challenge_participants` SELECT inherits `is_challenge_visible`; INSERT is self-only + visible + (team join requires active membership of `team_club_id`); DELETE self-only.
- `challenge_badges` SELECT: owner OR the badge's challenge is public.

### RPCs

- **`challenge_leaderboard(p_challenge_id uuid, p_by_team boolean default false)`** → `(user_id, display_name, team_club_id, value, rank)`. **SECURITY DEFINER**, gated on `is_challenge_visible`. ONE query joining participants to a per-user (or per-team) aggregate over each runner's `runs` within `[starts_at, ends_at)`, filtered by `activity_type` when set. DEFINER (not invoker) because the public-runs SELECT policy on `runs` was retired — an invoker aggregate would zero every competitor; the board exposes only the per-user SUM, never the run rows. `rank() over (order by value desc)`. N participants → 1 round trip. DNF runs are excluded from the aggregate (`is_dnf = false`, migration `20270407_001`, decisions §231), matching the PR + achievements engines. A **shadow-hidden participant keeps their row, value and rank but their `display_name` is withheld** from everyone but themselves (migration `20270524_001`, decisions §596) — DEFINER bypasses the "authenticated read profiles except shadow-hidden" policy, and dropping the row instead would restate every other participant's rank. The client already renders a null name through a fallback label.
- **`my_active_challenges()`** → challenge fields + `my_value, my_rank, participant_count, completed_at`. SECURITY INVOKER. The self-hide driver: only challenges the caller has joined that are live or ended within 7 days. An empty result = render nothing.
- **`recompute_challenge_completion(p_challenge_id, p_user_id)`** — SECURITY DEFINER. Recomputes the user's value; when `goal_value` is met and no badge exists, inserts `challenge_badges` + stamps `completed_at` + inserts a `challenge_complete` notification. Idempotent (the unique badge row guards). Called opportunistically client-side after a run saves + by the daily `sweep_challenge_completions()` pg_cron job (`sweep-challenge-completions`).
- **`browse_public_challenges(p_search text, p_limit int, p_offset int)`** → challenge fields + `participant_count`. **SECURITY DEFINER** (`20270308_001`, ADR §190). The ranked, paginated, searchable Browse discovery feed: public, unjoined, still-open challenges ordered by popularity `participant_count + joins_7d*2` (size + 7-day join velocity), dead-board suppression past a 7-day grace window, limit capped at 100. DEFINER because the velocity term counts all recent joins an invoker's RLS would undercount; returns only public challenges + aggregate counts. `p_search` ILIKEs `title` OR `description`, both served by pg_trgm GIN indexes (`challenges_title_trgm` / `challenges_description_trgm`, `20270316_001`).

pgTAP: `challenges_rls_test.sql`, `challenge_leaderboard_test.sql`, `challenge_completion_test.sql`, `challenge_participants_completed_lockdown_test.sql`, `challenge_browse_test.sql`.

---

## Supabase Storage

Three buckets in the live schema:

| Bucket | Access | Purpose |
|---|---|---|
| `runs` | Private (RLS, owner-scoped) | **Two content classes** under different path prefixes — see below. The bare-table public-read RLS that used to gate this on `runs.is_public` was dropped in `20260619_001_drop_public_runs_storage_policy.sql`; non-owner reads now go through the `clip-public-track` Edge Function. Owner SELECT on the `exports/` subprefix was removed in `20260816_001_runs_bucket_exports_signed_url_only.sql` — exports are reachable through the EF-issued 10-min signed URL only, never via direct REST GET. |
| `run-photos` | Private (RLS, parent-run-visibility join) | Photos attached to runs at `{owner_id}/{photo_id}.{ext}`. Per-user-folder INSERT/DELETE; storage SELECT joins through `run_photos` → `is_run_visible_to`. Bucket is private (migration `20260712_001`); clients use signed URLs with 1 h TTL. See `decisions.md § 36`. |
| `route-photos` | Private (RLS, parent-route-visibility join) | Photos attached to routes at `{owner_id}/{photo_id}.{ext}` (backlog C1, migration `20270114_001`). Per-user-folder INSERT/DELETE; storage SELECT joins through `route_photos` → `private.is_route_visible_to`. Private from creation; clients use signed URLs with 15-min TTL. `file_size_limit` 10 MB + image-only `allowed_mime_types`, matching `run-photos`. |
| `exports` | Private, **no policies at all** — signed-URL-only | Art 20 export artifacts at `{user_id}/exports/<ts>.{csv,zip}` (migration `20270602_001`). Its own bucket because `file_size_limit` is per bucket and `runs` caps an object at 25 MB — a tighter ceiling on a full-history archive than any of the caps [decisions § 703](../architecture/decisions.md) + [§ 708](../architecture/decisions.md) removed, and one storage-api enforces for `service_role` too. 5 GiB limit, `text/csv` + `application/zip` only. Zero `storage.objects` policies is deliberate: `20260816_001` made exports reachable through the function's 10-min signed URL and nothing else, and `service_role` (the only reader and writer) is RLS-exempt. **Operator step:** the project-level upload limit (Dashboard → Storage → Settings, 50 MB default) is the lower of the two ceilings until raised. Reaped at 7 days by the nightly `enqueue-export-blob-reap` job, whose Go handler erases through the Storage API (a `storage.objects` row delete would not, [§ 1049](../architecture/decisions.md)); drained by `delete-account`. |
| `avatars` | **Public** (CDN read) + owner-scoped writes | Profile pictures at `{user_id}/avatar.{ext}` (bucket created `20260927_001`; in-app upload added later). `public = true` because an avatar renders on the logged-out `/u/[id]` profile + share pages as a bare `<img src={avatar_url}>`, so `user_profiles.avatar_url` holds a plain public URL (the only thing that satisfies the `^https?://` CHECK for anon viewers). Owner-scoped INSERT/UPDATE/DELETE **and** an owner-scoped SELECT (`20270203_001` — the public CDN serves downloads, but authenticated `.list()`/`.remove()` query `storage.objects` under RLS, so an owner needs SELECT to manage their own object); all four policies are scoped `to authenticated` (`20270321_001` — they shipped `to public`, fail-closed only because every predicate needs `auth.uid()`; the role scope is pinned by `storage_bucket_privacy_test.sql`). 2 MB cap, `image/jpeg`/`png`/`webp` only (no SVG → no stored-XSS). Web `uploadAvatar`/`removeAvatar` (`data.ts`) + mobile `ApiClient.uploadAvatar`/`removeAvatar` (byte-identical twin) strip EXIF/GPS client-side before upload (no server-side strip worker on this bucket) and remove-then-insert at the stable path (the bucket grants INSERT/DELETE but not the upsert WITH-CHECK). |

The `routes` bucket shown in older revisions of this doc was never created — `routes.waypoints` is stored inline (jsonb on the `routes` table). The `exports` bucket **does** exist as of migration `20270602_001`; artifacts written before it live under the `runs` bucket's `exports/` prefix and are drained + swept from both places.

**Every bucket that accepts images accepts exactly `image/jpeg` + `image/png` + `image/webp`.** [decisions § 557](../architecture/decisions.md) made the accepted set BE the set the clients can strip, because `stripImageExif` returns an unrecognised format unchanged and the bucket then serves the geotagged original back through a signed URL; `20270622000002` landed it on the three buckets that still advertised HEIC/HEIF. Two guards hold it and they make different claims, so both are kept ([§ 858](../architecture/decisions.md)): `scripts/check_shared_constants.mjs` compares the migration text against `STRIPPABLE_IMAGE_MIME_TYPES` and `kStrippableImageMimeTypes` in source, which no SQL assertion can do, and `export_surface_contract_test.sql` reads the applied `storage.buckets` rows — over a derived population, so a new image bucket is held to the rule the day it appears.

### Path layout under the `runs` bucket

```
{user_id}/{run_id}.json.gz         # gzipped GPS track for run {run_id}
{user_id}/exports/{timestamp}.zip  # LEGACY data-export bundles (both rails
{user_id}/exports/{timestamp}.csv  # now write to the `exports` bucket)
```

Export artifacts moved to the `exports` bucket — the Edge Function in migration `20270602_001` ([decisions § 703](../architecture/decisions.md)), the Go worker in [§ 708](../architecture/decisions.md). What is left under this prefix is what was written before those, and it is still drained by `delete-account`, still reaped at 7 days — `enqueue_export_blob_reap()` emits one prefix-scoped job per user who still holds an archive here, so the set empties itself ([§ 1172](../architecture/decisions.md)) — and still skipped by the export's own Storage orphan walk so an export never archives a previous export.

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
