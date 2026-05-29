-- Add a 1-mile (1609 m) personal-record bracket (older-runner persona #31).
-- refresh_personal_records_for_user only bucketed 5k/10k/half/marathon, so a
-- runner's mile PR — a staple of masters / track training — was invisible.
--
-- Two parts: widen the personal_records.distance CHECK to admit '1_mile', and
-- (per the backend "bare-body create or replace strips prior fixes" gotcha)
-- re-create the refresher from the LATEST body (20261009_001: auth guard +
-- advisory lock + widened brackets + embedded bests + DNF exclusion) with the
-- new bracket added — NOT from scratch.

alter table personal_records drop constraint personal_records_distance_check;
alter table personal_records
  add constraint personal_records_distance_check
  check (distance in ('1_mile', '5k', '10k', 'half_marathon', 'marathon'));

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
        and coalesce(metadata->>'is_dnf', 'false') <> 'true'

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
