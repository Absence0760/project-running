-- Flip the `run-photos` Storage bucket to private + force signed-URL
-- access from clients.
--
-- Prior state: `20260525_001_run_photos.sql` created the bucket with
-- `public = true`. `20260705_001_run_photos_storage_visibility_gate.sql`
-- replaced the open SELECT policy with a `is_run_visible_to(...)` gate.
-- That migration's commentary said "bucket stays nominally 'public' so
-- getPublicUrl(...) keeps producing stable URLs; access is gated at
-- the policy layer" — that is incorrect. Supabase Storage routes
-- public-bucket reads through the unauthenticated CDN endpoint
-- (/storage/v1/object/public/...) which bypasses RLS on storage.objects.
-- The visibility gate from 20260705_001 is therefore unenforced for
-- direct public-URL fetches as long as the bucket flag is true.
--
-- Outcome of the leak: a private run's photo bytes were readable by
-- anyone who held a stable public URL — same shape we already closed
-- for the `runs` track bucket in 20260619_001.
--
-- This migration:
--   1. Sets `storage.buckets.public = false` for `run-photos`. RLS on
--      storage.objects is now enforced for every read.
--   2. Leaves the SELECT policy from 20260705_001 in place — it now
--      actually fires.
--
-- Client impact (handled in the same change set):
--   - apps/web/src/lib/data.ts: `getPublicUrl(...)` → `createSignedUrl(...)`
--     with a 1 h TTL.
--   - apps/mobile_android/lib/widgets/run_photos.dart: same.

update storage.buckets
   set public = false
 where id = 'run-photos';
