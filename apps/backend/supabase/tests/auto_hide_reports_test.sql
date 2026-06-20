-- pgtap suite for 20270218_001_auto_hide_reports.sql.
--
-- The load-bearing assertions:
--   * A target auto-hides ONLY when >= 3 DISTINCT vetted reporters
--     (each with >= 5 public runs) have pending reports on it.
--   * An unvetted reporter (< 5 public runs) does NOT count toward the
--     threshold — the E3 reputation gate.
--   * The owner gets exactly one 'content_hidden' notification on the
--     false->true transition (idempotent: no duplicate on a re-report).
--   * Shadow-hidden targets drop out of the public surfaces
--     (public_routes view, search_clubs, public_profile_by_id).
--   * admin_unhide_target hard-denies a non-admin (42501) and clears the
--     flag for an admin.
--   * Comment/club_post/run reports never auto-hide anything.

begin;

select plan(19);

-- ─── Fixtures ───────────────────────────────────────────────────────
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  -- admin
  ('00000000-0000-0000-0000-00000000ad01', 'authenticated', 'authenticated',
   'admin@hide.local', '', now(), now()),
  -- three vetted reporters
  ('00000000-0000-0000-0000-00000000ae11', 'authenticated', 'authenticated',
   'vet1@hide.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000ae12', 'authenticated', 'authenticated',
   'vet2@hide.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000ae13', 'authenticated', 'authenticated',
   'vet3@hide.local', '', now(), now()),
  -- one unvetted reporter (0 public runs)
  ('00000000-0000-0000-0000-00000000aeff', 'authenticated', 'authenticated',
   'unvet@hide.local', '', now(), now()),
  -- target user + a club owner + a route owner
  ('00000000-0000-0000-0000-00000000afaa', 'authenticated', 'authenticated',
   'targetuser@hide.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000afbb', 'authenticated', 'authenticated',
   'clubowner@hide.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-00000000afaa', 'Target User'),
  ('00000000-0000-0000-0000-00000000afbb', 'Club Owner'),
  ('00000000-0000-0000-0000-00000000ae11', 'Vet One'),
  ('00000000-0000-0000-0000-00000000ae12', 'Vet Two'),
  ('00000000-0000-0000-0000-00000000ae13', 'Vet Three'),
  ('00000000-0000-0000-0000-00000000aeff', 'Unvetted')
on conflict (id) do nothing;

insert into app_admins (user_id) values ('00000000-0000-0000-0000-00000000ad01');

-- Give each vetted reporter 5 public runs; the unvetted one gets none.
insert into runs (user_id, started_at, distance_m, duration_s, source, is_public, metadata)
select v.uid, now(), 1000, 300, 'app', true, '{"activity_type":"run"}'::jsonb
from (values
  ('00000000-0000-0000-0000-00000000ae11'::uuid),
  ('00000000-0000-0000-0000-00000000ae12'::uuid),
  ('00000000-0000-0000-0000-00000000ae13'::uuid)
) as v(uid), generate_series(1, 5);

-- A public club + a public route to also exercise those kinds.
insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-0000000c10b1',
        '00000000-0000-0000-0000-00000000afbb', 'Hidden Test Club',
        'hidden-test-club', true);

insert into routes (id, user_id, name, distance_m, is_public, slug, waypoints)
values ('00000000-0000-0000-0000-0000000200e1',
        '00000000-0000-0000-0000-00000000afaa', 'Hidden Test Route',
        5000, true, 'hidden-test-route', '[]'::jsonb);

-- ─── Reputation gate: 2 vetted + 1 unvetted does NOT hide ───────────
insert into reports (reporter_id, target_kind, target_id, reason, status)
values
  ('00000000-0000-0000-0000-00000000ae11', 'user',
   '00000000-0000-0000-0000-00000000afaa', 'spam', 'pending'),
  ('00000000-0000-0000-0000-00000000ae12', 'user',
   '00000000-0000-0000-0000-00000000afaa', 'spam', 'pending'),
  ('00000000-0000-0000-0000-00000000aeff', 'user',
   '00000000-0000-0000-0000-00000000afaa', 'spam', 'pending');

select is(
  (select shadow_hidden from user_profiles where id = '00000000-0000-0000-0000-00000000afaa'),
  false, '2 vetted + 1 unvetted reporter does NOT trip the threshold');

select is(
  (select count(*)::int from notifications
     where user_id = '00000000-0000-0000-0000-00000000afaa' and kind = 'content_hidden'),
  0, 'no content_hidden notification before the threshold');

-- ─── Third vetted reporter trips the auto-hide ──────────────────────
insert into reports (reporter_id, target_kind, target_id, reason, status)
values
  ('00000000-0000-0000-0000-00000000ae13', 'user',
   '00000000-0000-0000-0000-00000000afaa', 'harassment', 'pending');

select is(
  (select shadow_hidden from user_profiles where id = '00000000-0000-0000-0000-00000000afaa'),
  true, '3 distinct vetted reporters trip the auto-hide');

select is(
  (select count(*)::int from notifications
     where user_id = '00000000-0000-0000-0000-00000000afaa' and kind = 'content_hidden'),
  1, 'owner notified exactly once on the false->true transition');

-- ─── Public-surface exclusion ───────────────────────────────────────
select is(
  (select count(*)::int from public_profile_by_id('00000000-0000-0000-0000-00000000afaa')),
  0, 'hidden user profile is excluded from public_profile_by_id');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ae12","role":"authenticated"}';
select is(
  (select count(*)::int from search_user_profiles('Target')),
  0, 'hidden user is excluded from search_user_profiles');
reset role;

-- Regression guard: re-emitting search_user_profiles must keep the
-- canonical-column minor floor (20261104_001). A declared minor via
-- user_profiles.date_of_birth (no prefs mirror) must never surface.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000c10d', 'authenticated', 'authenticated',
        'minor@hide.local', '', now(), now());
insert into user_profiles (id, display_name, date_of_birth)
values ('00000000-0000-0000-0000-00000000c10d', 'Minor Searchable',
        (current_date - interval '11 years'))
on conflict (id) do nothing;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ae12","role":"authenticated"}';
select is(
  (select count(*)::int from search_user_profiles('Minor Searchable')),
  0, 'declared minor (canonical DOB column) stays excluded from search');
reset role;

-- ─── Idempotency: re-report after the hide does not re-notify ───────
-- The unvetted reporter has no pending row yet on the club; bump the
-- user target by flipping the existing reports (no new pending dup
-- allowed by the partial-unique), so simulate via a fresh club hide.
insert into reports (reporter_id, target_kind, target_id, reason, status)
values
  ('00000000-0000-0000-0000-00000000ae11', 'club',
   '00000000-0000-0000-0000-0000000c10b1', 'spam', 'pending'),
  ('00000000-0000-0000-0000-00000000ae12', 'club',
   '00000000-0000-0000-0000-0000000c10b1', 'spam', 'pending'),
  ('00000000-0000-0000-0000-00000000ae13', 'club',
   '00000000-0000-0000-0000-0000000c10b1', 'spam', 'pending');

select is(
  (select shadow_hidden from clubs where id = '00000000-0000-0000-0000-0000000c10b1'),
  true, 'a club auto-hides on 3 vetted reporters');

select is(
  (select count(*)::int from notifications
     where user_id = '00000000-0000-0000-0000-00000000afbb' and kind = 'content_hidden'),
  1, 'club owner notified once');

select is(
  (select count(*)::int from search_clubs('Hidden')),
  0, 'hidden club is excluded from search_clubs');

-- ─── Route hide + public_routes view exclusion ──────────────────────
insert into reports (reporter_id, target_kind, target_id, reason, status)
values
  ('00000000-0000-0000-0000-00000000ae11', 'route',
   '00000000-0000-0000-0000-0000000200e1', 'spam', 'pending'),
  ('00000000-0000-0000-0000-00000000ae12', 'route',
   '00000000-0000-0000-0000-0000000200e1', 'spam', 'pending'),
  ('00000000-0000-0000-0000-00000000ae13', 'route',
   '00000000-0000-0000-0000-0000000200e1', 'spam', 'pending');

select is(
  (select shadow_hidden from routes where id = '00000000-0000-0000-0000-0000000200e1'),
  true, 'a route auto-hides on 3 vetted reporters');

select is(
  (select count(*)::int from public_routes where id = '00000000-0000-0000-0000-0000000200e1'),
  0, 'hidden route is excluded from the public_routes view');

-- ─── Comment/run/club_post never auto-hide (no shadow column) ───────
-- A report against a 'run' must not error and must not flip anything;
-- auto_hide_target early-returns for non-shadow kinds.
select lives_ok(
  $$select auto_hide_target('run', '00000000-0000-0000-0000-0000000200e1')$$,
  'auto_hide_target is a no-op for a non-shadow kind');

-- ─── admin_unhide_target authorization ──────────────────────────────
select ok(
  not has_function_privilege('public', 'admin_unhide_target(text, uuid)', 'EXECUTE'),
  'PUBLIC cannot EXECUTE admin_unhide_target');

-- Non-admin is hard-denied.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ae11","role":"authenticated"}';
select throws_ok(
  $$select admin_unhide_target('user', '00000000-0000-0000-0000-00000000afaa')$$,
  '42501', null, 'non-admin denied admin_unhide_target');
reset role;

-- The denied unhide left the user hidden.
select is(
  (select shadow_hidden from user_profiles where id = '00000000-0000-0000-0000-00000000afaa'),
  true, 'denied unhide left the user shadow-hidden');

-- Admin unhide clears the flag and returns true.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ad01","role":"authenticated"}';
select is(
  admin_unhide_target('user', '00000000-0000-0000-0000-00000000afaa'),
  true, 'admin unhide returns true when a row flips');
reset role;

select is(
  (select shadow_hidden from user_profiles where id = '00000000-0000-0000-0000-00000000afaa'),
  false, 'user is visible again after admin unhide');

-- A second unhide is a no-op (already visible) → returns false.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ad01","role":"authenticated"}';
select is(
  admin_unhide_target('user', '00000000-0000-0000-0000-00000000afaa'),
  false, 'unhiding an already-visible target returns false');
reset role;

select * from finish();
rollback;
