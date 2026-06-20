-- Pins migration 20270218_001 (meal templates: meal_templates +
-- meal_template_items). The contract:
--
--   1. meal_templates is owner-only for SELECT/INSERT/UPDATE/DELETE (user_id =
--      auth.uid()). A stranger sees and writes nothing.
--   2. meal_template_items have no owner column of their own — visibility/writes
--      are gated via EXISTS against the parent template's user_id (the
--      "visible via parent" idiom gym_routine_sets uses).
--   3. The whole tree cascade-deletes when the owner's auth.users row is removed
--      (DSAR erasure path), and deleting a template cascades to its items.
begin;
select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-00000000d001', 'authenticated', 'authenticated', 'owner@mt.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000d002', 'authenticated', 'authenticated', 'stranger@mt.local', '', now(), now());

-- Seed a template tree for the owner (superuser, RLS bypassed).
insert into meal_templates (id, user_id, name, meal_slot, item_count)
values ('99999999-0000-0000-0000-0000000ddaa1', '99999999-0000-0000-0000-00000000d001', 'Pre-run breakfast', 'breakfast', 1);

insert into meal_template_items (id, template_id, position, item_name, calories)
values ('99999999-0000-0000-0000-0000000ddbb1', '99999999-0000-0000-0000-0000000ddaa1', 0, 'Oats', 300);

set local role authenticated;

-- ============================================================
-- meal_templates: owner-only
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000d001","role":"authenticated"}';

select is(
  (select count(*)::int from meal_templates where user_id = '99999999-0000-0000-0000-00000000d001'),
  1, 'owner reads their own template');

select lives_ok(
  $$ insert into meal_templates (user_id, name) values ('99999999-0000-0000-0000-00000000d001', 'Lunch') $$,
  'owner inserts their own template');

select is(
  (select count(*)::int from meal_template_items where template_id = '99999999-0000-0000-0000-0000000ddaa1'),
  1, 'owner reads their template''s items via the parent gate');

-- ============================================================
-- Stranger sees / writes nothing
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000d002","role":"authenticated"}';

select is(
  (select count(*)::int from meal_templates where user_id = '99999999-0000-0000-0000-00000000d001'),
  0, 'a stranger cannot read another user''s templates');
select is(
  (select count(*)::int from meal_template_items where template_id = '99999999-0000-0000-0000-0000000ddaa1'),
  0, 'a stranger cannot read another user''s template items');

select throws_ok(
  $$ insert into meal_templates (user_id, name) values ('99999999-0000-0000-0000-00000000d001', 'Forged') $$,
  '42501',
  null,
  'a stranger cannot insert a template owned by someone else');

select throws_ok(
  $$ insert into meal_template_items (template_id, position, item_name)
     values ('99999999-0000-0000-0000-0000000ddaa1', 1, 'Forged') $$,
  '42501',
  null,
  'a stranger cannot add an item to another user''s template (parent gate)');

-- A stranger's delete against the owner's template is RLS-filtered to zero.
select lives_ok(
  $$ delete from meal_templates where id = '99999999-0000-0000-0000-0000000ddaa1' $$,
  'a stranger''s delete runs but is RLS-filtered');
select is(
  (select count(*)::int from meal_templates where id = '99999999-0000-0000-0000-0000000ddaa1'),
  1, 'the owner''s template survived the stranger''s delete (row invisible)')
  from (select set_config('request.jwt.claims', '{"sub":"99999999-0000-0000-0000-00000000d001","role":"authenticated"}', true)) _;

-- Owner can delete their own template; the item cascades.
select lives_ok(
  $$ delete from meal_templates where id = '99999999-0000-0000-0000-0000000ddaa1' $$,
  'owner deletes their own template')
  from (select set_config('request.jwt.claims', '{"sub":"99999999-0000-0000-0000-00000000d001","role":"authenticated"}', true)) _;

-- ============================================================
-- cascade-delete on auth.users removal (DSAR erasure) — the whole tree
-- ============================================================
reset role;
delete from auth.users where id = '99999999-0000-0000-0000-00000000d001';
select is(
  (select count(*)::int
     from meal_templates t
     left join meal_template_items i on i.template_id = t.id
    where t.user_id = '99999999-0000-0000-0000-00000000d001'
       or i.id = '99999999-0000-0000-0000-0000000ddbb1'),
  0, 'deleting the auth user cascade-removes the template + its items');

select * from finish();
rollback;
