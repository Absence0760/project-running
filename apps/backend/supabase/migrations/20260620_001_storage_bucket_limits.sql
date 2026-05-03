-- Bucket-level size + MIME enforcement on runs + run-photos.
--
-- audit/storage Medium finding. The original
-- `insert into storage.buckets ...` calls in 20260410_001 (runs) and
-- 20260525_001 (run-photos) specified only (id, name, public),
-- leaving file_size_limit + allowed_mime_types null. The web client
-- enforces a 10MB cap + JPEG/PNG/WebP/HEIC/HEIF allow-list at upload
-- time, but a raw `supabase.storage.from('run-photos').upload(...)`
-- call bypasses the client filter. SVG with embedded script could
-- land in the public-read run-photos bucket and execute on the
-- share page (XSS via getPublicUrl + svg+xml MIME).
--
-- Per-bucket caps:
-- * runs — gzipped JSON tracks. A 5h run at 1Hz is ~18k points;
--   gzipped ~1MB. Cap at 25MB to leave headroom for high-frequency
--   recorders + the per-user exports/<ts>.{csv,zip} blobs that share
--   the prefix. No MIME allow-list — the bucket holds two distinct
--   content types and the upload paths are gated by RLS to the
--   owner anyway.
-- * run-photos — image bytes. Cap matches the client's
--   PHOTO_MAX_BYTES (10MB). MIME allow-list matches the client's
--   PHOTO_MIME_TO_EXT keys (no SVG; no GIF, since the share page
--   has no use for animation).

update storage.buckets
  set file_size_limit = 26214400  -- 25 MB
  where id = 'runs';

update storage.buckets
  set file_size_limit = 10485760, -- 10 MB
      allowed_mime_types = array[
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/heic',
        'image/heif'
      ]
  where id = 'run-photos';
