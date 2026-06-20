-- Vert / elevation-gain challenge metric (challenges.md Open Question 1).
--
-- Challenges shipped with distance / duration / activity_count / streak_days
-- (20270209_001 + 20270210_001); `vert` was deferred because total elevation
-- gain had no first-class per-run column — it lived only in
-- `runs.metadata.elevation_m`, which is populated for some imports (Strava /
-- Garmin) and absent for app-recorded runs, and the challenge aggregate sums
-- BASE `runs` columns directly (sum(r.distance_m) etc.), not the activities
-- view. So a `vert` board summing a jsonb key would silently undercount and
-- couldn't be expressed cleanly in the GROUP-BY.
--
-- This migration first-classes elevation gain as `runs.elevation_gain_m`
-- (mirroring how `activity_type` was promoted by 20261207_001), backfills it
-- from the existing `metadata.elevation_m` key, then extends the
-- ChallengeMetric union + CHECK + the two aggregate RPCs to sum it. The metadata
-- key is left in place (recap / export / Strava EF / Go worker / backup still
-- read it) — the column is the additive, queryable source; writers populate
-- both going forward. Additive + nullable: the recording L0/L1 path is untouched
-- (a null elevation contributes 0 to a vert board via coalesce).

-- ── runs.elevation_gain_m: first-class total ascent ─────────────────────────
alter table runs add column elevation_gain_m numeric;

comment on column runs.elevation_gain_m is
  'Total elevation gain (metres of ascent) for the run. Nullable: absent for '
  'runs with no elevation source. Backfilled from metadata.elevation_m; '
  'writers populate both. Summed by the vert challenge metric + projected into '
  'the activities view + public_runs (a single ascent integer, public-safe).';

-- Backfill from the existing metadata key for every run that carries it.
update runs
set elevation_gain_m = (metadata->>'elevation_m')::numeric
where metadata ? 'elevation_m'
  and (metadata->>'elevation_m') ~ '^-?[0-9]+(\.[0-9]+)?$'
  and elevation_gain_m is null;

-- Partial index: the vert leaderboard sums elevation_gain_m per user over a
-- window; the run window is already covered by the per-user/started_at scan,
-- so a narrow index on the non-null rows keeps the sum cheap without bloating
-- writes for the common no-elevation run.
create index runs_elevation_gain on runs (user_id, started_at)
  where elevation_gain_m is not null;

-- ── ChallengeMetric CHECK: add 'vert' ───────────────────────────────────────
-- Re-state the FULL metric set (the bare-body trap applies to CHECK swaps too).
-- The CHECK ↔ TS-union guard (check_constraint_unions.mjs) reads the LATEST
-- `check (metric in (...))` it finds and matches it against ChallengeMetric.
alter table challenges drop constraint challenges_metric_ck;
alter table challenges
  add constraint challenges_metric_ck check (
    metric in ('distance', 'duration', 'vert', 'activity_count', 'streak_days'));

-- ── activities view: project elevation_gain_m into the runs branch summary ──
-- Appended at the END of the runs branch's jsonb_build_object so CREATE OR
-- REPLACE stays legal (the view's column list / types are unchanged — only the
-- jsonb builder grows a key). Keeps metricFromActivity's client-side estimate
-- (which reads summary->>'elevation_gain_m') in lockstep with the server sum.
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
    'activity_type', r.activity_type,
    'elevation_gain_m', r.elevation_gain_m
  ) as summary,
  r.is_public
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
  ) as summary,
  w.is_public
from public.gym_workouts w
union all
select
  f.id,
  f.user_id,
  'meal'::text as kind,
  f.started_at,
  jsonb_build_object(
    'item_name', f.item_name,
    'calories', f.calories,
    'meal_slot', f.meal_slot
  ) as summary,
  f.is_public
from public.food_log f;

grant select on public.activities to authenticated;

-- ── public_runs: project the new ascent column ──────────────────────────────
-- elevation_gain_m is a single ascent integer — equivalent in sensitivity to
-- the metadata.elevation_m key that already passes through the view (public-
-- safe per metadata.md: it adds no geographic signal the rendered polyline
-- doesn't carry). Re-state the FULL view (bare CREATE OR REPLACE would drop the
-- metadata strip-list); the denylist is carried forward verbatim from
-- 20270214_001 + the column list gains elevation_gain_m.
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

grant select on public_runs to anon, authenticated;

-- ── challenge_leaderboard: add the vert case ────────────────────────────────
-- Full body re-stated from 20270210_001 (bare-body trap) with one new metric
-- branch in each CASE: vert sums runs.elevation_gain_m (coalesce-0 so a run
-- with no elevation source contributes nothing rather than nulling the sum).
create or replace function challenge_leaderboard(
  p_challenge_id uuid,
  p_by_team boolean default false
)
returns table (
  user_id uuid,
  display_name text,
  team_club_id uuid,
  value numeric,
  rank bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_metric        text;
  v_activity_type text;
  v_starts        timestamptz;
  v_ends          timestamptz;
begin
  if not is_challenge_visible(p_challenge_id) then
    return;
  end if;

  select c.metric, c.activity_type, c.starts_at, c.ends_at
    into v_metric, v_activity_type, v_starts, v_ends
  from challenges c
  where c.id = p_challenge_id;

  if v_metric is null then
    return;
  end if;

  if p_by_team then
    return query
    with per_team as (
      select
        pp.team_club_id,
        coalesce(
          case v_metric
            when 'distance' then sum(r.distance_m)
            when 'duration' then sum(r.duration_s)::numeric
            when 'vert' then sum(coalesce(r.elevation_gain_m, 0))
            when 'activity_count' then count(r.id)::numeric
            when 'streak_days' then count(distinct (r.started_at at time zone 'UTC')::date)::numeric
          end,
          0
        ) as value
      from challenge_participants pp
      left join runs r
        on r.user_id = pp.user_id
       and r.started_at >= v_starts
       and r.started_at < v_ends
       and (v_activity_type is null or r.activity_type = v_activity_type)
      where pp.challenge_id = p_challenge_id
      group by pp.team_club_id
    )
    select
      null::uuid as user_id,
      null::text as display_name,
      pt.team_club_id,
      pt.value,
      rank() over (order by pt.value desc) as rank
    from per_team pt
    order by rank, pt.team_club_id nulls last;
  else
    return query
    with per_user as (
      select
        pp.user_id,
        pp.team_club_id,
        coalesce(
          case v_metric
            when 'distance' then sum(r.distance_m)
            when 'duration' then sum(r.duration_s)::numeric
            when 'vert' then sum(coalesce(r.elevation_gain_m, 0))
            when 'activity_count' then count(r.id)::numeric
            when 'streak_days' then count(distinct (r.started_at at time zone 'UTC')::date)::numeric
          end,
          0
        ) as value
      from challenge_participants pp
      left join runs r
        on r.user_id = pp.user_id
       and r.started_at >= v_starts
       and r.started_at < v_ends
       and (v_activity_type is null or r.activity_type = v_activity_type)
      where pp.challenge_id = p_challenge_id
      group by pp.user_id, pp.team_club_id
    )
    select
      pu.user_id,
      p.display_name,
      pu.team_club_id,
      pu.value,
      rank() over (order by pu.value desc) as rank
    from per_user pu
    left join user_profiles p on p.id = pu.user_id
    order by rank, pu.user_id nulls last;
  end if;
end;
$$;

grant execute on function challenge_leaderboard(uuid, boolean) to authenticated, anon;

-- ── recompute_challenge_completion: add the vert case ───────────────────────
-- Full body re-stated from 20270210_001 with the vert branch in the value sum.
create or replace function recompute_challenge_completion(
  p_challenge_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_metric        text;
  v_activity_type text;
  v_goal          numeric;
  v_starts        timestamptz;
  v_ends          timestamptz;
  v_value         numeric;
begin
  select c.metric, c.activity_type, c.goal_value, c.starts_at, c.ends_at
    into v_metric, v_activity_type, v_goal, v_starts, v_ends
  from challenges c
  where c.id = p_challenge_id;

  if v_metric is null or v_goal is null then
    return;
  end if;

  if not exists (
    select 1 from challenge_participants pp
    where pp.challenge_id = p_challenge_id and pp.user_id = p_user_id
  ) then
    return;
  end if;

  if exists (
    select 1 from challenge_badges b
    where b.challenge_id = p_challenge_id and b.user_id = p_user_id
  ) then
    return;
  end if;

  select coalesce(
    case v_metric
      when 'distance' then sum(r.distance_m)
      when 'duration' then sum(r.duration_s)::numeric
      when 'vert' then sum(coalesce(r.elevation_gain_m, 0))
      when 'activity_count' then count(r.id)::numeric
      when 'streak_days' then count(distinct (r.started_at at time zone 'UTC')::date)::numeric
    end,
    0
  )
  into v_value
  from runs r
  where r.user_id = p_user_id
    and r.started_at >= v_starts
    and r.started_at < v_ends
    and (v_activity_type is null or r.activity_type = v_activity_type);

  if v_value >= v_goal then
    insert into challenge_badges (user_id, challenge_id, metric, final_value)
    values (p_user_id, p_challenge_id, v_metric, v_value)
    on conflict (user_id, challenge_id) do nothing;

    update challenge_participants
    set completed_at = now()
    where challenge_id = p_challenge_id
      and user_id = p_user_id
      and completed_at is null;

    insert into notifications (user_id, kind, challenge_id)
    values (p_user_id, 'challenge_complete', p_challenge_id);
  end if;
end;
$$;

revoke execute on function recompute_challenge_completion(uuid, uuid) from public;
grant execute on function recompute_challenge_completion(uuid, uuid) to authenticated;
