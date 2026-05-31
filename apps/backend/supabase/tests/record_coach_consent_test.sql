-- audit-findings 2026-05-30 Medium [compliance/gdpr] regression pin.
--
-- Coach consent must be server-stamped + tamper-resistant:
--   1. record_coach_consent() stamps a timestamp when none is set.
--   2. First-stamp-wins: when a stamp already exists, the RPC returns the
--      ORIGINAL value (it does NOT refresh it). Proven by pre-seeding a
--      known past value and asserting the RPC returns it unchanged — this
--      survives pgtap's single-transaction now() (which is constant).
--   3. A direct authenticated UPDATE of coach_consent_at is rejected by
--      the lock trigger, so it can't be backdated outside the RPC.
--   4. The trigger guards ONLY coach_consent_at — unrelated column
--      updates on the same row still work.

begin;

select plan(4);

-- User A: no consent yet.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000cca01', 'authenticated', 'authenticated',
        'consent-a@test.local', '', now(), now());
insert into user_profiles (id, display_name, preferred_unit)
values ('00000000-0000-0000-0000-0000000cca01', 'Consent A', 'km');

-- User B: consent already stamped at a fixed PAST time (set on INSERT,
-- which the BEFORE-UPDATE trigger doesn't gate).
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000cca02', 'authenticated', 'authenticated',
        'consent-b@test.local', '', now(), now());
insert into user_profiles (id, display_name, preferred_unit, coach_consent_at)
values ('00000000-0000-0000-0000-0000000cca02', 'Consent B', 'km', '2020-06-01T00:00:00Z');

-- ── User A: first stamp ──────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cca01","role":"authenticated"}';

select isnt(
  (select record_coach_consent()),
  null,
  'record_coach_consent() stamps a timestamp when none is set'
);

-- Clear the RPC's transaction-local bypass flag so the trigger guards the
-- direct write below (production: separate transactions, no leak).
select set_config('app.consent_write', 'off', true);

select throws_ok(
  $$ update user_profiles
       set coach_consent_at = '2000-01-01T00:00:00Z'
       where id = '00000000-0000-0000-0000-0000000cca01' $$,
  '42501',
  'coach_consent_at is set by record_coach_consent(), not a direct write',
  'a direct authenticated write to coach_consent_at is blocked'
);

select lives_ok(
  $$ update user_profiles set display_name = 'Renamed A'
       where id = '00000000-0000-0000-0000-0000000cca01' $$,
  'unrelated column updates are unaffected by the consent lock'
);

-- ── User B: first-stamp-wins (already set) ───────────────────────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cca02","role":"authenticated"}';

select is(
  (select record_coach_consent()),
  '2020-06-01T00:00:00Z'::timestamptz,
  'first-stamp-wins: an already-stamped consent is returned unchanged, not refreshed'
);

select * from finish();
rollback;
