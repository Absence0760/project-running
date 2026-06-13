-- Pins migration 20270116_001 -- run_engagement_counts(uuid[]) grouped counts.
--
-- The feed's batch engagement read returns one row per run with kudos_count +
-- comment_count from a server-side GROUP BY (replacing a client-side row count
-- that shipped every kudos/comment row). Assert the counts are correct, zero
-- for a run with no engagement, and that only requested ids come back.
begin;
select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('ec000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'owner@ec.local', '', now(), now()),
  ('ec000000-0000-0000-0000-00000000c001', 'authenticated', 'authenticated', 'fan1@ec.local', '', now(), now()),
  ('ec000000-0000-0000-0000-00000000c002', 'authenticated', 'authenticated', 'fan2@ec.local', '', now(), now());

insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
values
  ('ec000000-0000-0000-0000-0000000000f1', 'ec000000-0000-0000-0000-0000000000a1', now(), 1800, 5000, 'app', true, '{"activity_type":"run"}'),
  ('ec000000-0000-0000-0000-0000000000f2', 'ec000000-0000-0000-0000-0000000000a1', now(), 1200, 3000, 'app', true, '{"activity_type":"run"}');

-- Run f1: 2 kudos + 3 comments. Run f2: nothing.
insert into run_kudos (user_id, run_id) values
  ('ec000000-0000-0000-0000-00000000c001', 'ec000000-0000-0000-0000-0000000000f1'),
  ('ec000000-0000-0000-0000-00000000c002', 'ec000000-0000-0000-0000-0000000000f1');
insert into run_comments (run_id, author_id, body) values
  ('ec000000-0000-0000-0000-0000000000f1', 'ec000000-0000-0000-0000-00000000c001', 'one'),
  ('ec000000-0000-0000-0000-0000000000f1', 'ec000000-0000-0000-0000-00000000c002', 'two'),
  ('ec000000-0000-0000-0000-0000000000f1', 'ec000000-0000-0000-0000-00000000c001', 'three');

select is(
  (select kudos_count from run_engagement_counts(array['ec000000-0000-0000-0000-0000000000f1']::uuid[])),
  2::bigint, 'f1 kudos_count = 2');
select is(
  (select comment_count from run_engagement_counts(array['ec000000-0000-0000-0000-0000000000f1']::uuid[])),
  3::bigint, 'f1 comment_count = 3');

-- A run with no engagement returns explicit zeros (so the feed shows 0, not a
-- missing row).
select is(
  (select kudos_count from run_engagement_counts(array['ec000000-0000-0000-0000-0000000000f2']::uuid[])),
  0::bigint, 'f2 kudos_count = 0');
select is(
  (select comment_count from run_engagement_counts(array['ec000000-0000-0000-0000-0000000000f2']::uuid[])),
  0::bigint, 'f2 comment_count = 0');

-- One row per requested id, and only requested ids.
select is(
  (select count(*) from run_engagement_counts(array[
    'ec000000-0000-0000-0000-0000000000f1',
    'ec000000-0000-0000-0000-0000000000f2']::uuid[])),
  2::bigint, 'one row per requested id');
select is(
  (select count(*) from run_engagement_counts(array[]::uuid[])),
  0::bigint, 'empty input returns no rows');

select * from finish();
rollback;
