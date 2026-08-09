-- Issue #734 regression pin for the versioned AI-disclosure consent
-- (migration 20270511_001). The load-bearing property is #5: an acceptance
-- of the v1 (Coach-only) disclosure must NOT silently satisfy the widened
-- v2 scope the route-AI endpoints require, or the whole point of versioning
-- the record is lost and existing Coach users are retroactively opted in.
--
--   1. A direct authenticated UPDATE of ai_disclosure_version is blocked.
--      (Checked FIRST: the consent RPCs raise a transaction-local
--      app.consent_write flag that, once set, persists for the rest of the
--      pgtap transaction and would mask the trigger.)
--   2. ai_disclosure_current_version() is the version the clients target.
--   3. An unauthenticated caller is refused.
--   4. An unknown version is refused rather than stored.
--   5. record_coach_consent() records v1 and leaves a v1 holder at v1.
--   6/7. record_ai_disclosure_consent(2) upgrades and persists v2.
--   8. Monotone: a later v1 acceptance cannot downgrade a v2 holder.
--   9. A fresh user accepting v2 gets both halves of the record.
--  10. The pairing CHECK rejects a half-written record even from the owner.

begin;

select plan(10);

-- U1: no consent on record.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000ccf01', 'authenticated', 'authenticated',
        'aidisc-a@test.local', '', now(), now());
insert into user_profiles (id, display_name, preferred_unit)
values ('00000000-0000-0000-0000-0000000ccf01', 'Disclosure A', 'km');

-- U2: a legacy Coach acceptance, exactly as the migration's backfill
-- leaves it — stamped at a fixed past time, version 1.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000ccf02', 'authenticated', 'authenticated',
        'aidisc-b@test.local', '', now(), now());
insert into user_profiles (id, display_name, preferred_unit, coach_consent_at, ai_disclosure_version)
values ('00000000-0000-0000-0000-0000000ccf02', 'Disclosure B', 'km',
        '2020-06-01T00:00:00Z', 1);

-- ── 1. Self-granting the wider scope by PATCH is blocked ──────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccf02","role":"authenticated"}';
select throws_ok(
  $$ update user_profiles set ai_disclosure_version = 2
       where id = '00000000-0000-0000-0000-0000000ccf02' $$,
  '42501',
  'ai_disclosure_version is set by record_ai_disclosure_consent(), not a direct write',
  'a direct authenticated write to ai_disclosure_version is blocked'
);

-- ── 2. The version the web + SQL sides agree on ──────────────────
select is(
  (select ai_disclosure_current_version()),
  2::smallint,
  'ai_disclosure_current_version() is the widened all-AI-features version'
);

-- ── 3. No resolvable identity → refused ──────────────────────────
set local "request.jwt.claims" = '{"role":"authenticated"}';
select throws_ok(
  $$ select * from record_ai_disclosure_consent(2::smallint) $$,
  '42501',
  null,
  'record_ai_disclosure_consent() refuses a caller with no resolvable user id'
);

-- ── 4. Fail closed on a version this deployment cannot describe ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccf02","role":"authenticated"}';
select throws_ok(
  $$ select * from record_ai_disclosure_consent(99::smallint) $$,
  '22023',
  null,
  'an unknown disclosure version is refused, not stored'
);

-- ── 5. A Coach acceptance does not reach the widened scope ───────
select is(
  (select version from record_ai_disclosure_consent(1::smallint)),
  1::smallint,
  'record_ai_disclosure_consent(1) leaves a v1 holder at v1 — the widened scope is NOT granted'
);

-- ── 6/7. The explicit upgrade ────────────────────────────────────
select is(
  (select version from record_ai_disclosure_consent(2::smallint)),
  2::smallint,
  'record_ai_disclosure_consent(2) upgrades a v1 holder to v2'
);

reset role;
select is(
  (select ai_disclosure_version from user_profiles where id = '00000000-0000-0000-0000-0000000ccf02'),
  2::smallint,
  'the upgraded version is persisted on the row'
);

-- ── 8. Monotone — the Coach re-prompt cannot walk v2 back ────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccf02","role":"authenticated"}';
select lives_ok(
  $$ select record_coach_consent() $$,
  'record_coach_consent() still succeeds for a v2 holder'
);
reset role;
select is(
  (select ai_disclosure_version from user_profiles where id = '00000000-0000-0000-0000-0000000ccf02'),
  2::smallint,
  'a v1 acceptance does not downgrade a v2 holder'
);

-- ── 9. A fresh acceptance writes both halves ─────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ccf01","role":"authenticated"}';
select isnt(
  (select accepted_at from record_ai_disclosure_consent(2::smallint)),
  null,
  'a fresh v2 acceptance stamps the server-side acceptance time'
);

-- ── 10. Half a record is not a record ────────────────────────────
reset role;
select throws_ok(
  $$ update user_profiles set coach_consent_at = null
       where id = '00000000-0000-0000-0000-0000000ccf01' $$,
  '23514',
  null,
  'clearing the timestamp without the version violates the pairing CHECK'
);

select * from finish();
rollback;
