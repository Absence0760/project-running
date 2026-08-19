-- Pins clubs.member_count: the trigger-maintained cache (20260906_001, made
-- SECURITY DEFINER in 20270205_001) must always equal the authoritative query
--   count(*) from club_members where club_id = c.id and status = 'active'.
--
-- The web enrichClubs helper reads this cache as authoritative (issue #331,
-- derived_state.md) instead of re-counting the roster client-side, so a drift
-- here would surface a wrong member count on every /social clubs render. The
-- trigger's watch list is `OF status, club_id`, so a statement may change
-- either axis or both at once. Each assertion compares the cache to the live
-- active-count after a distinct mutation (insert active, insert pending,
-- approve, leave, demote, move club, move-and-approve, move-and-demote) so
-- every trigger branch is exercised. The club_id half was missing until
-- 20270526_001 — derived_state.md claimed this suite guarded every branch
-- while the combined status + club_id UPDATE (which the old trigger counted
-- twice, through two non-exclusive `if` blocks) was never run.
-- Owner auto-enrolment (enroll_club_owner_trigger) makes
-- the absolute baseline 1, which is exactly why this pins the invariant against
-- the authoritative query, not hardcoded totals. Runs as superuser so RLS is
-- out of the way.

begin;

select plan(12);

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
   'pending@memcount.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c0004', 'authenticated', 'authenticated',
   'mover@memcount.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c0005', 'authenticated', 'authenticated',
   'demoter@memcount.local', '', now(), now());

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

-- Two more clubs, so a membership can move between counted parents — and so
-- each combined-UPDATE case starts from a cache the previous case has not
-- already corrupted. A double increment followed by a double decrement on the
-- same club cancels out, which would let a broken trigger pass.
insert into clubs (id, owner_id, name, slug, is_public)
values ('c1000000-0000-0000-0000-0000000c0002',
        '00000000-0000-0000-0000-0000000c0001', 'Count Club Two', 'count-club-two', true),
       ('c1000000-0000-0000-0000-0000000c0003',
        '00000000-0000-0000-0000-0000000c0001', 'Count Club Three', 'count-club-three', true);

insert into club_members (club_id, user_id, role, status)
values ('c1000000-0000-0000-0000-0000000c0001',
        '00000000-0000-0000-0000-0000000c0004', 'member', 'active');

-- club_id alone changes: the source loses an active member, the destination
-- gains one.
update club_members set club_id = 'c1000000-0000-0000-0000-0000000c0002'
  where club_id = 'c1000000-0000-0000-0000-0000000c0001'
    and user_id = '00000000-0000-0000-0000-0000000c0004';
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0001'),
  'source member_count matches after an active member moves to another club'
);
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0002'),
  'destination member_count matches after an active member moves in'
);

-- Both axes in one statement: a pending member is approved into another club.
-- The old trigger ran both `if` blocks and incremented the destination twice.
update club_members
   set status = 'active', club_id = 'c1000000-0000-0000-0000-0000000c0002'
 where club_id = 'c1000000-0000-0000-0000-0000000c0001'
   and user_id = '00000000-0000-0000-0000-0000000c0003';
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0001'),
  'source member_count matches after a combined status + club_id UPDATE'
);
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0002'),
  'destination member_count matches after a combined status + club_id UPDATE '
  '(the double increment)'
);

-- The mirror case, on the untouched third club: an active member is demoted
-- AND moved in one statement. The old trigger decremented the source twice.
insert into club_members (club_id, user_id, role, status)
values ('c1000000-0000-0000-0000-0000000c0003',
        '00000000-0000-0000-0000-0000000c0005', 'member', 'active');
update club_members
   set status = 'pending', club_id = 'c1000000-0000-0000-0000-0000000c0001'
 where club_id = 'c1000000-0000-0000-0000-0000000c0003'
   and user_id = '00000000-0000-0000-0000-0000000c0005';
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0003'),
  'source member_count matches after a combined demote + move (the double '
  'decrement)'
);
select ok(
  _member_count_matches('c1000000-0000-0000-0000-0000000c0001'),
  'destination member_count matches after a combined demote + move'
);

select * from finish();
rollback;
