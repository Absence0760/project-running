-- A personal record is a time somebody ran, so every candidate time must be
-- positive -- including the whole-run one, which had no positivity filter at
-- all.
--
-- The filing was that the four embedded-best branches read `and fastest_5k_s
-- >= 0`, which `20270705000004`'s `> 0` column CHECKs had made equivalent
-- rather than load-bearing, so the filter was written in the shape that admits
-- the bad value and a reader could take it for the guard. That is true and the
-- four are tightened below. It is not the whole finding.
--
-- ── The reachable half ─────────────────────────────────────────────────────
-- The WHOLE-RUN branch filters `duration_s is not null` and nothing else, and
-- `runs_duration_s_check` is `duration_s >= 0` -- deliberately, since a run
-- imported or logged with a distance and no time is a row we store rather than
-- refuse, and 20270705000004 left it that way on purpose. So a zero-second run
-- in a PR bracket is storable, becomes the FASTEST candidate for that bracket
-- (`order by duration_s asc`), and reaches `personal_records`, whose own
-- `best_time_s > 0` CHECK then refuses it.
--
-- Refusing it there is the wrong place. This refresher is called from
-- `trigger_refresh_personal_records`, an AFTER trigger on `runs`, so the 23514
-- propagates out of the trigger and fails the INSERT of the run itself.
-- Measured on the local stack: an ordinary `authenticated` session inserting
-- `(duration_s => 0, distance_m => 5000, source => ''app'')` -- every `runs`
-- CHECK satisfied -- gets
--
--     new row for relation "personal_records" violates check constraint
--     "personal_records_best_time_s_check"
--
-- and the run is not saved. The runner cannot record the activity at all, and
-- the error names a table they have never heard of.
--
-- The fix belongs in the refresher, not on `runs.duration_s`: "you did not run
-- 5 km in zero seconds" is a PR-ELIGIBILITY rule, and moving it onto the column
-- would reject rows the app legitimately stores. A zero-duration run now simply
-- contributes no candidate -- it saves, and it sets no record.
--
-- No table, column, constraint or grant moves: one `create or replace` on a
-- SECURITY DEFINER plpgsql function, which preserves its ACL. Neither row-type
-- generator has anything to regenerate.

CREATE OR REPLACE FUNCTION public.refresh_personal_records_for_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        -- 'parkrun' (certified weekly 5K) + 'race' (chip-timed official results,
        -- the most authoritative source) are valid runs.source values (#378).
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        -- Run family only: a bicycle covers a PR bracket at speeds no runner
        -- reaches. Mirrors the client's `isRunFamily` in recap.ts.
        and activity_type <> 'cycle'
        and distance_m is not null
        and duration_s is not null
        and duration_s > 0
        and is_dnf = false

      union all

      -- Embedded-best 5k from the promoted fastest_5k_s column.
      select
        id as run_id, fastest_5k_s,
        started_at as achieved_at, '5k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_5k_s is not null
        and fastest_5k_s > 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_10k_s,
        started_at as achieved_at, '10k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_10k_s is not null
        and fastest_10k_s > 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_half_marathon_s,
        started_at as achieved_at, 'half_marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_half_marathon_s is not null
        and fastest_half_marathon_s > 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_marathon_s,
        started_at as achieved_at, 'marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_marathon_s is not null
        and fastest_marathon_s > 0
        and is_dnf = false
    ) candidates
    where distance is not null
  ) ranked
  where rn = 1;
end;
$function$;
