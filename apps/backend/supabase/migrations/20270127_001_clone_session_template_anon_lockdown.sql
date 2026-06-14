-- Defence-in-depth: revoke EXECUTE on clone_session_template from anon.
--
-- 20270104_001 created clone_session_template (the session-planner P3
-- adopt RPC) and did `revoke execute ... from public` + `grant ... to
-- authenticated`. But Supabase's bootstrap installs DEFAULT PRIVILEGES
-- that grant EXECUTE on every new public-schema function to anon (and
-- authenticated, service_role) directly — so revoking only from PUBLIC
-- leaves anon's direct grant intact, and `has_function_privilege('anon',
-- …)` stays true. The sibling clone_plan_template hardening
-- (20260926_001) revokes from `public, anon` for exactly this reason.
--
-- Match that pattern so an unauthenticated caller cannot reach the
-- SECURITY DEFINER body. The RPC's own first line still raises on a null
-- auth.uid(); this closes the grant before the body ever runs.
-- Pinned by rls_social_audit_hardening_test.sql ("anon must NOT have
-- EXECUTE on clone_session_template").

revoke execute on function clone_session_template(uuid) from public, anon;
grant execute on function clone_session_template(uuid) to authenticated;
