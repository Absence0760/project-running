-- pgtap suite for 20270104_001_admin_moderation.sql.
--
-- The load-bearing assertion is the authorization boundary: every
-- moderation RPC must HARD-DENY a non-admin and an anon caller, and
-- leak no report data. An admin gets the queue, the per-target detail,
-- and a working resolve action. The is_admin oracle must live in
-- `private` (not a PostgREST RPC oracle) and PUBLIC must not hold a
-- blanket EXECUTE on any moderation RPC.

begin;

select plan(22);

-- ─── Fixtures ───────────────────────────────────────────────────────
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000ad301', 'authenticated', 'authenticated',
   'admin@mod.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ad302', 'authenticated', 'authenticated',
   'reporter-a@mod.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ad303', 'authenticated', 'authenticated',
   'reporter-b@mod.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ad304', 'authenticated', 'authenticated',
   'target@mod.local', '', now(), now());

insert into app_admins (user_id)
values ('00000000-0000-0000-0000-0000000ad301');

-- Two reporters flag the same target user (service-role insert bypasses
-- the reports RLS, mirroring seed-time fixture planting).
insert into reports (reporter_id, target_kind, target_id, reason, notes, status)
values
  ('00000000-0000-0000-0000-0000000ad302', 'user',
   '00000000-0000-0000-0000-0000000ad304', 'spam', 'spammy dms', 'pending'),
  ('00000000-0000-0000-0000-0000000ad303', 'user',
   '00000000-0000-0000-0000-0000000ad304', 'harassment', null, 'pending');

-- ─── Oracle placement ───────────────────────────────────────────────
select hasnt_function(
  'public', 'is_admin', ARRAY['uuid'],
  'is_admin must NOT exist in public (no PostgREST RPC oracle)'
);
select has_function(
  'private', 'is_admin', ARRAY['uuid'],
  'is_admin must exist in private'
);

-- ─── PUBLIC holds no blanket EXECUTE on the moderation RPCs ──────────
select ok(
  not has_function_privilege('public', 'fetch_pending_reports()', 'EXECUTE'),
  'PUBLIC cannot EXECUTE fetch_pending_reports'
);
select ok(
  not has_function_privilege('public', 'resolve_target_reports(text, uuid, text, text)', 'EXECUTE'),
  'PUBLIC cannot EXECUTE resolve_target_reports'
);

-- ─── Non-admin authenticated caller is HARD-DENIED ──────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ad302","role":"authenticated"}';

select is(am_i_admin(), false, 'am_i_admin is false for a non-admin');

select throws_ok(
  $$select * from fetch_pending_reports()$$,
  '42501', null, 'non-admin denied fetch_pending_reports');

select throws_ok(
  $$select * from fetch_reports_for_target('user', '00000000-0000-0000-0000-0000000ad304')$$,
  '42501', null, 'non-admin denied fetch_reports_for_target');

select throws_ok(
  $$select resolve_target_reports('user', '00000000-0000-0000-0000-0000000ad304', 'reviewed', 'x')$$,
  '42501', null, 'non-admin denied resolve_target_reports');

-- The non-admin's resolve attempt must not have changed any row.
reset role;
select is(
  (select count(*)::int from reports where status = 'pending'
     and target_id = '00000000-0000-0000-0000-0000000ad304'),
  2, 'denied resolve left both reports pending');

-- ─── Anon caller is HARD-DENIED ─────────────────────────────────────
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select throws_ok(
  $$select * from fetch_pending_reports()$$,
  '42501', null, 'anon denied fetch_pending_reports');
select throws_ok(
  $$select * from fetch_reports_for_target('user', '00000000-0000-0000-0000-0000000ad304')$$,
  '42501', null, 'anon denied fetch_reports_for_target');
select throws_ok(
  $$select resolve_target_reports('user', '00000000-0000-0000-0000-0000000ad304', 'dismissed', null)$$,
  '42501', null, 'anon denied resolve_target_reports');

-- ─── Admin caller gets the queue + detail + resolve ─────────────────
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ad301","role":"authenticated"}';

select is(am_i_admin(), true, 'am_i_admin is true for an admin');

select is(
  (select count(*)::int from fetch_pending_reports()),
  1, 'queue has one reported target');

select is(
  (select report_count from fetch_pending_reports()),
  2::bigint, 'queue rolls up two reports for the target');

select is(
  (select reporter_count from fetch_pending_reports()),
  2::bigint, 'queue counts two distinct reporters');

select is(
  (select count(*)::int from fetch_reports_for_target('user', '00000000-0000-0000-0000-0000000ad304')),
  2, 'detail panel lists both individual reports');

-- Invalid status is rejected before any write.
select throws_ok(
  $$select resolve_target_reports('user', '00000000-0000-0000-0000-0000000ad304', 'bogus', null)$$,
  '22023', null, 'resolve rejects an invalid status');

-- Resolve marks both pending reports reviewed.
select is(
  resolve_target_reports('user', '00000000-0000-0000-0000-0000000ad304', 'reviewed', 'handled'),
  2, 'resolve returns the number of rows updated');

reset role;
select is(
  (select count(*)::int from reports where status = 'pending'
     and target_id = '00000000-0000-0000-0000-0000000ad304'),
  0, 'no pending reports remain after resolve');

select is(
  (select count(distinct reviewed_by)::int from reports
     where target_id = '00000000-0000-0000-0000-0000000ad304'),
  1, 'reviewed_by stamped on the resolved reports');

-- The target leaves the pending queue entirely.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ad301","role":"authenticated"}';
select is(
  (select count(*)::int from fetch_pending_reports()),
  0, 'resolved target is gone from the queue');

select * from finish();
rollback;
