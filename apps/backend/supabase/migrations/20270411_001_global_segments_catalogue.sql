-- Global / famous-segment catalogue (persona runner-strava-migration,
-- Medium — "segments have no global/famous-segment layer").
--
-- v1 segments (migration 20260526_001) are slices of a *saved route*:
-- a `segments` row references `routes(id)`, so a segment can only exist
-- once someone recreated the stretch of road as an in-app route first.
-- That's a chicken-and-egg gap for a brand-new market with zero routes,
-- and it means a migrating Strava user's runs match nothing.
--
-- This migration adds a FREE-STANDING catalogue: a `global_segments`
-- table carrying its OWN polyline geometry (no route dependency), plus a
-- parallel `global_segment_efforts` table. The catalogue is
-- world-readable; only admins/curators (the `app_admins` allow-list from
-- 20270105_001) may insert/curate. Efforts follow the same run-privacy
-- rules segment_efforts already carry (visibility via
-- `private.is_run_visible_to`, block-guarded leaderboard via
-- `is_blocked_either_way`).
--
-- STILL DEFERRED (decisions ADR): arbitrary-geometry HMM / Hausdorff
-- matching that would let a run auto-match ANY sub-stretch of a longer
-- track against every nearby segment. v1 matches a run END-TO-END against
-- a CURATED catalogue geometry only — the run must pass near the
-- segment's start, then its end, having covered roughly the segment's
-- length between them (see `computeGlobalSegmentEffort` in the
-- `segments` TS↔Dart parity pair). That reuses the proven
-- timestamp-interpolation + sparsity guard from `computeEffortFromTrack`
-- rather than inventing a new alignment pipeline.

-- ─────────────────────── global_segments table ───────────────────────

create table global_segments (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (length(name) between 1 and 120),
  description   text check (description is null or length(description) <= 2000),
  -- Own polyline geometry: [{lat, lng, ele?}], same shape as
  -- routes.waypoints. Free-standing — NOT a slice of any route.
  waypoints     jsonb not null,
  distance_m    numeric not null check (distance_m >= 100),  -- ≥ 100 m, mirrors segments §37
  elevation_m   numeric,
  surface       text not null default 'road',
  -- Human-readable locale label ("Central Park, New York") + ISO-3166
  -- alpha-2 for coarse filtering / grouping on the browse page.
  region        text,
  country_code  text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  -- Curator who added the row (null for a service_role/seed insert).
  created_by    uuid references auth.users(id) on delete set null,
  -- Soft-delete / hide flag so a bad catalogue entry can be pulled
  -- without cascading away the efforts athletes earned on it.
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

create index global_segments_active on global_segments (is_active, created_at desc)
  where is_active = true;
create index global_segments_country on global_segments (country_code)
  where country_code is not null;

alter table global_segments enable row level security;

-- World-readable: any caller (anon or authenticated) sees ACTIVE
-- catalogue segments. Inactive (pulled) rows are hidden from everyone
-- but service_role / a direct admin RPC.
create policy "active catalogue segments are world-readable"
  on global_segments for select
  using (is_active = true);

-- Only admins/curators may add, edit, or pull catalogue segments. The
-- allow-list oracle `private.is_admin` (20270105_001) is the same gate
-- the /admin/reports queue uses. service_role bypasses RLS, so seed.sql
-- and Studio curation still work without an admin JWT.
create policy "admins insert catalogue segments"
  on global_segments for insert
  with check (private.is_admin(auth.uid()));

create policy "admins edit catalogue segments"
  on global_segments for update
  using (private.is_admin(auth.uid()))
  with check (private.is_admin(auth.uid()));

create policy "admins delete catalogue segments"
  on global_segments for delete
  using (private.is_admin(auth.uid()));

-- ─────────────────── global_segment_efforts table ───────────────────

create table global_segment_efforts (
  id                 uuid primary key default gen_random_uuid(),
  global_segment_id  uuid references global_segments(id) on delete cascade not null,
  run_id             uuid references runs(id) on delete cascade not null,
  user_id            uuid references auth.users(id) on delete cascade not null,
  time_seconds       numeric not null check (time_seconds > 0),
  started_at         timestamptz not null,
  created_at         timestamptz not null default now(),
  unique (global_segment_id, run_id)
);

create index global_segment_efforts_segment
  on global_segment_efforts (global_segment_id, time_seconds asc);
create index global_segment_efforts_user
  on global_segment_efforts (user_id, started_at desc);
create index global_segment_efforts_run
  on global_segment_efforts (run_id);

alter table global_segment_efforts enable row level security;

-- Effort visibility = catalogue segment is active AND the run is visible
-- to the caller. `private.is_run_visible_to` is the same owner-or-public
-- oracle segment_efforts uses (20260812_001), so a private runner's
-- effort never leaks onto a catalogue leaderboard through the base table.
-- (The block graph is applied additionally in the leaderboard RPC below.)
create policy "efforts readable when segment active and run visible"
  on global_segment_efforts for select
  using (
    exists (
      select 1 from global_segments gs
      where gs.id = global_segment_efforts.global_segment_id
        and gs.is_active = true
    )
    and private.is_run_visible_to(run_id, auth.uid())
  );

-- A user inserts efforts on their own behalf for runs they own — the
-- run owner's client computes them after import/record. No third party
-- writes efforts on someone else's run.
create policy "run owner inserts catalogue efforts on their runs"
  on global_segment_efforts for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from runs
      where runs.id = global_segment_efforts.run_id
        and runs.user_id = auth.uid()
    )
    and exists (
      select 1 from global_segments gs
      where gs.id = global_segment_efforts.global_segment_id
        and gs.is_active = true
    )
  );

-- Effort owner can rescind (wrong match, manual recompute).
create policy "catalogue effort owner deletes"
  on global_segment_efforts for delete
  using (auth.uid() = user_id);

-- ─────────────────── block-guarded leaderboard RPC ───────────────────

-- Per-catalogue-segment leaderboard, mirroring `segment_leaderboard_tiered`
-- (20261115_001) minus the route join (the catalogue is public, so there
-- is no per-route visibility branch). SECURITY DEFINER so it can apply the
-- block graph + run-visibility gate uniformly; the caller must be
-- authenticated (blocks need a concrete caller identity). Demographic
-- columns (gender / age) are disclosed only for the caller's OWN row —
-- no DOB or gender of other athletes ever leaves the function.
create or replace function global_segment_leaderboard(
  p_segment_id uuid,
  p_gender text default null,
  p_age_band text default null,
  p_limit integer default 50,
  p_club_id uuid default null
)
returns table (
  effort_id uuid,
  user_id uuid,
  run_id uuid,
  time_seconds integer,
  started_at timestamptz,
  display_name text,
  avatar_url text,
  gender text,
  age integer
)
language plpgsql
stable
security definer
-- public, private so the membership oracle `is_club_member` (moved to
-- `private` in 20261120_001) and `is_run_visible_to` resolve unqualified;
-- `is_blocked_either_way` lives in public. Mirrors the live
-- segment_leaderboard_tiered search_path.
set search_path = public, private
as $$
declare
  age_min integer := null;
  age_max integer := null;
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'global_segment_leaderboard requires an authenticated caller'
      using errcode = '42501';
  end if;

  if p_age_band is not null then
    if p_age_band = '75+' then
      age_min := 75;
      age_max := 200;
    elsif p_age_band ~ '^[0-9]+-[0-9]+$' then
      age_min := split_part(p_age_band, '-', 1)::integer;
      age_max := split_part(p_age_band, '-', 2)::integer;
    else
      raise exception 'global_segment_leaderboard: invalid p_age_band %', p_age_band
        using errcode = '22023';
    end if;
  end if;

  -- A club filter only applies when the caller is a member of that club;
  -- otherwise it collapses to empty rather than leaking membership.
  if p_club_id is not null and not is_club_member(p_club_id) then
    return;
  end if;

  return query
  select
    se.id                                                      as effort_id,
    se.user_id                                                 as user_id,
    se.run_id                                                  as run_id,
    se.time_seconds::integer                                   as time_seconds,
    se.started_at,
    up.display_name,
    up.avatar_url,
    case when se.user_id = caller then up.gender else null end as gender,
    case
      when se.user_id = caller and up.date_of_birth is not null
        then extract(year from age(up.date_of_birth))::integer
      else null
    end                                                        as age
  from public.global_segment_efforts se
  join public.global_segments      gs on gs.id = se.global_segment_id
  join public.user_profiles        up on up.id = se.user_id
  where se.global_segment_id = p_segment_id
    and gs.is_active = true
    and private.is_run_visible_to(se.run_id, caller)
    -- Block-aware: hide efforts by users the caller has blocked (or who
    -- have blocked the caller). Own effort survives (block of self is false).
    and not is_blocked_either_way(caller, se.user_id)
    and (p_gender is null or up.gender = p_gender)
    and (
      p_age_band is null
      or (
        up.date_of_birth is not null
        and extract(year from age(up.date_of_birth))::integer between age_min and age_max
      )
    )
    and (
      p_club_id is null
      or exists (
        select 1 from public.club_members cm
        where cm.club_id = p_club_id
          and cm.user_id = se.user_id
          and cm.status = 'active'
      )
    )
  order by se.time_seconds asc, se.started_at asc
  limit p_limit;
end;
$$;

-- Grant to anon too (like segment_leaderboard_tiered): anon must hold
-- EXECUTE so the call enters the body and hits the in-body 42501 raise —
-- a role without EXECUTE crashes this Postgres build rather than erroring
-- cleanly (the same SEGV pattern documented on rls_segments).
revoke execute on function global_segment_leaderboard(uuid, text, text, integer, uuid) from public;
grant  execute on function global_segment_leaderboard(uuid, text, text, integer, uuid) to anon, authenticated;

-- ─────────────────── run-detail effort ranks RPC ───────────────────

-- Rank every catalogue-segment effort a run earned in ONE round-trip
-- (rank = 1 + strictly-faster visible efforts on the same segment), the
-- global-catalogue twin of `segment_effort_ranks` (20261223_001).
-- SECURITY INVOKER so the base-table RLS filters the comparison set
-- exactly as a client count would.
create or replace function global_segment_effort_ranks(p_run_id uuid)
returns table (
  effort_id uuid,
  rank integer
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    e.id as effort_id,
    (
      1 + (
        select count(*)
        from public.global_segment_efforts f
        where f.global_segment_id = e.global_segment_id
          and f.time_seconds < e.time_seconds
      )
    )::integer as rank
  from public.global_segment_efforts e
  where e.run_id = p_run_id;
$$;

revoke execute on function global_segment_effort_ranks(uuid) from public;
grant  execute on function global_segment_effort_ranks(uuid) to authenticated;
