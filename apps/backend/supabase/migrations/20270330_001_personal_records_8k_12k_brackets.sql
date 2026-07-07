-- Add 8k and 12k personal-record brackets (older-runner persona #33).
--
-- Masters / club racing leans on distances the four road-major brackets
-- skip: the 8k club handicap and the 12k (both age-grade-table standard
-- distances the client already grades — age_grade_tables.ts carries keys
-- for each). A qualifying run at either distance fell through the CASE
-- (`distance is null`) and was silently excluded from personal_records.
-- The 1-mile bracket landed earlier (20261021_001); this closes the
-- remaining two. Same ±2% window as every other bracket:
--   8k  @ 8000m:  7840 - 8160
--   12k @ 12000m: 11760 - 12240
--
-- Per the backend "bare CREATE OR REPLACE strips prior fixes" gotcha, the
-- refresher below is the LATEST live body (20270325_001: auth guard +
-- advisory lock + promoted fastest_* embedded-best branches + DNF
-- exclusion) with only the two CASE lines added — NOT rewritten.

alter table personal_records drop constraint personal_records_distance_check;
alter table personal_records
  add constraint personal_records_distance_check
  check (distance in ('1_mile', '5k', '8k', '10k', '12k', 'half_marathon', 'marathon'));

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

-- One-time backfill so already-logged 8k / 12k runs surface without
-- waiting for the next run write to fire the statement trigger.
do $$
declare
  u uuid;
begin
  for u in select distinct user_id from runs where distance_m between 7840 and 8160
              or distance_m between 11760 and 12240
  loop
    perform refresh_personal_records_for_user(u);
  end loop;
end;
$$;
