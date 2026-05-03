-- Gate event_attendees self-RSVP on event visibility.
--
-- Pre-prod RLS audit Low. The "organisers can add attendees"
-- policy from 20260428_001:79-88 has two branches:
--
--   1. auth.uid() = user_id      -- self-RSVP
--   2. is_event_organiser(...)   -- organiser registers a walk-up
--
-- Branch 1 only enforces that the writer is the row's user_id.
-- It does NOT gate on the linked event being visible to the
-- writer. So an authenticated user can plant RSVP rows against
-- any event_id (including UUIDs of private-club events they
-- enumerate). The SELECT policy hides their RSVP from anyone
-- but themselves when the event isn't visible, but the row is
-- still in the table — counts off, and the writer survives in
-- the attendee list visible to organisers.
--
-- Same shape as route_reviews INSERT (closed in 20260627_001).
-- The fix splits the policy into:
--
--   * Self-RSVP — gated on `exists (select 1 from events where
--     ...)` so RLS on events picks up automatically (writer
--     can only RSVP to events they could SELECT).
--   * Organiser-add — kept as-is (organising the parent club
--     already implies visibility, so no extra gate needed).
--
-- Branch 2 stays separate to keep the policy intent legible:
-- the organiser path is a privileged escalation, the self
-- path is a self-service action.

drop policy "organisers can add attendees" on event_attendees;

create policy "users RSVP to visible events"
  on event_attendees for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from events where events.id = event_attendees.event_id
    )
  );

create policy "organisers add attendees to their events"
  on event_attendees for insert
  to authenticated
  with check (
    exists (
      select 1 from events e
      where e.id = event_attendees.event_id
        and is_event_organiser(e.club_id)
    )
  );
