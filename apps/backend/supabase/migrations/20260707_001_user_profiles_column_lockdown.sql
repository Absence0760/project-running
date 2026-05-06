-- public-rows audit High: `user_profiles` SELECT policy was open to every
-- authenticated caller (`20260521_001_user_follows.sql`), exposing
-- `subscription_tier` (paywall reconnaissance — pre-launch this was harmless
-- but post `20260429_001` it's a billing discriminator) and `parkrun_number`
-- (a permanent real-world identity link). decisions.md §31 accepted the
-- broad-SELECT trade-off when those columns weren't sensitive; that
-- rationale is now stale.
--
-- Implementation note: the earlier shape of this migration was
--   `revoke select (subscription_tier, …) on user_profiles from authenticated, anon;`
-- That is a no-op when the role still has table-level SELECT (Postgres
-- uses the broadest grant). The correct shape — and the one applied
-- here — is to revoke the table-level SELECT for both anon and
-- authenticated, then re-grant SELECT only on the public-safe columns.
-- New columns added to this table will be deny-by-default for both
-- roles; if a future column is meant to be authenticated-readable, this
-- migration must be amended.
--
-- Self-read path: `get_my_profile()` SECURITY DEFINER RPC returns the
-- full self row (auth bootstrap, coach context, parkrun-import prefill,
-- backup export). Cross-user reads (display-name + avatar joins) keep
-- working because every existing caller already enumerates safe
-- columns; `select('*')` from these tables had no callers when this
-- was written.
--
-- Service role keeps full table access via its own grants — RevenueCat
-- webhooks, Edge Functions, and admin scripts continue working.

revoke select on user_profiles from authenticated, anon;

grant select (
  id,
  display_name,
  avatar_url,
  preferred_unit,
  created_at
) on user_profiles to authenticated, anon;

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
