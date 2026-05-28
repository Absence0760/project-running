-- Pins migration 20260529000003 — race-session state machine guards.
-- Persona-hunt Round 2 finding Pro #5.

begin;
select plan(10);

-- Seed: a club + event so race_sessions FK to a real event row.
do $$
declare
  v_user uuid := '99999999-9999-9999-9999-9999accec001';
  v_club uuid := '99999999-9999-9999-9999-9999accec0c1';
  v_event uuid := '99999999-9999-9999-9999-9999accec0e1';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'race-rd@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into clubs (id, slug, name, is_public, join_policy, owner_id)
    values (v_club, 'race-club', 'Race Club', true, 'open', v_user)
    on conflict (id) do nothing;
  insert into club_members (club_id, user_id, role, status, joined_at)
    values (v_club, v_user, 'admin', 'active', now())
    on conflict (club_id, user_id) do nothing;
  insert into events (id, club_id, title, starts_at, created_by)
    values (v_event, v_club, 'Test Race',
            '2026-04-15 09:00:00+00', v_user)
    on conflict (id) do nothing;
end $$;

-- 1. Initial INSERT as `armed` is fine (start_at + finished_at null).
insert into race_sessions (event_id, instance_start, status)
values ('99999999-9999-9999-9999-9999accec0e1',
        '2026-04-15 09:00:00+00', 'armed');
select pass('armed insert with null timestamps is accepted');

-- 2. armed → running with started_at set is allowed.
update race_sessions
set status = 'running', started_at = '2026-04-15 09:00:00+00'
where event_id = '99999999-9999-9999-9999-9999accec0e1';
select pass('armed → running with started_at is accepted');

-- 3. running → finished with finished_at set is allowed.
update race_sessions
set status = 'finished', finished_at = '2026-04-15 09:30:00+00'
where event_id = '99999999-9999-9999-9999-9999accec0e1';
select pass('running → finished with finished_at is accepted');

-- 4. finished → armed must fail (terminal status).
select throws_ok(
  $$update race_sessions set status = 'armed'
    where event_id = '99999999-9999-9999-9999-9999accec0e1'$$,
  '23514',
  null,
  'finished is terminal — cannot transition back to armed'
);

-- Clean for the next scenarios.
delete from race_sessions
where event_id = '99999999-9999-9999-9999-9999accec0e1';

-- 5. armed → finished WITHOUT going through running must fail.
insert into race_sessions (event_id, instance_start, status)
values ('99999999-9999-9999-9999-9999accec0e1',
        '2026-04-15 10:00:00+00', 'armed');
select throws_ok(
  $$update race_sessions
    set status = 'finished',
        started_at = '2026-04-15 10:00:00+00',
        finished_at = '2026-04-15 10:30:00+00'
    where event_id = '99999999-9999-9999-9999-9999accec0e1'$$,
  '23514',
  null,
  'armed → finished must go through running first (transition graph)'
);

-- 6. armed → cancelled is allowed.
update race_sessions
set status = 'cancelled'
where event_id = '99999999-9999-9999-9999-9999accec0e1';
select pass('armed → cancelled is accepted');

-- Clean.
delete from race_sessions
where event_id = '99999999-9999-9999-9999-9999accec0e1';

-- 7. Insert as `running` with null started_at must fail
-- (temporal-invariant CHECK, before the transition trigger fires).
select throws_ok(
  $$insert into race_sessions (event_id, instance_start, status)
    values ('99999999-9999-9999-9999-9999accec0e1',
            '2026-04-15 11:00:00+00', 'running')$$,
  '23514',
  null,
  'running without started_at is rejected by the temporal invariant'
);

-- 8. Insert as `finished` with null started_at must fail.
select throws_ok(
  $$insert into race_sessions (event_id, instance_start, status,
                                started_at, finished_at)
    values ('99999999-9999-9999-9999-9999accec0e1',
            '2026-04-15 12:00:00+00', 'finished',
            null, '2026-04-15 12:30:00+00')$$,
  '23514',
  null,
  'finished without started_at is rejected (must have actually run)'
);

-- 9. armed → cancelled WITH finished_at stamped must fail. The
-- temporal-invariant CHECK requires `finished_at IS NULL` when
-- status='cancelled'. Pins the bug fixed in `endRace` (web data.ts)
-- which used to stamp finished_at unconditionally — every Cancel
-- click from armed errored with 23514, the page's local raceSession
-- state never updated, and the Arm-race button never re-appeared
-- (`event-race-control.spec.ts:170` timed out for 4 CI runs in a
-- row).
insert into race_sessions (event_id, instance_start, status)
values ('99999999-9999-9999-9999-9999accec0e1',
        '2026-04-15 13:00:00+00', 'armed');
select throws_ok(
  $$update race_sessions
    set status = 'cancelled',
        finished_at = '2026-04-15 13:30:00+00'
    where event_id = '99999999-9999-9999-9999-9999accec0e1'
      and instance_start = '2026-04-15 13:00:00+00'$$,
  '23514',
  null,
  'armed → cancelled with finished_at stamped is rejected by the temporal invariant'
);

-- 10. armed → cancelled WITHOUT finished_at is accepted (the
-- positive companion to test 9 — what `endRace` should be doing).
update race_sessions
  set status = 'cancelled'
  where event_id = '99999999-9999-9999-9999-9999accec0e1'
    and instance_start = '2026-04-15 13:00:00+00';
select pass('armed → cancelled without finished_at is accepted');

rollback;
