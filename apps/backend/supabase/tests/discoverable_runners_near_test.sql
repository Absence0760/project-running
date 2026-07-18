-- Opt-in coarse-location "runners nearby" discovery (issue #466).
--
-- Pins the privacy contract of `discoverable_runners_near` (migration
-- 20270426_001): the SECURITY DEFINER reader must surface ONLY runners who
-- explicitly opted in (`discoverable_nearby` = 'true'), exclude everyone the
-- other person-discovery filters exclude (minors, shadow_hidden,
-- `discoverable_in_search` = 'false', blocked either-way), return a coarse
-- distance BUCKET rather than a coordinate, and fail closed for a caller who
-- has not themselves opted in with an area (reciprocity — no lurker scrape).

begin;

select plan(10);

set search_path = public, extensions;

-- ── Fixture (RLS bypassed as the implicit test-runner role) ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000db001'::uuid, 'authenticated', 'authenticated', 'me@nb.local',    '', now(), now()),
  ('00000000-0000-0000-0000-0000000db002'::uuid, 'authenticated', 'authenticated', 'near@nb.local',  '', now(), now()),
  ('00000000-0000-0000-0000-0000000db003'::uuid, 'authenticated', 'authenticated', 'out@nb.local',   '', now(), now()),
  ('00000000-0000-0000-0000-0000000db004'::uuid, 'authenticated', 'authenticated', 'minor@nb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000db005'::uuid, 'authenticated', 'authenticated', 'hid@nb.local',   '', now(), now()),
  ('00000000-0000-0000-0000-0000000db006'::uuid, 'authenticated', 'authenticated', 'nos@nb.local',   '', now(), now()),
  ('00000000-0000-0000-0000-0000000db007'::uuid, 'authenticated', 'authenticated', 'far@nb.local',   '', now(), now()),
  ('00000000-0000-0000-0000-0000000db008'::uuid, 'authenticated', 'authenticated', 'blk@nb.local',   '', now(), now()),
  ('00000000-0000-0000-0000-0000000db009'::uuid, 'authenticated', 'authenticated', 'lurk@nb.local',  '', now(), now());

insert into user_profiles (id, display_name, preferred_unit, subscription_tier, date_of_birth, shadow_hidden)
values
  ('00000000-0000-0000-0000-0000000db001'::uuid, 'Me',            'km', 'free', null, false),
  ('00000000-0000-0000-0000-0000000db002'::uuid, 'Near Runner',   'km', 'free', null, false),
  ('00000000-0000-0000-0000-0000000db003'::uuid, 'Opted Out',     'km', 'free', null, false),
  ('00000000-0000-0000-0000-0000000db004'::uuid, 'Minor Runner',  'km', 'free', (current_date - interval '12 years')::date, false),
  ('00000000-0000-0000-0000-0000000db005'::uuid, 'Hidden Runner', 'km', 'free', null, true),
  ('00000000-0000-0000-0000-0000000db006'::uuid, 'No Search',     'km', 'free', null, false),
  ('00000000-0000-0000-0000-0000000db007'::uuid, 'Far Runner',    'km', 'free', null, false),
  ('00000000-0000-0000-0000-0000000db008'::uuid, 'Blocked One',   'km', 'free', null, false),
  ('00000000-0000-0000-0000-0000000db009'::uuid, 'Lurker',        'km', 'free', null, false);

-- Areas: near runners cluster at (0.01, 0) ≈ 1.1 km from me at (0, 0);
-- the far runner sits 5° east ≈ 556 km away, beyond the 50 km clamp.
insert into user_settings (user_id, prefs, discoverable_area)
values
  -- Me: opted in + area set → eligible caller.
  ('00000000-0000-0000-0000-0000000db001'::uuid,
   '{"discoverable_nearby":"true"}'::jsonb,
   ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography),
  -- Near: opted in, non-minor, not hidden → the one row that should appear.
  ('00000000-0000-0000-0000-0000000db002'::uuid,
   '{"discoverable_nearby":"true"}'::jsonb,
   ST_SetSRID(ST_MakePoint(0.01, 0), 4326)::geography),
  -- Opted out: area set but discoverable_nearby unset (default false).
  ('00000000-0000-0000-0000-0000000db003'::uuid,
   '{}'::jsonb,
   ST_SetSRID(ST_MakePoint(0.01, 0), 4326)::geography),
  -- Minor: opted in but under 18 by the canonical DOB column.
  ('00000000-0000-0000-0000-0000000db004'::uuid,
   '{"discoverable_nearby":"true"}'::jsonb,
   ST_SetSRID(ST_MakePoint(0.01, 0), 4326)::geography),
  -- Hidden: opted in but shadow_hidden.
  ('00000000-0000-0000-0000-0000000db005'::uuid,
   '{"discoverable_nearby":"true"}'::jsonb,
   ST_SetSRID(ST_MakePoint(0.01, 0), 4326)::geography),
  -- Search opt-out: nearby on, but discoverable_in_search off.
  ('00000000-0000-0000-0000-0000000db006'::uuid,
   '{"discoverable_nearby":"true","discoverable_in_search":"false"}'::jsonb,
   ST_SetSRID(ST_MakePoint(0.01, 0), 4326)::geography),
  -- Far: opted in but outside the radius clamp.
  ('00000000-0000-0000-0000-0000000db007'::uuid,
   '{"discoverable_nearby":"true"}'::jsonb,
   ST_SetSRID(ST_MakePoint(5, 0), 4326)::geography),
  -- Blocked: opted in + near, but me blocks them.
  ('00000000-0000-0000-0000-0000000db008'::uuid,
   '{"discoverable_nearby":"true"}'::jsonb,
   ST_SetSRID(ST_MakePoint(0.01, 0), 4326)::geography),
  -- Lurker: NOT opted in, but has an area — used to test reciprocity.
  ('00000000-0000-0000-0000-0000000db009'::uuid,
   '{}'::jsonb,
   ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography);

insert into user_blocks (blocker_id, blocked_id)
values
  ('00000000-0000-0000-0000-0000000db001'::uuid,
   '00000000-0000-0000-0000-0000000db008'::uuid);

-- ── Call as Me ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000db001"}';

select is(
  (select count(*) from discoverable_runners_near()
     where id = '00000000-0000-0000-0000-0000000db002'::uuid),
  1::bigint, 'opted-in nearby non-minor runner appears');

select is(
  (select count(*) from discoverable_runners_near()
     where id = '00000000-0000-0000-0000-0000000db003'::uuid),
  0::bigint, 'runner who did not opt in is excluded');

select is(
  (select count(*) from discoverable_runners_near()
     where id = '00000000-0000-0000-0000-0000000db004'::uuid),
  0::bigint, 'declared minor is excluded even when opted in');

select is(
  (select count(*) from discoverable_runners_near()
     where id = '00000000-0000-0000-0000-0000000db005'::uuid),
  0::bigint, 'shadow_hidden runner is excluded');

select is(
  (select count(*) from discoverable_runners_near()
     where id = '00000000-0000-0000-0000-0000000db006'::uuid),
  0::bigint, 'discoverable_in_search=false runner is excluded');

select is(
  (select count(*) from discoverable_runners_near()
     where id = '00000000-0000-0000-0000-0000000db007'::uuid),
  0::bigint, 'runner beyond the radius is excluded');

select is(
  (select count(*) from discoverable_runners_near()
     where id = '00000000-0000-0000-0000-0000000db008'::uuid),
  0::bigint, 'blocked runner is excluded');

select is(
  (select count(*)::int from discoverable_runners_near()),
  1, 'exactly one eligible runner surfaces for the caller');

-- Coarse-only output: bucket 0 (<2 km), and the row carries no coordinate
-- column (guaranteed by the return type; asserting the bucket value here).
select is(
  (select bucket from discoverable_runners_near()
     where id = '00000000-0000-0000-0000-0000000db002'::uuid),
  0, 'distance is returned as coarse bucket 0 (~2 km), not a coordinate');

-- ── Reciprocity: a caller who has not opted in gets zero rows ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000db009"}';
select is(
  (select count(*)::int from discoverable_runners_near()),
  0, 'a caller who has not opted in sees nobody (fail-closed, no scrape)');

select set_config('request.jwt.claims', null, true);

select * from finish();
rollback;
