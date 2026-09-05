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
-- Adding a new kind means a migration extending the CHECK, a Go
-- dispatch case, and one row in the `job_kind` fixture below.
--
-- Coverage:
--   1. One INSERT per fixture row — each accepted, because a kind the
--      CHECK admits is a kind the Go dispatch switch must know.
--   2. INSERT 'unknown_kind'  — rejected (23514)
--   3. INSERT 'map-match'     — rejected (the typo-catcher path)
--   4. UPDATE flipping a valid kind to a junk one is also rejected
--      (so a future REST surface that lets a row be re-classified
--      can't bypass the constraint via UPDATE).
--   5. The set the fixture exercises is the set the CHECK admits,
--      read off `pg_get_constraintdef`.
--
-- (5) exists because (1) used to be a hand-kept list vouching for
-- itself, and three kinds fell out of it: `club_photo_process`
-- (20270301_001) and `safety_sms` (20270410_001) shipped their
-- migration and their handler but were never added, so for two rounds
-- the suite passed while asserting nothing about them, and
-- `export_blob_reap` (20270708000010) was the third. An omission is a
-- suite that silently covers less, which is the one failure a list
-- naming only what it does cover cannot report.
--
-- ── Why one list and not two ──
-- (5) landed beside sixteen hand-written `lives_ok` calls and a
-- hand-written expected string, which is two lists for one set: a kind
-- could be added to either and dropped from the other, and the second
-- copy is the one nothing else in the tree reads. The fixture table
-- below is now the single list. It is the source of BOTH halves —
-- every `lives_ok` is driven off a row, and (5) compares the CHECK
-- against the same rows — so the two can no longer disagree, and
-- `plan()` self-enforces: a row added without bumping the count is a
-- pgtap plan mismatch rather than a silently wider run.
--
-- The comparison is still not circular. The fixture is hand-written
-- source in this file; `pg_get_constraintdef` reads the constraint a
-- migration built. Two sources, one assertion between them.

begin;

select plan(20);

-- The one list: each row is both an INSERT the CHECK must accept and a
-- kind the CHECK must admit. The payloads are representative of what the
-- real producer writes, so a future payload CHECK fails here too.
create temporary table job_kind (kind text primary key, payload jsonb not null);

insert into job_kind (kind, payload) values
  ('map_match',            jsonb_build_object('run_id', gen_random_uuid(),
                                              'user_id', gen_random_uuid())),
  ('token_refresh',        '{}'::jsonb),
  ('strava_event',         jsonb_build_object('owner_id', 12345,
                                              'object_id', 67890,
                                              'aspect_type', 'create',
                                              'event_time', extract(epoch from now())::int)),
  ('photo_process',        jsonb_build_object('photo_id', gen_random_uuid(),
                                              'storage_path', 'user/photo.jpg',
                                              'owner_id', gen_random_uuid())),
  ('notification_email',   jsonb_build_object('notification_id', gen_random_uuid())),
  ('lifecycle_email',      jsonb_build_object('user_id', gen_random_uuid(),
                                              'template', 'welcome')),
  ('safety_email',         jsonb_build_object('template', 'finish',
                                              'contact_email', 'c@x.local',
                                              'run_id', gen_random_uuid())),
  ('web_push',             jsonb_build_object('notification_id', gen_random_uuid())),
  ('weekly_digest',        jsonb_build_object('user_id', gen_random_uuid())),
  ('native_push',          jsonb_build_object('notification_id', gen_random_uuid())),
  ('lifecycle_drip',       jsonb_build_object('user_id', gen_random_uuid(),
                                              'template', 'drip_onboarding')),
  ('route_photo_process',  jsonb_build_object('photo_id', gen_random_uuid(),
                                              'storage_path', 'user/route_photo.jpg',
                                              'owner_id', gen_random_uuid())),
  ('club_photo_process',   jsonb_build_object('photo_id', gen_random_uuid(),
                                              'storage_path', 'club/photo.jpg',
                                              'owner_id', gen_random_uuid())),
  ('safety_sms',           jsonb_build_object('template', 'overdue',
                                              'contact_phone', '+10000000000',
                                              'run_id', gen_random_uuid())),
  ('data_export',          jsonb_build_object('export_job_id', gen_random_uuid(),
                                              'user_id', gen_random_uuid(),
                                              'format', 'backup')),
  ('export_blob_reap',     '{}'::jsonb);

-- (1) Accepted kinds round-trip cleanly. We're not asserting any particular
-- id; just that the INSERT doesn't throw. One TAP line per fixture row,
-- ordered so the output is stable.
select lives_ok(
  format($$ insert into public.jobs (kind, payload) values (%L, %L::jsonb) $$,
         k.kind, k.payload),
  format('public.jobs accepts kind = %L', k.kind)
)
  from job_kind k
 order by k.kind collate "C";

-- (2) Junk kinds are rejected at INSERT time, not deferred to dispatch.
select throws_ok(
  $$ insert into public.jobs (kind, payload)
     values ('unknown_kind', '{}'::jsonb) $$,
  '23514',
  null,
  'public.jobs rejects unknown kind at INSERT'
);

-- (3) The typo path: hyphens vs underscores. Catches a class of
-- copy-paste regression where a trigger drifts away from the
-- worker's switch.
select throws_ok(
  $$ insert into public.jobs (kind, payload)
     values ('map-match', '{}'::jsonb) $$,
  '23514',
  null,
  'public.jobs rejects hyphenated map-match typo'
);

-- (4) UPDATE path: a future surface that re-classifies a job by flipping
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

-- (5) The set (1) exercises is the set the constraint admits. The kinds are the
-- only single-quoted literals `pg_get_constraintdef` renders for this CHECK
-- (`CHECK ((kind = ANY (ARRAY['map_match'::text, ...)))` — the casts and the
-- column name are unquoted), and both sides are ordered under `C` so the
-- comparison does not depend on the database's collation opinion about `_`.
select is(
  (select string_agg(m.caps[1], ', ' order by m.caps[1] collate "C")
     from pg_constraint c,
          lateral regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g') as m(caps)
    where c.conrelid = 'public.jobs'::regclass
      and c.conname = 'jobs_kind_chk'),
  (select string_agg(k.kind, ', ' order by k.kind collate "C") from job_kind k),
  'jobs_kind_chk admits exactly the kinds the fixture above exercises'
);

select * from finish();
rollback;
