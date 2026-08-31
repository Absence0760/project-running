-- Pins migration 20270605_001 (decisions § 721) by its CONSEQUENCE rather
-- than by its column.
--
-- `withdraw_health_data_consent()` used to null `user_profiles.date_of_birth`
-- alongside the Art 9 columns. § 718 established that the column is the
-- child-safety AGE RECORD — the under-18 floors in `search_user_profiles`
-- (20261104_001 / 20270218_001) and `discoverable_runners_near`
-- (20270424000005) read it, on a lawful basis the runner's Art 9 consent does
-- not supply — so erasing it produced the result the floor exists to prevent:
-- a declared minor became name-searchable and locatable BECAUSE they
-- exercised a data-subject right.
--
-- `withdraw_health_data_consent_test` pins the column's survival. This pins
-- what the column is FOR, which is the claim a future bare-body
-- `create or replace` would break without touching that assertion's fixture:
-- the minor is excluded before the withdrawal and still excluded after it,
-- while an adult who withdrew the same consent stays discoverable on both
-- surfaces. The withdrawal is proved to have actually happened in between, so
-- neither exclusion can be passing because the RPC did nothing.
--
-- The contrast at the end is the split the two rights describe: Art 7(3)
-- withdrawal keeps the age record, Art 17 erasure takes it — via the
-- `user_profiles_id_fkey` cascade off `auth.users`, which is delete-account's
-- own path.

begin;
select plan(16);

set search_path = public, extensions;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a9e0f100-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'hcw-viewer@test.local', '', now(), now()),
  ('a9e0f100-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'hcw-minor@test.local', '', now(), now()),
  ('a9e0f100-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'hcw-adult@test.local', '', now(), now());

-- Both subjects consented to health-data use and carry the Art 9 columns, so
-- the withdrawal has something to erase. Only the minor's date makes them a
-- minor; nothing else about the two rows differs.
insert into user_profiles (id, display_name, preferred_unit, subscription_tier,
                           date_of_birth, health_data_consent_at, height_cm, gender)
values
  ('a9e0f100-0000-0000-0000-000000000001', 'Hcw Viewer', 'km', 'free',
   (current_date - interval '35 years')::date, null, null, null),
  ('a9e0f100-0000-0000-0000-000000000002', 'Hcw Minor', 'km', 'free',
   (current_date - interval '12 years')::date, '2020-06-01T00:00:00Z', 150, 'female'),
  ('a9e0f100-0000-0000-0000-000000000003', 'Hcw Adult', 'km', 'free',
   (current_date - interval '40 years')::date, '2020-06-01T00:00:00Z', 178, 'male');

insert into body_metrics (user_id, weight_kg)
values ('a9e0f100-0000-0000-0000-000000000002', 41.0),
       ('a9e0f100-0000-0000-0000-000000000003', 74.5);

-- Nearby discovery is reciprocal: the viewer must be opted in with an area of
-- their own, and each subject opts in from ~1.1 km away.
insert into user_settings (user_id, prefs, discoverable_area)
values
  ('a9e0f100-0000-0000-0000-000000000001', '{"discoverable_nearby":"true"}'::jsonb,
   ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography),
  ('a9e0f100-0000-0000-0000-000000000002', '{"discoverable_nearby":"true"}'::jsonb,
   ST_SetSRID(ST_MakePoint(0.01, 0), 4326)::geography),
  ('a9e0f100-0000-0000-0000-000000000003', '{"discoverable_nearby":"true"}'::jsonb,
   ST_SetSRID(ST_MakePoint(0.01, 0), 4326)::geography);

-- ── before the withdrawal ───────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"a9e0f100-0000-0000-0000-000000000001","role":"authenticated"}';

-- refusal: the under-18 floor is a child-protection access control, not a search filter
select is(
  (select count(*)::int from search_user_profiles('Hcw', 60)
    where display_name = 'Hcw Minor'),
  0,
  'a consenting minor is excluded from name search before withdrawing'
);

select is(
  (select count(*)::int from search_user_profiles('Hcw', 60)
    where display_name = 'Hcw Adult'),
  1,
  'the consenting adult is name-searchable before withdrawing'
);

-- refusal: the same floor on the proximity surface
select is(
  (select count(*)::int from discoverable_runners_near(25000, 60)
    where display_name = 'Hcw Minor'),
  0,
  'a consenting minor is excluded from nearby discovery before withdrawing'
);

select is(
  (select count(*)::int from discoverable_runners_near(25000, 60)
    where display_name = 'Hcw Adult'),
  1,
  'the consenting adult is nearby-discoverable before withdrawing'
);

-- ── both subjects withdraw ──────────────────────────────────────────────────
set local "request.jwt.claims" =
  '{"sub":"a9e0f100-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok(
  $$ select withdraw_health_data_consent() $$,
  'the minor withdraws health-data consent'
);

set local "request.jwt.claims" =
  '{"sub":"a9e0f100-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok(
  $$ select withdraw_health_data_consent() $$,
  'the adult withdraws health-data consent'
);

-- The withdrawal really ran: without these the two exclusions below would be
-- satisfied by an RPC that did nothing at all.
reset role;
select is(
  (select count(*)::int from user_profiles
    where id in ('a9e0f100-0000-0000-0000-000000000002',
                 'a9e0f100-0000-0000-0000-000000000003')
      and health_data_consent_at is null
      and height_cm is null and gender is null),
  2,
  'both withdrawals nulled the consent stamp, the height and the gender'
);

select is(
  (select count(*)::int from body_metrics
    where user_id in ('a9e0f100-0000-0000-0000-000000000002',
                      'a9e0f100-0000-0000-0000-000000000003')),
  0,
  'both withdrawals erased the Art 9 weight series'
);

select is(
  (select count(*)::int from user_profiles
    where id in ('a9e0f100-0000-0000-0000-000000000002',
                 'a9e0f100-0000-0000-0000-000000000003')
      and date_of_birth is not null),
  2,
  'both age records survived the withdrawal'
);

-- ── after the withdrawal: the floor still holds ─────────────────────────────
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"a9e0f100-0000-0000-0000-000000000001","role":"authenticated"}';

-- refusal: withdrawing an Art 9 consent must not defeat the child-safety floor
select is(
  (select count(*)::int from search_user_profiles('Hcw', 60)
    where display_name = 'Hcw Minor'),
  0,
  'the minor is still excluded from name search after withdrawing'
);

select is(
  (select count(*)::int from search_user_profiles('Hcw', 60)
    where display_name = 'Hcw Adult'),
  1,
  'the adult is still name-searchable after withdrawing (the withdrawal hides nobody)'
);

-- refusal: the same floor on the proximity surface, after the withdrawal
select is(
  (select count(*)::int from discoverable_runners_near(25000, 60)
    where display_name = 'Hcw Minor'),
  0,
  'the minor is still excluded from nearby discovery after withdrawing'
);

select is(
  (select count(*)::int from discoverable_runners_near(25000, 60)
    where display_name = 'Hcw Adult'),
  1,
  'the adult is still nearby-discoverable after withdrawing'
);

-- A re-grant is a renewed affirmative act over the Art 9 processing; it says
-- nothing about the age record, which never left.
set local "request.jwt.claims" =
  '{"sub":"a9e0f100-0000-0000-0000-000000000002","role":"authenticated"}';
select isnt(
  (select grant_health_data_consent()),
  null,
  'the minor can re-grant health-data consent after withdrawing'
);

reset role;
select is(
  (select date_of_birth from user_profiles
    where id = 'a9e0f100-0000-0000-0000-000000000002'),
  (current_date - interval '12 years')::date,
  'the age record is unchanged across withdraw-then-re-grant'
);

-- ── Art 17 is the other right, and it does take the record ──────────────────
delete from auth.users where id = 'a9e0f100-0000-0000-0000-000000000002';

select is(
  (select count(*)::int from user_profiles
    where id = 'a9e0f100-0000-0000-0000-000000000002'),
  0,
  'deleting the account cascades the profile away, age record included'
);

select * from finish();
rollback;
