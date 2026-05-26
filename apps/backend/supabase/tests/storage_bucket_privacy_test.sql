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

select plan(6);

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

select * from finish();
rollback;
