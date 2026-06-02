-- Pins migration 20261127_001 -- the runs_hr_series_url_path_shape CHECK.
--
-- hr_series_url points at an owner-only Storage sidecar. Like track_url
-- (20260621_001), it must be pinned to the canonical
-- {user_id}/{run_id}.hr.json.gz path so a malicious owner can't rewrite their
-- own row's column to point at another user's blob. The runs UPDATE policy is
-- `auth.uid() = user_id`, so without this CHECK a user could forge the path.
begin;
select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'hr-owner@hr.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'hr-victim@hr.local', '', now(), now());

insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
values ('aaaaaaaa-0000-0000-0000-00000000ff01', 'aaaaaaaa-0000-0000-0000-0000000000a1', now(), 1800, 0, 'app', false, '{"activity_type":"run"}');

-- NULL is allowed (most runs have no HR sidecar).
select lives_ok(
  $$ update runs set hr_series_url = null
       where id = 'aaaaaaaa-0000-0000-0000-00000000ff01' $$,
  'hr_series_url may be null');

-- The canonical {user_id}/{run_id}.hr.json.gz path is accepted.
select lives_ok(
  $$ update runs set hr_series_url =
       'aaaaaaaa-0000-0000-0000-0000000000a1/aaaaaaaa-0000-0000-0000-00000000ff01.hr.json.gz'
       where id = 'aaaaaaaa-0000-0000-0000-00000000ff01' $$,
  'the canonical hr-sidecar path is accepted');

-- A path pointing at ANOTHER user's folder is rejected (the forge we care about).
select throws_ok(
  $$ update runs set hr_series_url =
       'aaaaaaaa-0000-0000-0000-0000000000a2/aaaaaaaa-0000-0000-0000-00000000ff01.hr.json.gz'
       where id = 'aaaaaaaa-0000-0000-0000-00000000ff01' $$,
  '23514',
  null,
  'a victim-folder hr_series_url path is rejected by the CHECK');

-- A path with the wrong extension / shape is rejected too.
select throws_ok(
  $$ update runs set hr_series_url =
       'aaaaaaaa-0000-0000-0000-0000000000a1/aaaaaaaa-0000-0000-0000-00000000ff01.json.gz'
       where id = 'aaaaaaaa-0000-0000-0000-00000000ff01' $$,
  '23514',
  null,
  'a non-canonical hr_series_url shape (track extension) is rejected');

select * from finish();
rollback;
