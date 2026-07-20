-- Pins migration 20270426_001 — the five extended nutrient columns on
-- food_log (issue #492): fiber_g, sugar_g, sodium_mg, saturated_fat_g,
-- cholesterol_mg. All nullable, all `>= 0`.
--
-- Asserts:
--   1-5. a row written with every new column round-trips its stored value
--   6.   a row that omits every new column stores them all null (no phantom 0)
--   7.   the fiber_g CHECK rejects a negative value
--   8.   the sodium_mg CHECK rejects a negative value

begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('eeeeeeee-0000-0000-0000-0000000004a1', 'authenticated', 'authenticated',
   'nutrients@food.local', '', now(), now());

set local role service_role;

insert into food_log (
  id, user_id, item_name, calories, protein_g, carbs_g, fat_g,
  fiber_g, sugar_g, sodium_mg, saturated_fat_g, cholesterol_mg
) values (
  'ffffffff-0000-0000-0000-0000000004a1',
  'eeeeeeee-0000-0000-0000-0000000004a1',
  'Cheddar cheese', 402, 25, 1.3, 33,
  0, 0.5, 621, 21, 105
);

select is(
  (select fiber_g from food_log where id = 'ffffffff-0000-0000-0000-0000000004a1'),
  0::numeric, 'fiber_g round-trips');
select is(
  (select sugar_g from food_log where id = 'ffffffff-0000-0000-0000-0000000004a1'),
  0.5::numeric, 'sugar_g round-trips');
select is(
  (select sodium_mg from food_log where id = 'ffffffff-0000-0000-0000-0000000004a1'),
  621::numeric, 'sodium_mg round-trips');
select is(
  (select saturated_fat_g from food_log where id = 'ffffffff-0000-0000-0000-0000000004a1'),
  21::numeric, 'saturated_fat_g round-trips');
select is(
  (select cholesterol_mg from food_log where id = 'ffffffff-0000-0000-0000-0000000004a1'),
  105::numeric, 'cholesterol_mg round-trips');

-- An item logged without the extended nutrients keeps them null, never 0.
insert into food_log (id, user_id, item_name, calories)
values (
  'ffffffff-0000-0000-0000-0000000004a2',
  'eeeeeeee-0000-0000-0000-0000000004a1',
  'Plain water', 0
);
select is(
  (select fiber_g is null and sugar_g is null and sodium_mg is null
     and saturated_fat_g is null and cholesterol_mg is null
   from food_log where id = 'ffffffff-0000-0000-0000-0000000004a2'),
  true, 'omitted extended nutrients stay null');

select throws_ok(
  $$insert into food_log (user_id, item_name, fiber_g)
    values ('eeeeeeee-0000-0000-0000-0000000004a1', 'Bad fiber', -1)$$,
  '23514', null, 'negative fiber_g rejected by CHECK');
select throws_ok(
  $$insert into food_log (user_id, item_name, sodium_mg)
    values ('eeeeeeee-0000-0000-0000-0000000004a1', 'Bad sodium', -5)$$,
  '23514', null, 'negative sodium_mg rejected by CHECK');

select * from finish();

rollback;
