-- Event photo gallery (social-group persona #49).
--
-- run_photos could only be read when the parent run was readable, so an
-- event's shared photos were scattered across each attendee's (often
-- private) run and there was no gallery. This tags a photo to an event
-- instance and opens a read path scoped to event visibility, so everyone
-- who can see the event sees the gallery — even when the underlying run
-- is private.
--
--   1. run_photos.event_id + event_instance_start (nullable) — a photo
--      can be tagged to a specific occurrence of an event.
--   2. A SELECT policy: an event-tagged photo is readable by anyone who
--      can read the event (the `exists (… from events …)` subquery is
--      itself subject to the events RLS, so this delegates visibility).
--   3. The INSERT policy is widened so that, when event_id is set, the
--      uploader must be able to see that event (can't tag a photo to a
--      private event you can't reach). Owner-of-run is still required.

alter table run_photos
  add column event_id uuid references events(id) on delete set null,
  add column event_instance_start timestamptz;

create index run_photos_by_event
  on run_photos (event_id, event_instance_start)
  where event_id is not null;

-- Gallery read path: event-tagged photos follow the event's visibility.
create policy "event photos readable when event is readable"
  on run_photos for select
  using (
    event_id is not null
    and exists (select 1 from public.events e where e.id = run_photos.event_id)
  );

-- Replace the INSERT policy (latest body is the original 20260525_001)
-- to add the event-visibility check when a photo is tagged to an event.
drop policy if exists "run owner attaches photos" on run_photos;
create policy "run owner attaches photos"
  on run_photos for insert
  with check (
    auth.uid() = owner_id
    and exists (
      select 1 from runs
      where runs.id = run_photos.run_id and runs.user_id = auth.uid()
    )
    and (
      event_id is null
      or exists (select 1 from public.events e where e.id = run_photos.event_id)
    )
  );
