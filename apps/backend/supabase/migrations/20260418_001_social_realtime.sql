-- Phase 4 of the social layer: enable Supabase Realtime on the three social
-- tables the client apps care about.
--
--   * club_posts       — so the feed live-updates when an admin posts
--   * event_attendees  — so the "Going" count on an event page ticks up
--                        as other members RSVP
--   * club_members     — so a pending request flips to active in the
--                        admin's browser without a manual refresh
--
-- `supabase_realtime` is the default publication the Realtime listener
-- subscribes to. Adding a table here is how you opt in — Supabase does not
-- publish every table by default (it would be a broadcast-everywhere
-- footgun). Clients must still pass through RLS, so membership/visibility
-- rules apply to realtime payloads exactly like they do to REST reads.

alter publication supabase_realtime add table club_posts;
alter publication supabase_realtime add table event_attendees;
alter publication supabase_realtime add table club_members;
