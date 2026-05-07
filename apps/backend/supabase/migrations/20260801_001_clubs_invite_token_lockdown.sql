-- /audit/all High: `clubs.invite_token` was returned by every `select *` from
-- the `clubs` table for any caller who could read a club row. The
-- `"public clubs are readable by anyone"` RLS policy applies to anon as
-- well as authenticated, so any anon caller could enumerate every public
-- club's invite token via
--   GET /rest/v1/clubs?is_public=eq.true&select=invite_token
-- and join an invite-only club via `join_club_by_token`, defeating
-- `join_policy = 'invite'` entirely.
--
-- Same shape as `20260707_001_user_profiles_column_lockdown.sql`: revoke
-- the table-level SELECT for anon + authenticated, then re-grant SELECT
-- on every column EXCEPT `invite_token`. Service role keeps full access
-- via its own grants, so server-side code (Edge Functions, admin scripts,
-- migrations) is unaffected.
--
-- Admin reads of `invite_token` go through a SECURITY DEFINER RPC
-- (`get_club_invite_token`) that gates on `is_club_admin`. Mirrors the
-- `get_my_profile()` pattern from `20260707_001`. Writes
-- (`createClub` insert, `regenerateInviteToken` update) are unaffected:
-- the writer already has the new token in client memory, and PostgREST
-- doesn't require column-level SELECT to perform an UPDATE/INSERT.
--
-- New columns added to `clubs` will be deny-by-default for anon +
-- authenticated; if a future column is meant to be cross-user readable,
-- this migration must be amended.

revoke select on clubs from authenticated, anon;

grant select (
  id,
  owner_id,
  name,
  slug,
  description,
  avatar_url,
  location_label,
  is_public,
  join_policy,
  created_at,
  updated_at
) on clubs to authenticated, anon;

create or replace function get_club_invite_token(target_club uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when is_club_admin(target_club) then (
      select invite_token from clubs where id = target_club
    )
    else null
  end;
$$;

revoke execute on function get_club_invite_token(uuid) from public;
grant execute on function get_club_invite_token(uuid) to authenticated;
