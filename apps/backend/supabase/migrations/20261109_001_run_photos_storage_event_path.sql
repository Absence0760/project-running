-- audit-findings 2026-05-30 Medium [security/storage]: the event photo
-- gallery (20261025_001) opened a run_photos *table* read path for
-- event-tagged photos even when the parent run is private — "everyone
-- who can see the event sees the gallery". But the run-photos Storage
-- SELECT policy still gated the BYTES solely on
-- private.is_run_visible_to(rp.run_id, auth.uid()). So an event viewer
-- who can see the event but not the underlying private run gets the
-- photo row yet a 403 when signing/reading the object → a permanently
-- broken image in the gallery.
--
-- Extend the Storage policy with the same event-visibility path the
-- table policy uses: an event-tagged photo's bytes are readable when the
-- event row is readable. The `events` subquery is itself subject to
-- events RLS, so it delegates visibility exactly like the table policy
-- (no new trust granted — only the byte path catches up to the row path).
--
-- The full prior body is preserved (per the bare-body-policy gotcha):
-- both `storage_path` and `thumb_512_path` are matched (the thumbnail
-- path was added by 20260826_001), and the function is the private-schema
-- `private.is_run_visible_to` (moved by 20260812_001).
drop policy if exists "run-photo bytes visible when parent run is visible" on storage.objects;

create policy "run-photo bytes visible when run or event is visible"
  on storage.objects for select
  to anon, authenticated
  using (
    bucket_id = 'run-photos'
    and exists (
      select 1
      from run_photos rp
      where (rp.storage_path = storage.objects.name or rp.thumb_512_path = storage.objects.name)
        and (
          private.is_run_visible_to(rp.run_id, auth.uid())
          or (
            rp.event_id is not null
            and exists (select 1 from public.events e where e.id = rp.event_id)
          )
        )
    )
  );
