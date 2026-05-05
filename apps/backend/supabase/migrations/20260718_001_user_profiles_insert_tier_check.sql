-- Block self-INSERT of `subscription_tier = 'pro' / 'lifetime'` on
-- `user_profiles`.
--
-- Audit pass 2 finding: the `users insert own profile` policy from
-- `20260624_001_lock_subscription_tier_to_service_role.sql:45-48`
-- checks only `auth.uid() = id`. The CHECK constraint on
-- `subscription_tier` (`20260429_001_subscription_paywall.sql:19`)
-- accepts the literal value `'pro'`. The companion BEFORE-UPDATE
-- trigger `lock_subscription_columns` blocks subsequent UPDATEs but
-- does NOT fire on INSERT — so a freshly-registered user can
-- self-insert their own row with `subscription_tier = 'pro'` and
-- the trigger never gets a chance to enforce the read-only contract.
--
-- Fix: extend the existing INSERT policy's WITH CHECK to require the
-- inserted tier be `'free'` for non-service-role callers. Service
-- role can still insert any tier (used by the RevenueCat webhook
-- bookkeeping path).

drop policy if exists "users insert own profile" on user_profiles;

create policy "users insert own profile"
  on user_profiles for insert
  with check (
    auth.uid() = id
    and (
      coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role'
      or subscription_tier = 'free'
    )
  );
