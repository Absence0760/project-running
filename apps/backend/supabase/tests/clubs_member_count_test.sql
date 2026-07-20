-- Pins clubs.member_count: the trigger-maintained cache (20260906_001, made
-- SECURITY DEFINER in 20270205_001) must always equal the authoritative query
--   count(*) from club_members where club_id = c.id and status = 'active'.
--
-- The web enrichClubs helper reads this cache as authoritative (issue #331,
-- derived_state.md) instead of re-counting the roster client-side, so a drift
-- here would surface a wrong member count on every /social clubs render. The
-- trigger increments/decrements per row rather than recomputing from scratch,
-- which is exactly the drift-prone shape this test guards. Each assertion
-- compares the cache to the live active-count after a distinct mutation
-- (insert active, insert pending, approve, leave, demote) so every trigger
-- branch is exercised. Owner auto-enrolment (enroll_club_owner_trigger) makes
-- the absolute baseline 1, which is exactly why this pins the invariant against
-- the authoritative query, not hardcoded totals. Runs as superuser so RLS is
-- out of the way.

begin;

select plan(6);

create or replace function _member_count_matches(p_club uuid) returns boolean
language sql stable as $$
  select (select member_count from clubs where id = p_club)
       = (select count(*)::int from club_members
            where club_id = p_club and status = 'active');
$$;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000c0001', 'authenticated', 'authenticated',
   'owner@memcount.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c0002', 'authenticated', 'authenticated',
   'active@memcount.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c0003', 'authenticated', 'authenticated',
   'pending@memcount.local', '', now(), now());

-- Creating the club auto-enrols the owner as an active member (owner-enroll
-- trigger); the count trigger must have tracked that.
insert into clubs (id, owner_id, name, slug, is_public)
values ('c1000000-0000-0000-0000-0000000c0001',
        '00000000-0000-0000-0000-0000000c0001', 'Count Club', 'count-club', true);
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0001'),
  'member_count matches the active count after club creation (owner auto-enrolled)'
);

-- Insert an active member.
insert into club_members (club_id, user_id, role, status)
values ('c1000000-0000-0000-0000-0000000c0001',
        '00000000-0000-0000-0000-0000000c0002', 'member', 'active');
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0001'),
  'member_count matches after inserting an active member'
);

-- Insert a pending member (must NOT count).
insert into club_members (club_id, user_id, role, status)
values ('c1000000-0000-0000-0000-0000000c0001',
        '00000000-0000-0000-0000-0000000c0003', 'member', 'pending');
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0001'),
  'member_count matches after inserting a pending member (pending excluded)'
);

-- Approve the pending member (pending -> active increments).
update club_members set status = 'active'
  where club_id = 'c1000000-0000-0000-0000-0000000c0001'
    and user_id = '00000000-0000-0000-0000-0000000c0003';
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0001'),
  'member_count matches after approving a pending member (status flip)'
);

-- A member leaves (delete of an active row decrements).
delete from club_members
  where club_id = 'c1000000-0000-0000-0000-0000000c0001'
    and user_id = '00000000-0000-0000-0000-0000000c0002';
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0001'),
  'member_count matches after an active member leaves (delete)'
);

-- Demote an active member back to pending (active -> pending decrements).
update club_members set status = 'pending'
  where club_id = 'c1000000-0000-0000-0000-0000000c0001'
    and user_id = '00000000-0000-0000-0000-0000000c0003';
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0001'),
  'member_count matches after demoting an active member to pending'
);

select * from finish();
rollback;
