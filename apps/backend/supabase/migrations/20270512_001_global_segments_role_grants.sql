-- The global / famous-segment catalogue tables ship with NO client grants,
-- so the entire feature is unreachable from web + mobile.
--
-- `20270408_001_restore_role_grant_matrix.sql` made the public-schema grant
-- matrix explicit precisely because Supabase's implicit default privileges
-- can no longer be relied on: the `postgres`-owned default ACL for tables in
-- `public` is `anon=Dxtm / authenticated=Dxtm / service_role=Dxtm` — TRUNCATE,
-- REFERENCES, TRIGGER, MAINTAIN, and none of SELECT/INSERT/UPDATE/DELETE. From
-- that migration on, a new table only gets a client-usable surface if the
-- migration that creates it grants one.
--
-- `20270411_001_global_segments_catalogue.sql` (authored before the matrix
-- landed, merged after it) creates `global_segments` + `global_segment_efforts`
-- and grants EXECUTE on the two RPCs, but never grants the tables. They are the
-- only two public base tables in the schema with no DML grant for any app role,
-- so every direct client path 42501s:
--
--   * fetchGlobalSegments / fetchGlobalSegment          (select global_segments)
--   * fetchGlobalSegmentEffortsForRun                   (select global_segment_efforts)
--   * scoreRunAgainstGlobalSegments                     (upsert global_segment_efforts)
--   * global_segment_effort_ranks                       (invoker-rights SQL fn)
--
-- Only `global_segment_leaderboard` works, because it is SECURITY DEFINER and
-- runs as the owner. It also breaks two pgtap suites at fixture setup:
-- `global_segments_test.sql` (42501 on the first seed insert) and the
-- `role_grant_matrix_test.sql` catch-all, which is the guard that was supposed
-- to catch exactly this and correctly reports these two tables today.
--
-- Fix: grant the surface each table's RLS policies were written against. RLS
-- stays the row-level gate; these grants only decide which verbs a role may
-- attempt at all. Unlike 20270408_001's uniform matrix (generated from a
-- pre-existing schema) this is scoped to the policy set:
--
--   global_segments        — world-readable while active, curator-only writes,
--                            so anon gets SELECT and only `authenticated`
--                            (where the admin allow-list lives) gets DML.
--   global_segment_efforts — readable when the segment is active and the run is
--                            visible; owner inserts + owner deletes, no UPDATE
--                            policy at all, so no UPDATE grant is issued.
--
-- service_role bypasses RLS but still needs grants — it gets the full surface
-- on both, matching every other table in the matrix.
--
-- No column changes, so no row-type regeneration is owed.

grant select on public.global_segments to anon;
grant select, insert, update, delete on public.global_segments to authenticated;
grant select, insert, update, delete on public.global_segments to service_role;

grant select on public.global_segment_efforts to anon;
grant select, insert, delete on public.global_segment_efforts to authenticated;
grant select, insert, update, delete on public.global_segment_efforts to service_role;
