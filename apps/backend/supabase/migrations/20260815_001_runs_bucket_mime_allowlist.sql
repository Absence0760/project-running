-- /audit/all storage Medium (defence-in-depth): the `runs` Storage
-- bucket has a 25 MB size cap (20260620_001) but no MIME allow-list.
-- The bucket holds gzipped JSON tracks and CSV / ZIP exports — none
-- are HTML-executed by a browser today, so there's no live XSS, but
-- a future code path that serves `runs` bytes with
-- `Content-Type: image/svg+xml` (e.g. a thumbnail Lambda, an
-- SSR-rendered share page) would become a vector. Lock the MIME set
-- to the four content classes legitimate writers actually use.
--
-- Writers today:
--   - `_runFromRow` / `RunRecorder.finalise` — gzipped JSON track:
--     `application/gzip` (mobile sets this on .upload).
--   - `export-data` Edge Function CSV: `text/csv`.
--   - `export-data` Edge Function GPX-zip: `application/zip`.
--
-- `application/octet-stream` is included as a defence-in-depth
-- fallback because supabase-js historically defaulted to that when
-- a Blob's MIME wasn't explicitly set; some older mobile callers
-- might still emit it. Adding it doesn't open new XSS surface
-- (octet-stream isn't HTML-executed) and a future writer that
-- forgot to set Content-Type still works.

update storage.buckets
  set allowed_mime_types = array[
    'application/gzip',
    'application/octet-stream',
    'text/csv',
    'application/zip'
  ]
  where id = 'runs';
