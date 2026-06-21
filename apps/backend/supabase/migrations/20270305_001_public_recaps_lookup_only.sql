-- public_recaps: remove the bulk-readable SELECT policy; expose a
-- lookup-by-id RPC instead.
--
-- Privacy-zones quality round finding. The original table (migration
-- 20270207_001) gated SELECT with `using (true)`, with a comment
-- claiming "the uuid in the share link IS the capability token. There
-- is no enumeration surface beyond an already-known id." That claim was
-- factually wrong: PostgREST exposes the table with full filter +
-- pagination, so an anon caller could
--   GET /rest/v1/public_recaps?select=user_id,period_key,snapshot&limit=1000&offset=N
-- and harvest every user who published a recap — their identifier, the
-- period, and the frozen `snapshot` jsonb (which carries schedule
-- signals like earliestStartLocal / latestStartLocal). Same class of
-- leak the public_profiles view had (fixed in 20261011_001).
--
-- GDPR posture (mirrors 20261011_001):
--   Art 5(1)(c) — minimisation: the stated purpose (render a share page
--     + og:image for a viewer who already has the link) needs
--     lookup-by-known-uuid, not full-table SELECT.
--   Art 6 — lawful basis: a user who published one recap has no basis
--     for their identifier being anon-enumerable in bulk alongside
--     every other publisher.
--
-- Fix:
--   1. Add a SECURITY DEFINER RPC `public_recap_by_id(p_id uuid)` that
--      returns the share-page columns for ONE explicit id — no filter /
--      order / pagination surface.
--   2. Drop the `using (true)` SELECT policy so the bare table is no
--      longer anon/authenticated-readable. The owner FULL policy
--      (auth.uid() = user_id) stays, so owner read/publish/revoke and
--      the publishRecap upsert are unchanged.
--
-- Callers updated in the same change: fetchPublicRecap (web data.ts) and
-- lookupSharedRecap (web dev SSR + the share-recap Lambda) switch from
-- `.from('public_recaps').select(...).eq('id', id)` to
-- `.rpc('public_recap_by_id', { p_id: id })`. The mobile client only
-- WRITES recaps (publishRecap upsert, owner-RLS) and links to the web
-- share page to read — no Dart reader to migrate.

create or replace function public_recap_by_id(p_id uuid)
returns table (
  id uuid,
  user_id uuid,
  period_kind text,
  period_key text,
  snapshot jsonb
)
language sql
security definer
set search_path = public
stable
as $$
  select id, user_id, period_kind, period_key, snapshot
  from public_recaps
  where id = p_id;
$$;

revoke all on function public_recap_by_id(uuid) from public;
grant execute on function public_recap_by_id(uuid) to anon, authenticated;

-- Drop the bulk-readable SELECT policy. The owner CRUD policy
-- (public_recaps_owner) remains the only direct-table access; the share
-- audience reaches a row only through the RPC above.
drop policy if exists public_recaps_public_read on public_recaps;
