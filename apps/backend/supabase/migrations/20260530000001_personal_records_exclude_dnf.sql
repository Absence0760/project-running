-- Personal-records: exclude DNF runs from PR candidates.
--
-- Persona-hunt Round 3 finding Ultra #3 — pre-fix, a runner who drops
-- at mile 26 of UTMB stops the recording and the run sits at
-- distance 42,000 m. Round 1's PR-bracket widening made the marathon
-- bracket 41,351–43,039 m, so the DNF-26-mile lands in-bracket and
-- the trigger promotes a 7-hour "marathon" as the user's PR — a
-- marathon that was never a marathon.
--
-- Wire shape: client writers set `runs.metadata.is_dnf = true` when
-- the runner marks the recording as a DNF. The trigger union-alls
-- whole-run + embedded-best candidates as before but excludes any
-- row with `metadata->>'is_dnf' = 'true'` from BOTH candidate
-- streams (a DNF effort isn't a credible embedded effort either —
-- the runner stopped, hydration / cramping / hypothermia colours the
-- whole effort, so the embedded fastest segment may be artificially
-- low-quality but should still be excluded for the same "this wasn't
-- a race" reason).

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
    p_user_id, distance, duration_s, run_id, achieved_at
  from (
    select
      run_id, duration_s, achieved_at, distance,
      row_number() over (partition by distance order by duration_s asc) as rn
    from (
      -- Whole-run candidates, excluding DNFs.
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
        and coalesce(metadata->>'is_dnf', 'false') <> 'true'

      union all

      select
        id as run_id, (metadata->>'fastest_5k_s')::int,
        started_at as achieved_at, '5k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_5k_s'
        and (metadata->>'fastest_5k_s') ~ '^[0-9]+$'
        and coalesce(metadata->>'is_dnf', 'false') <> 'true'

      union all

      select
        id as run_id, (metadata->>'fastest_10k_s')::int,
        started_at as achieved_at, '10k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_10k_s'
        and (metadata->>'fastest_10k_s') ~ '^[0-9]+$'
        and coalesce(metadata->>'is_dnf', 'false') <> 'true'

      union all

      select
        id as run_id, (metadata->>'fastest_half_marathon_s')::int,
        started_at as achieved_at, 'half_marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_half_marathon_s'
        and (metadata->>'fastest_half_marathon_s') ~ '^[0-9]+$'
        and coalesce(metadata->>'is_dnf', 'false') <> 'true'

      union all

      select
        id as run_id, (metadata->>'fastest_marathon_s')::int,
        started_at as achieved_at, 'marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
        and metadata ? 'fastest_marathon_s'
        and (metadata->>'fastest_marathon_s') ~ '^[0-9]+$'
        and coalesce(metadata->>'is_dnf', 'false') <> 'true'
    ) candidates
    where distance is not null
  ) ranked
  where rn = 1;
end;
$$;

-- Refresh all users so an existing run already flagged is_dnf
-- (defensive — none today, but safe) drops out of the cache.
do $$
declare
  u uuid;
begin
  for u in select distinct user_id from runs loop
    perform refresh_personal_records_for_user(u);
  end loop;
end;
$$;
