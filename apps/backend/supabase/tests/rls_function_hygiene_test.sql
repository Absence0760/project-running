-- Pin the function-grant + search_path hygiene closures from the
-- audit-pass low / medium findings. None of these were exploitable
-- gaps individually, but each is a cheap "fail closed" that catches
-- a class of future regression at no runtime cost.
--
-- Migrations covered:
--   20260710_001_database_functions_search_path.sql — pin
--     weekly_mileage + personal_records to `set search_path = public`.
--   20260711_001_function_execute_grant_cleanup.sql — revoke EXECUTE
--     from PUBLIC on `is_route_visible_to` and `recompute_event_ranks`
--     (and the privacy helpers; those are tested in
--     rls_privacy_clipping_test.sql).
--   20260713_001_is_run_visible_to_anon_grant.sql — restore the anon
--     grant that pass-1 dropped, breaking every social-affordance read
--     on /share/run/<id>.
--   20260812_001_is_run_visible_to_private_schema.sql — move
--     `is_run_visible_to` to the `private` schema (closes the
--     PostgREST RPC oracle without breaking the share page).
--   20260819_001_is_route_visible_to_private_schema.sql — same
--     pattern for `is_route_visible_to`, after 20260711_001's
--     anon revoke turned out to break anon SELECT on
--     `route_reviews` + `segments` (PG 17.6 manifested it as a
--     server SEGV instead of a clean 42501).
--
-- Coverage:
--   1. `weekly_mileage` and `personal_records` both pin search_path.
--   2. `public.is_route_visible_to` has been dropped (PostgREST RPC
--      oracle closed by 20260819_001).
--   3. `private.is_route_visible_to` IS executable by anon (every
--      dependent policy on `route_reviews` + `segments` calls it
--      from anon-reachable SELECT predicates).
--   4. `private.is_run_visible_to` IS executable by anon (Pass-2
--      fix — anonymous /share/run/<id> visitors need it for kudos
--      / comments / photos / segment efforts / live pings).
--   5. `public.is_run_visible_to` has been dropped.
--   6/7. `recompute_event_ranks` grants.

begin;

select plan(9);

-- 1. weekly_mileage has search_path = public pinned.
select results_eq(
  $$ select 'set search_path' = any(p.proconfig) or
            'search_path' = any(string_to_array(
              regexp_replace(
                array_to_string(coalesce(p.proconfig, '{}'::text[]), ','),
                '=.*', ''
              ), ','
            ))
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'weekly_mileage' $$,
  $$ values (true) $$,
  'weekly_mileage pins search_path'
);

-- 2. personal_records has search_path = public pinned.
select results_eq(
  $$ select 'search_path' = any(string_to_array(
              regexp_replace(
                array_to_string(coalesce(p.proconfig, '{}'::text[]), ','),
                '=.*', ''
              ), ','
            ))
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'personal_records' $$,
  $$ values (true) $$,
  'personal_records pins search_path'
);

-- 3. public.is_route_visible_to has been dropped (PostgREST RPC
--    oracle closed by 20260819_001 — the function lives in the
--    `private` schema now).
select ok(
  not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'is_route_visible_to'
  ),
  'public.is_route_visible_to has been dropped (PostgREST RPC oracle closed by 20260819_001)'
);

-- 4. private.is_route_visible_to IS executable by anon. The SELECT
--    + INSERT policies on `route_reviews` + `segments` (20260703_001)
--    call this from anon-reachable paths — anonymous viewers of
--    /share/route/<id> need it.
select is(
  has_function_privilege('anon', 'private.is_route_visible_to(uuid, uuid)', 'execute'),
  true,
  'anon CAN EXECUTE private.is_route_visible_to (anonymous /share/route/<id> needs it for reviews + segments)'
);

-- 4b. ...and by authenticated (route-detail page reads, route_reviews
--     INSERT, segments INSERT, routes_run_count_trigger).
select is(
  has_function_privilege('authenticated', 'private.is_route_visible_to(uuid, uuid)', 'execute'),
  true,
  'authenticated CAN EXECUTE private.is_route_visible_to (route_reviews + segments policies + run_count trigger)'
);

-- 5. is_run_visible_to IS executable by anon AND has been moved to
--    the `private` schema (20260812_001) so PostgREST can't expose
--    it as an RPC oracle. Anon EXECUTE grant is required because
--    every share-page RLS evaluation calls the qualified
--    `private.is_run_visible_to(...)`.
select is(
  has_function_privilege('anon', 'private.is_run_visible_to(uuid, uuid)', 'execute'),
  true,
  'anon CAN EXECUTE private.is_run_visible_to (anonymous /share/run/<id> needs it for kudos / comments / photos / segments / pings)'
);

-- 5b. The public-schema version must be GONE — that's the
--     PostgREST RPC oracle the schema move closed. If a future
--     migration recreates `public.is_run_visible_to`, this fails.
select ok(
  not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'is_run_visible_to'
  ),
  'public.is_run_visible_to has been dropped (PostgREST RPC oracle closed by 20260812_001)'
);

-- 6. recompute_event_ranks is NOT executable by PUBLIC. Today this
--    function is trigger-called only; the explicit revoke prevents a
--    future EXECUTE-to-authenticated extension from letting any user
--    force a rank recompute on any event.
select is(
  has_function_privilege('public', 'recompute_event_ranks(uuid, timestamptz)', 'execute'),
  false,
  'PUBLIC cannot EXECUTE recompute_event_ranks (closed in 20260711_001)'
);

-- 7. recompute_event_ranks IS executable by authenticated (the
--    AFTER-INSERT trigger on event_results runs in the writer's
--    SECURITY INVOKER context — drop this grant and inserts fail).
select is(
  has_function_privilege('authenticated', 'recompute_event_ranks(uuid, timestamptz)', 'execute'),
  true,
  'authenticated CAN EXECUTE recompute_event_ranks (the event_results AFTER-INSERT trigger calls it)'
);

select * from finish();

rollback;
