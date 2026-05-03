-- Gate `run-photos` Storage bytes on parent-run visibility.
--
-- Closes the audit/storage Medium finding from /audit/all on 2026-05-03:
-- run_photos *metadata* visibility was tightened in
-- 20260701_001_drop_runs_public_select_policy.sql via
-- `is_run_visible_to(...)`, but the Storage SELECT policy on the
-- `run-photos` bucket stayed wide open (`using (bucket_id =
-- 'run-photos')` from 20260525_001_run_photos.sql).
--
-- That asymmetry meant: a private run's photo *row* was hidden by RLS,
-- but the photo *bytes* at `{owner_id}/{photo_id}.{ext}` were
-- world-readable to anyone who held a stable URL — including URLs
-- that had been rendered while the run was still public, then never
-- expired. The mitigation was uuid-unguessability of the photo path,
-- which doesn't survive any leaked URL (cache, screenshot, scraper).
--
-- This migration replaces the open SELECT policy with one that joins
-- through `run_photos` → `runs.is_public` (via `is_run_visible_to`).
-- The bucket stays nominally "public" so `getPublicUrl(...)` keeps
-- producing stable URLs for the cacheable share path; access is gated
-- at the policy layer, not at the URL-signing layer. Same shape that
-- the runs bucket adopted in 20260619_001_drop_public_runs_storage_policy.sql.

drop policy if exists "Anyone can read run photo bytes" on storage.objects;

create policy "run-photo bytes visible when parent run is visible"
  on storage.objects for select
  to anon, authenticated
  using (
    bucket_id = 'run-photos'
    and exists (
      select 1
      from run_photos rp
      where rp.storage_path = storage.objects.name
        and is_run_visible_to(rp.run_id, auth.uid())
    )
  );
