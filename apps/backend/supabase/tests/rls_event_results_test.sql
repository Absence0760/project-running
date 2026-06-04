-- Pin the `event_results` INSERT visibility check from migration
-- 20260613_001_rls_hardening.sql.
--
-- Pre-fix: the original `event_results_insert_self` policy only gated
-- INSERT on `auth.uid() = user_id`. An authenticated user with a guessed
-- `event_id` could plant a self-attributed result on any event,
-- including private clubs they could not even read. Today every event
-- ID is a uuid (guess-resistant) but the principle — "you can't write
-- to a leaderboard you can't read" — is what the fix pinned.
--
-- The policy now mirrors the SELECT visibility chain:
--   auth.uid() = user_id  AND  caller can see the parent event
-- Caller-can-see-event = `c.is_public OR owner OR member` joined
-- through `events → clubs`.
--
-- Coverage:
--   1. User attempting to plant a result on a private-club event they
--      are NOT a member of is rejected (42501) — the regression fix.
--   2. User CAN INSERT a result on a public-club event (positive
--      control — public-events leaderboard still works).
--   3. User CAN INSERT a result on a private-club event they ARE a
--      member of (positive control — members can post their own time).
--   4. Forging `user_id` (writing a result attributing it to someone
--      else) is rejected even on a public event the caller can see.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000a701', 'authenticated', 'authenticated',
   'organiser@evt.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000a702', 'authenticated', 'authenticated',
   'attacker@evt.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000a703', 'authenticated', 'authenticated',
   'priv-member@evt.local', '', now(), now());

set local role service_role;

-- One public club + one private club, each with one event whose
-- ID the attacker has somehow obtained.
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('33333333-3333-3333-3333-333333333301',
   '00000000-0000-0000-0000-00000000a701', 'Public Club', 'public-evt-c', true),
  ('33333333-3333-3333-3333-333333333302',
   '00000000-0000-0000-0000-00000000a701', 'Private Club', 'private-evt-c', false);

-- enroll_club_owner_trigger creates the owner rows; only seed the
-- explicit private-club member.
insert into club_members (club_id, user_id, role, status)
values
  ('33333333-3333-3333-3333-333333333302',
   '00000000-0000-0000-0000-00000000a703', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id)
values
  ('33333333-3333-3333-3333-333333333311',
   '33333333-3333-3333-3333-333333333301', 'Public Tuesday',
   '2026-06-02 19:00+00', '00000000-0000-0000-0000-00000000a701'),
  ('33333333-3333-3333-3333-333333333312',
   '33333333-3333-3333-3333-333333333302', 'Private Tuesday',
   '2026-06-02 19:00+00', '00000000-0000-0000-0000-00000000a701');

-- ── Attacker (not a member of the private club) ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000a702","role":"authenticated"}';

-- 1. Cannot plant a result on a private-club event you can't see.
select throws_ok(
  $$ insert into event_results (event_id, instance_start, user_id,
                                duration_s, distance_m)
     values ('33333333-3333-3333-3333-333333333312',
             '2026-06-02 19:00+00',
             '00000000-0000-0000-0000-00000000a702',
             1800, 5000) $$,
  '42501',
  null,
  'attacker cannot INSERT event_results on a private-club event they are not a member of (the regression fix)'
);

-- 2. Public-club event: attacker CAN INSERT their own result
--    (positive control — the visibility chain admits public events).
do $$
begin
  insert into event_results (event_id, instance_start, user_id,
                             duration_s, distance_m)
  values ('33333333-3333-3333-3333-333333333311',
          '2026-06-02 19:00+00',
          '00000000-0000-0000-0000-00000000a702',
          1800, 5000);
end $$;
select pass('attacker (random authed user) can INSERT a self-attributed result on a public-club event');

-- 4. Forged user_id is rejected even on a public event the caller
--    can see. Ordering: do the forge test BEFORE switching to the
--    private-club member so we don't conflate identities.
select throws_ok(
  $$ insert into event_results (event_id, instance_start, user_id,
                                duration_s, distance_m)
     values ('33333333-3333-3333-3333-333333333311',
             '2026-06-02 19:00+00',
             '00000000-0000-0000-0000-00000000a701',
             1800, 5000) $$,
  '42501',
  null,
  'forged user_id INSERT on event_results is rejected even on a public-club event'
);

-- ── Switch to the private-club member ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000a703","role":"authenticated"}';

-- 3. Private-club member CAN INSERT their result on the private-club
--    event (positive control — members can post their times).
do $$
begin
  insert into event_results (event_id, instance_start, user_id,
                             duration_s, distance_m)
  values ('33333333-3333-3333-3333-333333333312',
          '2026-06-02 19:00+00',
          '00000000-0000-0000-0000-00000000a703',
          1800, 5000);
end $$;
select pass('private-club member can INSERT a self-attributed result on the private-club event');

select * from finish();

rollback;
