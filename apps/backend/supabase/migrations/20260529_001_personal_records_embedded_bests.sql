-- Personal-records: also consider embedded best efforts from
-- `metadata.fastest_5k_s` / `_10k_s` / `_half_marathon_s` / `_marathon_s`
-- when computing PRs.
--
-- Pre-fix the trigger only looked at whole-run `distance_m` against the
-- canonical brackets. A pro who runs a sub-20 5k inside an 18 km long
-- run (whole-run distance_m = 18000, well outside the marathon bracket
-- too) never sees that 5k effort land in the canonical
-- `personal_records` cache. The mobile dashboard computes
-- `fastestWindowOf(track, 5000)` locally and shows it, but that result
-- never reaches the web Dashboard PR card or `share/u/[id]`.
--
-- Persona-hunt Round 2 finding Pro #4.
--
-- Wire shape: client writers (mobile recorder, future server-side
-- recompute over imported tracks) write the embedded best times to
-- `runs.metadata` as integer seconds:
--     metadata.fastest_5k_s, _10k_s, _half_marathon_s, _marathon_s
-- The trigger union-alls a whole-run candidate per distance bracket
-- AND a per-distance embedded-best candidate per run-with-metadata.
-- `row_number() over (partition by distance order by duration_s asc)`
-- picks the best of either kind per distance.

create or replace function refresh_personal_records_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(
    hashtext('personal_records:' || p_user_id::text)
  );

  delete from personal_records where user_id = p_user_id;

  insert into personal_records (user_id, distance, best_time_s, run_id, achieved_at)
  select
    p_user_id,
    distance,
    duration_s,
    run_id,
    achieved_at
  from (
    select
      run_id,
      duration_s,
      achieved_at,
      distance,
      row_number() over (
        partition by distance
        order by duration_s asc
      ) as rn
    from (
      -- Whole-run candidates: run's distance_m fits the canonical
      -- bracket, run's duration_s is the candidate time.
      select
        id as run_id,
        duration_s,
        started_at as achieved_at,
        case
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

      union all

      -- Embedded-best candidates: client wrote a per-distance best
      -- effort to metadata. Each key fans out into its own row so
      -- the row_number() partition can pick the user's best across
      -- whole-run AND embedded efforts in one pass.
      select
        id as run_id,
        (metadata->>'fastest_5k_s')::int as duration_s,
        started_at as achieved_at,
        '5k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_5k_s'
        and (metadata->>'fastest_5k_s') ~ '^[0-9]+$'

      union all

      select
        id as run_id,
        (metadata->>'fastest_10k_s')::int as duration_s,
        started_at as achieved_at,
        '10k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_10k_s'
        and (metadata->>'fastest_10k_s') ~ '^[0-9]+$'

      union all

      select
        id as run_id,
        (metadata->>'fastest_half_marathon_s')::int as duration_s,
        started_at as achieved_at,
        'half_marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_half_marathon_s'
        and (metadata->>'fastest_half_marathon_s') ~ '^[0-9]+$'

      union all

      select
        id as run_id,
        (metadata->>'fastest_marathon_s')::int as duration_s,
        started_at as achieved_at,
        'marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_marathon_s'
        and (metadata->>'fastest_marathon_s') ~ '^[0-9]+$'
    ) candidates
    where distance is not null
  ) ranked
  where rn = 1;
end;
$$;

-- Refresh all users so existing rows with metadata.fastest_X_s (if
-- any future writer beat the trigger) get picked up.
do $$
declare
  u uuid;
begin
  for u in select distinct user_id from runs loop
    perform refresh_personal_records_for_user(u);
  end loop;
end;
$$;
