-- Subscription tier enforcement. The column already exists as
-- `user_profiles.subscription_tier text default 'free'` with no CHECK.
-- This migration adds the constraint + a helper function that gated
-- endpoints (Edge Functions, the coach endpoint, etc.) can call to
-- verify a user's tier before proceeding.
--
-- Tiers:
--   free     → default; gets the core feature set
--   pro      → monthly/annual paid; unlocks gated features
--   lifetime → one-time purchase; same as pro, never expires
--
-- The old `premium` value from the client type overlay is aliased to
-- `pro` by updating any existing rows.

update user_profiles set subscription_tier = 'pro' where subscription_tier = 'premium';

alter table user_profiles
  add constraint user_profiles_subscription_tier_check
  check (subscription_tier in ('free', 'pro', 'lifetime'));

-- Helper: does the current user have a paid tier?
create or replace function is_pro()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from user_profiles
    where id = auth.uid()
      and subscription_tier in ('pro', 'lifetime')
  );
$$;

grant execute on function is_pro() to authenticated;

-- Helper: does a specific user have a paid tier? Used by the coach
-- endpoint which authenticates via JWT but doesn't run in an RLS
-- context (it's a server-side function).
create or replace function is_user_pro(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from user_profiles
    where id = p_user_id
      and subscription_tier in ('pro', 'lifetime')
  );
$$;

grant execute on function is_user_pro(uuid) to authenticated;

-- RevenueCat webhook writes. The receiver Edge Function runs with the
-- service role and needs to update subscription_tier for any user.
-- This is already permitted by the service role (bypasses RLS), so no
-- additional policy is needed — just documenting the contract.
