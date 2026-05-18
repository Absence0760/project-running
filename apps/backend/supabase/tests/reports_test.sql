-- Pin the user-reports surface (migration 20260908_001):
--
--   * submit_report inserts when target exists + reporter is authed
--   * duplicate-pending against the same target raises 23505
--   * self-report on target_kind='user' is rejected
--   * RLS isolates reporter A's reports from reporter B
--   * the partial unique index releases once status flips off pending
--     (so the same user CAN re-report a re-offender)
--
-- Rate-limit and forged-INSERT defences are exercised in
-- create_rate_limits_test.sql + rls_clubs_test.sql respectively
-- — same shared helpers.

begin;

select plan(7);

-- ── Fixture ──────────────────────────────────────────────────────
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-1111111111aa', 'authenticated', 'authenticated',
   'reporter-a@reports.local', '', now(), now()),
  ('00000000-0000-0000-0000-1111111111bb', 'authenticated', 'authenticated',
   'reporter-b@reports.local', '', now(), now()),
  ('00000000-0000-0000-0000-1111111111cc', 'authenticated', 'authenticated',
   'target-user@reports.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-1111111111cc', 'Reported User')
on conflict (id) do nothing;

insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values
  ('77777777-7777-7777-7777-1111111111aa',
   '00000000-0000-0000-0000-1111111111cc',
   'Reportable Club', 'reportable-club', true, 'open');

-- ── 1. Happy path ────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-1111111111aa"}';

select lives_ok(
  $$ select submit_report('club', '77777777-7777-7777-7777-1111111111aa', 'spam', 'Selling links in posts') $$,
  'reporter A files first report'
);

-- ── 2. Duplicate pending raises 23505 ────────────────────────────
select throws_like(
  $$ select submit_report('club', '77777777-7777-7777-7777-1111111111aa', 'spam', null) $$,
  '%already reported%',
  'second pending report against same target by same reporter is rejected'
);

-- ── 3. Self-report rejected ──────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-1111111111cc"}';
select throws_like(
  $$ select submit_report('user', '00000000-0000-0000-0000-1111111111cc', 'spam', null) $$,
  '%cannot report yourself%',
  'cannot report your own user_id'
);

-- ── 4. Unknown target rejected ───────────────────────────────────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-1111111111aa"}';
select throws_like(
  $$ select submit_report('club', '99999999-9999-9999-9999-999999999999', 'spam', null) $$,
  '%not found%',
  'reporting a nonexistent target is rejected'
);

-- ── 5. Reporter B cannot read reporter A's reports ───────────────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-1111111111bb"}';
select is(
  (select count(*)::int from reports
   where target_kind = 'club'
     and target_id = '77777777-7777-7777-7777-1111111111aa'),
  0,
  'RLS hides another reporter''s reports'
);

-- ── 6. Reporter A sees their own report ──────────────────────────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-1111111111aa"}';
select is(
  (select count(*)::int from reports
   where target_kind = 'club'
     and target_id = '77777777-7777-7777-7777-1111111111aa'),
  1,
  'reporter sees their own report'
);

-- ── 7. Flipping the report off-pending releases the unique index ─
-- Bump up to service_role to imitate a moderator marking the report
-- reviewed via Studio. Reporter A can then file a fresh report.
reset role;
reset "request.jwt.claims";
update reports
  set status = 'dismissed', reviewed_at = now()
  where reporter_id = '00000000-0000-0000-0000-1111111111aa'
    and target_kind = 'club'
    and target_id = '77777777-7777-7777-7777-1111111111aa';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-1111111111aa"}';
select lives_ok(
  $$ select submit_report('club', '77777777-7777-7777-7777-1111111111aa', 'spam', 'Re-offended after dismissal') $$,
  'after the prior report is dismissed, the same reporter can re-file'
);

select * from finish();
rollback;
