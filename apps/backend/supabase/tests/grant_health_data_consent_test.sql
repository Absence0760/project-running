-- audit/gdpr 2026-05-31 Medium [compliance/gdpr] regression pin.
--
-- Health-data consent (Art 9(2)(a)) must be server-stamped + tamper-
-- resistant, mirroring coach consent (record_coach_consent_test.sql):
--   1. grant_health_data_consent() stamps a timestamp when none is set.
--   2. First-stamp-wins: an already-stamped consent is returned unchanged.
--   3. A direct authenticated UPDATE setting health_data_consent_at to a
--      NON-NULL value is rejected by the lock trigger (no backdating).
--   4. The withdrawal path — a direct write nulling health_data_consent_at
--      (alongside gender + DOB, per Art 7(3)) — is still allowed.
--   5. Direct gender / date_of_birth writes are unaffected by the lock.

begin;

select plan(6);

-- User A: no consent yet.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000fda01'::uuid, 'authenticated', 'authenticated',
        'hdc-a@test.local', '', now(), now());
insert into user_profiles (id, display_name, preferred_unit)
values ('00000000-0000-0000-0000-0000000fda01'::uuid, 'HDC A', 'km');

-- User B: consent already stamped at a fixed PAST time on INSERT (the
-- BEFORE-UPDATE trigger doesn't gate inserts).
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000fda02'::uuid, 'authenticated', 'authenticated',
        'hdc-b@test.local', '', now(), now());
insert into user_profiles (id, display_name, preferred_unit, health_data_consent_at)
values ('00000000-0000-0000-0000-0000000fda02'::uuid, 'HDC B', 'km', '2020-06-01T00:00:00Z');

-- ── User A: first stamp ──────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fda01","role":"authenticated"}';

select isnt(
  (select grant_health_data_consent()),
  null,
  'grant_health_data_consent() stamps a timestamp when none is set'
);

-- Clear the RPC's transaction-local bypass flag so the trigger guards the
-- direct writes below (production: separate transactions, no leak).
select set_config('app.consent_write', 'off', true);

select throws_ok(
  $$ update user_profiles
       set health_data_consent_at = '2000-01-01T00:00:00Z'
       where id = '00000000-0000-0000-0000-0000000fda01'::uuid $$,
  '42501',
  'health_data_consent_at is set by grant_health_data_consent(), not a direct write',
  'a direct authenticated GRANT (non-null) of health_data_consent_at is blocked'
);

select lives_ok(
  $$ update user_profiles set gender = 'female', date_of_birth = '1990-01-01'
       where id = '00000000-0000-0000-0000-0000000fda01'::uuid $$,
  'gender / date_of_birth writes are unaffected by the consent lock'
);

-- ── User A: withdrawal (null write) is allowed ───────────────────
select lives_ok(
  $$ update user_profiles
       set health_data_consent_at = null, gender = null, date_of_birth = null
       where id = '00000000-0000-0000-0000-0000000fda01'::uuid $$,
  'withdrawal — nulling health_data_consent_at directly — is allowed (Art 7(3))'
);

-- Verify under a privileged role: `authenticated` has UPDATE but no
-- direct table SELECT grant on user_profiles (the app reads via
-- column-scoped / RLS paths), so a raw SELECT as authenticated would
-- hit a permission-denied unrelated to the lock under test.
set local role postgres;
select is(
  (select health_data_consent_at from user_profiles
     where id = '00000000-0000-0000-0000-0000000fda01'::uuid),
  null,
  'after withdrawal the consent timestamp is null'
);

-- ── User B: first-stamp-wins (already set) ───────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fda02","role":"authenticated"}';

select is(
  (select grant_health_data_consent()),
  '2020-06-01T00:00:00Z'::timestamptz,
  'first-stamp-wins: an already-stamped consent is returned unchanged, not refreshed'
);

select * from finish();
rollback;
