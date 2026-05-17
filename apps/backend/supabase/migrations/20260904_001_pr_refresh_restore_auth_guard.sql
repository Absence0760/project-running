-- Restore the caller-identity guard on refresh_personal_records_for_user
-- that 20260831_001_personal_records_concurrent_safe.sql dropped when it
-- added the per-user advisory_xact_lock. The concurrent-safe rewrite did
-- a bare `create or replace function` that replaced the entire body and
-- silently deleted the 20260802_001 guard (which itself was the null-safe
-- hardening of the original 20260515_001 guard).
--
-- Same fix shape as 20260802_001_pr_refresh_null_guard.sql: read the JWT
-- role from BOTH PostgREST claim formats, bypass for service_role and
-- empty-role (direct-SQL / trigger / seed), otherwise require
-- `auth.uid() is not null and auth.uid() is not distinct from p_user_id`.
-- Pinned by rls_pr_refresh_null_guard_test.sql (3 assertions).
--
-- The advisory-lock semantics from 20260831_001 are preserved unchanged.

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
