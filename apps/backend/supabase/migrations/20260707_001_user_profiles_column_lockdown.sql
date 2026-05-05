-- public-rows audit High: `user_profiles` SELECT policy was open to every
-- authenticated caller (`20260521_001_user_follows.sql`), exposing
-- `subscription_tier` (paywall reconnaissance — pre-launch this was harmless
-- but post `20260429_001` it's a billing discriminator) and `parkrun_number`
-- (a permanent real-world identity link). decisions.md §31 accepted the
-- broad-SELECT trade-off when those columns weren't sensitive; that
-- rationale is now stale.
--
-- Fix shape: keep the row-level cross-user SELECT (so existing display-name
-- joins continue to work) but use a column-level REVOKE to hide the three
-- sensitive columns from every authenticated caller, then add a
-- SECURITY DEFINER RPC that returns the full self row for paths that
-- need to read them (auth bootstrap, coach context, parkrun-import prefill).
--
-- Service role keeps full table access via its own grants — RevenueCat
-- webhooks, Edge Functions, and admin scripts continue working.

revoke select (subscription_tier, subscription_at, parkrun_number)
  on user_profiles from authenticated, anon;

create or replace function get_my_profile()
returns user_profiles
language sql
stable
security definer
set search_path = public
as $$
  select * from user_profiles where id = auth.uid();
$$;

revoke execute on function get_my_profile() from public;
grant execute on function get_my_profile() to authenticated;
