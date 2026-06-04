-- Pin the full metadata-key denylist on the `public_runs` view.
--
-- The view evolved across multiple audit passes — keys were added to
-- the strip list at:
--   20260626_001_public_runs_view.sql       — initial strip
--   20260714_001_public_runs_strip_race_keys.sql — race_name, bib,
--                                              overall_place, chip_time,
--                                              perceived_effort
--   20260724_001_public_runs_strip_run_number.sql — run_number
-- Each addition closed a real audit finding (race-source PII, perceived
-- effort leaking through seed rows, parkrun attendance counter). Every
-- one is a "you only catch the leak if someone tests for it" — the
-- happy-path public-feed render shows nothing missing because the page
-- never read the stripped key in the first place.
--
-- This test asserts the full denylist by inserting a runs row carrying
-- every sensitive key, then SELECTing through the view as anon and
-- verifying none survive. Adding a new key to the strip list = add it
-- to the array below; removing a key = explicit signal that the public-
-- ness gate has shifted (audit it).
--
-- Companion: `rls_runs_test.sql` covers strava_id + plan_workout_id +
-- the row-level visibility chain. This file is denylist-coverage only.

begin;

select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000bc01', 'authenticated', 'authenticated',
   'denylist@runs.local', '', now(), now());

set local role service_role;

-- One public run carrying every sensitive metadata key the strip
-- list claims to remove. Service-role insert so the row is created
-- regardless of any column-write trigger that might inspect metadata.
-- activity_type + is_dnf are real columns now (F3 / 20261207_001); set
-- them on the row (non-default values) to prove the view exposes the
-- columns, not a stale bag copy.
insert into runs (
  id, user_id, started_at, duration_s, distance_m, source, is_public,
  activity_type, is_dnf, metadata
) values (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01',
  '00000000-0000-0000-0000-00000000bc01',
  '2026-04-15 09:00+00', 1800, 5000, 'parkrun', true,
  'walk', true,
  jsonb_build_object(
    -- Audit / import linkage
    'strava_id', '12345', 'garmin_id', '67890',
    'imported_from', 'strava', 'imported_at', '2026-04-15T09:30:00Z',
    'health_connect_type', 'running', 'strava_activity_type', 'Run',
    'source_file', 'export.gpx', 'max_bpm', 188,
    -- Plan-linkage / workout adherence
    'plan_workout_id', '00000000-0000-0000-0000-000000000000',
    'workout_step_results', '[]'::jsonb, 'workout_adherence', 0.95,
    -- Recorder internal state
    'last_modified_at', '2026-04-15T09:35:00Z',
    'recovered_from_crash', true, 'in_progress_saved_at', '2026-04-15T09:33:00Z',
    'in_progress', false, 'manual_entry', false,
    -- Indoor / GPS-source flags
    'indoor_estimated', false, 'distance_source', 'gps',
    -- Race-source PII (20260714_001)
    'race_name', 'parkrun #1', 'bib', '777',
    'overall_place', 12, 'chip_time', '24:18',
    'perceived_effort', 7,
    -- parkrun attendance counter (20260724_001)
    'run_number', 100,
    -- Public-safe bag keys included to confirm they DO survive the view
    -- (activity_type + is_dnf are columns now, asserted separately below)
    'event', 'parkrun', 'position', 12, 'age_grade', 65.4
  )
);

-- ── Anon view of the row (the worst case — public share page) ──
set local role anon;
set local "request.jwt.claims" = '';

-- 1. None of the denylist keys appear in the view. The expression
--    builds a one-row table of "key was found" booleans for every
--    sensitive key; if any are true, the assertion fails with a
--    diff-style message that names the leaking key.
do $$
declare
  meta jsonb;
  bad_keys text[] := array[]::text[];
  k text;
  denylist text[] := array[
    'strava_id', 'garmin_id', 'imported_from', 'imported_at',
    'health_connect_type', 'strava_activity_type', 'source_file',
    'max_bpm', 'plan_workout_id', 'workout_step_results',
    'workout_adherence', 'last_modified_at', 'recovered_from_crash',
    'in_progress_saved_at', 'in_progress', 'manual_entry',
    'indoor_estimated', 'distance_source',
    'race_name', 'bib', 'overall_place', 'chip_time', 'perceived_effort',
    'run_number'
  ];
begin
  select metadata into meta from public_runs
   where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01';
  foreach k in array denylist loop
    if meta ? k then
      bad_keys := array_append(bad_keys, k);
    end if;
  end loop;
  if array_length(bad_keys, 1) is not null then
    raise exception 'public_runs_denylist_leak: keys still in view: %',
      array_to_string(bad_keys, ', ');
  end if;
end $$;
select pass('public_runs view strips every key on the audit denylist');

-- 2. activity_type is exposed as a real column (F3) — every public-run
--    reader (web feed, mobile feed, share page) needs it. The value
--    flows from the column, not the bag.
select results_eq(
  $$ select activity_type from public_runs
     where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01' $$,
  $$ values ('walk'::text) $$,
  'public_runs view exposes the activity_type column'
);

-- 3. is_dnf is exposed as a real column too (public-safe, was a bag key).
select results_eq(
  $$ select is_dnf from public_runs
     where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01' $$,
  $$ values (true) $$,
  'public_runs view exposes the is_dnf column'
);

select * from finish();

rollback;
