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

begin;

select plan(10);

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

select * from finish();
rollback;
