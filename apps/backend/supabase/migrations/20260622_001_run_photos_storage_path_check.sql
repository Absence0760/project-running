-- Pin run_photos.storage_path to the canonical {owner_id}/...
-- shape so a malicious owner can't rewrite the column to point at
-- another user's blob.
--
-- audit/storage pass-3 Low. Same threat shape as runs.track_url
-- before 20260621_001 closed it: storage_path was owner-writable
-- text with no shape constraint, even though the column comment
-- says `e.g. {owner_id}/{photo_id}.{ext}`. The run-photos bucket
-- is currently public-read, so a forged path doesn't escalate
-- access today (an attacker can already hot-link any photo via
-- its public URL). But this is the exact shape runs.track_url had
-- before the High fix, and a future migration that flips the
-- bucket to private — for paid clubs / private feed — would
-- re-open the same forge vector. Pre-empt it now while every
-- legitimate writer (web data.ts, mobile api_client.dart) already
-- uses the canonical shape.
--
-- The empty-string branch accommodates the mobile insert flow:
-- packages/api_client/lib/src/api_client.dart:1142 inserts a row
-- with `storage_path = ''` because the photo_id is generated
-- server-side on insert; the function then uploads to
-- {owner_id}/{photo_id}.{ext} and updates the row to point at the
-- real path. The placeholder window is short (one round-trip)
-- and the bucket public-read means an empty path is never
-- dereferenced as a blob; the security property — "a non-empty
-- storage_path must be owner-prefixed" — is preserved.
--
-- LIKE-prefix rather than strict equality because the path
-- includes a photo_id and a content-dependent extension that
-- vary per upload. Pinning the prefix is enough — the photo_id
-- and ext are already server-determined or driven by validated
-- MIME (per 20260620_001's allow-list).

alter table run_photos
  add constraint run_photos_storage_path_shape
  check (
    storage_path = ''
    or storage_path like owner_id::text || '/%'
  ) not valid;

alter table run_photos validate constraint run_photos_storage_path_shape;
