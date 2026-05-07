-- /audit/all High: the "users insert own profile" INSERT policy from
-- 20260718_001 reads the JWT role via the legacy
-- `current_setting('request.jwt.claim.role', true)` form. Newer
-- PostgREST (since the per-claim individual-setting deprecation) only
-- populates the JSON blob `request.jwt.claims`. Same regression that
-- 20260726_001 (rate-limit) and 20260727_001 (lock_subscription_columns)
-- closed for their respective consumers.
--
-- Net effect on a stack on the new PostgREST baseline (including
-- local dev): the service-role escape hatch silently breaks. A
-- service-role caller (RevenueCat webhook bookkeeping, future admin
-- provisioning) attempting to INSERT a `subscription_tier = 'pro'`
-- bootstrap row gets a policy violation rather than the documented
-- pass-through. The user-facing INSERT path (auth.svelte.ts hardcodes
-- 'free') is unaffected because the second branch of the OR still
-- holds — but the documented service-role contract is broken.
--
-- Fix shape mirrors 20260727_001: read the role from BOTH sources
-- via a coalesce so backwards-compat holds on stacks that still set
-- the legacy claim. No behaviour change for user JWTs (same WITH
-- CHECK semantics for them).

drop policy if exists "users insert own profile" on user_profiles;

create policy "users insert own profile"
  on user_profiles for insert
  with check (
    auth.uid() = id
    and (
      coalesce(
        nullif(current_setting('request.jwt.claim.role', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
        ''
      ) = 'service_role'
      or subscription_tier = 'free'
    )
  );
