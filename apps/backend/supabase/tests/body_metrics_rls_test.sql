-- Pins migration 20261216_001 (body_metrics weight time-series + height_cm on
-- user_profiles). Body metrics are GDPR special-category health data, so the
-- contract is strict:
--
--   1. body_metrics is owner-only for SELECT/INSERT/UPDATE/DELETE — there is
--      NO public-read policy (unlike gym_workouts / food_log). A stranger sees
--      and writes nothing.
--   2. weight_kg is range-checked (> 0, <= 500); a non-physical value is
--      rejected at insert.
--   3. The row cascade-deletes when its auth.users row is removed (DSAR
--      erasure path).
--   4. height_cm on user_profiles is owner-only: it is NOT on the public-safe
--      column grant (20260707_001 lockdown), so a stranger's table SELECT of
--      it is denied, while the owner reads it back through get_my_profile().
begin;
select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'owner@bm.local', '', now(), now()),
  ('99999999-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated', 'stranger@bm.local', '', now(), now());

-- user_profiles rows exist via the handle_new_user trigger on auth.users
-- insert; set the owner's height (superuser, RLS bypassed).
update user_profiles set height_cm = 178.0 where id = '99999999-0000-0000-0000-0000000000b1';

-- Seed two weight entries for the owner (superuser).
insert into body_metrics (id, user_id, recorded_at, weight_kg)
values
  ('99999999-0000-0000-0000-0000000bbb01', '99999999-0000-0000-0000-0000000000b1', now() - interval '7 days', 70.5),
  ('99999999-0000-0000-0000-0000000bbb02', '99999999-0000-0000-0000-0000000000b1', now(), 69.8);

set local role authenticated;

-- ============================================================
-- body_metrics: owner-only time-series
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000000b1","role":"authenticated"}';

select is(
  (select count(*)::int from body_metrics where user_id = '99999999-0000-0000-0000-0000000000b1'),
  2, 'owner reads their own weight time-series');

select lives_ok(
  $$ insert into body_metrics (user_id, weight_kg) values ('99999999-0000-0000-0000-0000000000b1', 71.2) $$,
  'owner inserts their own weight entry');

select throws_ok(
  $$ insert into body_metrics (user_id, weight_kg) values ('99999999-0000-0000-0000-0000000000b1', 0) $$,
  '23514',
  null,
  'a non-physical weight (0) is rejected by the CHECK');

select throws_ok(
  $$ insert into body_metrics (user_id, weight_kg) values ('99999999-0000-0000-0000-0000000000b1', 900) $$,
  '23514',
  null,
  'a non-physical weight (900 kg) is rejected by the CHECK');

-- Stranger sees none of the owner's metrics and cannot forge one.
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000000b2","role":"authenticated"}';

select is(
  (select count(*)::int from body_metrics where user_id = '99999999-0000-0000-0000-0000000000b1'),
  0, 'a stranger cannot read another user''s weight metrics');

select throws_ok(
  $$ insert into body_metrics (user_id, weight_kg) values ('99999999-0000-0000-0000-0000000000b1', 65.0) $$,
  '42501',
  null,
  'a stranger cannot insert a weight entry owned by someone else');

-- A stranger's delete against the owner's row is RLS-filtered to zero rows.
select lives_ok(
  $$ delete from body_metrics where id = '99999999-0000-0000-0000-0000000bbb01' $$,
  'a stranger''s delete runs but is RLS-filtered');
select is(
  (select count(*)::int from body_metrics where id = '99999999-0000-0000-0000-0000000bbb01'),
  1, 'the owner''s weight entry survived the stranger''s delete (row invisible)')
  from (select set_config('request.jwt.claims', '{"sub":"99999999-0000-0000-0000-0000000000b1","role":"authenticated"}', true)) _;

-- ============================================================
-- cascade-delete on auth.users removal (DSAR erasure)
-- ============================================================
reset role;
delete from auth.users where id = '99999999-0000-0000-0000-0000000000b1';
select is(
  (select count(*)::int from body_metrics where user_id = '99999999-0000-0000-0000-0000000000b1'),
  0, 'deleting the auth user cascade-removes their body_metrics');

-- ============================================================
-- height_cm on user_profiles is owner-only (off the public grant)
-- ============================================================
-- The stranger (still present) cannot SELECT height_cm at the table level:
-- the 20260707_001 lockdown revoked table SELECT and height_cm is not in the
-- re-granted public-safe column list.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000000b2","role":"authenticated"}';
select throws_ok(
  $$ select height_cm from user_profiles where id = '99999999-0000-0000-0000-0000000000b2' $$,
  '42501',
  null,
  'height_cm is not on the public-safe column grant (owner-only via get_my_profile)');

reset role;
select * from finish();
rollback;
