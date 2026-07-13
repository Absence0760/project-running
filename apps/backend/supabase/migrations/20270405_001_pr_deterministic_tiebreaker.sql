-- Deterministic personal-record selection on tied times (bughunt #4).
--
-- `refresh_personal_records_for_user` picked the winning effort per distance
-- bucket with `row_number() over (partition by distance order by duration_s
-- asc)` — no secondary sort key. When two eligible efforts share the exact
-- same `duration_s`, `row_number()` breaks the tie arbitrarily, so which run
-- becomes `personal_records.run_id` / `achieved_at` could flip between
-- rebuilds (e.g. after any unrelated run edit re-fires the refresher). The
-- dashboard "your PB run" link then points at a different tied run.
--
-- Fix: add a stable tiebreaker — earliest `achieved_at`, then lowest `run_id`
-- — so the same physical run is credited every rebuild.
--
-- Per the backend "bare CREATE OR REPLACE strips prior fixes" gotcha, the
-- refresher below is the LATEST live body (20270330_001: auth guard +
-- advisory lock + widened brackets + promoted fastest_* embedded-best
-- branches + DNF exclusion + 8k/12k brackets) with ONLY the window ORDER BY
-- extended — NOT rewritten.

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
      row_number() over (
        partition by distance
        order by duration_s asc, achieved_at asc, run_id asc
      ) as rn
    from (
      -- Whole-run candidates, widened brackets, DNFs excluded.
      select
        id as run_id,
        duration_s,
        started_at as achieved_at,
        case
          when distance_m between 1559  and 1659   then '1_mile'
          when distance_m between 4900  and 5100   then '5k'
          when distance_m between 7840  and 8160   then '8k'
          when distance_m between 9800  and 10200  then '10k'
          when distance_m between 11760 and 12240  then '12k'
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

-- One-time rebuild so any user whose current PB row was assigned off the old
-- arbitrary tiebreak settles onto the deterministic winner.
do $$
declare
  u uuid;
begin
  for u in select distinct user_id from personal_records
  loop
    perform refresh_personal_records_for_user(u);
  end loop;
end;
$$;
