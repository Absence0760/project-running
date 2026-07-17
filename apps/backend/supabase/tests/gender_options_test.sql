-- pgtap suite for the narrowed user_profiles.gender CHECK (migration 20270421_001).
--
-- gender drops the `nonbinary` option end-to-end (issue #220). The CHECK is
-- role-independent, so this exercises it as the default (superuser) role rather
-- than reaching through the profile-insert RLS. Pins:
--   1. The column exists.
--   2. `nonbinary` is now rejected by the CHECK.
--   3. Each surviving value (male / female / prefer_not_to_say) is accepted.
--   4. null (unset / withheld) is still accepted.

begin;

select plan(6);

select has_column('public', 'user_profiles', 'gender', 'user_profiles has a gender column');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000c0001'::uuid, 'authenticated', 'authenticated',
   'gender@profile.local', '', now(), now());

-- 2. nonbinary is rejected by the narrowed CHECK.
select throws_ok(
  $$insert into user_profiles (id, display_name, gender)
    values ('00000000-0000-0000-0000-0000000c0001', 'NB', 'nonbinary')$$,
  '23514',
  null,
  'nonbinary is rejected by the narrowed gender CHECK'
);

-- 3. Each surviving value is accepted + round-trips.
insert into user_profiles (id, display_name, gender)
values ('00000000-0000-0000-0000-0000000c0001', 'Runner', 'male');
select is(
  (select gender from user_profiles where id = '00000000-0000-0000-0000-0000000c0001'),
  'male',
  'male is accepted'
);

update user_profiles set gender = 'female' where id = '00000000-0000-0000-0000-0000000c0001';
select is(
  (select gender from user_profiles where id = '00000000-0000-0000-0000-0000000c0001'),
  'female',
  'female is accepted'
);

update user_profiles set gender = 'prefer_not_to_say' where id = '00000000-0000-0000-0000-0000000c0001';
select is(
  (select gender from user_profiles where id = '00000000-0000-0000-0000-0000000c0001'),
  'prefer_not_to_say',
  'prefer_not_to_say is accepted'
);

-- 4. null (unset / withheld) is still accepted.
update user_profiles set gender = null where id = '00000000-0000-0000-0000-0000000c0001';
select is(
  (select gender from user_profiles where id = '00000000-0000-0000-0000-0000000c0001'),
  null,
  'null gender is accepted'
);

select * from finish();
rollback;
