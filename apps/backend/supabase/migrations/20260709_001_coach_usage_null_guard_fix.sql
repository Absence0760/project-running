-- RLS audit High: increment_coach_usage and get_coach_usage check
-- `auth.uid() != p_user_id`, which evaluates to NULL (falsy) for an
-- anon-role caller because `null != <uuid>` returns NULL in three-valued
-- logic. The guard silently passes for unauthenticated callers.
--
-- Currently the EXECUTE grants only target `authenticated` (set in
-- `20260430_001_coach_usage.sql`), so this is not directly reachable from
-- an anon JWT today. But the guard is semantically broken — any future
-- grant extension to `anon`, or any path that reaches the function via a
-- service-role context with no JWT, would silently bypass it.
--
-- Fix: rewrite the guard with `is null or is distinct from`, mirroring the
-- service-role-aware pattern in `check_rate_limit` /
-- `check_rate_limit_tiered` after their `20260616_001` hardening. Service
-- role is allowed to call on behalf of any user (RevenueCat webhook
-- bookkeeping, admin scripts); other roles must match `p_user_id`.

create or replace function increment_coach_usage(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
begin
  if v_role <> 'service_role' and (auth.uid() is null or auth.uid() is distinct from p_user_id) then
    raise exception 'increment_coach_usage: not authorized';
  end if;
  insert into user_coach_usage (user_id, usage_date, message_count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, usage_date) do update
    set message_count = user_coach_usage.message_count + 1
  returning message_count into v_count;
  return v_count;
end;
$$;

create or replace function get_coach_usage(p_user_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
begin
  if v_role <> 'service_role' and (auth.uid() is null or auth.uid() is distinct from p_user_id) then
    raise exception 'get_coach_usage: not authorized';
  end if;
  return coalesce(
    (select message_count from user_coach_usage
     where user_id = p_user_id and usage_date = current_date),
    0
  );
end;
$$;
