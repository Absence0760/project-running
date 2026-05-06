-- RLS audit grant-hygiene cleanup. Three SECURITY DEFINER functions had
-- their EXECUTE grants left at the public-default in their original
-- migrations, opening unintended call surfaces:
--
-- 1. `is_route_visible_to(uuid, uuid)` (Medium, `20260628_001`) — granted
--    explicitly to authenticated and service_role but the public default
--    grant was never revoked, so anon callers get an existence oracle on
--    every route_id × user_id pair via the bare RPC.
--
-- 2. `recompute_event_ranks(uuid, timestamptz)` (Low, `20260615_001`) —
--    trigger-called only today, but grant-to-public means any future
--    EXECUTE-to-authenticated extension would let any user force a
--    rank recompute on any event.
--
-- 3. `privacy_distance_m` and `privacy_in_any_zone` (Low,
--    `20260523_001`) — pure helpers exposed alongside `clip_track_for_user`
--    with no independent security purpose. The Edge Function uses only
--    `clip_track_for_user`; the helpers don't need to be callable.

-- Revoke from anon explicitly: Postgres treats `public` (the default
-- role group meaning "all roles") and `anon` as independent grant
-- targets. Supabase pre-grants EXECUTE on every function in the
-- `public` schema to anon as a project-wide default; revoking from
-- `public` alone leaves the explicit anon grant intact (regression
-- caught by `rls_function_hygiene_test.sql` after this migration was
-- written). Same for recompute_event_ranks.
revoke execute on function is_route_visible_to(uuid, uuid) from public, anon;

revoke execute on function recompute_event_ranks(uuid, timestamptz) from public, anon;

revoke execute on function privacy_distance_m(float, float, float, float) from public, anon, authenticated;
revoke execute on function privacy_in_any_zone(float, float, jsonb) from public, anon, authenticated;
