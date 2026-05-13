-- Server-side thumbnails on run_photos.
--
-- The photo_process job (added in 20260825_001) downloads the photo,
-- strips JPEG EXIF, and re-uploads. This migration extends the same
-- job so it ALSO generates a 512-wide gallery thumbnail, uploads it
-- alongside the original at `{owner_id}/{photo_id}_512.jpg`, and
-- PATCHes the run_photos row with the thumbnail's storage path.
-- Clients then prefer the smaller file in gallery views (faster
-- first-paint on the run-detail screen, less mobile data) and fall
-- back to the original when the column is still null (worker hasn't
-- caught up with a fresh upload).
--
-- One size for v1 — 512w covers the gallery and is enough of a saving
-- (typical 4032×3024 photo iPhone JPEG is ~2-3 MB; the 512w version
-- lands around 60-80 KB). A 1024w "lightbox preview" tier is a
-- natural v2; the original is fine for the lightbox today since
-- it's loaded on demand from a tap.
--
-- Storage RLS: thumbnails live in the same bucket but at a path that
-- isn't `run_photos.storage_path`. The 20260705_001 visibility gate
-- only matched the original path; this migration widens that policy
-- to also accept `thumb_512_path` so a non-owner viewing a public
-- run can fetch the thumbnail bytes. Same join-through-runs check.

-- ─────────────────── add column ───────────────────

alter table public.run_photos
  add column thumb_512_path text;

create index run_photos_thumb_512_path
  on public.run_photos (thumb_512_path)
  where thumb_512_path is not null;

-- ─────────────────── extend storage RLS ───────────────────

drop policy if exists "run-photo bytes visible when parent run is visible"
  on storage.objects;

create policy "run-photo bytes visible when parent run is visible"
  on storage.objects for select
  to anon, authenticated
  using (
    bucket_id = 'run-photos'
    and exists (
      select 1
      from run_photos rp
      where (
              rp.storage_path = storage.objects.name
              or rp.thumb_512_path = storage.objects.name
            )
        and is_run_visible_to(rp.run_id, auth.uid())
    )
  );

-- ─────────────────── service-role write grant ───────────────────
-- The worker PATCHes thumb_512_path via the service role, which
-- bypasses RLS by design. No new policy needed — the existing
-- service_role privileges cover the column the same way they cover
-- the rest of the row.
