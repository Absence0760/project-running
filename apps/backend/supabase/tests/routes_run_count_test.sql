-- Pins routes.run_count: the trigger-maintained cache (20260628_001 +
-- 20260716_001, recompute-from-authoritative since 20270526_001) must always
-- equal the authoritative query
--   count(*) from runs where route_id = r.id and is_public = true
--                        and private.is_route_visible_to(route_id, user_id).
--
-- derived_state.md carried this cache with no "Pinned by" line at all, which is
-- how a permanent overcount survived: the old trigger decided whether a
-- decrement was owed by re-evaluating is_route_visible_to on the OLD row at
-- trigger time. That reads the route's CURRENT visibility, so a route that had
-- gone private since the increment answered "was not counted" and the run
-- detached without giving the count back. Assertion 6 is that case.
--
-- The accepted drift (the RUN's is_public flip is not watched) is deliberately
-- not asserted mid-flight; assertion 8 pins the property that replaced it —
-- the next route_id touch recomputes the route from source, so the drift heals
-- instead of compounding. Runs as superuser so RLS is out of the way.

begin;

select plan(8);

create or replace function _run_count_matches(p_route uuid) returns boolean
language sql stable as $$
  select (select run_count from routes where id = p_route)
       = (select count(*)::int from runs
            where route_id = p_route
              and is_public = true
              and private.is_route_visible_to(route_id, user_id));
$$;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000f0001', 'authenticated', 'authenticated',
   'owner@runcount.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000f0002', 'authenticated', 'authenticated',
   'runner@runcount.local', '', now(), now());

-- Two public routes owned by someone other than the runner: the visibility
-- gate is only load-bearing when the counted run is not the route owner's.
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('f1000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f0001',
   'Route P', '[]'::jsonb, 5000, true),
  ('f1000000-0000-0000-0000-0000000f0002', '00000000-0000-0000-0000-0000000f0001',
   'Route Q', '[]'::jsonb, 5000, true),
  ('f1000000-0000-0000-0000-0000000f0003', '00000000-0000-0000-0000-0000000f0001',
   'Route S', '[]'::jsonb, 5000, true);

-- A public run by a non-owner on a visible route counts.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, route_id)
values ('f2000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f0002',
        now(), 1800, 5000, 'app', true, 'f1000000-0000-0000-0000-0000000f0001');
select ok(
  _run_count_matches('f1000000-0000-0000-0000-0000000f0001'),
  'run_count matches after a public run is matched to a visible route'
);

-- A private run must not count (20260716_001).
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, route_id)
values ('f2000000-0000-0000-0000-0000000f0002', '00000000-0000-0000-0000-0000000f0002',
        now(), 1500, 4000, 'app', false, 'f1000000-0000-0000-0000-0000000f0001');
select ok(
  _run_count_matches('f1000000-0000-0000-0000-0000000f0001'),
  'run_count matches after a private run is matched (private excluded)'
);

-- Moving a run between routes must decrement the source and increment the
-- destination.
update runs set route_id = 'f1000000-0000-0000-0000-0000000f0002'
  where id = 'f2000000-0000-0000-0000-0000000f0001';
select ok(
  _run_count_matches('f1000000-0000-0000-0000-0000000f0001'),
  'run_count matches on the source route after a run moves away'
);
select ok(
  _run_count_matches('f1000000-0000-0000-0000-0000000f0002'),
  'run_count matches on the destination route after a run moves in'
);

-- Deleting a counted run decrements.
delete from runs where id = 'f2000000-0000-0000-0000-0000000f0001';
select ok(
  _run_count_matches('f1000000-0000-0000-0000-0000000f0002'),
  'run_count matches after a counted run is deleted'
);

-- The overcount: the run was counted while the route was public, the route
-- then went private, and only afterwards did the run detach. The old trigger
-- read the route's current visibility to decide the OLD row "was not counted"
-- and skipped the decrement, leaving the counter permanently high.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, route_id)
values ('f2000000-0000-0000-0000-0000000f0003', '00000000-0000-0000-0000-0000000f0002',
        now(), 1800, 5000, 'app', true, 'f1000000-0000-0000-0000-0000000f0001');
update routes set is_public = false where id = 'f1000000-0000-0000-0000-0000000f0001';
update runs set route_id = null where id = 'f2000000-0000-0000-0000-0000000f0003';
select ok(
  _run_count_matches('f1000000-0000-0000-0000-0000000f0001'),
  'run_count matches after a run detaches from a route that went private '
  'since the increment (the skipped decrement)'
);

-- The last two run on a fresh route so each starts from a cache the earlier
-- assertions have not already corrupted — otherwise a compensating pair of
-- errors can make a broken trigger look right.
--
-- A run matched to a route the runner cannot see is not counted at all.
update routes set is_public = false where id = 'f1000000-0000-0000-0000-0000000f0003';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, route_id)
values ('f2000000-0000-0000-0000-0000000f0004', '00000000-0000-0000-0000-0000000f0002',
        now(), 1800, 5000, 'app', true, 'f1000000-0000-0000-0000-0000000f0003');
select ok(
  _run_count_matches('f1000000-0000-0000-0000-0000000f0003'),
  'run_count matches when a public run is matched to a route the runner '
  'cannot see (visibility gate)'
);

-- Route-side visibility flips are still not watched (accepted drift), but the
-- next route_id touch recomputes the whole route from source rather than
-- applying a delta on top of the stale value — so the drift heals instead of
-- compounding.
update routes set is_public = true where id = 'f1000000-0000-0000-0000-0000000f0003';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, route_id)
values ('f2000000-0000-0000-0000-0000000f0005', '00000000-0000-0000-0000-0000000f0002',
        now(), 1800, 5000, 'app', true, 'f1000000-0000-0000-0000-0000000f0003');
select ok(
  _run_count_matches('f1000000-0000-0000-0000-0000000f0003'),
  'run_count self-heals a route-visibility flip on the next route_id touch'
);

select * from finish();
rollback;
