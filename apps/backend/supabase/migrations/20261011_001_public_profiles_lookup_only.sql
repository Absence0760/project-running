-- public_profiles: revoke anon SELECT on the view; expose a
-- lookup-by-id RPC instead.
--
-- Persona-hunt Round 3 finding Privacy-Conscious #1. Pre-fix the
-- `public_profiles` view (migration 20260824_001) granted SELECT to
-- anon AND authenticated. PostgREST exposes the view with full
-- filter + pagination, so an anon caller could
--   GET /rest/v1/public_profiles?select=*&limit=1000&offset=N
-- and harvest every user's display_name + avatar_url in bulk —
-- regardless of whether the user ever published a public run. The
-- migration's own "Anti-enumeration" comment was factually wrong:
-- PostgREST treats views identically to tables, and lookup-by-known-
-- uuid was never enforced.
--
-- GDPR posture:
--   Art 5(1)(c) — minimisation: the stated purpose (bake display_
--     name into share-page unfurls) needs lookup-by-known-uuid, not
--     full-table SELECT.
--   Art 6 — lawful basis: users who never opted into a public surface
--     (no public_runs / public_routes row) have no basis for their
--     identifier being anon-readable in bulk.
--
-- Fix:
--   1. Replace anon SELECT on the view with a SECURITY DEFINER RPC
--      `public_profile_by_id(p_id uuid)` that returns the same two
--      columns but ONLY for an explicit known id — no filter / order
--      / pagination surface.
--   2. Revoke the anon grant on the view.
--   3. The view itself stays for `authenticated` callers (they could
--      already read user_profiles via the owner RLS; the view is just
--      a convenience projection).
--
-- Callers updated in the same change: share_run_lookup.ts (web dev
-- + share-run Lambda) and live/[id]/+page.svelte both switch from
-- `.from('public_profiles').select(...)` to
-- `.rpc('public_profile_by_id', {p_id: uid})`.

create or replace function public_profile_by_id(p_id uuid)
returns table (
  id uuid,
  display_name text,
  avatar_url text
)
language sql
security definer
set search_path = public
stable
as $$
  select id, display_name, avatar_url
  from user_profiles
  where id = p_id;
$$;

revoke all on function public_profile_by_id(uuid) from public;
grant execute on function public_profile_by_id(uuid) to anon, authenticated;

-- Revoke anon's bulk-readable grant on the view. authenticated keeps
-- its grant (anon-equivalent gain is nil — authenticated users can
-- already read user_profiles via owner-RLS for their own row, and
-- the view is now redundant with the RPC for everything else).
revoke select on public_profiles from anon;
