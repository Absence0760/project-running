-- Pin the run_id redaction in event_results_redacted view from
-- migration 20260805_001_event_results_run_id_redaction.sql.
--
-- Pre-fix: `event_results.run_id` was returned over the wire to
-- every authenticated user who could read a public-club event's
-- leaderboard. Combined with the `is_run_visible_to` anon-callable
-- existence oracle, a caller could bridge from a public leaderboard
-- row to confirm the existence of a participant's private run that
-- they linked to their result.
--
-- The fix adds an `event_results_redacted` view with
-- `security_invoker = on` that masks `run_id` with NULL for non-
-- owner viewers via a `case when user_id = auth.uid()` branch.
--
-- Coverage:
--   1. Owner reads their own row's run_id unchanged via the view.
--   2. Non-owner reads the same row's run_id as NULL via the view.
--   3. Anon (auth.uid() is null) reads run_id as NULL.
--   4. Owner reads their own age_grade_pct + note (added 20260809_001).
--   5. Non-owner reads NULL for age_grade_pct + note.

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated',
   'owner@event.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000e2', 'authenticated', 'authenticated',
   'rival@event.local', '', now(), now());

set local role service_role;

-- Public club + event so non-owner authenticated callers can see
-- the leaderboard row through the existing RLS chain.
insert into clubs (id, owner_id, name, slug, is_public)
values ('44444444-4444-4444-4444-444444444444',
        '00000000-0000-0000-0000-0000000000e1',
        'Public Race Club', 'public-race-club', true);

insert into events (id, club_id, title, starts_at, distance_m, created_by)
values ('55555555-5555-5555-5555-555555555555',
        '44444444-4444-4444-4444-444444444444',
        'Saturday Test Race',
        '2026-04-01T08:00:00Z',
        5000.0,
        '00000000-0000-0000-0000-0000000000e1');

-- Owner's private run + event_result that links to it.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('66666666-6666-6666-6666-666666666666',
        '00000000-0000-0000-0000-0000000000e1',
        '2026-04-01T08:00:00Z',
        5000.0, 1500, 'app', false,
        '{"activity_type":"run"}'::jsonb);

insert into event_results
  (event_id, instance_start, user_id, run_id, duration_s, distance_m,
   finisher_status, age_grade_pct, note)
values
  ('55555555-5555-5555-5555-555555555555',
   '2026-04-01T08:00:00Z',
   '00000000-0000-0000-0000-0000000000e1',
   '66666666-6666-6666-6666-666666666666',
   1500, 5000.0, 'finished',
   72.5,
   'organiser note: minor injury, slowed at km 4');

-- ── 1. Owner reads their own row's run_id unmasked ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}';

select results_eq(
  $$ select run_id::text from event_results_redacted
     where event_id = '55555555-5555-5555-5555-555555555555'
       and user_id = '00000000-0000-0000-0000-0000000000e1' $$,
  $$ values ('66666666-6666-6666-6666-666666666666'::text) $$,
  'owner reads their own event_result.run_id unmasked through the view'
);

-- ── 2. Non-owner reads the same row's run_id as NULL ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}';

select results_eq(
  $$ select run_id from event_results_redacted
     where event_id = '55555555-5555-5555-5555-555555555555'
       and user_id = '00000000-0000-0000-0000-0000000000e1' $$,
  $$ values (null::uuid) $$,
  'non-owner sees NULL for the linked run_id (cross-link closed)'
);

-- ── 3. Anon (no auth.uid()) reads run_id as NULL ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select results_eq(
  $$ select run_id from event_results_redacted
     where event_id = '55555555-5555-5555-5555-555555555555'
       and user_id = '00000000-0000-0000-0000-0000000000e1' $$,
  $$ values (null::uuid) $$,
  'anon sees NULL for the linked run_id (auth.uid() is null branch)'
);

-- ── 4. Owner reads their own age_grade_pct + note ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}';

select results_eq(
  $$ select age_grade_pct, note from event_results_redacted
     where event_id = '55555555-5555-5555-5555-555555555555'
       and user_id = '00000000-0000-0000-0000-0000000000e1' $$,
  $$ values (72.5::float8, 'organiser note: minor injury, slowed at km 4'::text) $$,
  'owner reads their own age_grade_pct + note unmasked'
);

-- ── 5. Non-owner sees NULL for age_grade_pct + note ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}';

select results_eq(
  $$ select age_grade_pct, note from event_results_redacted
     where event_id = '55555555-5555-5555-5555-555555555555'
       and user_id = '00000000-0000-0000-0000-0000000000e1' $$,
  $$ values (null::float8, null::text) $$,
  'non-owner sees NULL for age_grade_pct + note (cross-user PII closed)'
);

select * from finish();

rollback;
