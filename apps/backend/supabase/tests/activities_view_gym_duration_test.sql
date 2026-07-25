-- activities view projects gym_workouts.duration_s into the lift-branch
-- summary jsonb (migration 20270429_001). The mobile nutrition surface derives
-- its exercise calories + hydration minutes from this field, so without it a
-- logged strength session contributed zero on both counts. A session with no
-- timer must still project the key, as an explicit null — "unknown", never 0.

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000e0000001', 'authenticated', 'authenticated', 'g@dur.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000e0000001', 'Gee')
on conflict (id) do nothing;

-- A timed gym workout and an untimed one.
insert into gym_workouts (id, user_id, started_at, duration_s, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeee00000001', '00000000-0000-0000-0000-0000e0000001', '2026-07-03 06:00:00+00', 3600, true),
  ('eeeeeeee-eeee-eeee-eeee-eeee00000002', '00000000-0000-0000-0000-0000e0000001', '2026-07-04 06:00:00+00', null, true);

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, activity_type) values
  ('eeeeeeee-eeee-eeee-eeee-eeee00000003', '00000000-0000-0000-0000-0000e0000001', '2026-07-05 06:00:00+00', 10000, 3000, 'app', true, 'run');

-- The timed session projects its real duration.
select is(
  (select (summary->>'duration_s')::int from activities where id = 'eeeeeeee-eeee-eeee-eeee-eeee00000001'),
  3600, 'activities: a timed gym workout projects duration_s');

-- The untimed one still carries the key, as null — a consumer must be able to
-- tell "no timer" from "zero seconds".
select ok(
  (select summary ? 'duration_s' from activities where id = 'eeeeeeee-eeee-eeee-eeee-eeee00000002'),
  'activities: an untimed gym workout still carries the duration_s key');

select is(
  (select summary->>'duration_s' from activities where id = 'eeeeeeee-eeee-eeee-eeee-eeee00000002'),
  null, 'activities: an untimed gym workout projects duration_s as null');

-- The lift branch keeps its existing keys …
select ok(
  (select summary ? 'volume_kg' and summary ? 'set_count' and summary ? 'title'
   from activities where id = 'eeeeeeee-eeee-eeee-eeee-eeee00000001'),
  'activities: the lift summary keeps title / set_count / volume_kg');

-- … and the runs branch is untouched.
select is(
  (select (summary->>'duration_s')::int from activities where id = 'eeeeeeee-eeee-eeee-eeee-eeee00000003'),
  3000, 'activities: the runs branch still projects duration_s');

select * from finish();

rollback;
