-- Drop the legacy "users can RSVP" policy on event_attendees that
-- was meant to be retired in 20260428_001 but slipped through.
--
-- Postgres quoted identifiers are case-sensitive. 20260428_001:93-94
-- runs `drop policy if exists "users can rsvp" on event_attendees`
-- (lowercase) and `"attendees can rsvp"` (lowercase) — both no-ops
-- against the actual policies created with the original casing in
-- 20260416_001:205 ("users can RSVP", uppercase) and 20260420_001
-- ("Attendees can RSVP", title case).
--
-- Net effect today is benign: the surviving "users can RSVP" + the
-- new "organisers can add attendees" union to exactly the allow set
-- the new policy was supposed to provide on its own (auth.uid() =
-- user_id OR is_event_organiser(...)). Cosmetic finding — pg_policies
-- shows a duplicate INSERT policy and the dead drops mislead readers
-- about what's actually live.
--
-- Drop the legacy policy with the correct casing this time. The
-- surviving "organisers can add attendees" already covers self-RSVP
-- via its `auth.uid() = user_id` branch.

drop policy if exists "users can RSVP" on event_attendees;
drop policy if exists "Attendees can RSVP" on event_attendees;
