-- db-design High: promote the four embedded-best PR-time keys out of the
-- runs.metadata jsonb bag — fastest_5k_s / fastest_10k_s /
-- fastest_half_marathon_s / fastest_marathon_s — to real integer columns.
--
-- Same "should be a column" bar as the activity_type / is_dnf promotion
-- (20261207_001): these keys are filtered + cast + regex-validated in SQL
-- on every personal-records refresh (7-branch UNION in
-- refresh_personal_records_for_user, statement-level trigger since
-- 20270315_001). A typed column replaces the per-row `metadata ? key`
-- probe + `->>` cast + `~ '^[0-9]+$'` validation with a plain
-- `is not null` read, and gives the type system (and both row-type
-- generators) visibility the bag never had.
--
-- Lock hygiene: the column adds are nullable with no default (catalog-only).
-- The backfill touches ONLY rows whose bag carries at least one of the four
-- keys (`?|`), rewrites each such row exactly once (columns set + keys
-- stripped in the same UPDATE), and runs in bounded batches so no single
-- statement scans/rewrites the whole table. The PR update trigger is
-- disabled around the backfill: the rewritten refresher produces identical
-- personal_records rows from the moved values, so recomputing every
-- affected user's full PR history mid-migration would be pure waste.

-- ─────────────────── 1. Columns ───────────────────

alter table public.runs add column fastest_5k_s integer;
alter table public.runs add column fastest_10k_s integer;
alter table public.runs add column fastest_half_marathon_s integer;
alter table public.runs add column fastest_marathon_s integer;

-- ─────────────────── 2. Backfill + strip (batched) ───────────────────

alter table public.runs disable trigger runs_personal_records_update;

do $$
declare
  v_rows int;
begin
  loop
    with batch as (
      select id
      from public.runs
      where metadata ?| array[
        'fastest_5k_s', 'fastest_10k_s',
        'fastest_half_marathon_s', 'fastest_marathon_s'
      ]
      limit 5000
    )
    update public.runs r
    set
      -- Same validation the trigger's regex applied: non-negative integer
      -- strings backfill, anything else (non-numeric, negative, fractional)
      -- is dropped exactly as the old `~ '^[0-9]+$'` read skipped it.
      fastest_5k_s = case
        when (r.metadata ->> 'fastest_5k_s') ~ '^[0-9]+$'
        then (r.metadata ->> 'fastest_5k_s')::int end,
      fastest_10k_s = case
        when (r.metadata ->> 'fastest_10k_s') ~ '^[0-9]+$'
        then (r.metadata ->> 'fastest_10k_s')::int end,
      fastest_half_marathon_s = case
        when (r.metadata ->> 'fastest_half_marathon_s') ~ '^[0-9]+$'
        then (r.metadata ->> 'fastest_half_marathon_s')::int end,
      fastest_marathon_s = case
        when (r.metadata ->> 'fastest_marathon_s') ~ '^[0-9]+$'
        then (r.metadata ->> 'fastest_marathon_s')::int end,
      metadata = r.metadata
        - 'fastest_5k_s' - 'fastest_10k_s'
        - 'fastest_half_marathon_s' - 'fastest_marathon_s'
    from batch
    where r.id = batch.id;
    get diagnostics v_rows = row_count;
    exit when v_rows = 0;
  end loop;
end $$;

alter table public.runs enable trigger runs_personal_records_update;

-- ─────────────────── 3. personal-records refresher ───────────────────
-- Re-emit refresh_personal_records_for_user from the LATEST body
-- (20261207_001: auth guard + advisory lock + widened brackets + mile
-- bracket + embedded bests + DNF exclusion via the is_dnf column) with the
-- four embedded-best branches switched from the metadata probe/cast/regex
-- to the columns. `>= 0` mirrors the old regex domain (which admitted '0'
-- but no sign), so a rogue negative write can never become a PR. Patched
-- on top of the live body per the bare-body gotcha, NOT rewritten.

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

      -- Embedded-best 5k from the promoted fastest_5k_s column.
      select
        id as run_id, fastest_5k_s,
        started_at as achieved_at, '5k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and fastest_5k_s is not null
        and fastest_5k_s >= 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_10k_s,
        started_at as achieved_at, '10k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and fastest_10k_s is not null
        and fastest_10k_s >= 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_half_marathon_s,
        started_at as achieved_at, 'half_marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and fastest_half_marathon_s is not null
        and fastest_half_marathon_s >= 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_marathon_s,
        started_at as achieved_at, 'marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and fastest_marathon_s is not null
        and fastest_marathon_s >= 0
        and is_dnf = false
    ) candidates
    where distance is not null
  ) ranked
  where rn = 1;
end;
$$;

-- ─────────────────── 4. trigger watch-list ───────────────────
-- Re-emit trigger_refresh_personal_records from the LATEST body
-- (20270315_001, statement-level with transition tables) with the UPDATE
-- changed-value filter's `metadata` entry replaced by the four promoted
-- columns — the refresher no longer reads the bag at all, so a
-- metadata-only edit (title, notes) no longer forces a full PR recompute.

create or replace function trigger_refresh_personal_records()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if tg_op = 'INSERT' then
    for v_user_id in select distinct user_id from changed_runs loop
      perform refresh_personal_records_for_user(v_user_id);
    end loop;
  elsif tg_op = 'UPDATE' then
    for v_user_id in
      select u.user_id
      from (
        select n.user_id
        from changed_runs n
        join old_runs o on o.id = n.id
        where (n.distance_m, n.duration_s, n.source, n.user_id, n.is_dnf,
               n.fastest_5k_s, n.fastest_10k_s,
               n.fastest_half_marathon_s, n.fastest_marathon_s)
          is distinct from
          (o.distance_m, o.duration_s, o.source, o.user_id, o.is_dnf,
           o.fastest_5k_s, o.fastest_10k_s,
           o.fastest_half_marathon_s, o.fastest_marathon_s)
        union
        select o.user_id
        from old_runs o
        join changed_runs n on n.id = o.id
        where (n.distance_m, n.duration_s, n.source, n.user_id, n.is_dnf,
               n.fastest_5k_s, n.fastest_10k_s,
               n.fastest_half_marathon_s, n.fastest_marathon_s)
          is distinct from
          (o.distance_m, o.duration_s, o.source, o.user_id, o.is_dnf,
           o.fastest_5k_s, o.fastest_10k_s,
           o.fastest_half_marathon_s, o.fastest_marathon_s)
      ) u
    loop
      perform refresh_personal_records_for_user(v_user_id);
    end loop;
  else
    for v_user_id in select distinct user_id from old_runs loop
      perform refresh_personal_records_for_user(v_user_id);
    end loop;
  end if;
  return null;
end;
$$;

-- ─────────────────── 5. public_runs view ───────────────────
-- The four keys were public-safe (never on the strip-list, rode through the
-- view's metadata projection). Now that they are columns, expose them as
-- columns — same treatment as activity_type / is_dnf in 20261207_001. The
-- bag rows were stripped above, so the denylist is unchanged. DROP + CREATE
-- because the column list changes (CREATE OR REPLACE would hit 42P16).
-- Body otherwise identical to the live view (20270302_001).

drop view if exists public_runs;

create view public_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.elevation_gain_m,
  r.source,
  r.activity_type,
  r.is_dnf,
  r.is_public,
  r.created_at,
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
  r.race_listing_id,
  (r.track_url is not null) as has_track,
  r.fastest_5k_s,
  r.fastest_10k_s,
  r.fastest_half_marathon_s,
  r.fastest_marathon_s,
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
    - 'gun_time'
    - 'age_group_place'
    - 'age_group'
    - 'perceived_effort'
    - 'run_number'
    as metadata
from runs r
where r.is_public = true;

revoke all on public.public_runs from public, anon, authenticated;
grant select on public_runs to anon, authenticated;
