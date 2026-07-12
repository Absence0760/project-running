-- Make the RevenueCat tier write monotonic against out-of-order delivery.
--
-- The webhook's replay defence (webhook_events insert-first dedupe,
-- 20260623_001) only rejects the SAME event.id twice. It does nothing
-- against two DISTINCT events delivered out of order, and RevenueCat does
-- not guarantee delivery ordering. With the 7-day freshness window an old
-- EXPIRATION stays "fresh" long after a newer re-subscribe:
--
--   1. Pro sub lapses            → EXPIRATION E1 (event ts T1)
--   2. User re-subscribes minutes later → RENEWAL/INITIAL_PURCHASE (ts T2 > T1)
--   3. Delivery reorders: the RENEWAL arrives first → tier 'pro'
--   4. E1 arrives second (distinct id, age < 7d → passes freshness + dedupe)
--      → mapEventToTier('EXPIRATION', …) = 'free' → the paying user is
--      silently downgraded and stays there until the next RENEWAL fires.
--
-- Fix: record the driving event's timestamp alongside the tier, and gate
-- the tier write on it — a tier change is applied only when its event is
-- at least as recent as the event that last moved the tier. The webhook
-- does this atomically (a conditional UPDATE … where tier_updated_event_ts
-- is null or <= incoming), so a stale deactivation matches zero rows and
-- leaves the tier alone. Epoch-milliseconds bigint mirrors RevenueCat's
-- `event_timestamp_ms` exactly (no timezone / sub-ms rounding in the
-- comparison).

alter table user_profiles
  add column tier_updated_event_ts bigint;

comment on column user_profiles.tier_updated_event_ts is
  'RevenueCat event_timestamp_ms (epoch ms) of the event that last moved subscription_tier. The webhook only applies a tier change when the incoming event is >= this, so an out-of-order deactivation cannot downgrade a re-subscribed user.';

-- Lock the new column against user-JWT writes exactly like the tier it
-- guards: a user who could stamp a far-future timestamp on their own row
-- (without touching subscription_tier, so the existing guard wouldn't
-- fire) would freeze out every later EXPIRATION and keep 'pro' forever.
-- Re-emit the COMPLETE latest body (20261112_001) with the extra column
-- check — per the "bare CREATE OR REPLACE strips prior fixes" gotcha, NOT
-- a rewrite from scratch.
create or replace function lock_subscription_columns()
returns trigger
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
  -- Trusted callers (unchanged from 20261107_001):
  --   * REST service role — by JWT role, the only in-band signal inside
  --     a SECURITY DEFINER function (current_user is masked to owner).
  --   * Genuine direct-SQL (migrations + seed) — empty role claim AND a
  --     privileged session_user. PostgREST authenticates every request
  --     as the `authenticator` login role, so an end-user request can
  --     never present session_user=postgres.
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;

  if old.subscription_tier is distinct from new.subscription_tier then
    raise exception 'subscription_tier is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  if old.subscription_at is distinct from new.subscription_at then
    raise exception 'subscription_at is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  if old.billing_issue_at is distinct from new.billing_issue_at then
    raise exception 'billing_issue_at is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  if old.tier_updated_event_ts is distinct from new.tier_updated_event_ts then
    raise exception 'tier_updated_event_ts is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
