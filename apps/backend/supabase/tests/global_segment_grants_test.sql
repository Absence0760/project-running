-- Pins migration 20270512_001 (role grants for the global/famous-segment
-- catalogue tables).
--
-- 20270411_001 created `global_segments` + `global_segment_efforts` without any
-- table grants, three days after 20270408_001 established that the grant matrix
-- must be explicit (the postgres-owned default ACL for public tables carries no
-- SELECT/INSERT/UPDATE/DELETE). Every direct client read/write on the catalogue
-- 42501'd, and only the SECURITY DEFINER leaderboard RPC still worked.
--
--   1. The per-table grants the RLS policies were written against.
--   2. No UPDATE grant leaks onto global_segment_efforts — it has no UPDATE
--      policy, so the verb should not be reachable at all.
--   3. Catch-all: every public base table except the deliberately
--      service_role-only pair must be writable by `service_role`. The existing
--      role_grant_matrix_test catch-all only covers READS by `authenticated`,
--      so a table shipped with zero grants at all (this incident) is caught
--      here on the write side too.
--   4. Functional end-to-end: an anon caller really can read an active
--      catalogue segment (grant + policy compose).
--   5. Both rank RPCs are reachable by anon — the EXECUTE grant AND the
--      functions their SECURITY INVOKER bodies name (20270609_001).

begin;

select plan(16);

-- (1) global_segments — anon reads, authenticated (where the admin allow-list
--     lives) gets the curator DML surface.
select ok(
  has_table_privilege('anon', 'public.global_segments', 'SELECT'),
  'anon has SELECT on global_segments (world-readable catalogue)'
);
select ok(
  has_table_privilege('authenticated', 'public.global_segments', 'SELECT')
    and has_table_privilege('authenticated', 'public.global_segments', 'INSERT')
    and has_table_privilege('authenticated', 'public.global_segments', 'UPDATE')
    and has_table_privilege('authenticated', 'public.global_segments', 'DELETE'),
  'authenticated has the full curator DML surface on global_segments'
);
select ok(
  has_table_privilege('service_role', 'public.global_segments', 'SELECT')
    and has_table_privilege('service_role', 'public.global_segments', 'INSERT')
    and has_table_privilege('service_role', 'public.global_segments', 'UPDATE')
    and has_table_privilege('service_role', 'public.global_segments', 'DELETE'),
  'service_role has full DML on global_segments (seed + curation)'
);

-- (2) global_segment_efforts — read + owner insert/delete only.
select ok(
  has_table_privilege('anon', 'public.global_segment_efforts', 'SELECT'),
  'anon has SELECT on global_segment_efforts'
);
select ok(
  has_table_privilege('authenticated', 'public.global_segment_efforts', 'SELECT')
    and has_table_privilege('authenticated', 'public.global_segment_efforts', 'INSERT')
    and has_table_privilege('authenticated', 'public.global_segment_efforts', 'DELETE'),
  'authenticated can read, score, and rescind catalogue efforts'
);
select ok(
  not has_table_privilege('authenticated', 'public.global_segment_efforts', 'UPDATE'),
  'authenticated has NO UPDATE on global_segment_efforts — there is no UPDATE '
  'policy, so the verb stays unreachable'
);
select ok(
  has_table_privilege('service_role', 'public.global_segment_efforts', 'SELECT')
    and has_table_privilege('service_role', 'public.global_segment_efforts', 'INSERT')
    and has_table_privilege('service_role', 'public.global_segment_efforts', 'UPDATE')
    and has_table_privilege('service_role', 'public.global_segment_efforts', 'DELETE'),
  'service_role has full DML on global_segment_efforts'
);

-- (3) Catch-all on the write side. app_quota + deletion_audit_log are the
--     documented service_role-only tables, and they DO have service_role DML —
--     so nothing is exempt here.
select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
     where c.relkind = 'r'
       and not (has_table_privilege('service_role', c.oid, 'SELECT')
                and has_table_privilege('service_role', c.oid, 'INSERT')
                and has_table_privilege('service_role', c.oid, 'UPDATE')
                and has_table_privilege('service_role', c.oid, 'DELETE'))),
  0,
  'every public base table carries full service_role DML — a table shipped '
  'with no grants at all fails HERE'
);

-- (4) Functional: the grant + the "active catalogue segments are
--     world-readable" policy actually compose for a logged-out caller.
insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('a2a2a2a2-0000-0000-0000-0000000000f1', 'Grant Probe Hill',
   '[{"lat":40.0,"lng":-73.0},{"lat":40.002,"lng":-73.0}]', 400, true),
  ('a2a2a2a2-0000-0000-0000-0000000000f2', 'Grant Probe Retired',
   '[{"lat":40.0,"lng":-73.0},{"lat":40.002,"lng":-73.0}]', 400, false);

set local role anon;
set local "request.jwt.claims" = '';
select results_eq(
  $$ select name from global_segments where id = 'a2a2a2a2-0000-0000-0000-0000000000f1' $$,
  $$ values ('Grant Probe Hill'::text) $$,
  'anon can actually SELECT an active catalogue segment through the grant'
);
select is_empty(
  $$ select id from global_segments where id = 'a2a2a2a2-0000-0000-0000-0000000000f2' $$,
  'the grant does not widen the policy — an inactive segment stays hidden'
);

reset role;

-- (5) Both rank RPCs must be answerable by a logged-out reader of a public run.
--     20270411_001 granted the catalogue twin to `authenticated` only while
--     20270512_001 granted `anon` SELECT on both catalogue tables, so anon got
--     the effort rows and 42501'd on the ranks over them. Both clients then
--     degraded that missing row to `#1`, painting a crown on every catalogue
--     chip for every anonymous visitor (decisions §746). Fixed by 20270609_001.
select ok(
  has_function_privilege('anon', 'public.global_segment_effort_ranks(uuid)', 'EXECUTE'),
  'anon can execute global_segment_effort_ranks — SECURITY INVOKER means it '
  'reads under the caller''s own RLS, so it asks only about rows anon may '
  'already SELECT'
);

-- The route-segment sibling has been anon+authenticated since 20261223_001.
-- The two answer the same question over two tables and must not disagree about
-- who may ask it — that divergence IS the defect above.
select ok(
  has_function_privilege('anon', 'public.global_segment_effort_ranks(uuid)', 'EXECUTE')
    = has_function_privilege('anon', 'public.segment_effort_ranks(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.global_segment_effort_ranks(uuid)', 'EXECUTE')
    = has_function_privilege('authenticated', 'public.segment_effort_ranks(uuid)', 'EXECUTE'),
  'the catalogue rank RPC and its route-segment sibling grant the same roles'
);

-- (6) The EXECUTE grant is necessary and not sufficient. Both bodies are
--     SECURITY INVOKER, so every function they NAME is ACL-checked against the
--     calling role — the principle 20270402000001 wrote down for this exact
--     function. 20270523_001 added `not is_blocked_either_way(auth.uid(), ...)`
--     to both, and 20261108_001 had revoked anon's EXECUTE on it, so an anon
--     caller was admitted into the body and then denied inside it. The
--     predicate is only evaluated once the rival subquery yields a row, so the
--     failure landed exactly on the efforts the runner had NOT won — which is
--     precisely where `?? 1` then drew the crown. Both now call
--     private.viewer_blocks, which anon may execute (20270402000001).
select ok(
  not has_function_privilege('anon', 'public.is_blocked_either_way(uuid,uuid)', 'EXECUTE'),
  'anon still has no EXECUTE on is_blocked_either_way — 20261108_001''s '
  'anti-oracle revoke stands; the fix routes around it, it does not undo it'
);
select ok(
  has_function_privilege('anon', 'private.viewer_blocks(uuid)', 'EXECUTE'),
  'anon can execute private.viewer_blocks — the definer wrapper both rank '
  'RPCs now name instead'
);
select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where p.proname in ('segment_effort_ranks', 'global_segment_effort_ranks')
      and pg_get_functiondef(p.oid) like '%is_blocked_either_way%'),
  0,
  'neither rank RPC names is_blocked_either_way directly — a SECURITY INVOKER '
  'body that does is unexecutable by anon whatever its EXECUTE grant says'
);
select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where p.proname in ('segment_effort_ranks', 'global_segment_effort_ranks')
      and pg_get_functiondef(p.oid) like '%viewer_blocks%'),
  2,
  'both rank RPCs apply the block filter through private.viewer_blocks'
);

select * from finish();
rollback;
