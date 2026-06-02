-- Run photos are NOT shared with a coach via the coaching link
-- (reviews/audit-storage.md — coach receives run-photo bytes without an
-- explicit photo-sharing consent surface).
--
-- 20261103_001 spent the coach-link redemption as consent to share TRAINING
-- DATA (run rows, stats, the is_run_visible_to-gated social tables) and
-- deliberately kept the raw GPS track coach-excluded ("a separate privacy
-- decision … rather than silently bypassing the privacy-zone clip"). Run
-- photos rode the same is_run_visible_to gate, so the coach silently received
-- photo BYTES too — faces, home interiors, kids, EXIF-stripped-but-still-
-- recognisable locations — with no separate opt-in. Photos are at least as
-- sensitive as the track that was withheld.
--
-- Decision (owner-confirmed 2026-06-02): scope photo visibility to
-- owner-or-public, matching the track precedent. A coach reviewing training
-- still sees the run, stats, splits, HR, route line, comments and kudos — but
-- not the athlete's uploaded photos. If coach photo access is ever wanted it
-- should be an explicit photo_sharing_consent opt-in, not a side effect of the
-- link (left as a tracked followup, NOT built here).
--
-- Mechanism: a photo-specific visibility helper that omits the coach branch,
-- swapped into both the run_photos TABLE SELECT policy and the run-photos
-- Storage SELECT policy. The event-gallery path (event-tagged photos follow
-- the event's visibility) and the thumbnail path are preserved unchanged — a
-- coach who is also an event member still sees event-tagged photos through
-- that separate, consented surface.

create or replace function private.is_run_photo_visible_to(p_run_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- Owner-or-public only. Intentionally NO is_active_coach_of branch: the
  -- coaching link is not consent to share photos (see 20261125_001 header).
  select exists (
    select 1 from runs r
    where r.id = p_run_id
      and (r.user_id = p_user_id or r.is_public = true)
  );
$$;

revoke execute on function private.is_run_photo_visible_to(uuid, uuid) from public;
grant execute on function private.is_run_photo_visible_to(uuid, uuid)
  to anon, authenticated, service_role;

-- run_photos TABLE: the run-based read path drops to owner-or-public. The
-- sibling "event photos readable when event is readable" policy (20261025_001)
-- is left untouched — event galleries keep their own visibility.
drop policy "photos readable when run is readable" on run_photos;
create policy "photos readable when run is readable"
  on run_photos for select
  using (private.is_run_photo_visible_to(run_id, auth.uid()));

-- run-photos Storage BYTES: full prior body from 20261109_001 (storage_path +
-- thumb_512_path, event path preserved per the bare-body-policy gotcha), with
-- the run-visibility gate swapped to the photo-specific (coach-excluded) fn.
drop policy if exists "run-photo bytes visible when run or event is visible" on storage.objects;
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
          private.is_run_photo_visible_to(rp.run_id, auth.uid())
          or (
            rp.event_id is not null
            and exists (select 1 from public.events e where e.id = rp.event_id)
          )
        )
    )
  );
