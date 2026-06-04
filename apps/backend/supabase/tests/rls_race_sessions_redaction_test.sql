-- Pin the column-redaction in race_sessions_redacted view from
-- migration 20260813_001_race_sessions_admin_column_redaction.sql.
--
-- Pre-fix: `race_sessions.started_by` (admin who pressed Start) and
-- `race_sessions.is_auto_approve` (whether results land approved or
-- pending review) were returned to every authenticated caller who
-- could see the parent event — including non-members of a public
-- club. The redacted view masks both for non-admin viewers via
-- `case when is_club_admin(...) then ... else null end`.
--
-- Coverage:
--   1. Club admin reads `started_by` + `is_auto_approve` unmasked via
--      the view.
--   2. Non-admin authenticated caller (member or stranger) reads
--      both columns as NULL via the view.
--   3. Anon caller reads both columns as NULL via the view.

begin;

select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000ad', 'authenticated', 'authenticated',
   'admin@race.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000ab', 'authenticated', 'authenticated',
   'spectator@race.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('88888888-8888-8888-8888-888888888888',
        '00000000-0000-0000-0000-0000000000ad',
        'Race Public Club', 'race-public-club', true);

insert into events (id, club_id, title, starts_at, distance_m, author_id)
values ('88888888-8888-8888-8888-888888888801',
        '88888888-8888-8888-8888-888888888888',
        'Race Saturday',
        '2026-04-01T08:00:00Z',
        5000.0,
        '00000000-0000-0000-0000-0000000000ad');

insert into race_sessions (event_id, instance_start, status, started_at, started_by, is_auto_approve)
values ('88888888-8888-8888-8888-888888888801',
        '2026-04-01T08:00:00Z',
        'running',
        '2026-04-01T08:00:00Z',
        '00000000-0000-0000-0000-0000000000ad',
        false);

-- ── 1. Admin reads both columns unmasked via the view ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000ad","role":"authenticated"}';

select results_eq(
  $$ select started_by::text, is_auto_approve from race_sessions_redacted
     where event_id = '88888888-8888-8888-8888-888888888801' $$,
  $$ values ('00000000-0000-0000-0000-0000000000ad'::text, false) $$,
  'admin reads started_by + is_auto_approve unmasked via the view'
);

-- ── 2. Non-admin authenticated caller sees NULL for both ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000ab","role":"authenticated"}';

select results_eq(
  $$ select started_by, is_auto_approve from race_sessions_redacted
     where event_id = '88888888-8888-8888-8888-888888888801' $$,
  $$ values (null::uuid, null::boolean) $$,
  'non-admin authenticated caller sees NULL for started_by + is_auto_approve'
);

-- ── 3. Anon sees NULL for both ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select results_eq(
  $$ select started_by, is_auto_approve from race_sessions_redacted
     where event_id = '88888888-8888-8888-8888-888888888801' $$,
  $$ values (null::uuid, null::boolean) $$,
  'anon sees NULL for started_by + is_auto_approve'
);

select * from finish();

rollback;
