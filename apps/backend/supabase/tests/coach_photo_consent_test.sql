-- Pins 20261125_001 — run photos are NOT shared with a coach via the coaching
-- link (audit-storage). The coach link still shares the run row + stats +
-- comments/kudos (is_run_visible_to, incl. the coach branch), but run-photo
-- rows + bytes are gated by is_run_photo_visible_to (owner-or-public, NO coach
-- branch). The exclusion must be surgical: only the coach-via-private-run path
-- disappears; the owner and public-run paths are untouched.

begin;
select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000cea0c01', 'authenticated', 'authenticated', 'coach@cpc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000cea0a01', 'authenticated', 'authenticated', 'athlete@cpc.local', '', now(), now());

set local role service_role;

-- A PRIVATE run and a PUBLIC run for the athlete, each with one photo.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
values
  ('0aa00000-0000-0000-0000-00000cea00f1', '00000000-0000-0000-0000-00000cea0a01', now(), 1800, 5000, 'app', false, '{"activity_type":"run"}'),
  ('0aa00000-0000-0000-0000-00000cea00f2', '00000000-0000-0000-0000-00000cea0a01', now(), 2400, 8000, 'app', true,  '{"activity_type":"run"}');

insert into run_photos (run_id, owner_id, storage_path) values
  ('0aa00000-0000-0000-0000-00000cea00f1', '00000000-0000-0000-0000-00000cea0a01', '00000000-0000-0000-0000-00000cea0a01/priv.jpg'),
  ('0aa00000-0000-0000-0000-00000cea00f2', '00000000-0000-0000-0000-00000cea0a01', '00000000-0000-0000-0000-00000cea0a01/pub.jpg');

-- An ACTIVE coaching link (the redemption-as-consent for training data).
insert into coach_athletes (coach_id, athlete_id, status, invite_token)
values ('00000000-0000-0000-0000-00000cea0c01', '00000000-0000-0000-0000-00000cea0a01', 'active', 'tok-cpc-1');

set local role authenticated;

-- Owner sees their own private-run photo.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000cea0a01","role":"authenticated"}';
select is(
  (select count(*)::int from run_photos where run_id = '0aa00000-0000-0000-0000-00000cea00f1'),
  1, 'owner sees the photo on their own private run');

-- Coach: the run ROW is still visible (the exclusion is photo-specific)...
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000cea0c01","role":"authenticated"}';
select is(
  (select count(*)::int from runs where id = '0aa00000-0000-0000-0000-00000cea00f1'),
  1, 'an active coach still sees the athlete''s private RUN row (unchanged)');

-- ...but the private-run PHOTO row is not.
select is(
  (select count(*)::int from run_photos where run_id = '0aa00000-0000-0000-0000-00000cea00f1'),
  0, 'an active coach does NOT see the photo on the athlete''s private run');

-- The public-run photo is still visible to the coach (and anyone) — only the
-- coach-via-private path was removed.
select is(
  (select count(*)::int from run_photos where run_id = '0aa00000-0000-0000-0000-00000cea00f2'),
  1, 'the photo on the athlete''s PUBLIC run is still visible (owner-or-public path intact)');

-- Helper-level assertions.
select ok(
  private.is_run_photo_visible_to('0aa00000-0000-0000-0000-00000cea00f1', '00000000-0000-0000-0000-00000cea0a01'),
  'is_run_photo_visible_to: owner sees their private run''s photos');
select ok(
  private.is_run_photo_visible_to('0aa00000-0000-0000-0000-00000cea00f2', '00000000-0000-0000-0000-00000cea0c01'),
  'is_run_photo_visible_to: a public run''s photos are visible to anyone');
select ok(
  not private.is_run_photo_visible_to('0aa00000-0000-0000-0000-00000cea00f1', '00000000-0000-0000-0000-00000cea0c01'),
  'is_run_photo_visible_to: an active coach does NOT get the athlete''s private-run photos');

-- Contrast: the run-level helper DOES still include the coach branch, proving
-- photos diverge from runs by design.
select ok(
  private.is_run_visible_to('0aa00000-0000-0000-0000-00000cea00f1', '00000000-0000-0000-0000-00000cea0c01'),
  'is_run_visible_to still includes the coach branch (run row stays visible; photos diverge)');

select * from finish();
rollback;
