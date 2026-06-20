-- Pins migration 20270224_001 (gear_wear_logs — per-shoe wear-pattern logging).
--
-- gear_wear_logs is owner-private end to end: only the owner reads/writes their
-- wear observations, and an INSERT must own BOTH the log row (owner_id = me)
-- AND the parent gear. Unlike run_gear, there is NO public-visibility path —
-- wear notes never leak via a public run.
--
--   1. owner reads only their own wear logs; a stranger sees none.
--   2. INSERT requires owning the parent gear (the gear EXISTS gate).
--   3. INSERT as owner-of-gear succeeds.
--   4. a stranger's UPDATE/DELETE against the owner's log is RLS-filtered to
--      zero rows (the row is invisible, so no error, no effect).
--   5. deleting the parent gear cascades the wear logs away.
begin;
select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'owner@wearlog.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'stranger@wearlog.local', '', now(), now());

-- Seed (superuser, RLS bypassed): owner has one shoe + one wear log on it.
insert into gear (id, owner_id, kind, name)
values
  ('aaaaaaaa-0000-0000-0000-00000000ee01', 'aaaaaaaa-0000-0000-0000-0000000000a1', 'shoe', 'Owner Shoe');

insert into gear_wear_logs (id, gear_id, owner_id, note, area)
values
  ('aaaaaaaa-0000-0000-0000-000000001101', 'aaaaaaaa-0000-0000-0000-00000000ee01', 'aaaaaaaa-0000-0000-0000-0000000000a1', 'outsole lugs worn at the heel', 'outsole');

set local role authenticated;

-- ============================================================
-- owner-only read
-- ============================================================
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select count(*)::int from gear_wear_logs where gear_id = 'aaaaaaaa-0000-0000-0000-00000000ee01'),
  1, 'owner reads their own wear log');

select is(
  (select note from gear_wear_logs where id = 'aaaaaaaa-0000-0000-0000-000000001101'),
  'outsole lugs worn at the heel', 'owner reads the wear note text');

set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated"}';

select is(
  (select count(*)::int from gear_wear_logs where gear_id = 'aaaaaaaa-0000-0000-0000-00000000ee01'),
  0, 'a stranger cannot read another user''s wear log');

-- ============================================================
-- INSERT gate: must own the log row AND the parent gear
-- ============================================================
-- Stranger inserts a log on the owner's gear, as themselves → fails the gear
-- EXISTS gate (they don't own gee01).
select throws_ok(
  $$ insert into gear_wear_logs (gear_id, owner_id, note)
       values ('aaaaaaaa-0000-0000-0000-00000000ee01', 'aaaaaaaa-0000-0000-0000-0000000000e1', 'forged') $$,
  '42501',
  null,
  'a stranger cannot log wear against gear they do not own');

-- Stranger inserts a log claiming the OWNER's id → fails the owner_id = me check.
select throws_ok(
  $$ insert into gear_wear_logs (gear_id, owner_id, note)
       values ('aaaaaaaa-0000-0000-0000-00000000ee01', 'aaaaaaaa-0000-0000-0000-0000000000a1', 'forged') $$,
  '42501',
  null,
  'a stranger cannot insert a wear log claiming another user as owner');

-- Owner inserts a second log on their own gear → succeeds.
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$ insert into gear_wear_logs (gear_id, owner_id, note, area)
       values ('aaaaaaaa-0000-0000-0000-00000000ee01', 'aaaaaaaa-0000-0000-0000-0000000000a1', 'midsole feels dead', 'midsole') $$,
  'owner can log wear against their own gear');
select is(
  (select count(*)::int from gear_wear_logs where gear_id = 'aaaaaaaa-0000-0000-0000-00000000ee01'),
  2, 'owner now sees both wear logs');

-- ============================================================
-- stranger UPDATE/DELETE is RLS-filtered (no error, zero effect)
-- ============================================================
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated"}';
select lives_ok(
  $$ delete from gear_wear_logs where id = 'aaaaaaaa-0000-0000-0000-000000001101' $$,
  'a stranger''s delete runs but is RLS-filtered');

-- Back to owner: the row the stranger "deleted" is still there.
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is(
  (select count(*)::int from gear_wear_logs where id = 'aaaaaaaa-0000-0000-0000-000000001101'),
  1, 'the stranger''s delete matched no visible row (log survives)');

-- ============================================================
-- cascade: deleting the gear removes its wear logs
-- ============================================================
delete from gear where id = 'aaaaaaaa-0000-0000-0000-00000000ee01';
select is(
  (select count(*)::int from gear_wear_logs where gear_id = 'aaaaaaaa-0000-0000-0000-00000000ee01'),
  0, 'deleting the parent gear cascades its wear logs');

select * from finish();
rollback;
