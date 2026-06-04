-- F3 (audit-db-optimization, decision D4): promote the two load-bearing
-- runs.metadata keys — activity_type and is_dnf — to real columns.
--
-- Both are attributes pretending to be metadata:
--   * activity_type is required by a CHECK, read by the `activities` view +
--     `public_runs`, drives gear auto-tagging and VDOT qualification.
--   * is_dnf is a boolean predicate the personal-records engine filters on
--     (a DNF must not be promoted as a distance PR).
-- The audit's "should be a column" bar is: present on most rows, and
-- filtered / aggregated / constrained in SQL. These two clear it; the
-- telemetry trio (avg_bpm / steps / elevation_m) is displayed but never
-- filtered, so it stays in the bag (decision D4).
--
-- Both columns carry a default (activity_type 'run', is_dnf false) so the
-- generated Insert types mark them optional. That keeps the web + mobile
-- writers — which still write metadata.activity_type until the Round-4
-- Tier-2 switch — inserting cleanly (they get the default) rather than
-- hard-failing a NOT NULL. It relaxes the "every writer is explicit"
-- invariant the metadata CHECK (20260601_001) enforced; Round 4 restores
-- explicitness by wiring the client writers to set the column directly.
-- Until then, a non-run activity saved via an un-migrated client lands as
-- 'run' on the column (its real value still rides in the now-stripped bag
-- on that one client's write). Pre-prod, gym/nutrition unreleased — the
-- known, documented interim state of a phased Tier-2 rollout.

-- ─────────────────── 1. Columns + backfill ───────────────────

alter table public.runs
  add column activity_type text not null default 'run';

alter table public.runs
  add column is_dnf boolean not null default false;

-- Backfill from the jsonb bag before constraining / stripping.
update public.runs
set activity_type = metadata ->> 'activity_type'
where metadata ? 'activity_type'
  and length(coalesce(metadata ->> 'activity_type', '')) > 0;

update public.runs
set is_dnf = true
where coalesce(metadata ->> 'is_dnf', '') = 'true';

-- Value domain mirrors docs/backend/metadata.md (the finer-grained
-- running-family classification). Replaces the jsonb-level
-- runs_metadata_activity_type_check.
alter table public.runs
  add constraint runs_activity_type_check
    check (activity_type in ('run', 'walk', 'hike', 'cycle', 'stroller'));

-- Shrink the bag: the keys are columns now, so drop them from jsonb to
-- avoid double-storage and a stale second copy.
update public.runs
set metadata = metadata - 'activity_type' - 'is_dnf'
where metadata is not null;

alter table public.runs
  drop constraint runs_metadata_activity_type_check;

-- ─────────────────── 2. activities view ───────────────────
-- summary now reads the real column instead of metadata->>'activity_type'.

create or replace view public.activities
with (security_invoker = true) as
select
  r.id,
  r.user_id,
  'run'::text as kind,
  r.started_at,
  jsonb_build_object(
    'distance_m', r.distance_m,
    'duration_s', r.duration_s,
    'activity_type', r.activity_type
  ) as summary
from public.runs r
union all
select
  w.id,
  w.user_id,
  'lift'::text as kind,
  w.started_at,
  jsonb_build_object(
    'title', w.title,
    'set_count', (select count(*) from public.gym_sets s where s.workout_id = w.id),
    'volume_kg', (
      select coalesce(sum(coalesce(s.reps, 0) * coalesce(s.weight_kg, 0)), 0)
      from public.gym_sets s where s.workout_id = w.id
    )
  ) as summary
from public.gym_workouts w
union all
select
  f.id,
  f.user_id,
  'meal'::text as kind,
  f.logged_at as started_at,
  jsonb_build_object(
    'item_name', f.item_name,
    'calories', f.calories,
    'meal_slot', f.meal_slot
  ) as summary
from public.food_log f;

grant select on public.activities to authenticated;

-- ─────────────────── 3. public_runs view ───────────────────
-- activity_type + is_dnf were public-safe metadata keys (never on the
-- strip-list). Now that they are columns, expose them as columns. The
-- metadata projection no longer carries them (stripped above), so the
-- denylist is unchanged — there is simply less in the bag to reason about.
-- DROP + CREATE because the column list changes (CREATE OR REPLACE would
-- hit 42P16).

drop view if exists public_runs;

create view public_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.source,
  r.activity_type,
  r.is_dnf,
  r.is_public,
  r.created_at,
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
  -- Boolean existence signal only — never the Storage path itself.
  (r.track_url is not null) as has_track,
  coalesce(r.metadata, '{}'::jsonb)
    - 'strava_id'
    - 'garmin_id'
    - 'imported_from'
    - 'imported_at'
    - 'health_connect_type'
    - 'strava_activity_type'
    - 'source_file'
    - 'max_bpm'
    - 'plan_workout_id'
    - 'workout_step_results'
    - 'workout_adherence'
    - 'last_modified_at'
    - 'recovered_from_crash'
    - 'in_progress_saved_at'
    - 'in_progress'
    - 'manual_entry'
    - 'indoor_estimated'
    - 'distance_source'
    - 'race_name'
    - 'bib'
    - 'overall_place'
    - 'chip_time'
    - 'perceived_effort'
    - 'run_number'
    as metadata
from runs r
where r.is_public = true;

grant select on public_runs to anon, authenticated;

-- ─────────────────── 4. gear auto-tag trigger ───────────────────
-- Re-emit auto_tag_default_gear (20260901_001) reading the activity_type
-- column instead of new.metadata->>'activity_type'. Body otherwise
-- identical (SECURITY DEFINER, default-to-shoe, on-conflict-do-nothing).

create or replace function auto_tag_default_gear()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  activity_kind text;
begin
  -- Default to 'shoe' when the activity maps to no bike — most runs are
  -- runs, and a bike default tag-stamping a foot-powered run is more
  -- surprising than the reverse.
  activity_kind := case new.activity_type
    when 'cycle' then 'bike'
    else 'shoe'
  end;

  insert into run_gear (run_id, gear_id)
  select new.id, g.id
  from gear g
  where g.owner_id = new.user_id
    and g.kind = activity_kind
    and g.is_default = true
    and g.retired_at is null
  on conflict (run_id, gear_id) do nothing;

  return new;
end;
$$;

-- Keep the audit lockdown from 20260915_001: this is a trigger-only
-- SECURITY DEFINER function, never invoked directly by a caller. Re-emit
-- the revokes (CREATE OR REPLACE preserves grants, but be explicit) so
-- rls_audit_function_grant_lockdowns_test stays green.
revoke execute on function auto_tag_default_gear() from public;
revoke execute on function auto_tag_default_gear() from anon;
revoke execute on function auto_tag_default_gear() from authenticated;

-- ─────────────────── 5. personal-records refresher ───────────────────
-- Re-emit refresh_personal_records_for_user from the LATEST body
-- (20261021_001: auth guard + advisory lock + widened brackets + mile
-- bracket + embedded bests + DNF exclusion) with the five DNF filters
-- switched from coalesce(metadata->>'is_dnf','false') <> 'true' to the
-- is_dnf column (= false). Per the backend "bare-body strips prior fixes"
-- gotcha — patched on top of the live body, NOT rewritten from scratch.

create or replace function refresh_personal_records_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  if v_role <> 'service_role' and v_role <> '' then
    if auth.uid() is null or auth.uid() is distinct from p_user_id then
      raise exception 'refresh_personal_records_for_user: not authorized'
        using errcode = '42501';
    end if;
  end if;

  perform pg_advisory_xact_lock(
    hashtext('personal_records:' || p_user_id::text)
  );

  delete from personal_records where user_id = p_user_id;

  insert into personal_records (user_id, distance, best_time_s, run_id, achieved_at)
  select
    p_user_id, distance, duration_s, run_id, achieved_at
  from (
    select
      run_id, duration_s, achieved_at, distance,
      row_number() over (partition by distance order by duration_s asc) as rn
    from (
      -- Whole-run candidates, widened brackets, DNFs excluded.
      select
        id as run_id,
        duration_s,
        started_at as achieved_at,
        case
          when distance_m between 1559  and 1659   then '1_mile'
          when distance_m between 4900  and 5100   then '5k'
          when distance_m between 9800  and 10200  then '10k'
          when distance_m between 20675 and 21519  then 'half_marathon'
          when distance_m between 41351 and 43039  then 'marathon'
        end as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and distance_m is not null
        and duration_s is not null
        and is_dnf = false

      union all

      -- Embedded-best 5k from metadata.fastest_5k_s.
      select
        id as run_id, (metadata->>'fastest_5k_s')::int,
        started_at as achieved_at, '5k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_5k_s'
        and (metadata->>'fastest_5k_s') ~ '^[0-9]+$'
        and is_dnf = false

      union all

      select
        id as run_id, (metadata->>'fastest_10k_s')::int,
        started_at as achieved_at, '10k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_10k_s'
        and (metadata->>'fastest_10k_s') ~ '^[0-9]+$'
        and is_dnf = false

      union all

      select
        id as run_id, (metadata->>'fastest_half_marathon_s')::int,
        started_at as achieved_at, 'half_marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_half_marathon_s'
        and (metadata->>'fastest_half_marathon_s') ~ '^[0-9]+$'
        and is_dnf = false

      union all

      select
        id as run_id, (metadata->>'fastest_marathon_s')::int,
        started_at as achieved_at, 'marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_marathon_s'
        and (metadata->>'fastest_marathon_s') ~ '^[0-9]+$'
        and is_dnf = false
    ) candidates
    where distance is not null
  ) ranked
  where rn = 1;
end;
$$;
