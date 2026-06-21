-- Pins migration 20270207_001 (public_recaps table) + 20270305_001
-- (lookup-by-id hardening).
--
-- A published recap is the FAIL-CLOSED public-share artifact for the
-- Year-in-Running / "Wrapped" recap. Contract:
--   1. Owner has full CRUD on their own rows (publish / re-publish / revoke).
--   2. The uuid id IS the capability token, BUT it is enforced as
--      lookup-by-id through the SECURITY DEFINER `public_recap_by_id` RPC.
--      The bare table is NOT anon/authenticated-readable — a non-owner
--      cannot bulk-enumerate every publisher's user_id + snapshot.
--   3. A non-owner CANNOT write (insert/update/delete) another user's recap.
--   4. The (user_id, period_kind, period_key) unique key makes re-publishing a
--      period an upsert, not a duplicate.
--   5. Rows cascade-delete when the owner's auth.users row is deleted.
begin;
select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'owner@recap.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'stranger@recap.local', '', now(), now());

-- Seed (superuser, RLS bypassed): the owner has one published year recap.
insert into public_recaps (id, user_id, period_kind, period_key, snapshot)
values
  ('aaaaaaaa-0000-0000-0000-0000000000f1', 'aaaaaaaa-0000-0000-0000-0000000000a1',
   'year', '2026', '{"year":2026,"runCount":142,"totalDistanceM":1234000}'::jsonb);

set local role authenticated;

-- ============================================================
-- 1. Owner full CRUD
-- ============================================================
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select count(*)::int from public_recaps where user_id = 'aaaaaaaa-0000-0000-0000-0000000000a1'),
  1, 'owner reads their own recap');

select lives_ok(
  $$ insert into public_recaps (user_id, period_kind, period_key, snapshot)
       values ('aaaaaaaa-0000-0000-0000-0000000000a1', 'month', '2026-03', '{"year":2026,"month":3}'::jsonb) $$,
  'owner can publish a new (month) recap');

select lives_ok(
  $$ update public_recaps set snapshot = '{"year":2026,"runCount":200}'::jsonb
       where id = 'aaaaaaaa-0000-0000-0000-0000000000f1' $$,
  'owner can re-publish (update) their recap');

select lives_ok(
  $$ delete from public_recaps where period_kind = 'month' and user_id = 'aaaaaaaa-0000-0000-0000-0000000000a1' $$,
  'owner can revoke (delete) their recap');

-- The unique key makes a same-period re-publish an upsert target, not a dup.
select throws_ok(
  $$ insert into public_recaps (user_id, period_kind, period_key, snapshot)
       values ('aaaaaaaa-0000-0000-0000-0000000000a1', 'year', '2026', '{}'::jsonb) $$,
  '23505',
  null,
  'a second row for the same (user, kind, key) violates the unique key');

-- ============================================================
-- 2 + 3. A stranger CANNOT enumerate the table or write another user's recap
-- ============================================================
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated"}';

-- The bare table is no longer SELECT-able by a non-owner: the
-- `public_recaps_public_read` policy was dropped, so a stranger's
-- direct-table read of the owner's row returns zero (RLS-filtered).
select is(
  (select count(*)::int from public_recaps where id = 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  0, 'a stranger CANNOT read the owner''s recap off the bare table');

-- A bulk enumeration query (no id filter) also returns zero — no
-- publisher harvest surface.
select is(
  (select count(*)::int from public_recaps),
  0, 'a stranger CANNOT bulk-enumerate published recaps');

-- The capability-token path is the RPC, which returns the row by id.
select is(
  (select count(*)::int from public_recap_by_id('aaaaaaaa-0000-0000-0000-0000000000f1')),
  1, 'a stranger CAN read the owner''s recap via public_recap_by_id (the share link)');

select throws_ok(
  $$ insert into public_recaps (user_id, period_kind, period_key, snapshot)
       values ('aaaaaaaa-0000-0000-0000-0000000000a1', 'year', '2025', '{}'::jsonb) $$,
  '42501',
  null,
  'a stranger cannot publish a recap owned by someone else');

-- Update against the owner's row is RLS-filtered to zero rows.
select lives_ok(
  $$ update public_recaps set snapshot = '{"hijacked":true}'::jsonb
       where id = 'aaaaaaaa-0000-0000-0000-0000000000f1' $$,
  'a stranger''s update runs but is RLS-filtered');
select is(
  (select snapshot->>'hijacked' from public_recap_by_id('aaaaaaaa-0000-0000-0000-0000000000f1')),
  null, 'the stranger''s update matched no writable row (snapshot unchanged)');

-- ============================================================
-- anon (the actual share-page audience) — RPC only, no table read
-- ============================================================
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select count(*)::int from public_recaps),
  0, 'anon CANNOT enumerate the bare table');

select is(
  (select count(*)::int from public_recap_by_id('aaaaaaaa-0000-0000-0000-0000000000f1')),
  1, 'anon reads the published recap via the RPC (the unfurl path)');

reset role;

-- ============================================================
-- 5. Cascade on owner delete
-- ============================================================
delete from auth.users where id = 'aaaaaaaa-0000-0000-0000-0000000000a1';
select is(
  (select count(*)::int from public_recaps where user_id = 'aaaaaaaa-0000-0000-0000-0000000000a1'),
  0, 'deleting the owner cascades away their published recaps');

select * from finish();
rollback;
