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
--
-- Coverage:
--   1. `weekly_mileage` and `personal_records` both pin search_path.
--   2. `is_route_visible_to` is NOT executable by anon (Pass-2 closed
--      the existence-oracle on bookmarked-private routes).
--   3. `is_route_visible_to` IS executable by authenticated (its
--      five sibling policies still need it).
--   4. `is_run_visible_to` IS executable by anon (Pass-2 fix —
--      anonymous /share/run/<id> visitors need it for kudos /
--      comments / photos / segment efforts / live pings).
--   5. `recompute_event_ranks` is NOT executable by PUBLIC.

begin;

select plan(7);

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

-- 3. is_route_visible_to is NOT executable by anon (existence-oracle
--    closed in 20260711_001).
select is(
  has_function_privilege('anon', 'is_route_visible_to(uuid, uuid)', 'execute'),
  false,
  'anon cannot EXECUTE is_route_visible_to (existence oracle closed)'
);

-- 4. is_route_visible_to IS executable by authenticated (five
--    sibling policies still need it).
select is(
  has_function_privilege('authenticated', 'is_route_visible_to(uuid, uuid)', 'execute'),
  true,
  'authenticated can EXECUTE is_route_visible_to (sibling policies depend on it)'
);

-- 5. is_run_visible_to IS executable by anon (20260713_001 restored
--    the grant pass-1 dropped). Without this every social affordance
--    on the public share page returns 42501.
select is(
  has_function_privilege('anon', 'is_run_visible_to(uuid, uuid)', 'execute'),
  true,
  'anon CAN EXECUTE is_run_visible_to (anonymous /share/run/<id> needs it for kudos / comments / photos / segments / pings)'
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
