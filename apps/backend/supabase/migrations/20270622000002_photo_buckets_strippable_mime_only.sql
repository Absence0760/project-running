-- The three photo buckets still advertise HEIC/HEIF; the clients stopped
-- accepting them, and the bucket is the rail a raw upload actually meets.
--
-- decisions.md § 557 settled that "an image we cannot strip is an image we do
-- not accept", and made the accepted set BE the strippable set — JPEG, PNG,
-- WebP — because `stripImageExif` returned an unrecognised format unchanged
-- and the bucket then served the geotagged original back through a signed URL.
-- That change landed on the client rails: `STRIPPABLE_IMAGE_MIME_TYPES`
-- (apps/web/src/lib/util/exif_strip.ts), `kStrippableImageMimeTypes`
-- (apps/mobile_android/lib/exif_strip.dart) and `PHOTO_MIME_TO_EXT`, with a
-- guard in security_guards.test.ts asserting accepted ⊆ strippable.
--
-- It did not land here. `run-photos` (20260620_001), `route-photos`
-- (20270114_001) and `club-photos` (20270301_001) were all written before
-- § 557 and still carry 'image/heic' + 'image/heif'. Those three bucket
-- migrations exist precisely because "a raw
-- `supabase.storage.from(...).upload(...)` call bypasses the client filter" —
-- so the one door § 557 could not close from the client is the one still open:
-- storage-api accepts a HEIC, nothing strips it (the Go worker's
-- `handler_photo_process` returns early on any non-JPEG), and the GPS EXIF is
-- served back to everyone who can see the gallery. That is § 33's home
-- coordinate handed over by a different door, which is § 557's own phrase for
-- it.
--
-- `avatars` (20260927_001) already carries exactly the three and is left
-- alone; `runs` and `exports` hold non-image payloads and are unrelated.
--
-- scripts/check_shared_constants.mjs reads these arrays and the two client
-- lists from source now, so the four cannot drift apart again silently
-- (decisions.md § 787).
--
-- No table DDL: three single-row updates on storage.buckets.

update storage.buckets
  set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
  where id in ('run-photos', 'route-photos', 'club-photos');
