-- activities view projects runs.is_dnf into the runs-branch summary jsonb
-- (migration 20270408_001), so the client twin `metricFromActivity` can exclude
-- DNF'd runs from an offline-optimistic challenge estimate — matching the
-- server aggregate (ADR 231). The lift/meal branches must NOT carry the key.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000d0000001', 'authenticated', 'authenticated', 'd@dnf.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000d0000001', 'Dee')
on conflict (id) do nothing;

-- A DNF'd run and a finished run for the same user.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, activity_type, is_dnf) values
  ('dddddddd-dddd-dddd-dddd-dddd00000001', '00000000-0000-0000-0000-0000d0000001', '2026-07-01 06:00:00+00', 42000, 18000, 'app', true, 'run', true),
  ('dddddddd-dddd-dddd-dddd-dddd00000002', '00000000-0000-0000-0000-0000d0000001', '2026-07-02 06:00:00+00', 10000, 3000, 'app', true, 'run', false);

insert into gym_workouts (id, user_id, started_at, is_public) values
  ('dddddddd-dddd-dddd-dddd-dddd00000003', '00000000-0000-0000-0000-0000d0000001', '2026-07-03 06:00:00+00', true);

insert into food_log (id, user_id, item_name, started_at, is_public) values
  ('dddddddd-dddd-dddd-dddd-dddd00000004', '00000000-0000-0000-0000-0000d0000001', 'Oats', '2026-07-04 06:00:00+00', true);

-- Runs branch: is_dnf projected, true for the DNF'd run …
select is(
  (select (summary->>'is_dnf')::boolean from activities where id = 'dddddddd-dddd-dddd-dddd-dddd00000001'),
  true, 'activities: a DNF run projects is_dnf = true');

-- … and false for the finished run.
select is(
  (select (summary->>'is_dnf')::boolean from activities where id = 'dddddddd-dddd-dddd-dddd-dddd00000002'),
  false, 'activities: a finished run projects is_dnf = false');

-- Lift / meal branches carry no is_dnf key (it is a runs-only concept).
select ok(
  not (select summary ? 'is_dnf' from activities where id = 'dddddddd-dddd-dddd-dddd-dddd00000003'),
  'activities: a gym workout summary has no is_dnf key');

select ok(
  not (select summary ? 'is_dnf' from activities where id = 'dddddddd-dddd-dddd-dddd-dddd00000004'),
  'activities: a food-log summary has no is_dnf key');

select * from finish();

rollback;
