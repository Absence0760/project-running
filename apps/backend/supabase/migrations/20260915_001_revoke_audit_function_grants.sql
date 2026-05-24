-- audit/rls (May 2026) flagged two function grants that widened the
-- attack surface beyond the legitimate callers:
--
-- 1) clip_track_for_user(uuid, jsonb) was granted to `anon` in
--    20260523_001. The intended client entry point is the
--    `clip-public-track` Edge Function, which uses the service-role
--    key — it never needs the anon RPC grant. Letting an unauth'd
--    POSTREST caller hit the function directly lets a determined
--    attacker iteratively probe the clipping output to reconstruct
--    approximate privacy-zone geometry (the documented residual
--    risk in decisions §33 is widened by exactly this grant).
--
-- 2) auto_tag_default_gear() is a SECURITY DEFINER trigger function
--    granted `EXECUTE TO authenticated` in 20260901_001. Trigger
--    functions don't need any user-facing grant — they fire inside
--    a trigger context regardless. The grant lets any authenticated
--    caller invoke `select auto_tag_default_gear()` directly. It
--    returns null outside of a trigger (so no immediate exploit),
--    but it violates the "trigger functions are internal" contract
--    and is the kind of grant a future refactor accidentally relies
--    on. Defense-in-depth: drop it now.
--
-- Postgres grants EXECUTE TO PUBLIC by default when a function is
-- created, so revoking from anon/authenticated alone leaves them
-- with access via PUBLIC. We revoke from PUBLIC first and then
-- re-grant only the roles that legitimately need the function.

-- 1. clip_track_for_user: keep authenticated (in-DB callers with a
-- user JWT), drop anon (EF uses service_role).
revoke execute on function clip_track_for_user(uuid, jsonb) from public;
revoke execute on function clip_track_for_user(uuid, jsonb) from anon;
grant execute on function clip_track_for_user(uuid, jsonb) to authenticated, service_role;

-- 2. auto_tag_default_gear: trigger-only. Supabase's default-privilege
-- setup ships a grant to `anon` on every public function, so we have
-- to revoke from all three (public + anon + authenticated) to leave
-- only postgres + service_role with EXECUTE.
revoke execute on function auto_tag_default_gear() from public;
revoke execute on function auto_tag_default_gear() from anon;
revoke execute on function auto_tag_default_gear() from authenticated;
-- service_role still has it implicitly via the function owner; do not
-- re-grant to any user role.
