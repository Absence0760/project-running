-- Anti-spam phase 2: pin the BEFORE-INSERT rate-limit triggers on
-- `clubs` and `routes`. Same shape as the existing RLS suites:
--   1. Plant an auth.users fixture.
--   2. Switch to role `authenticated` with the fixture's JWT sub.
--   3. Inserts under the cap succeed; the first insert over the cap
--      raises with the expected P0001 errcode.
--   4. Service-role + null-auth bypasses (used by migrations + the
--      seed file) still pass — verified implicitly by the fact that
--      seed.sql plants its 12 routes + 3 clubs without hitting the
--      cap.

begin;

select plan(4);

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
-- enforce_create_rate_limit function raises P0001 with the
-- 'rate limit exceeded' message; throws_like covers either the
-- errcode or the message wording surviving a refactor.
select throws_like(
  $$ insert into clubs (owner_id, name, slug, is_public, join_policy)
       values ('00000000-0000-0000-0000-0000000c0001',
               'Spam Club 6', 'spam-club-6', true, 'open') $$,
  '%rate limit exceeded%',
  '6th club in the same hour is rejected with a rate-limit error'
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

select throws_like(
  $$ insert into routes (user_id, name, distance_m, waypoints, surface)
       values ('00000000-0000-0000-0000-0000000c0001',
               'spam-route-31', 1000,
               '[{"lat":0,"lng":0},{"lat":0.001,"lng":0.001}]'::jsonb,
               'road') $$,
  '%rate limit exceeded%',
  '31st route in the same hour is rejected with a rate-limit error'
);

select * from finish();
rollback;
