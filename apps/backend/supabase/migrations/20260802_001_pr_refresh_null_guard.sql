-- /audit/all High: `refresh_personal_records_for_user` uses
-- `auth.uid() != p_user_id` as its caller-identity guard.  Under
-- Postgres three-valued logic, `null != <uuid>` evaluates to NULL
-- (falsy), so the guard silently passes for any caller with
-- `auth.uid() = null`.  The direct-EXECUTE grant is `authenticated`-
-- only today, but a future SECURITY DEFINER chain or trigger with no
-- JWT context could reach the function and bypass the guard, churn
-- the table at will, or rebuild a victim's PB cache mid-transaction.
--
-- The 20260709_001_coach_usage_null_guard_fix migration closed the
-- exact same shape on the coach-usage RPCs.  Apply that pattern here:
-- read the JWT role from BOTH PostgREST claim formats (legacy
-- `request.jwt.claim.role` AND new `request.jwt.claims` jsonb),
-- service-role bypasses, otherwise require `auth.uid() is not null
-- and auth.uid() is not distinct from p_user_id`.
--
-- Also tighten the EXECUTE grant: `revoke ... from public, anon`
-- before the targeted re-grant to `authenticated`, so the project-
-- wide default `grant ... to public` doesn't leave the function
-- callable from anon.  Mirrors the hygiene in
-- 20260711_001_definer_grant_hygiene.sql.

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
  -- Service-role and direct-SQL (empty role) callers are trusted —
  -- triggers and seed.sql run in those contexts.  Every other role
  -- (authenticated, anon, future custom roles) must match p_user_id.
  if v_role <> 'service_role' and v_role <> '' then
    if auth.uid() is null or auth.uid() is distinct from p_user_id then
      raise exception 'refresh_personal_records_for_user: not authorized'
        using errcode = '42501';
    end if;
  end if;

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
        when distance_m between 9900  and 10100  then '10k'
        when distance_m between 21000 and 21200  then 'half_marathon'
        when distance_m between 42100 and 42300  then 'marathon'
      end as distance,
      row_number() over (
        partition by
          case
            when distance_m between 4900  and 5100   then '5k'
            when distance_m between 9900  and 10100  then '10k'
            when distance_m between 21000 and 21200  then 'half_marathon'
            when distance_m between 42100 and 42300  then 'marathon'
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

revoke execute on function refresh_personal_records_for_user(uuid) from public, anon;
grant execute on function refresh_personal_records_for_user(uuid) to authenticated;
