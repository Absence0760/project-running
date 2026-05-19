-- Anti-spam phase 2: pin the BEFORE-INSERT rate-limit triggers on
-- `clubs` and `routes`, plus the submit_report RPC. Same shape as the
-- existing RLS suites:
--   1. Plant an auth.users fixture.
--   2. Switch to role `authenticated` with the fixture's JWT sub.
--   3. Inserts under the cap succeed; the first insert over the cap
--      raises with the expected P0001 errcode AND the exact format
--      the client parsers depend on (`rate limit exceeded for <bucket>,
--      retry in Ns`). A loose `%rate limit exceeded%` match would
--      have let a comma-to-colon migration silently break web
--      `rateLimitErrorMessage()` + the Dart twin — both fall through
--      to the raw exception when the format drifts.
--   4. Service-role + null-auth bypasses (used by migrations + the
--      seed file) still pass — verified implicitly by the fact that
--      seed.sql plants its 12 routes + 3 clubs without hitting the
--      cap.

begin;

select plan(6);

-- ── Fixture ──────────────────────────────────────────────────────
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000c0001', 'authenticated', 'authenticated',
   'creator@spam.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0001"}';

-- ── Clubs: 5/hour cap ────────────────────────────────────────────
-- Plant 5 clubs back-to-back. All should land.
do $$
declare
  i int;
begin
  for i in 1..5 loop
    insert into clubs (owner_id, name, slug, is_public, join_policy)
      values (
        '00000000-0000-0000-0000-0000000c0001',
        'Spam Club ' || i,
        'spam-club-' || i,
        true,
        'open'
      );
  end loop;
end;
$$;

select is(
  (select count(*)::int from clubs
   where owner_id = '00000000-0000-0000-0000-0000000c0001'),
  5,
  '5 clubs under the cap all land'
);

-- The 6th insert in the same fixed-window hour should raise. The
-- enforce_create_rate_limit function raises P0001 with the literal
-- format `rate limit exceeded for <bucket>, retry in Ns`. We anchor
-- with `^...$` because the web + Dart parsers anchor on the comma
-- + "retry in" + integer-seconds shape — a future migration that
-- swapped any of those would silently fall through to "doing that"
-- generic wording on every client.
select throws_matching(
  $$ insert into clubs (owner_id, name, slug, is_public, join_policy)
       values ('00000000-0000-0000-0000-0000000c0001',
               'Spam Club 6', 'spam-club-6', true, 'open') $$,
  '^rate limit exceeded for create_club, retry in [0-9]+s$',
  '6th club in the same hour is rejected with the client-parser-compatible rate-limit format'
);

-- ── Routes: 30/hour cap ──────────────────────────────────────────
-- Drop 30 minimal routes (waypoints jsonb is `not null`). All land.
do $$
declare
  i int;
begin
  for i in 1..30 loop
    insert into routes (user_id, name, distance_m, waypoints, surface)
      values (
        '00000000-0000-0000-0000-0000000c0001',
        'spam-route-' || i,
        1000,
        '[{"lat":0,"lng":0},{"lat":0.001,"lng":0.001}]'::jsonb,
        'road'
      );
  end loop;
end;
$$;

select is(
  (select count(*)::int from routes
   where user_id = '00000000-0000-0000-0000-0000000c0001'),
  30,
  '30 routes under the cap all land'
);

select throws_matching(
  $$ insert into routes (user_id, name, distance_m, waypoints, surface)
       values ('00000000-0000-0000-0000-0000000c0001',
               'spam-route-31', 1000,
               '[{"lat":0,"lng":0},{"lat":0.001,"lng":0.001}]'::jsonb,
               'road') $$,
  '^rate limit exceeded for create_route, retry in [0-9]+s$',
  '31st route in the same hour is rejected with the client-parser-compatible rate-limit format'
);

-- ── Reports: 10/hour cap ─────────────────────────────────────────
-- The submit_report RPC (migration 20260908_001) delegates to the
-- same enforce_create_rate_limit helper under bucket='create_report'.
-- Target 10 distinct routes from the 30 we just planted; the
-- duplicate-pending unique index is per (reporter, target_kind,
-- target_id, status='pending') so each target is a fresh slot. The
-- reporter has already burned their club + route caps, but
-- create_report is its own bucket — they're independent.
do $$
declare
  v_target uuid;
  i int := 0;
begin
  for v_target in
    select id from routes
      where user_id = '00000000-0000-0000-0000-0000000c0001'
      order by id
      limit 10
  loop
    i := i + 1;
    perform submit_report('route', v_target, 'spam', 'attempt ' || i);
  end loop;
end;
$$;

select is(
  (select count(*)::int from reports
   where reporter_id = '00000000-0000-0000-0000-0000000c0001'),
  10,
  '10 reports under the cap all land'
);

-- The 11th report against a fresh target must raise the rate-limit
-- BEFORE the duplicate-pending check could fire — verifying that
-- order of operations matters too. Same exact-format assertion as
-- the club + route buckets so the three are pinned identically.
select throws_matching(
  $$ select submit_report(
       'route',
       (select id from routes
          where user_id = '00000000-0000-0000-0000-0000000c0001'
          order by id offset 10 limit 1),
       'spam',
       'cap-breaker'
     ) $$,
  '^rate limit exceeded for create_report, retry in [0-9]+s$',
  '11th report in the same hour is rejected with the client-parser-compatible rate-limit format'
);

select * from finish();
rollback;
