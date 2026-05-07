-- /audit/all Low (public-rows): `user_profiles.preferred_unit` is in
-- the cross-user re-grant from 20260707_001 but is never read on a
-- cross-user surface. Self-reads go through `get_my_profile()`
-- (SECURITY DEFINER, returns the full row regardless of grant).
-- Cross-user surfaces (`/u/[id]`, feed cards, comment author strips,
-- club rosters) all enumerate only `id, display_name, avatar_url`.
--
-- Dropping `preferred_unit` from the cross-user re-grant:
--   - removes the localisation reconnaissance surface (km/mi telegraphs
--     a rough region — UK/AUS/NZ/CA vs US),
--   - keeps the door shut for future column extensions (preferred_unit
--     is the precedent for "small display preference" — without this
--     fix, adding `preferred_timezone` or `preferred_language` would
--     just inherit the cross-user grant),
--   - costs nothing: every reader of preferred_unit on the calling
--     user goes via auth.svelte.ts → get_my_profile.
--
-- Re-grant is cumulative — we have to revoke + re-grant the narrow
-- column list to drop a single column.

revoke select on user_profiles from authenticated, anon;

grant select (
  id,
  display_name,
  avatar_url,
  created_at
) on user_profiles to authenticated, anon;
