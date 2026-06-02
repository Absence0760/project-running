-- Publish the notifications table to Supabase Realtime so the web app's
-- bell badge updates live when a kudos / comment / follow row arrives,
-- instead of only on window focus (persona round-5 very-social).
--
-- RLS already restricts SELECT to `auth.uid() = user_id`
-- (20260528000001_notifications.sql), and Realtime honours RLS on
-- postgres_changes, so a subscriber only ever receives their own rows.
--
-- REPLICA IDENTITY FULL is required so DELETE payloads carry user_id
-- (not just the primary key); without it the client-side
-- `user_id=eq.<me>` filter can't match a delete event. The table is
-- low-volume (one row per social interaction) so the extra WAL cost is
-- negligible.

alter table notifications replica identity full;
alter publication supabase_realtime add table notifications;
