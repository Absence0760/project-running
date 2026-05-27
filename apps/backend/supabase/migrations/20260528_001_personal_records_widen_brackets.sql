-- Widen the personal-records distance brackets from 200 m windows to
-- ±2% so real-world race-day finishes qualify.
--
-- The Apr/May/Aug migrations used asymmetric brackets:
--   5k:  4900 - 5100   (±2% — fine)
--   10k: 9900 - 10100  (±1% — too tight)
--   HM:  21000 - 21200 (~0.5% — too tight)
--   M:   42100 - 42300 (~0.25% — too tight)
--
-- A typical Strava-recorded marathon finish is ~42.45 km — tangents are
-- imperfect, GPS jitter adds ~0.5-1% of polyline length on top of the
-- measured course. So a 2:50 marathon recorded at 42.45 km was rejected
-- outright by the old brackets, leaving the marathon PR row missing
-- entirely for most pros. Same problem at 10k (Strava records
-- 10.15 km → excluded) and HM (21.25 km → excluded).
--
-- ±2% across all distances:
--   5k @ 5000m:  4900 - 5100
--   10k @ 10000m: 9800 - 10200
--   HM @ 21097m: 20675 - 21519
--   M @ 42195m:  41351 - 43039
--
-- This still rejects clearly-different distances (a 41 km long run
-- isn't a marathon PR, a 45 km ultra isn't either) while accepting
-- typical race-day overshoot. ±2% is what the 5k bracket already used;
-- the longer-distance brackets just inherited a copy-paste tightening
-- that drifted from the symmetric model.
--
-- Persona-driven bug-hunt finding Pro #1 — pinned by
-- supabase/tests/personal_records_brackets_test.sql.

create or replace function refresh_personal_records_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Serialize per-user (concurrent_safe migration 20260831_001).
  perform pg_advisory_xact_lock(
    hashtext('personal_records:' || p_user_id::text)
  );

  delete from personal_records where user_id = p_user_id;

  insert into personal_records (user_id, distance, best_time_s, run_id, achieved_at)
  select
    p_user_id,
    distance,
    duration_s,
    id,
    started_at
  from (
    select
      id,
      duration_s,
      started_at,
      case
        when distance_m between 4900  and 5100   then '5k'
        when distance_m between 9800  and 10200  then '10k'
        when distance_m between 20675 and 21519  then 'half_marathon'
        when distance_m between 41351 and 43039  then 'marathon'
      end as distance,
      row_number() over (
        partition by
          case
            when distance_m between 4900  and 5100   then '5k'
            when distance_m between 9800  and 10200  then '10k'
            when distance_m between 20675 and 21519  then 'half_marathon'
            when distance_m between 41351 and 43039  then 'marathon'
          end
        order by duration_s asc
      ) as rn
    from runs
    where user_id = p_user_id
      and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
      and distance_m is not null
      and duration_s is not null
  ) ranked
  where rn = 1 and distance is not null;
end;
$$;

-- One-time backfill: re-run the PR refresh for every user so newly-
-- eligible runs (those that were excluded under the tight brackets)
-- get their PR rows created without waiting for a stray run-update
-- to trigger the refresh.
do $$
declare
  u uuid;
begin
  for u in select distinct user_id from runs loop
    perform refresh_personal_records_for_user(u);
  end loop;
end;
$$;
