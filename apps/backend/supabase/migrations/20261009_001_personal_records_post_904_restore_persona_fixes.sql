-- Re-apply the Round 2/3 persona-fixes to refresh_personal_records_for_user
-- that 20260904_001_pr_refresh_restore_auth_guard.sql unwittingly stripped
-- when it did a `create or replace function` to restore the JWT-role auth
-- guard. The Round 2/3 commits had already replaced the body to widen the
-- distance brackets (20260528000002), include embedded-best efforts
-- (20260529000002), and exclude DNFs (20260530000001) — each was a
-- bare-body rewrite that dropped the auth-guard, so 20260904_001 reset to
-- the OLD tight brackets / whole-run-only / DNF-included shape to restore
-- the guard.
--
-- This consolidation rolls the auth-guard from 20260904_001 together with
-- all three persona-fixes so the live function honours every one:
--   - Auth guard: JWT-role check from BOTH PostgREST claim formats,
--     bypass for service_role + empty (direct SQL / trigger / seed),
--     else require auth.uid() = p_user_id.
--   - Advisory lock: per-user serialisation from 20260831_001.
--   - Widened brackets (±2%) from Round 2 #1: 4900-5100, 9800-10200,
--     20675-21519, 41351-43039.
--   - Embedded-best efforts from Round 2 #4: union-all fastest_5k_s /
--     fastest_10k_s / fastest_half_marathon_s / fastest_marathon_s as
--     additional candidates, ranked best-time-wins per distance.
--   - DNF exclusion from Round 3 Ultra #3: `coalesce(metadata->>'is_dnf',
--     'false') <> 'true'` on every candidate stream.
--
-- The three earlier persona-fix migrations (20260528000002, 20260529000002,
-- 20260530000001) remain in the migration chain as historical no-ops —
-- they each replace the function with their own body, then this migration
-- replaces it one more time at the end. The chain reaches the same final
-- state on `db reset` regardless. Pinned by personal_records_brackets_test
-- + personal_records_embedded_bests_test + personal_records_dnf_test.

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

revoke execute on function refresh_personal_records_for_user(uuid) from public, anon;
grant execute on function refresh_personal_records_for_user(uuid) to authenticated;
