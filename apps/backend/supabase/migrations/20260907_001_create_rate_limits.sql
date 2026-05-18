-- Anti-spam phase 2: soft rate-limits on row creates.
--
-- The search-scalability audit flagged that without create-rate-
-- limits, a single user account can mass-create clubs or routes and
-- flood every Browse / Explore page. Phase 1 (20260906_001) deferred
-- low-reputation rows in the search ORDER BY; this phase prevents
-- them from being created in bulk in the first place.
--
-- We reuse the existing rate-limit infrastructure
-- (rate_limits table + check_rate_limit RPC, migrations 20260604_001
-- + 20260614_001 + 20260616_001) rather than rolling a parallel
-- counter. Each trigger calls check_rate_limit for a per-resource
-- bucket; on `allowed = false` the trigger raises so the INSERT
-- aborts before the row lands.
--
-- Thresholds are intentionally generous — a human creating a few
-- clubs or routes a day will never hit them. They're a ceiling for
-- automated abuse, not a UX gate.
--
--   * `create_club`  — 5 / hour   (a runner won't legitimately create
--                                  more than a handful of clubs in
--                                  one session)
--   * `create_route` — 30 / hour  (bulk import via ImportRoute
--                                  legitimately creates ~10-30 at
--                                  once when a user uploads a Strava
--                                  /Garmin zip; the next zip is rare
--                                  in the same hour)
--
-- When a user hits the cap, PostgREST surfaces the raised exception
-- as a 500. That's not ideal UX — the client will show a generic
-- "Failed to create" — but it's a soft ceiling: cap is per-user, no
-- locks, and the count resets at the next fixed window boundary. A
-- follow-up could intercept the SQLSTATE in data.ts and surface a
-- "Slow down — try again in a few minutes" toast.

create or replace function enforce_create_rate_limit(
  p_bucket text,
  p_user_id uuid,
  p_max integer,
  p_window_seconds integer
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
  v_allowed boolean;
  v_retry integer;
begin
  -- Three skip cases:
  --   1. service_role — admin tooling / Edge Functions writing on a
  --      user's behalf shouldn't get throttled by their own queue.
  --   2. No auth context at all (auth.uid() IS NULL) — direct SQL,
  --      migrations, seed.sql. These are trusted by definition; if
  --      they weren't, the underlying row-level grants would already
  --      have rejected the INSERT before this trigger fired.
  --   3. Caller is not the row owner (auth.uid() <> p_user_id) — a
  --      forged INSERT under another user_id. We MUST NOT raise our
  --      own P0001 here; the existing RLS WITH CHECK policy rejects
  --      forges with 42501, and the rls_clubs / rls_routes pgtap
  --      suites assert that errcode. Beating RLS to the punch with
  --      a different error mis-classifies the attack and breaks
  --      those guards.
  --
  -- The existing check_rate_limit guard on auth.uid() <> p_user_id
  -- raises 'not authorized' under both (1) and (2) without these
  -- short-circuits, which is what broke seed.sql on first land.
  if v_role = 'service_role' then return; end if;
  if auth.uid() is null then return; end if;
  if auth.uid() is distinct from p_user_id then return; end if;

  select allowed, retry_after_seconds
    into v_allowed, v_retry
  from check_rate_limit(p_user_id, p_bucket, p_max, p_window_seconds);

  if not v_allowed then
    raise exception 'rate limit exceeded for %, retry in %s', p_bucket, v_retry
      using errcode = 'P0001',
            hint = 'You are creating these too quickly. Please wait and try again.';
  end if;
end;
$$;

revoke execute on function enforce_create_rate_limit(text, uuid, integer, integer) from public;

-- ─── clubs ───
create or replace function clubs_create_rate_limit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform enforce_create_rate_limit('create_club', new.owner_id, 5, 3600);
  return new;
end;
$$;

create trigger clubs_enforce_create_rate_limit
  before insert on clubs
  for each row
  execute function clubs_create_rate_limit_trigger();

-- ─── routes ───
create or replace function routes_create_rate_limit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform enforce_create_rate_limit('create_route', new.user_id, 30, 3600);
  return new;
end;
$$;

create trigger routes_enforce_create_rate_limit
  before insert on routes
  for each row
  execute function routes_create_rate_limit_trigger();
