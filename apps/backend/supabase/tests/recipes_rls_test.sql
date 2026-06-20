-- Pins migration 20270221_001 (recipes: recipes + recipe_ingredients). The
-- contract:
--
--   1. recipes is owner-only for SELECT/INSERT/UPDATE/DELETE (user_id =
--      auth.uid()). A stranger sees and writes nothing.
--   2. recipe_ingredients have no owner column of their own — visibility/writes
--      are gated via EXISTS against the parent recipe's user_id (the
--      "visible via parent" idiom meal_template_items / gym_routine_sets use).
--   3. The whole tree cascade-deletes when the owner's auth.users row is removed
--      (DSAR erasure path), and deleting a recipe cascades to its ingredients.
begin;
select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-00000000e001', 'authenticated', 'authenticated', 'owner@rc.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000e002', 'authenticated', 'authenticated', 'stranger@rc.local', '', now(), now());

-- Seed a recipe tree for the owner (superuser, RLS bypassed).
insert into recipes (id, user_id, name, servings, meal_slot, ingredient_count)
values ('99999999-0000-0000-0000-0000000eeaa1', '99999999-0000-0000-0000-00000000e001', 'Chilli', 2, 'dinner', 1);

insert into recipe_ingredients (id, recipe_id, position, item_name, quantity, calories)
values ('99999999-0000-0000-0000-0000000eebb1', '99999999-0000-0000-0000-0000000eeaa1', 0, 'Beans', 1, 300);

set local role authenticated;

-- ============================================================
-- recipes: owner-only
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000e001","role":"authenticated"}';

select is(
  (select count(*)::int from recipes where user_id = '99999999-0000-0000-0000-00000000e001'),
  1, 'owner reads their own recipe');

select lives_ok(
  $$ insert into recipes (user_id, name) values ('99999999-0000-0000-0000-00000000e001', 'Stew') $$,
  'owner inserts their own recipe');

select is(
  (select count(*)::int from recipe_ingredients where recipe_id = '99999999-0000-0000-0000-0000000eeaa1'),
  1, 'owner reads their recipe''s ingredients via the parent gate');

-- ============================================================
-- Stranger sees / writes nothing
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000e002","role":"authenticated"}';

select is(
  (select count(*)::int from recipes where user_id = '99999999-0000-0000-0000-00000000e001'),
  0, 'a stranger cannot read another user''s recipes');
select is(
  (select count(*)::int from recipe_ingredients where recipe_id = '99999999-0000-0000-0000-0000000eeaa1'),
  0, 'a stranger cannot read another user''s recipe ingredients');

select throws_ok(
  $$ insert into recipes (user_id, name) values ('99999999-0000-0000-0000-00000000e001', 'Forged') $$,
  '42501',
  null,
  'a stranger cannot insert a recipe owned by someone else');

select throws_ok(
  $$ insert into recipe_ingredients (recipe_id, position, item_name)
     values ('99999999-0000-0000-0000-0000000eeaa1', 1, 'Forged') $$,
  '42501',
  null,
  'a stranger cannot add an ingredient to another user''s recipe (parent gate)');

-- A stranger's delete against the owner's recipe is RLS-filtered to zero.
select lives_ok(
  $$ delete from recipes where id = '99999999-0000-0000-0000-0000000eeaa1' $$,
  'a stranger''s delete runs but is RLS-filtered');
select is(
  (select count(*)::int from recipes where id = '99999999-0000-0000-0000-0000000eeaa1'),
  1, 'the owner''s recipe survived the stranger''s delete (row invisible)')
  from (select set_config('request.jwt.claims', '{"sub":"99999999-0000-0000-0000-00000000e001","role":"authenticated"}', true)) _;

-- Owner can delete their own recipe; the ingredient cascades.
select lives_ok(
  $$ delete from recipes where id = '99999999-0000-0000-0000-0000000eeaa1' $$,
  'owner deletes their own recipe')
  from (select set_config('request.jwt.claims', '{"sub":"99999999-0000-0000-0000-00000000e001","role":"authenticated"}', true)) _;

-- ============================================================
-- cascade-delete on auth.users removal (DSAR erasure) — the whole tree
-- ============================================================
reset role;
delete from auth.users where id = '99999999-0000-0000-0000-00000000e001';
select is(
  (select count(*)::int
     from recipes r
     left join recipe_ingredients i on i.recipe_id = r.id
    where r.user_id = '99999999-0000-0000-0000-00000000e001'
       or i.id = '99999999-0000-0000-0000-0000000eebb1'),
  0, 'deleting the auth user cascade-removes the recipe + its ingredients');

select * from finish();
rollback;
