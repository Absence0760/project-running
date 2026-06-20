-- Multi-athlete coach roster summary (coach_roster.md).
--
-- A read-only aggregation over the consent model already shipped by
-- 20261102_001 (coach_athletes link) + 20261103_001 (coach run visibility)
-- + 20261116_001 (coach plan access). Returns one row per ACTIVE-linked
-- athlete with the headline triage signals a coach needs to scan their
-- whole roster at a glance: last-run recency, 7-day run count + distance,
-- 7-day acute load + 28-day chronic load (so the client computes ACWR via
-- the shared coach_load helper), and the athlete's active-plan completion %.
--
-- Why a SECURITY DEFINER RPC and not a client fan-out:
--   The durable shape is one round-trip that re-checks consent server-side
--   per athlete. The `mine` CTE (coach_id = auth.uid() AND status='active')
--   is the ONLY membership gate, and it is evaluated INSIDE the definer body
--   -- SECURITY DEFINER bypasses the caller's RLS, so the gate cannot lean on
--   the runs/training_plans coach-read policies; it must be the CTE here. A
--   non-coach gets zero rows; an unauthenticated caller raises (fail-closed).
--
-- What this deliberately does NOT expose:
--   No raw GPS track. The function reads run ROW stats only (distance/
--   duration/started_at) -- the track bytes stay owner-only (decisions §98),
--   exactly as the coach review surface already does. No new privacy
--   boundary is opened: every value here is already coach-readable under the
--   shipped policies; this only aggregates it.
--
-- Load math note: the function returns RAW acute (7d) + chronic (28d-avg-
-- per-7d) distance-proxy stress sums. The ACWR ratio + injury-risk band live
-- in the shared coach_load parity helper (web + mobile), NOT in this SQL, so
-- the risk policy is in one testable place and web/mobile/RPC agree.

create or replace function coach_roster_summary()
returns table (
  athlete_id          uuid,
  display_name        text,
  avatar_url          text,
  last_run_at         timestamptz,
  runs_7d             int,
  distance_7d_m       double precision,
  load_acute          double precision,
  load_chronic        double precision,
  active_plan_id      uuid,
  plan_completion_pct int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  return query
  with mine as (
    select ca.athlete_id
    from coach_athletes ca
    where ca.coach_id = auth.uid()
      and ca.status = 'active'
      and ca.athlete_id is not null
  ),
  -- Distance-proxy daily stress mirrors training_load.ts's distance fallback
  -- (10 points / km). The headline "load" column is a coarse triage signal,
  -- not the calibrated TRIMP curve on the athlete's own dashboard -- a coach
  -- scanning a roster wants "ramping vs tapering", which the acute:chronic
  -- ratio gives from the proxy alone. is_dnf runs are excluded (they aren't a
  -- training stimulus the athlete completed).
  athlete_runs as (
    select
      r.user_id,
      r.started_at,
      r.distance_m,
      (coalesce(r.distance_m, 0) / 1000.0) * 10.0 as stress
    from runs r
    join mine on mine.athlete_id = r.user_id
    where coalesce((r.metadata->>'is_dnf')::boolean, false) = false
      and r.started_at >= now() - interval '28 days'
  ),
  run_agg as (
    select
      ar.user_id,
      max(ar.started_at) as last_run_at_28d,
      count(*) filter (where ar.started_at >= now() - interval '7 days')::int as runs_7d,
      coalesce(sum(ar.distance_m) filter (where ar.started_at >= now() - interval '7 days'), 0)::double precision as distance_7d_m,
      coalesce(sum(ar.stress) filter (where ar.started_at >= now() - interval '7 days'), 0)::double precision as load_acute,
      -- Chronic load is the average weekly stress over the 28-day window
      -- (total 28-day stress / 4), the conventional ACWR denominator scale.
      (coalesce(sum(ar.stress), 0) / 4.0)::double precision as load_chronic
    from athlete_runs ar
    group by ar.user_id
  ),
  -- Each athlete's most-recent run regardless of the 28-day window, so the
  -- recency column is honest for an athlete who hasn't run in a month (the
  -- run_agg window would otherwise show last_run_at as null for them).
  last_run as (
    select r.user_id, max(r.started_at) as last_run_at
    from runs r
    join mine on mine.athlete_id = r.user_id
    group by r.user_id
  ),
  active_plan as (
    select distinct on (tp.user_id)
      tp.user_id,
      tp.id as plan_id
    from training_plans tp
    join mine on mine.athlete_id = tp.user_id
    where tp.status = 'active'
      and coalesce(tp.is_template, false) = false
    order by tp.user_id, tp.created_at desc
  ),
  -- Completion % mirrors fetchAthletePlanOverview: done = completed_run_id is
  -- not null OR manually_completed; denominator excludes rest workouts and
  -- intentionally-skipped ones (skipped_at not null).
  plan_progress as (
    select
      ap.user_id,
      ap.plan_id,
      count(*) filter (
        where pw.completed_run_id is not null or pw.manually_completed = true
      )::int as done,
      count(*) filter (
        where pw.kind <> 'rest' and pw.skipped_at is null
      )::int as total
    from active_plan ap
    join plan_weeks pwk on pwk.plan_id = ap.plan_id
    join plan_workouts pw on pw.week_id = pwk.id
    group by ap.user_id, ap.plan_id
  )
  select
    p.id as athlete_id,
    p.display_name,
    p.avatar_url,
    lr.last_run_at,
    coalesce(ra.runs_7d, 0) as runs_7d,
    coalesce(ra.distance_7d_m, 0)::double precision as distance_7d_m,
    coalesce(ra.load_acute, 0)::double precision as load_acute,
    coalesce(ra.load_chronic, 0)::double precision as load_chronic,
    ap.plan_id as active_plan_id,
    case
      when pp.total is null or pp.total = 0 then 0
      else round((pp.done::numeric / pp.total::numeric) * 100)::int
    end as plan_completion_pct
  from mine
  join user_profiles p on p.id = mine.athlete_id
  left join run_agg ra on ra.user_id = mine.athlete_id
  left join last_run lr on lr.user_id = mine.athlete_id
  left join active_plan ap on ap.user_id = mine.athlete_id
  left join plan_progress pp on pp.user_id = mine.athlete_id
  order by lr.last_run_at desc nulls last, p.display_name asc;
end;
$$;

-- The definer body owned by postgres reads coach_athletes / runs /
-- training_plans / plan_weeks / plan_workouts / user_profiles; the auto-grants
-- on those tables already cover postgres. authenticated callers only need the
-- function grant. NOT anon -- the roster is consent-gated, never public.
revoke execute on function coach_roster_summary() from public;
grant execute on function coach_roster_summary() to authenticated;
