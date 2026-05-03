-- Add service-role escape hatch to the rate-limit caller guards.
--
-- 20260614_001 prepended `auth.uid() is distinct from p_user_id`
-- to both check_rate_limit and check_rate_limit_tiered to close
-- a DoS vector (any authenticated user could drain a victim's
-- rate-limit window by passing the victim's id). The guard is
-- correct for user-context callers — every Edge Function today
-- forwards the caller's JWT, so auth.uid() resolves to the user.
--
-- The forward-compat gap: `auth.uid()` is null under service role
-- and `null is distinct from p_user_id` evaluates true, so a
-- future service-role consumer (cron-driven background sweep that
-- wants to debit a per-user bucket on the user's behalf) will hit
-- 'not authorized'. Copy the explicit role-check pattern that
-- get_integration_tokens / set_integration_tokens use
-- (20260603_001:82, :122) so the user-context lockdown stays
-- intact while service-role callers can act on any user_id.

create or replace function check_rate_limit(
  p_user_id uuid,
  p_bucket text,
  p_max integer,
  p_window_seconds integer
)
returns table (allowed boolean, retry_after_seconds integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_count integer;
begin
  if v_role <> 'service_role' and auth.uid() is distinct from p_user_id then
    raise exception 'check_rate_limit: not authorized';
  end if;

  if p_max <= 0 or p_window_seconds <= 0 then
    raise exception 'check_rate_limit: max and window must be positive';
  end if;

  v_window_start := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );
  v_window_end := v_window_start + make_interval(secs => p_window_seconds);

  insert into rate_limits (user_id, bucket, window_start, count)
    values (p_user_id, p_bucket, v_window_start, 1)
    on conflict (user_id, bucket, window_start) do update
      set count = rate_limits.count + 1
    returning rate_limits.count into v_count;

  if v_count > p_max then
    return query
      select false, greatest(1, ceil(extract(epoch from v_window_end - now()))::integer);
  else
    return query select true, 0;
  end if;
end;
$$;

create or replace function check_rate_limit_tiered(
  p_user_id uuid,
  p_bucket text,
  p_free_max integer,
  p_pro_max integer,
  p_window_seconds integer
)
returns table (allowed boolean, retry_after_seconds integer, tier text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_count integer;
  v_tier text;
  v_max integer;
begin
  if v_role <> 'service_role' and auth.uid() is distinct from p_user_id then
    raise exception 'check_rate_limit_tiered: not authorized';
  end if;

  if p_free_max <= 0 or p_pro_max <= 0 or p_window_seconds <= 0 then
    raise exception 'check_rate_limit_tiered: free_max, pro_max, window must be positive';
  end if;

  select coalesce(subscription_tier, 'free') into v_tier
    from user_profiles where id = p_user_id;
  v_tier := coalesce(v_tier, 'free');

  v_max := case when v_tier in ('pro', 'lifetime') then p_pro_max else p_free_max end;

  v_window_start := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );
  v_window_end := v_window_start + make_interval(secs => p_window_seconds);

  insert into rate_limits (user_id, bucket, window_start, count)
    values (p_user_id, p_bucket, v_window_start, 1)
    on conflict (user_id, bucket, window_start) do update
      set count = rate_limits.count + 1
    returning rate_limits.count into v_count;

  if v_count > v_max then
    return query
      select false, greatest(1, ceil(extract(epoch from v_window_end - now()))::integer), v_tier;
  else
    return query select true, 0, v_tier;
  end if;
end;
$$;
