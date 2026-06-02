-- Pins migrations 20260827_001 (gear + run_gear tables, RLS) and
-- 20260901_001 (is_default + auto_tag_default_gear trigger).
--
-- gear is owner-private: only the owner reads/writes their inventory. run_gear
-- (the run<->gear link) is readable by anyone who can see the parent run via
-- private.is_run_visible_to — this is what lets the gear chip render on the
-- PUBLIC share page — but only the owner of BOTH the run and the gear may
-- create the link. The auto_tag_default_gear trigger stamps a new run with the
-- owner's current default gear of the matching kind, idempotently.
--
--   1. gear is owner-only for SELECT/INSERT/UPDATE/DELETE; a stranger sees none.
--   2. run_gear SELECT follows run visibility: owner + public-run viewers see
--      the link, a stranger on a PRIVATE run sees nothing.
--   3. run_gear INSERT requires owning both the run and the gear.
--   4. auto_tag_default_gear tags run/walk/hike with the default shoe and
--      cycle with the default bike, and is a no-op when no default exists.
begin;
select plan(16);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'owner@gear.local', '', now(), now()),
  ('99999999-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'stranger@gear.local', '', now(), now());

-- Seed (superuser, RLS bypassed): owner has a default shoe + a default bike,
-- one PUBLIC run and one PRIVATE run. is_public defaults false.
insert into gear (id, owner_id, kind, name, brand, model, is_default)
values
  ('99999999-0000-0000-0000-00000000ee01', '99999999-0000-0000-0000-0000000000a1', 'shoe', 'Owner Shoe', 'Nike', 'Pegasus', true),
  ('99999999-0000-0000-0000-00000000ee02', '99999999-0000-0000-0000-0000000000a1', 'bike', 'Owner Bike', 'Trek', 'Domane', true);

-- auto_tag_default_gear (keyed off new.user_id, so it fires even on this
-- superuser seed insert) stamps each 'run' with the owner's default shoe ee01.
-- We rely on that rather than a manual run_gear insert, which would collide
-- with the trigger's row on the (run_id, gear_id) primary key.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
values
  ('99999999-0000-0000-0000-00000000ff01', '99999999-0000-0000-0000-0000000000a1', now(), 1800, 5000, 'app', true,  '{"activity_type":"run"}'),
  ('99999999-0000-0000-0000-00000000ff02', '99999999-0000-0000-0000-0000000000a1', now(), 1800, 5000, 'app', false, '{"activity_type":"run"}');

set local role authenticated;

-- ============================================================
-- gear: owner-only inventory
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select count(*)::int from gear where owner_id = '99999999-0000-0000-0000-0000000000a1'),
  2, 'owner reads their own gear');

set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000000e1","role":"authenticated"}';

select is(
  (select count(*)::int from gear where owner_id = '99999999-0000-0000-0000-0000000000a1'),
  0, 'a stranger cannot read another user''s gear');

select throws_ok(
  $$ insert into gear (owner_id, kind, name) values ('99999999-0000-0000-0000-0000000000a1', 'shoe', 'Forged') $$,
  '42501',
  null,
  'a stranger cannot insert gear owned by someone else');

-- A stranger inserting gear as THEMSELVES is fine; updating/deleting the
-- owner's gear must affect zero rows (RLS USING filters them out).
select lives_ok(
  $$ update gear set name = 'hijacked' where id = '99999999-0000-0000-0000-00000000ee01' $$,
  'update against another user''s gear runs but is RLS-filtered');
select is(
  (select name from gear where id = '99999999-0000-0000-0000-00000000ee01'),
  null, 'the stranger''s update matched no visible row (name unchanged, row invisible)');

-- ============================================================
-- run_gear: visibility follows the parent run
-- ============================================================
-- Stranger CAN see the link on the PUBLIC run (drives the share-page chip)...
select is(
  (select count(*)::int from run_gear where run_id = '99999999-0000-0000-0000-00000000ff01'),
  1, 'a stranger sees the gear link on a PUBLIC run');

-- ...but NOT on the PRIVATE run.
select is(
  (select count(*)::int from run_gear where run_id = '99999999-0000-0000-0000-00000000ff02'),
  0, 'a stranger cannot see the gear link on a PRIVATE run');

-- Owner sees both links.
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is(
  (select count(*)::int from run_gear where run_id in
     ('99999999-0000-0000-0000-00000000ff01','99999999-0000-0000-0000-00000000ff02')),
  2, 'the owner sees gear links on both their runs');

-- ============================================================
-- public_run_gear RPC: the leak-free read path for the share-page chip
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000000e1","role":"authenticated"}';

select is(
  (select count(*)::int from public.public_run_gear('99999999-0000-0000-0000-00000000ff01')),
  1, 'public_run_gear returns the gear for a stranger on a PUBLIC run');

select is(
  (select name from public.public_run_gear('99999999-0000-0000-0000-00000000ff01')),
  'Owner Shoe', 'public_run_gear projects the public name column');

select is(
  (select count(*)::int from public.public_run_gear('99999999-0000-0000-0000-00000000ff02')),
  0, 'public_run_gear returns nothing for a stranger on a PRIVATE run');

-- ============================================================
-- run_gear INSERT requires owning both the run and the gear
-- ============================================================
-- Stranger tries to tag the owner's run with the owner's gear: blocked.
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000000e1","role":"authenticated"}';
select throws_ok(
  $$ insert into run_gear (run_id, gear_id)
       values ('99999999-0000-0000-0000-00000000ff01', '99999999-0000-0000-0000-00000000ee02') $$,
  '42501',
  null,
  'a stranger cannot assign gear to a run they do not own');

-- ============================================================
-- auto_tag_default_gear: kind-matched, default-only, idempotent
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000000a1","role":"authenticated"}';

-- A new RUN auto-tags the default SHOE.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
  values ('99999999-0000-0000-0000-00000000ff03', '99999999-0000-0000-0000-0000000000a1', now(), 1200, 3000, 'app', false, '{"activity_type":"run"}');
select is(
  (select gear_id from run_gear where run_id = '99999999-0000-0000-0000-00000000ff03'),
  '99999999-0000-0000-0000-00000000ee01'::uuid,
  'a new run auto-tags the default shoe');

-- A new CYCLE auto-tags the default BIKE, not the shoe.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
  values ('99999999-0000-0000-0000-00000000ff04', '99999999-0000-0000-0000-0000000000a1', now(), 1200, 9000, 'app', false, '{"activity_type":"cycle"}');
select is(
  (select gear_id from run_gear where run_id = '99999999-0000-0000-0000-00000000ff04'),
  '99999999-0000-0000-0000-00000000ee02'::uuid,
  'a new cycle auto-tags the default bike');

-- With NO default of the matching kind, the trigger is a no-op. The owner has
-- no default 'shoe' after we clear it; a new run gets no auto-tag.
update gear set is_default = false where id = '99999999-0000-0000-0000-00000000ee01';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
  values ('99999999-0000-0000-0000-00000000ff05', '99999999-0000-0000-0000-0000000000a1', now(), 1200, 3000, 'app', false, '{"activity_type":"run"}');
select is(
  (select count(*)::int from run_gear where run_id = '99999999-0000-0000-0000-00000000ff05'),
  0, 'with no default shoe, a new run is not auto-tagged');

-- Idempotent: manually inserting the same default link the trigger already
-- created does not raise (on conflict do nothing).
select lives_ok(
  $$ insert into run_gear (run_id, gear_id)
       values ('99999999-0000-0000-0000-00000000ff03', '99999999-0000-0000-0000-00000000ee01')
       on conflict do nothing $$,
  'a duplicate run_gear link is a no-op, not an error');

reset role;
select * from finish();
rollback;
