-- Issue #233 (GDPR Art 7(3)/Art 9) regression pin. The health-data consent
-- RPCs (20270418_001) must be insert-or-update — user_profiles rows are
-- client-provisioned, so both a grant and a withdrawal can legitimately run
-- BEFORE any profile row exists, and a 0-row silent no-op here means
-- special-category data lives on (or consent never stamps) while the client
-- confirms success. Assertion order matters: the direct-write block is
-- checked FIRST because the consent RPCs raise a transaction-local
-- app.consent_write flag that persists for the rest of the pgtap
-- transaction and would mask the trigger.

begin;

select plan(10);

-- Seed users: A has a consented profile + Art 9 columns + a weight series;
-- B and C have NO profile row (the client-provisioned-row gap).
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000ccd11', 'authenticated', 'authenticated',
   'hdc-a@test.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ccd12', 'authenticated', 'authenticated',
   'hdc-b@test.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ccd13', 'authenticated', 'authenticated',
   'hdc-c@test.local', '', now(), now());
insert into user_profiles (id, display_name, preferred_unit, health_data_consent_at,
                           height_cm, gender, date_of_birth)
values ('00000000-0000-0000-0000-0000000ccd11', 'HDC A', 'km',
        '2020-06-01T00:00:00Z', 178, 'female', '1990-01-15');
insert into body_metrics (user_id, weight_kg)
values ('00000000-0000-0000-0000-0000000ccd11', 65.5),
       ('00000000-0000-0000-0000-0000000ccd11', 66.0);

-- ── 1. Direct non-null write is still blocked (flag not yet raised) ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccd11","role":"authenticated"}';
select throws_ok(
  $$ update user_profiles set health_data_consent_at = now()
     where id = '00000000-0000-0000-0000-0000000ccd11' $$,
  '42501',
  null,
  'a direct authenticated non-null write of health_data_consent_at is blocked'
);

-- ── 2. A caller with no resolvable identity is refused ───────────────
set local "request.jwt.claims" = '{"role":"authenticated"}';
select throws_ok(
  $$ select withdraw_health_data_consent() $$,
  '42501',
  null,
  'withdraw_health_data_consent() refuses a caller with no resolvable user id'
);

-- ── 3. Grant with NO profile row lands a row + stamps (user B) ───────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccd12","role":"authenticated"}';
select isnt(
  (select grant_health_data_consent()),
  null,
  'grant_health_data_consent() stamps even when no profile row existed'
);
reset role;
select is(
  (select count(*)::int from user_profiles
    where id = '00000000-0000-0000-0000-0000000ccd12'
      and health_data_consent_at is not null),
  1,
  'the grant inserted the missing profile row with the stamp'
);

-- ── 4. The consented owner withdraws (user A) ────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccd11","role":"authenticated"}';
select lives_ok(
  $$ select withdraw_health_data_consent() $$,
  'withdraw_health_data_consent() succeeds for the authenticated owner'
);

-- ── 5. Every Art 9 profile column is nulled ──────────────────────────
reset role;
select is(
  (select count(*)::int from user_profiles
    where id = '00000000-0000-0000-0000-0000000ccd11'
      and health_data_consent_at is null and height_cm is null
      and gender is null and date_of_birth is null),
  1,
  'withdrawal nulled the consent stamp + height + gender + DOB'
);

-- ── 6. The weight series is erased in the same call ──────────────────
select is(
  (select count(*)::int from body_metrics
    where user_id = '00000000-0000-0000-0000-0000000ccd11'),
  0,
  'withdrawal erased the body_metrics series'
);

-- ── 7. Withdrawal with NO profile row lands a withdrawn row (user C) ─
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccd13","role":"authenticated"}';
select lives_ok(
  $$ select withdraw_health_data_consent() $$,
  'withdraw_health_data_consent() succeeds with no pre-existing profile row'
);
reset role;
select is(
  (select count(*)::int from user_profiles
    where id = '00000000-0000-0000-0000-0000000ccd13'
      and health_data_consent_at is null),
  1,
  'the withdrawal inserted the missing profile row in the withdrawn state'
);

-- ── 8. Re-grant after a withdrawal re-stamps (renewed affirmative act) ─
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccd11","role":"authenticated"}';
select isnt(
  (select grant_health_data_consent()),
  null,
  'grant_health_data_consent() re-stamps after a withdrawal'
);

select * from finish();
rollback;
