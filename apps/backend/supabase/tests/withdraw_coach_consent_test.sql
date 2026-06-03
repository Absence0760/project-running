-- audit-gdpr #11 (Art 7(3)) regression pin. withdraw_coach_consent() must:
--   1. Leave the lock_consent_columns trigger intact — a direct authenticated
--      UPDATE of coach_consent_at is rejected. (Checked FIRST: the consent
--      RPCs raise a transaction-local app.consent_write flag that, once set,
--      persists for the rest of the pgtap transaction and would mask the
--      trigger — so the block must be asserted before any RPC runs.)
--   2. Refuse an unauthenticated caller.
--   3. Succeed for the authenticated owner.
--   4. Clear coach_consent_at (verified as the owner role — the column is
--      privilege-protected from the `authenticated` role).
--   5. Round-trip: after withdrawal, record_coach_consent() re-stamps.

begin;

select plan(5);

-- Seed (as the superuser test connection — bypasses the BEFORE-UPDATE gate):
-- a user whose consent is already stamped at a fixed past time.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000ccd01', 'authenticated', 'authenticated',
        'withdraw-a@test.local', '', now(), now());
insert into user_profiles (id, display_name, preferred_unit, coach_consent_at)
values ('00000000-0000-0000-0000-0000000ccd01', 'Withdraw A', 'km', '2020-06-01T00:00:00Z');

-- ── 1. Direct write is still blocked (flag not yet raised) ────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccd01","role":"authenticated"}';
select throws_ok(
  $$ update user_profiles set coach_consent_at = null
     where id = '00000000-0000-0000-0000-0000000ccd01' $$,
  '42501',
  null,
  'a direct authenticated UPDATE of coach_consent_at is blocked'
);

-- ── 2. A caller with no resolvable identity is refused ───────────
-- (authenticated role but no `sub` claim → auth.uid() is null → the
-- in-function guard raises. Tested as `authenticated`, not `anon`: the
-- function is revoked from anon, and calling SECURITY DEFINER consent
-- helpers under the anon role trips a crash in this local stack's
-- auth.uid() that the shipped record_coach_consent test also avoids.)
set local "request.jwt.claims" = '{"role":"authenticated"}';
select throws_ok(
  $$ select withdraw_coach_consent() $$,
  '42501',
  null,
  'withdraw_coach_consent() refuses a caller with no resolvable user id'
);

-- ── 3. The owner withdraws ───────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccd01","role":"authenticated"}';
select lives_ok(
  $$ select withdraw_coach_consent() $$,
  'withdraw_coach_consent() succeeds for the authenticated owner'
);

-- ── 4. The stamp is cleared (read as the owner role) ─────────────
reset role;
select is(
  (select coach_consent_at from user_profiles where id = '00000000-0000-0000-0000-0000000ccd01'),
  null,
  'withdraw_coach_consent() cleared coach_consent_at'
);

-- ── 5. Re-consent re-stamps (first-stamp-wins on the now-null row)
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccd01","role":"authenticated"}';
select isnt(
  (select record_coach_consent()),
  null,
  'record_coach_consent() re-stamps after a withdrawal'
);

select * from finish();
rollback;
