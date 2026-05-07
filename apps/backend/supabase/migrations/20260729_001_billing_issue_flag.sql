-- Track when a Pro user's most recent renewal payment failed, so the
-- web app can show a "Update your card to keep Pro" banner without
-- demoting them to free during the store's grace period (~16 days
-- App Store, up to 30 days Play). RevenueCat fires `BILLING_ISSUE`
-- when a renewal charge fails but the entitlement is still active;
-- it then fires `RENEWAL` if the retry succeeds, or `EXPIRATION` /
-- `CANCELLATION` once the grace period exhausts.
--
-- Tier semantics today:
--   BILLING_ISSUE → mapEventToTier returns null (no tier change).
--                   This migration adds the flag write.
--   RENEWAL / UNCANCELLATION → tier flips back to pro AND flag clears
--                              (payment recovered).
--   EXPIRATION / CANCELLATION → tier flips to free AND flag clears
--                                (the payment story is over).
--
-- Why a timestamp not a boolean: `since when` lets the UI show
-- "your renewal failed N days ago — update your card before <date>"
-- and lets us age out a stuck flag (e.g. RC's webhook delivery for
-- the recovery event was lost). Boolean would be a one-bit
-- regression.
--
-- Locking: add the column to the lock_subscription_columns trigger
-- so non-service-role writers can't clear the flag from the client
-- to suppress the banner (a self-DoS but the user-data integrity
-- contract is the same as subscription_tier — RC is the only writer).
--
-- Read access: get_my_profile() (SECURITY DEFINER) returns the full
-- row, so the auth store reads the flag as part of the existing
-- profile-fetch round trip. No additional grant needed for direct
-- column SELECT — the column lockdown migration revoked the table
-- SELECT and re-granted only the public-safe columns; billing_issue_at
-- stays out of that grant on purpose (matches subscription_tier /
-- subscription_at).

alter table user_profiles
  add column billing_issue_at timestamptz;

-- Update the lock to also gate billing_issue_at. Same coalesce shape
-- as 20260727_001 (read role from both claim formats).
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
  if v_role = 'service_role' or v_role = '' then
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
  return new;
end;
$$;
