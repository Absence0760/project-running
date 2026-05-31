-- audit-findings 2026-05-30 Low [security/rls] regression pin.
--
-- is_blocked_either_way must not be EXECUTE-able by anon (20261108_001
-- revoked the default anon grant) so an unauthenticated caller can't
-- probe block relationships. Assert the grant state rather than invoking
-- — SECURITY DEFINER functions called by an under-privileged role can
-- segfault the local dev Postgres image, and the ACL check is the more
-- direct pin anyway. authenticated keeps its grant (the real caller, in
-- block_user / user_blocks flows, is signed-in).

begin;

select plan(2);

select ok(
  not has_function_privilege('anon', 'public.is_blocked_either_way(uuid, uuid)', 'EXECUTE'),
  'anon cannot EXECUTE is_blocked_either_way'
);
select ok(
  has_function_privilege('authenticated', 'public.is_blocked_either_way(uuid, uuid)', 'EXECUTE'),
  'authenticated retains EXECUTE on is_blocked_either_way'
);

select * from finish();
rollback;
