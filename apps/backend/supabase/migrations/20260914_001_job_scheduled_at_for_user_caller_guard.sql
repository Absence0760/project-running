-- audit/rls (May 2026) flagged that job_scheduled_at_for_user(uuid),
-- introduced in 20260730_001, was SECURITY DEFINER + granted to
-- `authenticated` and accepted any UUID. Any signed-in user could
-- call it with a victim UUID and read the result: `now()` ⇒ victim
-- is pro / lifetime, `now() + 30 s` ⇒ victim is free / unknown.
-- That's a subscription-tier oracle on every other user.
--
-- The legitimate callers (the runs_enqueue_match_job trigger + the
-- enqueue_run_rematch RPC) always pass the owning user's id, which
-- equals auth.uid() in both contexts:
--   - trigger fires inside an INSERT/UPDATE on `runs` where RLS
--     already forces user_id = auth.uid() on writes (no admin path
--     to runs).
--   - RPC explicitly checks `v_run_user_id = v_caller` first.
-- So enforcing `auth.uid() is null or auth.uid() = p_user_id`
-- preserves every legitimate call site and closes the oracle.
--
-- Service role keeps full access (auth.uid() is null when calling
-- from a service-role JWT) for any future server-side enqueue path.

create or replace function job_scheduled_at_for_user(p_user_id uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- auth.uid() is null for service_role / postgres-side calls.
  -- For authenticated calls it must match the user being inspected.
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception
      'job_scheduled_at_for_user: caller cannot inspect another user'
      using errcode = '42501';
  end if;

  return case
    when coalesce(
           (select subscription_tier
              from user_profiles
             where id = p_user_id),
           'free'
         ) in ('pro', 'lifetime')
    then now()
    else now() + interval '30 seconds'
  end;
end;
$$;

-- Re-issue the same grants. 20260730_001 already revoked from public
-- + granted to authenticated + service_role; keep that.
revoke execute on function job_scheduled_at_for_user(uuid) from public;
grant execute on function job_scheduled_at_for_user(uuid) to authenticated, service_role;
