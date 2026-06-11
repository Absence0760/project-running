-- Pins migration 20261227_001 (typed events, slice E):
--   * events.category defaults to 'run' and host_user_id defaults to author_id
--   * race_sessions + event_results inserts are rejected at the DATA layer
--     when the parent event is not athletic (category not in run/cycle) — a
--     yoga class must be un-race-able / un-result-able via direct SQL, not
--     merely hidden in the UI.

begin;
select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'te-owner@evt.local', '', now(), now()),
  ('aaaa0000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'te-finisher@evt.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb0000-0000-0000-0000-000000000001',
        'aaaa0000-0000-0000-0000-000000000001', 'Typed Club', 'typed-evt-c', true);

-- A run event with category + host_user_id OMITTED, to exercise the defaults.
insert into events (id, club_id, title, starts_at, author_id)
values ('cccc0000-0000-0000-0000-000000000001',
        'bbbb0000-0000-0000-0000-000000000001', 'Default Run',
        '2026-06-02 19:00+00', 'aaaa0000-0000-0000-0000-000000000001');

select is(
  (select category from events where id = 'cccc0000-0000-0000-0000-000000000001'),
  'run',
  'category defaults to run when omitted'
);

select is(
  (select host_user_id from events where id = 'cccc0000-0000-0000-0000-000000000001'),
  'aaaa0000-0000-0000-0000-000000000001'::uuid,
  'host_user_id defaults to the author when omitted'
);

-- Athletic + non-athletic events for the guard tests.
insert into events (id, club_id, title, starts_at, author_id, category)
values
  ('cccc0000-0000-0000-0000-000000000002', 'bbbb0000-0000-0000-0000-000000000001',
   'Yoga Class', '2026-06-03 18:00+00', 'aaaa0000-0000-0000-0000-000000000001', 'class'),
  ('cccc0000-0000-0000-0000-000000000003', 'bbbb0000-0000-0000-0000-000000000001',
   'Saturday Ride', '2026-06-04 08:00+00', 'aaaa0000-0000-0000-0000-000000000001', 'cycle'),
  ('cccc0000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000001',
   'Coffee Meetup', '2026-06-05 09:00+00', 'aaaa0000-0000-0000-0000-000000000001', 'social');

-- A class is not raceable.
select throws_ok(
  $$ insert into race_sessions (event_id, instance_start)
     values ('cccc0000-0000-0000-0000-000000000002', '2026-06-03 18:00+00') $$,
  '23514',
  null,
  'race_sessions insert on a class event is rejected'
);

-- A run is raceable (this event omitted category, so it is 'run').
select lives_ok(
  $$ insert into race_sessions (event_id, instance_start)
     values ('cccc0000-0000-0000-0000-000000000001', '2026-06-02 19:00+00') $$,
  'race_sessions insert on a run event succeeds'
);

-- A social event cannot carry results.
select throws_ok(
  $$ insert into event_results (event_id, instance_start, user_id, distance_m, duration_s, finisher_status)
     values ('cccc0000-0000-0000-0000-000000000004', '2026-06-05 09:00+00',
             'aaaa0000-0000-0000-0000-000000000002', 5000, 1200, 'finished') $$,
  '23514',
  null,
  'event_results insert on a social event is rejected'
);

-- A cycle event can carry results.
select lives_ok(
  $$ insert into event_results (event_id, instance_start, user_id, distance_m, duration_s, finisher_status)
     values ('cccc0000-0000-0000-0000-000000000003', '2026-06-04 08:00+00',
             'aaaa0000-0000-0000-0000-000000000002', 30000, 3600, 'finished') $$,
  'event_results insert on a cycle event succeeds'
);

select * from finish();
rollback;
