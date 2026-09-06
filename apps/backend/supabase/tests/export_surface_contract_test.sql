-- The Art 20 export surface: the bucket the archive lands in, the row that
-- tracks it, and the sweep that expires both (migrations 20270602_001,
-- 20270603_001, and the photo-bucket narrowing 20270622000002 beside them).
--
-- What was already measured: that `exports` exists, is private, carries no
-- `storage.objects` policies, has SOME size limit, has SOME mime list, and is
-- bigger than `runs`. What was not: any of the actual VALUES. A regression to
-- a 26 MB cap — back inside the range 20270602_001 was written to escape,
-- where a full-history archive was truncated to "on the order of tens of
-- runs" — satisfies `exports.file_size_limit > runs.file_size_limit`, and a
-- mime list widened to `text/html` satisfies `allowed_mime_types is not null`.
--
-- The photo buckets are the same shape one door along. decisions § 557 made
-- the accepted set BE the strippable set because `stripImageExif` returns an
-- unrecognised format unchanged and the bucket then serves the geotagged
-- original back through a signed URL; 20270622000002 finally landed that on
-- the three buckets that still advertised HEIC/HEIF. `check_shared_constants`
-- compares the migration TEXT against the two client lists, which is a
-- different claim from what the applied `storage.buckets` row says — a manual
-- console edit, a partially applied migration, or a bucket created by
-- storage-api's own defaults is invisible to it. The two claims are kept
-- side by side rather than one replacing the other: the script reads four
-- source files against each other and can say the clients and the migration
-- agree, which no SQL assertion can; these read the row and can say the
-- database holds it, which no source read can.
--
-- The photo-bucket population here is DERIVED — every bucket accepting any
-- `image/` type — so a fifth image bucket is held to § 557 the day it appears
-- rather than the day somebody remembers to extend a list of four names.
--
-- `data_export_jobs` is asserted on both rails, because the migration's own
-- header says it is on both deliberately: RLS with no policies, AND no client
-- grant, so "a policy added by mistake later still cannot open a client read
-- path". `role_grant_matrix_test` names the table only to EXCLUDE it from its
-- readability catch-all, so a later `grant select … to authenticated` is
-- invisible there.

begin;

select plan(33);

-- ── the exports bucket ──────────────────────────────────────────────────────

-- (1) The three settings that make it the archive bucket, as values. The
-- mime-array LENGTH is the positive-control half: without it, a list widened
-- to include `text/html` still satisfies both membership probes.
select results_eq(
  $$ select public, file_size_limit, array_length(allowed_mime_types, 1),
            'text/csv' = any(allowed_mime_types),
            'application/zip' = any(allowed_mime_types)
       from storage.buckets where id = 'exports' $$,
  $$ values (false, 5368709120::bigint, 2, true, true) $$,
  'the exports bucket is private, admits a 5 GiB archive, and accepts exactly csv + zip');

-- (2) The relational reason the bucket exists at all, kept beside the absolute
-- value so the pair states both the figure and why it is not the runs cap.
select cmp_ok(
  (select file_size_limit from storage.buckets where id = 'exports'),
  '>',
  (select file_size_limit from storage.buckets where id = 'runs'),
  'and is bigger than the runs bucket, which truncated a full-history export');

-- ── the photo buckets ───────────────────────────────────────────────────────
-- § 557 made the accepted set BE the strippable set. `check_shared_constants`
-- compares the migration TEXT against the two client lists, which is a claim
-- about four source files agreeing with each other; these three are the claim
-- about what the database actually holds. Neither subsumes the other — the
-- script cannot see a console edit or an unapplied migration, and pgtap cannot
-- read `STRIPPABLE_IMAGE_MIME_TYPES` at all.

-- (3) The POPULATION is derived, not named: every bucket that accepts any
-- image type at all. A fifth image bucket — created by a later migration, by
-- the dashboard, or by storage-api with its own defaults — lands in this set
-- and fails until somebody holds it to § 557, which a hard-coded list of four
-- names could never do. It is also what makes (4) non-vacuous: a bucket whose
-- list went null drops out of this set rather than out of that filter.
select is(
  (select coalesce(string_agg(id, ', ' order by id), '')
     from storage.buckets
    where exists (select 1 from unnest(allowed_mime_types) t where t like 'image/%')),
  'avatars, club-photos, route-photos, run-photos',
  'exactly four buckets accept images — a new one is held to the strippable set or it is not created');

-- (4) And each accepts exactly the strippable set, in both directions. `@>`
-- alone would pass a bucket narrowed to `['image/png']`, which breaks every
-- JPEG upload; `<@` alone would pass an empty list. The `coalesce(..., true)`
-- is the null arm: `null @> array[...]` is null, so without it a bucket that
-- lost its allowlist entirely would be filtered out of its own check.
select is(
  (select coalesce(string_agg(id || ': ' || coalesce(array_to_string(allowed_mime_types, ','), '<null>'),
                              '; ' order by id), '')
     from storage.buckets
    where id in ('run-photos', 'route-photos', 'club-photos', 'avatars')
      and coalesce(not (allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp']
                        and allowed_mime_types <@ array['image/jpeg', 'image/png', 'image/webp']), true)),
  '',
  'every photo bucket accepts exactly the strippable set — an accepted-but-unstrippable upload serves its GPS EXIF back through a signed URL');

-- (5) The formats § 557 is about, named. 20270622000002 removed HEIC/HEIF from
-- three buckets that had advertised them since 20260620_001 / 20270114_001 /
-- 20270301_001; `stripImageExif` returns an unrecognised format unchanged and
-- the bucket then serves the geotagged original. This is bucket-agnostic on
-- purpose — (3) and (4) are about the four we know, this one holds for any
-- bucket that ever exists, including `runs` and `exports`.
select is(
  (select coalesce(string_agg(b.id || ': ' || t, ', ' order by b.id, t), '')
     from storage.buckets b, unnest(b.allowed_mime_types) t
    where t in ('image/heic', 'image/heif')),
  '',
  'no bucket anywhere accepts image/heic or image/heif — an image we cannot strip is an image we do not accept');

-- ── data_export_jobs: both rails ────────────────────────────────────────────

-- (6) The grant rail. The migration grants `authenticated` nothing at all.
select is(
  (select coalesce(string_agg(r.role || ' ' || v.verb, ', ' order by r.role, v.verb), '')
     from (values ('anon'::name), ('authenticated'::name)) r(role)
     cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) v(verb)
    where has_table_privilege(r.role, 'public.data_export_jobs'::regclass, v.verb)),
  '',
  'no client role holds any grant on data_export_jobs — the second rail behind RLS');

-- (7) The positive control for (6): the only writer keeps its whole surface,
-- so an empty client set is a withholding rather than a table nobody can use.
select is(
  (select coalesce(string_agg(v.verb, ', ' order by v.verb), '')
     from (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) v(verb)
    where not has_table_privilege('service_role', 'public.data_export_jobs'::regclass, v.verb)),
  '',
  'service_role keeps full DML on data_export_jobs — the Go worker is the only writer');

-- (8) The RLS rail, which the grant rail is deliberately redundant with.
select results_eq(
  $$ select c.relrowsecurity, (select count(*)::int from pg_policy p where p.polrelid = c.oid)
       from pg_class c where c.oid = 'public.data_export_jobs'::regclass $$,
  $$ values (true, 0) $$,
  'data_export_jobs keeps RLS on and carries no policy — there is no client read path to serve');

-- ── the row's own constraints, and its lifetime ─────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('e8000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
        'export-subject@dsar.local', '', now(), now());

insert into data_export_jobs (id, user_id, format, status, object_path)
values ('e8000000-0000-0000-0000-0000000000d1', 'e8000000-0000-0000-0000-0000000000a1',
        'backup', 'ready', 'e8000000-0000-0000-0000-0000000000a1/export.zip');

-- (9) `error_code` is a machine token, never prose: a raw upstream error
-- string carries paths and addresses into a durable row.
select lives_ok(
  $$ update data_export_jobs set error_code = repeat('a', 64)
      where id = 'e8000000-0000-0000-0000-0000000000d1' $$,
  'a 64-character machine token is accepted');

select throws_ok(
  $$ update data_export_jobs set error_code = repeat('a', 65)
      where id = 'e8000000-0000-0000-0000-0000000000d1' $$,
  '23514',
  null,
  'a 65-character error_code is rejected — the column is a token, not a place to put prose');

-- (10) One in-flight export per subject. This is what makes a re-POST
-- idempotent rather than a second full archive build charged to Storage.
insert into data_export_jobs (user_id, format, status)
values ('e8000000-0000-0000-0000-0000000000a1', 'csv', 'queued');

select throws_ok(
  $$ insert into data_export_jobs (user_id, format, status)
       values ('e8000000-0000-0000-0000-0000000000a1', 'gpx', 'running') $$,
  '23505',
  null,
  'a second in-flight export for the same subject is refused by the partial unique index');

select lives_ok(
  $$ insert into data_export_jobs (user_id, format, status)
       values ('e8000000-0000-0000-0000-0000000000a1', 'gpx', 'failed') $$,
  'but a terminal-status row is not in flight, so the index is partial rather than one-row-per-user');

-- (11) Art 17. The table comment claims it "cascades away with the account";
-- nothing measured it, and the row carries the fact and timing of a DSAR plus
-- a Storage key naming the subject.
select cmp_ok(
  (select count(*)::int from data_export_jobs
    where user_id = 'e8000000-0000-0000-0000-0000000000a1'),
  '>', 0,
  'the export state rows exist before the erasure');

delete from auth.users where id = 'e8000000-0000-0000-0000-0000000000a1';

select is(
  (select count(*)::int from data_export_jobs
    where user_id = 'e8000000-0000-0000-0000-0000000000a1'),
  0,
  'Art 17 erasure cascades every export state row away with the account');

-- ── the sweep, driven rather than read ──────────────────────────────────────
-- `cleanup_stale_export_blobs` is COMPOSED: it deletes the objects and then
-- calls `expire_stale_export_jobs`, so a `ready` row cannot outlive the object
-- it points at. Nothing measured the composition — `data_export_jobs_test`
-- calls the expiry directly, so dropping the `perform` leaves that file green
-- while production stops expiring rows. It also still has to reach the LEGACY
-- prefix, `runs/{uid}/exports/`, where archives landed before 20270602_001.

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('e8000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated',
        'sweep-subject@dsar.local', '', now(), now());

insert into data_export_jobs (id, user_id, format, status, object_path, finished_at)
values ('e8000000-0000-0000-0000-0000000000d2', 'e8000000-0000-0000-0000-0000000000a2',
        'backup', 'ready', 'e8000000-0000-0000-0000-0000000000a2/old.zip',
        now() - interval '8 days');

insert into storage.objects (bucket_id, name, created_at) values
  ('exports', 'e8000000-0000-0000-0000-0000000000a2/old.zip', now() - interval '8 days'),
  ('runs',    'e8000000-0000-0000-0000-0000000000a2/exports/legacy.zip', now() - interval '8 days'),
  ('exports', 'e8000000-0000-0000-0000-0000000000a2/fresh.zip', now() - interval '1 day'),
  ('runs',    'e8000000-0000-0000-0000-0000000000a2/track.json.gz', now() - interval '8 days');

-- The GUC is deliberately NOT set here. storage-api's
-- `0055-prevent-direct-deletes` migration installs a BEFORE DELETE FOR EACH
-- STATEMENT trigger on `storage.objects` that raises 42501 unless
-- `storage.allow_delete_query` is `'true'`, and it is present in the image
-- BOTH CLIs start — v1.44.11 for CI's pinned 2.84.2 and v1.62.5 for the
-- workstation's 2.109.1 (§ 839 said CI's image lacked it; measured, it does
-- not). Setting it in the fixture is what made the sweep look sound: the
-- function set nothing of its own, so production raised nightly while this
-- file stayed green. 20270703000002 moved the escape into the function, and
-- these assertions now drive it.

-- (12) Everything the sweep is about is present first.
select is(
  (select count(*)::int from storage.objects
    where name like 'e8000000-0000-0000-0000-0000000000a2/%'),
  4,
  'all four fixture objects exist before the sweep');

select is(
  (select count(*)::int from cleanup_stale_export_blobs() as t(n) where true),
  1,
  'the sweep runs and returns a row');

-- (13) The stale archive in the new bucket AND the one at the legacy prefix
-- are both gone; the fresh archive and an unrelated track are both kept.
select is(
  (select coalesce(string_agg(bucket_id || '/' || name, ', ' order by name), '')
     from storage.objects
    where name like 'e8000000-0000-0000-0000-0000000000a2/%'),
  'exports/e8000000-0000-0000-0000-0000000000a2/fresh.zip, '
  'runs/e8000000-0000-0000-0000-0000000000a2/track.json.gz',
  'the sweep removes the stale archive from BOTH the exports bucket and the legacy runs/{uid}/exports/ prefix, and touches nothing else');

-- (14) And the row that pointed at the deleted object was expired in the same
-- call — the composition, not a second cron entry somebody has to remember.
select results_eq(
  $$ select status, object_path from data_export_jobs
      where id = 'e8000000-0000-0000-0000-0000000000d2' $$,
  $$ values ('expired', null::text) $$,
  'the ready row is expired and its path cleared by the same sweep — a ready row cannot outlive its object');

-- ── a sweep that cannot sweep must not read as a sweep that found nothing ───
-- (15) The belt for (12)-(14). Those pass on an image WITHOUT the trigger
-- whatever the function does, so on such an image nothing would notice the
-- escape being deleted again — and a Cloud project WITH the trigger would then
-- go back to raising nightly. This reads the applied body, which is a weaker
-- claim than driving it and is here only to cover that one case.
select ok(
  (select prosrc from pg_proc where proname = 'cleanup_stale_export_blobs')
    like '%storage.allow_delete_query%',
  'the sweep carries its own escape from storage-api''s protect_delete() rather than borrowing a caller''s');

-- (16) The negative control, and the reason the post-condition check exists at
-- all. `get diagnostics row_count` counts what the statement deleted, not what
-- the window required, so a delete that is FILTERED rather than refused looks
-- exactly like a night with nothing stale. A row-level trigger returning null
-- is the cheapest way to produce that shape; an RLS policy on
-- `storage.objects` or a future guard that skips instead of raising would
-- produce the same one. Before 20270703000002 this returned 0.
insert into data_export_jobs (id, user_id, format, status, object_path, finished_at)
values ('e8000000-0000-0000-0000-0000000000d3', 'e8000000-0000-0000-0000-0000000000a2',
        'backup', 'ready', 'e8000000-0000-0000-0000-0000000000a2/blocked.zip',
        now() - interval '9 days');

insert into storage.objects (bucket_id, name, created_at) values
  ('exports', 'e8000000-0000-0000-0000-0000000000a2/blocked.zip', now() - interval '9 days');

create function public.pgtap_skip_object_delete() returns trigger
language plpgsql as $skip$ begin return null; end; $skip$;

create trigger zzz_pgtap_skip_object_delete
  before delete on storage.objects
  for each row execute function public.pgtap_skip_object_delete();

select throws_ok(
  $$ select cleanup_stale_export_blobs() $$,
  'P0001',
  null,
  'a sweep whose delete was filtered raises instead of reporting zero — the archive is still readable and the operator has to hear about it');

-- (17) And it fails CLOSED: the raise takes the expiry with it, so no row
-- claims its object is gone while the object is still there. That ordering is
-- the whole point of checking before `expire_stale_export_jobs()` rather than
-- after.
select is(
  (select status from data_export_jobs where id = 'e8000000-0000-0000-0000-0000000000d3'),
  'ready',
  'and the job row is left alone — an expired row pointing at a surviving archive is worse than either failure on its own');

drop trigger zzz_pgtap_skip_object_delete on storage.objects;
drop function public.pgtap_skip_object_delete();


-- ── the enqueue, which is the half that is actually scheduled ───────────────
-- 20270709000001 took `cleanup-stale-export-blobs` off the clock ([§ 1172]) and
-- left `enqueue_export_blob_reap()` as the ONLY scheduled half of Art 20
-- retention. It shipped with no pgtap coverage at all: neither the function nor
-- the `export_blob_reap` kind was named anywhere under `supabase/tests/`, and
-- what it does is not a one-liner — it derives a worklist from
-- `storage.objects`, deduplicates it per user, and guards on the PAYLOAD rather
-- than the kind. Its author verified it against a throwaway container with the
-- surrounding objects stubbed, which cannot see a `jobs` CHECK or an RLS
-- interaction; these drive the real schema.

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('e8000000-0000-0000-0000-0000000000a3', 'authenticated', 'authenticated',
        'reap-legacy-two@dsar.local', '', now(), now()),
       ('e8000000-0000-0000-0000-0000000000a4', 'authenticated', 'authenticated',
        'reap-legacy-one@dsar.local', '', now(), now()),
       ('e8000000-0000-0000-0000-0000000000a5', 'authenticated', 'authenticated',
        'reap-no-legacy@dsar.local', '', now(), now());

-- a3 holds TWO legacy archives (one job, not two), a4 holds one, and a5 holds
-- only a track in the same bucket — the object the prefix filter must not
-- mistake for an export.
insert into storage.objects (bucket_id, name, created_at) values
  ('runs',    'e8000000-0000-0000-0000-0000000000a3/exports/one.zip', now() - interval '9 days'),
  ('runs',    'e8000000-0000-0000-0000-0000000000a3/exports/two.zip', now() - interval '8 days'),
  ('runs',    'e8000000-0000-0000-0000-0000000000a4/exports/only.zip', now() - interval '8 days'),
  ('runs',    'e8000000-0000-0000-0000-0000000000a5/track.json.gz', now() - interval '9 days'),
  ('exports', 'e8000000-0000-0000-0000-0000000000a5/archive.zip', now() - interval '9 days');

-- A `ready` row past the window, for the composition assertion below. Its
-- object lives in the `exports` bucket, which the default payload covers.
insert into data_export_jobs (id, user_id, format, status, object_path, finished_at)
values ('e8000000-0000-0000-0000-0000000000d4', 'e8000000-0000-0000-0000-0000000000a5',
        'backup', 'ready', 'e8000000-0000-0000-0000-0000000000a5/archive.zip',
        now() - interval '9 days');

-- (18) Nothing has queued a reap yet, so what follows is this call's work and
-- not the seed's. Every assertion below reads only this kind.
select is(
  (select count(*)::int from jobs where kind = 'export_blob_reap'),
  0,
  'no reap is queued before the enqueue runs');

select lives_ok(
  $$ select enqueue_export_blob_reap() $$,
  'the enqueue runs against the real schema — the jobs CHECK admits the kind it writes');

-- (19) The worklist, named. One job for the `exports` bucket at its default
-- window, one per USER still holding a legacy `runs/{uid}/exports/*` archive —
-- a3 holds two archives and gets one job — and none for a5, whose only object
-- in that bucket is a track. A whole-`runs` walk would be O(users) list calls,
-- which is why the prefix set is derived from the rows that exist.
select is(
  (select coalesce(string_agg(payload::text, ' | ' order by payload::text), '')
     from jobs where kind = 'export_blob_reap'),
  '{"bucket": "runs", "prefix": "e8000000-0000-0000-0000-0000000000a3/exports/"} | '
  '{"bucket": "runs", "prefix": "e8000000-0000-0000-0000-0000000000a4/exports/"} | {}',
  'one job for the exports bucket plus one per user with a legacy archive, deduplicated, and none for a plain track object in the same bucket');

-- (20) `max_attempts` 3 rather than the table default of 5. A reap re-lists, so
-- a retry cannot re-erase; three failures is an outage rather than a blip, and
-- the next night re-derives the same worklist anyway.
select is(
  (select coalesce(string_agg(distinct max_attempts::text, ', '), '')
     from jobs where kind = 'export_blob_reap'),
  '3',
  'every queued reap carries max_attempts 3, not the table default of 5');

-- (21) The composition, which is the half that runs whether or not a worker
-- ever claims the job: `expire_stale_export_jobs()` is called by the ENQUEUE,
-- so reachability is removed on the pg_cron tick rather than on the worker's.
-- Dropping the `perform` leaves the worker's own tests green while a subject is
-- handed a signed path to an archive the reaper is about to erase.
select results_eq(
  $$ select status, object_path from data_export_jobs
      where id = 'e8000000-0000-0000-0000-0000000000d4' $$,
  $$ values ('expired', null::text) $$,
  'the enqueue expired the ready row itself — reachability goes first, erasure second, on the scheduled path');

-- (22) The singleton guard. A week of nights with the worker down must leave
-- one job per worklist, not seven: the second call re-derives the same
-- payloads and finds each already queued.
select lives_ok(
  $$ select enqueue_export_blob_reap() $$,
  'a second enqueue over the same worklist runs');

select is(
  (select count(*)::int from jobs where kind = 'export_blob_reap'),
  3,
  'and adds nothing — the guard is per payload, so a night the worker was down cannot stack identical sweeps');

-- (23) And it is per PAYLOAD rather than per KIND, which is what stops the
-- `exports` job from suppressing the legacy ones every night. Drain the default
-- job alone; the next call re-emits that payload and still suppresses the two
-- that are queued.
update jobs set status = 'done', finished_at = now()
 where kind = 'export_blob_reap' and payload = '{}'::jsonb;

do $reap$ begin perform enqueue_export_blob_reap(); end $reap$;

select is(
  (select coalesce(string_agg(payload::text || ' ' || status, ' | ' order by payload::text, status), '')
     from jobs where kind = 'export_blob_reap'),
  '{"bucket": "runs", "prefix": "e8000000-0000-0000-0000-0000000000a3/exports/"} queued | '
  '{"bucket": "runs", "prefix": "e8000000-0000-0000-0000-0000000000a4/exports/"} queued | '
  '{} done | {} queued',
  'a drained payload is re-queued while the two still in flight are not — a kind-wide guard would have let the first payload inserted suppress the others every night');



-- ── the retention overrun, which is the condition and not the cause ────────
-- `jobs_backlog_summary` (20270710000004) catches a reap nobody claimed. It
-- cannot catch a reap that WAS claimed, ran, and whose Go handler erased
-- nothing: that job is `done` and the queue is drained while the archives stay
-- readable. Only a count over `storage.objects` can tell, and § 1172 left
-- nothing counting -- `cleanup_stale_export_blobs`'s own post-condition raise
-- fires only when something calls it, and nothing calls it any more.
--
-- The storage fixture is reset first. Everything above left objects behind on
-- purpose (the sweep's survivors, the blocked one, the legacy prefixes the
-- enqueue derives from), and `export_retention_overrun` counts the whole
-- bucket -- so the assertions below would be about that debris plus whatever
-- this block files. The GUC is storage-api's `protect_delete()` escape, set
-- transaction-locally exactly as the sweep sets it.
do $reset$
begin
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
   where (bucket_id = 'runs' and name like '%/exports/%') or bucket_id = 'exports';
end
$reset$;

insert into storage.objects (bucket_id, name, created_at) values
  ('exports', 'e8000000-0000-0000-0000-0000000000a3/way-past.zip', now() - interval '30 days'),
  ('runs',    'e8000000-0000-0000-0000-0000000000a3/exports/legacy-past.zip', now() - interval '12 days'),
  ('exports', 'e8000000-0000-0000-0000-0000000000a3/inside-grace.zip', now() - interval '7 days 6 hours'),
  ('exports', 'e8000000-0000-0000-0000-0000000000a3/fresh.zip', now() - interval '1 day'),
  ('runs',    'e8000000-0000-0000-0000-0000000000a3/track.json.gz', now() - interval '30 days');

-- (24) Both archive prefixes count, the object inside the grace day does not,
-- and a track in the same bucket is not an export artifact. The predicate is
-- the sweep's own, so the alert and the reaper cannot disagree about what they
-- are talking about.
select results_eq(
  $$ select (export_retention_overrun() ->> 'overrun_count')::int,
            (export_retention_overrun() -> 'by_bucket') $$,
  $$ values (2, '{"runs": 1, "exports": 1}'::jsonb) $$,
  'the overrun counts stale archives in both the exports bucket and the legacy prefix, and nothing else');

-- (25) The grace day is the whole reason this can be scheduled. Objects cross
-- the 7-day line continuously and the reap runs once a night, so at any instant
-- up to a day of archives are legitimately waiting. Without the grace this
-- would fire every day forever, which is the same as not alerting.
select is(
  (select (export_retention_overrun('0 seconds'::interval) ->> 'overrun_count')::int),
  3,
  'and without the grace the object waiting for tonight''s reap would be reported too');

-- (26) The oldest age is reported, so a scraper can alert on how long the
-- overrun has lasted rather than on the fact of one.
select cmp_ok(
  (export_retention_overrun() ->> 'oldest_age_s')::int,
  '>=',
  30 * 86400,
  'the age of the oldest survivor is reported alongside the count');

-- (27) And a clean bucket reports zero rather than null, so a scraper routing
-- on `overrun_count > 0` is not comparing against null on every healthy day.
do $clean$
begin
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
   where (bucket_id = 'runs' and name like '%/exports/%') or bucket_id = 'exports';
end
$clean$;

select results_eq(
  $$ select (export_retention_overrun() ->> 'overrun_count')::int,
            (export_retention_overrun() ->> 'oldest_age_s')::int,
            (export_retention_overrun() -> 'by_bucket') $$,
  $$ values (0, 0, '{}'::jsonb) $$,
  'a bucket inside its retention window reports zero and an empty breakdown, never null');

select * from finish();

rollback;
