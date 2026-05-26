-- pgtap suite for the Storage-bucket privacy invariants flagged by
-- the audit:storage sweep (May 2026 round). Two assertions:
--
--   1. Both runs + run-photos buckets MUST have public = false. A
--      `public = true` bucket bypasses every storage.objects RLS
--      policy at the CDN endpoint — anyone with the object path
--      can GET it without any token. The runs bucket was created
--      private; run-photos was flipped from true to false in
--      20260712_001 once the audit caught the original mistake.
--      Pinning both so a future `update storage.buckets set public
--      = true` (e.g. while debugging a "why is my photo 401-ing"
--      ticket) doesn't ship.
--
--   2. file_size_limit + allowed_mime_types are non-null on every
--      user-upload bucket — a bucket created without either is the
--      shape that triggered 20260620_001 (the SVG-XSS vector that
--      let an authenticated user upload an SVG to run-photos and
--      have it render as XSS on the CDN domain).

begin;

select plan(14);

-- ─── 1. public = false on private buckets ──────────────────────────
select is(
  (select public from storage.buckets where id = 'runs'),
  false,
  'runs bucket MUST have public = false — a public-flag bypass would '
  'let anyone with the {user_id}/{run_id}.json.gz path GET the '
  'gzipped track without any auth, bypassing the per-folder owner '
  'SELECT policy and the clip-public-track Edge Function'
);

select is(
  (select public from storage.buckets where id = 'run-photos'),
  false,
  'run-photos bucket MUST have public = false — flipped from true '
  'to false in 20260712_001 after the audit caught it; regressing '
  'would re-open the same RLS-bypass surface'
);

-- ─── 2. file_size_limit set on user-upload buckets ─────────────────
select isnt(
  (select file_size_limit from storage.buckets where id = 'runs'),
  null,
  'runs bucket MUST set file_size_limit — a missing cap lets a single '
  'upload allocate up to the platform ceiling (~10 GB) and DoS the '
  'function host'
);

select isnt(
  (select file_size_limit from storage.buckets where id = 'run-photos'),
  null,
  'run-photos bucket MUST set file_size_limit'
);

-- ─── 3. allowed_mime_types set on user-upload buckets ──────────────
select isnt(
  (select allowed_mime_types from storage.buckets where id = 'runs'),
  null,
  'runs bucket MUST set allowed_mime_types — without it, an attacker '
  'can upload an SVG (which the CDN serves with the uploaded '
  'content-type) and execute XSS on the storage domain (decisions §33 '
  '+ migration 20260620_001 / 20260815_001 history)'
);

select isnt(
  (select allowed_mime_types from storage.buckets where id = 'run-photos'),
  null,
  'run-photos bucket MUST set allowed_mime_types — same SVG-XSS '
  'vector applies to any image-rendering bucket without a tight '
  'image/* allowlist'
);

-- ─── 4. avatars bucket configuration ───────────────────────────────
-- Created in 20260927_001 with public=true (avatars render on
-- public profile pages), tight size cap, and owner-scoped writes.
select is(
  (select public from storage.buckets where id = 'avatars'),
  true,
  'avatars bucket MUST have public = true — avatars render on public '
  'profile pages, so the bucket is intentionally CDN-readable'
);

select isnt(
  (select file_size_limit from storage.buckets where id = 'avatars'),
  null,
  'avatars bucket MUST set file_size_limit — 2 MB cap is documented'
);

select isnt(
  (select allowed_mime_types from storage.buckets where id = 'avatars'),
  null,
  'avatars bucket MUST set allowed_mime_types to image/*'
);

select ok(
  (select count(*) from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and policyname = 'avatars owner can upload') = 1,
  'avatars bucket MUST have an owner-scoped INSERT policy '
  '(without it, the bucket is upload-by-anyone — same shape that '
  '20260712_001 closed for run-photos)'
);

-- ─── 5. run-photos SELECT policy content pin ───────────────────────
-- Pins the policy USING expression contains the
-- `private.is_run_visible_to` helper — that's the only path that
-- joins back through the run_photos row to the parent run for
-- visibility. A regression that silently swaps the SELECT policy
-- to a bare `bucket_id = 'run-photos'` form would let any caller
-- with the object path GET it, bypassing the private-run gate.
select ok(
  exists (
    select 1 from pg_policies
     where schemaname = 'storage'
       and tablename = 'objects'
       and cmd = 'SELECT'
       and qual ilike '%is_run_visible_to%'
  ),
  'run-photos SELECT policy MUST reference private.is_run_visible_to '
  '— without it, the bytes for a private runs photo are reachable '
  'via a direct Storage GET with the object path'
);

-- ─── 6. Generalised: every bucket has size + mime caps ─────────────
-- Catches a new bucket being created without limits — the exact
-- omission that triggered 20260620_001 (SVG-XSS vector). Iterates
-- over storage.buckets rather than naming each one.
select is(
  (select count(*) from storage.buckets where file_size_limit is null),
  0::bigint,
  'every storage bucket MUST set file_size_limit — a missing cap '
  'lets a single upload allocate up to the platform ceiling. Iterates '
  'over storage.buckets so a future bucket without the cap fails '
  'this test instead of the test having to be re-extended.'
);

select is(
  (select count(*) from storage.buckets where allowed_mime_types is null),
  0::bigint,
  'every storage bucket MUST set allowed_mime_types — without it, an '
  'SVG-XSS upload renders as XSS on the CDN domain. Iterates over '
  'all buckets per the audit:storage May 2026 recommendation.'
);

-- ─── 7. Orphan cleanup did its job ─────────────────────────────────
-- After 20260927_001's cleanup, every run-photos blob is referenced
-- by some run_photos row. A non-empty result here means the cleanup
-- failed or a new orphan was inserted without going through the
-- run_photos table.
select is(
  (
    select count(*) from storage.objects
      where bucket_id = 'run-photos'
        and name not in (
          select storage_path from run_photos
            where storage_path is not null
          union
          select thumb_512_path from run_photos
            where thumb_512_path is not null
        )
  )::int,
  0::int,
  'every blob in run-photos MUST be referenced by a run_photos row '
  '(via storage_path OR thumb_512_path) — orphans pay for storage '
  'cost + are a latent privacy footprint if anyone guesses the path'
);

select * from finish();
rollback;
