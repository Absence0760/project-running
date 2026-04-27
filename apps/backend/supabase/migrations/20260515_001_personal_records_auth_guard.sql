-- Add caller-identity guard to refresh_personal_records_for_user.
--
-- Same footgun pattern that 20260503_001_coach_usage_auth_guard.sql
-- closed for the coach-usage RPCs: the function is `security definer`
-- and granted to `authenticated`, so any logged-in user could call
-- `rpc('refresh_personal_records_for_user', { p_user_id: <victim> })`
-- and force-rebuild another user's PB cache. The cache rebuild itself
-- doesn't expose another user's data — it just deletes + reinserts
-- their own rows from the runs table the trigger already had access
-- to — but it lets an attacker (a) churn the table at will and
-- (b) potentially hide a victim's PBs by repeatedly rebuilding mid-
-- transaction. Either way, the function should not be reachable with
-- an arbitrary `p_user_id`.
--
-- The trigger path is unaffected: the trigger sets `p_user_id` to
-- `new.user_id` / `old.user_id`, which RLS already constrained to
-- `auth.uid()` on the underlying `runs` insert/update/delete. The
-- guard's `auth.uid() != p_user_id` is therefore false in the trigger
-- path. Service-role / seed inserts run with `auth.uid() = null`,
-- where `null != p_user_id` evaluates to null (falsy) and skips the
-- guard — so seed.sql still works.

create or replace function refresh_personal_records_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and auth.uid() != p_user_id then
    raise exception 'not authorized';
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
