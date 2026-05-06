-- Bring `check_rate_limit` and `check_rate_limit_tiered` back in sync
-- with how PostgREST surfaces JWT claims today. Newer PostgREST
-- (since the `request.jwt.claim.<name>` deprecation) only sets the
-- JSON blob `request.jwt.claims`; the per-claim individual settings
-- (`request.jwt.claim.role`, `…sub`, etc.) are no longer populated.
--
-- The service-role bypass added in 20260616_001 reads
-- `request.jwt.claim.role` directly. On the local dev stack (and any
-- production stack on the same PostgREST baseline) that setting is
-- now empty, so `v_role <> 'service_role'` is always true and the
-- bypass never fires. The visible symptom: every fail-closed
-- Edge Function (`clip-public-track`, `delete-account`,
-- `export-data`) rejects ALL anon callers with HTTP 503 because the
-- IP-bucket rate-limit RPC raises 'not authorized' instead of
-- accepting the service-role-keyed admin call. Surfaced by the
-- e2e cross-user privacy-clipping test in
-- `apps/web/tests-e2e/cross-cutting/privacy-zones.spec.ts`.
--
-- Fix: read the role from BOTH sources via the same coalesce shape
-- the supabase-bundled `auth.role()` helper uses. Keeps backwards
-- compat with any deployment that DOES still set the legacy claim
-- (e.g. older PostgREST mid-rollout) while also working against the
-- current behaviour. No table or signature changes; pure function-
-- body update so no codegen impact.

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
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
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
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
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
