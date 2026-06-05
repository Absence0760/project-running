-- Pin the `jobs.kind` CHECK allowlist from migration
-- 20260822_001_jobs_kind_allowlist.sql.
--
-- Pre-fix, `jobs.kind` was open-ended `text`. A typo in a trigger
-- (`'map-match'` vs `'map_match'`) or an operator-inserted job with
-- the wrong string would slip through INSERT and only surface at
-- worker dispatch as `finish_job(failed, "unknown job kind ...")`.
-- The constraint catches every drift at INSERT time so a new kind
-- without a matching worker handler can't ship silently.
--
-- The migration adds `check (kind in ('map_match', 'token_refresh'))`.
-- Adding a new kind requires a new migration that extends the CHECK
-- + a Go dispatch case + extending this test.
--
-- Coverage:
--   1. INSERT 'map_match'     — accepted (worker handler exists)
--   2. INSERT 'token_refresh' — accepted (worker handler exists)
--   3. INSERT 'unknown_kind'  — rejected (23514)
--   4. INSERT 'map-match'     — rejected (the typo-catcher path)
--   5. UPDATE flipping a valid kind to a junk one is also rejected
--      (so a future REST surface that lets a row be re-classified
--      can't bypass the constraint via UPDATE).

begin;

select plan(11);

-- Accepted kinds round-trip cleanly. We're not asserting any
-- particular id; just that the INSERT doesn't throw.
select lives_ok(
  $$ insert into public.jobs (kind, payload)
     values ('map_match',
             jsonb_build_object('run_id', gen_random_uuid(),
                                'user_id', gen_random_uuid())) $$,
  'public.jobs accepts kind = ''map_match'''
);

select lives_ok(
  $$ insert into public.jobs (kind, payload)
     values ('token_refresh', '{}'::jsonb) $$,
  'public.jobs accepts kind = ''token_refresh'''
);

select lives_ok(
  $$ insert into public.jobs (kind, payload)
     values ('strava_event',
             jsonb_build_object('owner_id', 12345,
                                'object_id', 67890,
                                'aspect_type', 'create',
                                'event_time', extract(epoch from now())::int)) $$,
  'public.jobs accepts kind = ''strava_event'''
);

select lives_ok(
  $$ insert into public.jobs (kind, payload)
     values ('photo_process',
             jsonb_build_object('photo_id', gen_random_uuid(),
                                'storage_path', 'user/photo.jpg',
                                'owner_id', gen_random_uuid())) $$,
  'public.jobs accepts kind = ''photo_process'''
);

select lives_ok(
  $$ insert into public.jobs (kind, payload)
     values ('notification_email',
             jsonb_build_object('notification_id', gen_random_uuid())) $$,
  'public.jobs accepts kind = ''notification_email'''
);

select lives_ok(
  $$ insert into public.jobs (kind, payload)
     values ('lifecycle_email',
             jsonb_build_object('user_id', gen_random_uuid(), 'template', 'welcome')) $$,
  'public.jobs accepts kind = ''lifecycle_email'''
);

select lives_ok(
  $$ insert into public.jobs (kind, payload)
     values ('safety_email',
             jsonb_build_object('template', 'finish',
                                'contact_email', 'c@x.local',
                                'run_id', gen_random_uuid())) $$,
  'public.jobs accepts kind = ''safety_email'''
);

select lives_ok(
  $$ insert into public.jobs (kind, payload)
     values ('web_push',
             jsonb_build_object('notification_id', gen_random_uuid())) $$,
  'public.jobs accepts kind = ''web_push'''
);

-- Junk kinds are rejected at INSERT time, not deferred to dispatch.
select throws_ok(
  $$ insert into public.jobs (kind, payload)
     values ('unknown_kind', '{}'::jsonb) $$,
  '23514',
  null,
  'public.jobs rejects unknown kind at INSERT'
);

-- The typo path: hyphens vs underscores. Catches a class of
-- copy-paste regression where a trigger drifts away from the
-- worker's switch.
select throws_ok(
  $$ insert into public.jobs (kind, payload)
     values ('map-match', '{}'::jsonb) $$,
  '23514',
  null,
  'public.jobs rejects hyphenated map-match typo'
);

-- UPDATE path: a future surface that re-classifies a job by flipping
-- `kind` (say, a manual operator retry through a different handler)
-- can't bypass the constraint. `jobs.id` is `generated always as
-- identity` so we can't poke a literal id; we grab the just-inserted
-- one via `currval` on the column's sequence and feed it into the
-- statement under test.
insert into public.jobs (kind, payload)
  values ('token_refresh', '{}'::jsonb);
select throws_ok(
  format($$ update public.jobs set kind = 'rogue_kind' where id = %s $$,
         currval(pg_get_serial_sequence('public.jobs', 'id'))),
  '23514',
  null,
  'public.jobs UPDATE rejects flipping kind to a junk value'
);

select * from finish();
rollback;
