-- RLS suite for `public.runs` (and the `public_runs` view that's the
-- documented public read path).
--
-- Invariants under test:
--   - Only the owner can SELECT / UPDATE / DELETE / INSERT their own
--     runs (initial_schema "users own their runs" FOR ALL policy).
--   - Direct reads of `runs` from a non-owner — even of `is_public=true`
--     rows — return zero rows. The legacy "public runs are readable by
--     anyone" SELECT policy was DROPPED in 20260701_001 to close the
--     wire-leak (decisions §33). Public visibility now flows through
--     the `public_runs` view (see 20260626_001).
--   - The `public_runs` view exposes public rows to anon + authenticated
--     and strips audit-only / training-plan-linkage / sync-state keys
--     from `metadata`, plus nulls `route_id` / `event_id` when the
--     join target isn't itself public.
--
-- Blast radius if either policy regresses: the entire private run
-- corpus of every user, plus the redaction guarantees on the public
-- share + feed paths.

begin;

select plan(16);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
   'a@test.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated',
   'b@test.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000a"}';

insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata, is_public)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01',
   '00000000-0000-0000-0000-00000000000a',
   '2026-04-10 10:00:00+00', 1800, 5000, 'app',
   '{"activity_type":"run","strava_id":"123","plan_workout_id":"abc"}', false),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02',
   '00000000-0000-0000-0000-00000000000a',
   '2026-04-11 10:00:00+00', 2400, 8000, 'app',
   '{"activity_type":"run","strava_id":"456","plan_workout_id":"def"}', true);

-- 1. Owner can SELECT both runs.
select results_eq(
  $$ select count(*)::int from runs where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  $$ values (2) $$,
  'owner can read both their runs (private + public)'
);

-- 2. Forged INSERT (under another user_id) is rejected.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select throws_ok(
  $$ insert into runs (user_id, started_at, duration_s, distance_m, source, metadata)
       values ('00000000-0000-0000-0000-00000000000a',
               now(), 600, 1000, 'app', '{"activity_type":"run"}') $$,
  '42501',
  null,
  'cannot INSERT a run under another user_id'
);

-- 3. Direct SELECT from `runs` as a non-owner returns ZERO rows even
--    for is_public=true (post-20260701_001 invariant).
select is_empty(
  $$ select id from runs where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  'non-owner direct SELECT on runs returns zero (wire-leak closed; decisions §33)'
);

-- 4. Non-owner UPDATE on a private run: no-op.
update runs set distance_m = 9999
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select results_eq(
  $$ select distance_m from runs where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01' $$,
  $$ values (5000.00::numeric) $$,
  'non-owner UPDATE on a private run does not modify it'
);

-- 5. Non-owner UPDATE on a public run: also no-op (no public-runs SELECT
--    policy means non-owner can't even target the row for UPDATE).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
update runs set distance_m = 1
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select results_eq(
  $$ select distance_m from runs where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02' $$,
  $$ values (8000.00::numeric) $$,
  'non-owner UPDATE on a public run does not modify it'
);

-- 6. Non-owner DELETE: no-op.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
delete from runs where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
delete from runs where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select results_eq(
  $$ select count(*)::int from runs where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  $$ values (2) $$,
  'non-owner DELETE on either run is a no-op'
);

-- 7. Owner UPDATE works.
update runs set distance_m = 5500
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
select results_eq(
  $$ select distance_m from runs where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01' $$,
  $$ values (5500.00::numeric) $$,
  'owner UPDATE works on their own run'
);

-- 8. Owner DELETE works.
delete from runs where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
select is_empty(
  $$ select id from runs where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01' $$,
  'owner DELETE works on their own run'
);

-- ── public_runs view ──
-- 9. Non-owner can read the public run via the view.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select results_eq(
  $$ select id from public_runs
       where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  $$ values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02'::uuid) $$,
  'non-owner can SELECT the public run via public_runs view'
);

-- 10. Metadata is redacted via the view (strava_id + plan_workout_id stripped).
select is(
  (select metadata ? 'strava_id' from public_runs
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02'),
  false,
  'public_runs view strips strava_id from metadata'
);
select is(
  (select metadata ? 'plan_workout_id' from public_runs
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02'),
  false,
  'public_runs view strips plan_workout_id from metadata'
);
-- 11. Public-safe key (activity_type) survives.
select is(
  (select metadata ->> 'activity_type' from public_runs
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02'),
  'run',
  'public_runs view preserves activity_type in metadata'
);

-- ── Anonymous ──
set local role anon;
set local "request.jwt.claims" = '';

-- 12. Anon direct SELECT on runs (filtered to fixture user): ZERO rows.
select is_empty(
  $$ select id from runs
       where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  'anon cannot SELECT from runs base table'
);

-- 13. Anon SELECT on public_runs: gets the fixture public row.
select results_eq(
  $$ select id from public_runs
       where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  $$ values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02'::uuid) $$,
  'anon can SELECT from public_runs view'
);

-- 14. Anon INSERT on runs: rejected.
select throws_ok(
  $$ insert into runs (user_id, started_at, duration_s, distance_m, source, metadata)
       values ('00000000-0000-0000-0000-00000000000a',
               now(), 600, 1000, 'app', '{"activity_type":"run"}') $$,
  '42501',
  null,
  'anon cannot INSERT a run'
);

-- 15. The is_run_visible_to helper (used by run_kudos / run_comments /
--     run_photos / segment_efforts / live_run_pings policies) returns
--     true for the public run regardless of the caller — it's
--     SECURITY DEFINER and bypasses RLS by design.
select is(
  private.is_run_visible_to('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02',
                    '00000000-0000-0000-0000-00000000000b'),
  true,
  'private.is_run_visible_to() returns true for any caller on a public run'
);

select * from finish();

rollback;
