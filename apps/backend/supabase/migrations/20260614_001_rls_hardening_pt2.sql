-- RLS hardening pt 2 — closes the three Medium-severity findings
-- from /audit/rls that pt 1 (20260613_001) didn't cover:
--
-- 1. check_rate_limit + check_rate_limit_tiered are SECURITY DEFINER,
--    granted to `authenticated`, and accept p_user_id without
--    verifying it matches auth.uid(). An authenticated attacker can
--    drain a victim's per-EF rate window by passing the victim's id.
--    Same footgun closed for increment_coach_usage / get_coach_usage
--    in 20260503_001 — apply the identical guard.
--
-- 2. "club admins write club routes" on routes is `for all using
--    (...)` with no explicit `with check`. USING is reused as WITH
--    CHECK for INSERT, but the rule doesn't constrain user_id, so
--    an admin can INSERT a club route attributing user_id to any
--    user. Split the `for all` into INSERT (constrained to
--    user_id = auth.uid()) plus UPDATE / DELETE (existing relaxed
--    rule preserved — admins legitimately need write on routes
--    owned by other club members).
--
-- 3. "club admins write club templates" on training_plans has the
--    identical shape and the identical forgery vector. Same split.

-- ─────────────────── check_rate_limit (4-arg) ───────────────────

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
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_count integer;
begin
  if auth.uid() is distinct from p_user_id then
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

-- ─────────────────── check_rate_limit_tiered (5-arg) ───────────────────

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
  if auth.uid() is distinct from p_user_id then
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

-- ─────────────────── routes — split admin write policy ───────────────────

drop policy if exists "club admins write club routes" on routes;

create policy "club admins insert club routes"
  on routes for insert
  with check (
    club_id is not null
    and is_club_admin(club_id)
    and user_id = auth.uid()
  );

create policy "club admins update club routes"
  on routes for update
  using (
    club_id is not null
    and is_club_admin(club_id)
  )
  with check (
    club_id is not null
    and is_club_admin(club_id)
  );

create policy "club admins delete club routes"
  on routes for delete
  using (
    club_id is not null
    and is_club_admin(club_id)
  );

-- ─────────────────── training_plans — split admin write policy ───────────────────

drop policy if exists "club admins write club templates" on training_plans;

create policy "club admins insert club templates"
  on training_plans for insert
  with check (
    is_template = true
    and club_id is not null
    and is_club_admin(club_id)
    and user_id = auth.uid()
  );

create policy "club admins update club templates"
  on training_plans for update
  using (
    is_template = true
    and club_id is not null
    and is_club_admin(club_id)
  )
  with check (
    is_template = true
    and club_id is not null
    and is_club_admin(club_id)
  );

create policy "club admins delete club templates"
  on training_plans for delete
  using (
    is_template = true
    and club_id is not null
    and is_club_admin(club_id)
  );
