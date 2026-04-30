-- Tier-aware rate limiting on Edge Function endpoints.
--
-- Roadmap Phase 3 "Tier-aware rate-limiting on Edge Functions / Go
-- service so the *priority processing* bullet has concrete enforcement
-- beyond the coach-cap bypass."
--
-- The free-tier `check_rate_limit` from migration 20260604_001 takes
-- a single `max` parameter; this adds a sibling helper that picks
-- between two ceilings based on `user_profiles.subscription_tier`.
-- Single SQL round-trip instead of "fetch tier from JS, then call
-- check_rate_limit with the right max" so EF latency stays constant.

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
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_count integer;
  v_tier text;
  v_max integer;
begin
  if p_free_max <= 0 or p_pro_max <= 0 or p_window_seconds <= 0 then
    raise exception 'check_rate_limit_tiered: free_max, pro_max, window must be positive';
  end if;

  -- Resolve tier. Missing profile or unknown value defaults to 'free'
  -- — the conservative choice. The webhook keeps user_profiles in
  -- sync with RevenueCat, so 'free' for an actual paying user means
  -- something is broken upstream and a stricter limit is the right
  -- way to surface it.
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

revoke all on function check_rate_limit_tiered(uuid, text, integer, integer, integer) from public;
grant execute on function check_rate_limit_tiered(uuid, text, integer, integer, integer)
  to authenticated, service_role;
