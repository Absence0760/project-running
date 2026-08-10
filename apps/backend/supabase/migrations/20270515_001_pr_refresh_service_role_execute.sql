-- `service_role` cannot execute `refresh_personal_records_for_user`, so the
-- function's own service-role branch is unreachable dead code.
--
-- `20260802_001` tightened the grant with `revoke execute … from public, anon`
-- followed by a targeted `grant … to authenticated`. The intent named in that
-- migration is "not anon, not the world" — but `service_role` held EXECUTE only
-- through `PUBLIC`, so the revoke took it away as collateral, and the two later
-- re-emissions (`20260904_001`, `20261009_001`) copied the same pair forward.
--
-- The function still carries the branch that is supposed to serve that caller:
--
--   if v_role <> 'service_role' and v_role <> '' then … raise 42501 … end if;
--
-- and `rls_pr_refresh_null_guard_test.sql` opens by asserting the path works
-- ("service-role context refreshes another user PB cache (trigger / seed
-- path)"). It does not: the call is rejected at the EXECUTE-grant layer with
-- `42501 permission denied for function refresh_personal_records_for_user`
-- before the body runs, which aborts the whole pgtap file at its first
-- assertion. Either the branch or the grant is wrong, and the test says the
-- grant.
--
-- No escalation: `service_role` already bypasses RLS and has full DML on both
-- `personal_records` and `runs`, so it can already produce any cache state by
-- hand. The grant only lets it produce the CORRECT one — the recompute the
-- derived_state.md contract defines. `authenticated` keeps its own-user-only
-- guard; `public` and `anon` stay revoked.
--
-- Restated in full rather than as a bare grant so the revoke half travels with
-- it and a future re-emission has one line to copy.

revoke execute on function refresh_personal_records_for_user(uuid) from public, anon;
grant execute on function refresh_personal_records_for_user(uuid) to authenticated;
grant execute on function refresh_personal_records_for_user(uuid) to service_role;
