-- Pins migration 20260529_002 — race-session state machine guards.
-- Persona-hunt Round 2 finding Pro #5.

begin;
select plan(8);

-- Seed: a club + event so race_sessions FK to a real event row.
do $$
declare
  v_user uuid := '99999999-9999-9999-9999-9999race0001';
  v_club uuid := '99999999-9999-9999-9999-9999race0c01';
  v_event uuid := '99999999-9999-9999-9999-9999race0e01';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'race-rd@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into clubs (id, slug, name, visibility, join_policy, created_by)
    values (v_club, 'race-club', 'Race Club', 'public', 'open', v_user)
    on conflict (id) do nothing;
  insert into club_members (club_id, user_id, role, status, joined_at)
    values (v_club, v_user, 'admin', 'active', now())
    on conflict (club_id, user_id) do nothing;
  insert into events (id, club_id, title, kind, starts_at, created_by)
    values (v_event, v_club, 'Test Race', 'race',
            '2026-04-15 09:00:00+00', v_user)
    on conflict (id) do nothing;
end $$;

-- 1. Initial INSERT as `armed` is fine (start_at + finished_at null).
insert into race_sessions (event_id, instance_start, status)
values ('99999999-9999-9999-9999-9999race0e01',
        '2026-04-15 09:00:00+00', 'armed');
select pass('armed insert with null timestamps is accepted');

-- 2. armed → running with started_at set is allowed.
update race_sessions
set status = 'running', started_at = '2026-04-15 09:00:00+00'
where event_id = '99999999-9999-9999-9999-9999race0e01';
select pass('armed → running with started_at is accepted');

-- 3. running → finished with finished_at set is allowed.
update race_sessions
set status = 'finished', finished_at = '2026-04-15 09:30:00+00'
where event_id = '99999999-9999-9999-9999-9999race0e01';
select pass('running → finished with finished_at is accepted');

-- 4. finished → armed must fail (terminal status).
select throws_ok(
  $$update race_sessions set status = 'armed'
    where event_id = '99999999-9999-9999-9999-9999race0e01'$$,
  '23514',
  null,
  'finished is terminal — cannot transition back to armed'
);

-- Clean for the next scenarios.
delete from race_sessions
where event_id = '99999999-9999-9999-9999-9999race0e01';

-- 5. armed → finished WITHOUT going through running must fail.
insert into race_sessions (event_id, instance_start, status)
values ('99999999-9999-9999-9999-9999race0e01',
        '2026-04-15 10:00:00+00', 'armed');
select throws_ok(
  $$update race_sessions
    set status = 'finished',
        started_at = '2026-04-15 10:00:00+00',
        finished_at = '2026-04-15 10:30:00+00'
    where event_id = '99999999-9999-9999-9999-9999race0e01'$$,
  '23514',
  null,
  'armed → finished must go through running first (transition graph)'
);

-- 6. armed → cancelled is allowed.
update race_sessions
set status = 'cancelled'
where event_id = '99999999-9999-9999-9999-9999race0e01';
select pass('armed → cancelled is accepted');

-- Clean.
delete from race_sessions
where event_id = '99999999-9999-9999-9999-9999race0e01';

-- 7. Insert as `running` with null started_at must fail
-- (temporal-invariant CHECK, before the transition trigger fires).
select throws_ok(
  $$insert into race_sessions (event_id, instance_start, status)
    values ('99999999-9999-9999-9999-9999race0e01',
            '2026-04-15 11:00:00+00', 'running')$$,
  '23514',
  null,
  'running without started_at is rejected by the temporal invariant'
);

-- 8. Insert as `finished` with null started_at must fail.
select throws_ok(
  $$insert into race_sessions (event_id, instance_start, status,
                                started_at, finished_at)
    values ('99999999-9999-9999-9999-9999race0e01',
            '2026-04-15 12:00:00+00', 'finished',
            null, '2026-04-15 12:30:00+00')$$,
  '23514',
  null,
  'finished without started_at is rejected (must have actually run)'
);

rollback;
