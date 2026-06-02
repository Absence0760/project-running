-- Pins reviews/audit-rls.md (2026-05-31) pass-3 hygiene fixes
-- (migration 20261123_001):
--
--   * notify_direct_message / notify_event_cancel / notify_event_rsvp are no
--     longer EXECUTE-able by anon or authenticated, but their triggers still
--     fire (trigger contexts use the owner's rights, not a caller grant).
--   * run_kudos_reject_self / gear_set_updated_at pin search_path.
--   * run_kudos_reject_self reads the MODERN dual-format JWT claim, so its
--     service_role bypass is live again (the legacy-only read was dead).
--   * event_results_redacted keeps security_invoker=on: anon sees results for
--     a public-club event but NOT for a private-club event. A flip to
--     security_invoker=off would run the view as owner, bypass RLS, and leak
--     the private-event row — this test fails if that happens.
--   * clone_plan_template refuses a non-owner cloning a private template.

begin;
select plan(16);

-- ── grant lockdowns on the three notify trigger functions ───────────────
select ok(not has_function_privilege('anon', 'public.notify_direct_message()', 'EXECUTE'),
  'anon must NOT execute notify_direct_message');
select ok(not has_function_privilege('authenticated', 'public.notify_direct_message()', 'EXECUTE'),
  'authenticated must NOT execute notify_direct_message');
select ok(not has_function_privilege('anon', 'public.notify_event_cancel()', 'EXECUTE'),
  'anon must NOT execute notify_event_cancel');
select ok(not has_function_privilege('authenticated', 'public.notify_event_cancel()', 'EXECUTE'),
  'authenticated must NOT execute notify_event_cancel');
select ok(not has_function_privilege('anon', 'public.notify_event_rsvp()', 'EXECUTE'),
  'anon must NOT execute notify_event_rsvp');
select ok(not has_function_privilege('authenticated', 'public.notify_event_rsvp()', 'EXECUTE'),
  'authenticated must NOT execute notify_event_rsvp');

-- ── triggers still wired (revoke must not break firing) ─────────────────
select ok(exists(select 1 from pg_trigger where tgname='trg_notify_direct_message' and not tgisinternal),
  'trg_notify_direct_message still exists after revoke');
select ok(exists(select 1 from pg_trigger where tgname='trg_notify_event_cancel' and not tgisinternal),
  'trg_notify_event_cancel still exists after revoke');
select ok(exists(select 1 from pg_trigger where tgname='event_attendees_notify' and not tgisinternal),
  'event_attendees_notify (notify_event_rsvp) still exists after revoke');

-- ── search_path pinned ──────────────────────────────────────────────────
select ok(
  (select proconfig from pg_proc where proname='run_kudos_reject_self')
    @> array['search_path=public'],
  'run_kudos_reject_self pins search_path=public');
select ok(
  (select proconfig from pg_proc where proname='gear_set_updated_at')
    @> array['search_path=public'],
  'gear_set_updated_at pins search_path=public');

-- All auth.users rows are created up front as the superuser — service_role
-- lacks INSERT on auth.users, so these cannot be interleaved after a
-- `set local role service_role`.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000ab230001', 'authenticated', 'authenticated', 'kudos@hyg3.local',     '', now(), now()),
  ('00000000-0000-0000-0000-0000ab230002', 'authenticated', 'authenticated', 'tmplown@hyg3.local',   '', now(), now()),
  ('00000000-0000-0000-0000-0000ab230003', 'authenticated', 'authenticated', 'tmplother@hyg3.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000ab230004', 'authenticated', 'authenticated', 'pubown@hyg3.local',    '', now(), now()),
  ('00000000-0000-0000-0000-0000ab230005', 'authenticated', 'authenticated', 'privown@hyg3.local',   '', now(), now());

-- ── run_kudos_reject_self modern-JWT service_role bypass ────────────────
set local role service_role;
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values ('a0000000-0000-0000-0000-0000ab230001', '00000000-0000-0000-0000-0000ab230001',
        now(), 5000, 1500, 'app', '{"activity_type":"run"}');

-- Modern claims blob with role=service_role AND a non-null sub. The legacy
-- read alone would leave v_role='' here, so without the dual-format fix the
-- exists()-check would fire on this self-kudos and raise. With the fix the
-- service_role bypass returns NEW.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000ab230001","role":"service_role"}';
select lives_ok(
  $$ insert into run_kudos (user_id, run_id)
     values ('00000000-0000-0000-0000-0000ab230001', 'a0000000-0000-0000-0000-0000ab230001') $$,
  'service_role (modern JWT) bypasses run_kudos_reject_self for a self-kudos');

-- An authenticated user still cannot kudos their own run (the trigger fires
-- before the RLS WITH CHECK, which would itself permit the self-row).
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000ab230001","role":"authenticated"}';
select throws_ok(
  $$ insert into run_kudos (user_id, run_id)
     values ('00000000-0000-0000-0000-0000ab230001', 'a0000000-0000-0000-0000-0000ab230001') $$,
  'self_kudos_not_allowed',
  'an authenticated user cannot kudos their own run');

-- ── event_results_redacted preserves RLS row visibility (security_invoker) ─
set local role service_role;
insert into clubs (id, owner_id, name, slug, is_public) values
  ('c0000000-0000-0000-0000-0000ab230001', '00000000-0000-0000-0000-0000ab230004', 'Hyg3 Public',  'hyg3-pub',  true),
  ('c0000000-0000-0000-0000-0000ab230002', '00000000-0000-0000-0000-0000ab230005', 'Hyg3 Private', 'hyg3-priv', false);

insert into events (id, club_id, title, starts_at, created_by) values
  ('e0000000-0000-0000-0000-0000ab230001', 'c0000000-0000-0000-0000-0000ab230001', 'Pub 5k',  '2026-06-06 09:00+00', '00000000-0000-0000-0000-0000ab230004'),
  ('e0000000-0000-0000-0000-0000ab230002', 'c0000000-0000-0000-0000-0000ab230002', 'Priv 5k', '2026-06-06 09:00+00', '00000000-0000-0000-0000-0000ab230005');

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m) values
  ('e0000000-0000-0000-0000-0000ab230001', '2026-06-06 09:00+00', '00000000-0000-0000-0000-0000ab230004', 1500, 5000),
  ('e0000000-0000-0000-0000-0000ab230002', '2026-06-06 09:00+00', '00000000-0000-0000-0000-0000ab230005', 1500, 5000);

set local role anon;
set local "request.jwt.claims" = '';
select isnt_empty(
  $$ select 1 from event_results_redacted where event_id = 'e0000000-0000-0000-0000-0000ab230001' $$,
  'anon sees a public-club event result via event_results_redacted');
select is_empty(
  $$ select 1 from event_results_redacted where event_id = 'e0000000-0000-0000-0000-0000ab230002' $$,
  'anon must NOT see a private-club event result via event_results_redacted '
    || '(security_invoker=on preserves RLS; a flip to off would leak this row)');

-- ── clone_plan_template refuses a non-owner cloning a private template ───
set local role service_role;
insert into training_plans
  (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, is_template)
values
  ('11110000-0000-0000-0000-0000ab230001', '00000000-0000-0000-0000-0000ab230002',
   'Private Template', 'distance_5k', 5000, '2026-01-01', '2026-03-01', 4, 'completed', true);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000ab230003","role":"authenticated"}';
select throws_ok(
  $$ select clone_plan_template('11110000-0000-0000-0000-0000ab230001', '2026-07-01') $$,
  'clone_plan_template: not authorised to clone template 11110000-0000-0000-0000-0000ab230001',
  'a non-owner cannot clone a private (non-club) template');

select * from finish();
rollback;
