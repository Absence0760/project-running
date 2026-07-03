-- Pins migration 20270311_001 — the public-rows column lockdown on the
-- Phase-4 multi-modal tables gym_workouts + food_log.
--
-- Two Highs from audit-public-rows.md (2026-07-02): a public gym_workouts /
-- food_log row leaked external_id + last_modified_at (+ gym notes/metadata)
-- to any reader via `select=*` on the base table. The fix drops the base
-- "owner or public read" branch (base table → owner-only) and serves public
-- reads through the redacted `public_gym_workouts` / `public_food_log`
-- views, which project only the safe columns.
--
-- This test asserts, as a non-owner (anon):
--   1. the base gym_workouts table exposes NO public row (branch dropped)
--   2. the base food_log table exposes NO public row (branch dropped)
--   3. public_gym_workouts exposes the public row (headline still works)
--   4. public_food_log exposes the public row
--   5. public_gym_workouts's column set is EXACTLY the safe projection
--      (no external_id / last_modified_at / notes / metadata)
--   6. public_food_log's column set is EXACTLY the safe projection
--      (no external_id / last_modified_at)
--   7. the OWNER still reads their own full row from the base table
--      (the redaction must not lock the owner out — 20260817_001 regression)

begin;

select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('dddddddd-0000-0000-0000-0000000000f1', 'authenticated', 'authenticated',
   'owner@gymfood.local', '', now(), now());

set local role service_role;

-- One public gym workout carrying the internal columns the view must strip.
insert into gym_workouts (
  id, user_id, title, started_at, duration_s, notes, is_public,
  external_id, last_modified_at, set_count, volume_kg, metadata
) values (
  'aaaaaaaa-0000-0000-0000-0000000000f1',
  'dddddddd-0000-0000-0000-0000000000f1',
  'Leg day', '2026-04-15 09:00+00', 3600, 'felt strong; PR on squat', true,
  'strava:987654', '2026-04-15T09:35:00Z', 5, 4200,
  jsonb_build_object('plan_workout_id', '00000000-0000-0000-0000-000000000000')
);

-- One public food_log row, same shape.
insert into food_log (
  id, user_id, started_at, item_name, meal_slot, calories,
  protein_g, carbs_g, fat_g, is_public, external_id, last_modified_at
) values (
  'bbbbbbbb-0000-0000-0000-0000000000f1',
  'dddddddd-0000-0000-0000-0000000000f1',
  '2026-04-15 12:00+00', 'Chicken bowl', 'lunch', 650,
  55, 60, 18, true, 'mfp:112233', '2026-04-15T12:05:00Z'
);

-- ── Non-owner (anon) — the worst case: a stranger with the public key ──
set local role anon;
set local "request.jwt.claims" = '';

-- 1 + 2. base tables no longer expose the public row to a non-owner.
select is(
  (select count(*)::int from gym_workouts where id = 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  0, 'base gym_workouts exposes no public row to a non-owner (public branch dropped)');

select is(
  (select count(*)::int from food_log where id = 'bbbbbbbb-0000-0000-0000-0000000000f1'),
  0, 'base food_log exposes no public row to a non-owner (public branch dropped)');

-- 3 + 4. the redacted views still serve the public row.
select is(
  (select count(*)::int from public_gym_workouts where id = 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  1, 'public_gym_workouts exposes the public workout to a non-owner');

select is(
  (select count(*)::int from public_food_log where id = 'bbbbbbbb-0000-0000-0000-0000000000f1'),
  1, 'public_food_log exposes the public meal to a non-owner');

-- 5 + 6. exact-column pins — the sensitive columns are absent from each view.
select columns_are(
  'public', 'public_gym_workouts',
  array['id', 'user_id', 'started_at', 'title', 'duration_s',
        'is_public', 'set_count', 'volume_kg', 'created_at'],
  'public_gym_workouts projects only the safe columns (no external_id / last_modified_at / notes / metadata)');

select columns_are(
  'public', 'public_food_log',
  array['id', 'user_id', 'started_at', 'item_name', 'meal_slot', 'calories',
        'protein_g', 'carbs_g', 'fat_g', 'is_public', 'created_at'],
  'public_food_log projects only the safe columns (no external_id / last_modified_at)');

-- 7. the owner still reads their own full row from the base table.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"dddddddd-0000-0000-0000-0000000000f1","role":"authenticated"}';
select is(
  (select external_id from gym_workouts where id = 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  'strava:987654', 'the owner still reads their own gym_workouts row (incl. external_id) from the base table');

select * from finish();

rollback;
