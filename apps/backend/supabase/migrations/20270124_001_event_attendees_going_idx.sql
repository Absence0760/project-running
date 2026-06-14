-- Partial index for the hot "how many are going to this instance" count.
--
-- The confirm-time capacity recheck in stripe-events-webhook (and the
-- create-time precheck in events-checkout, the capacity trigger from
-- 20261018_001, and the next-instance going counts from 20270122_001) all
-- count event_attendees by (event_id, instance_start) filtered to
-- status='going'. The existing event_attendees_event_instance index covers
-- the first two predicates but not status, so Postgres index-range-scanned
-- the (event_id, instance_start) slice and then re-checked status='going' on
-- every row in it — for a popular recurring instance with maybe + declined +
-- waitlisted rows mixed in, that filtered set can be a large fraction of the
-- attendee table, and the count runs on every paid checkout confirmation.
--
-- A partial index keyed on (event_id, instance_start) WHERE status='going'
-- holds only the rows the count cares about, so the going count is served
-- straight from the index with no heap re-check.
create index event_attendees_going_instance_idx
  on event_attendees (event_id, instance_start)
  where status = 'going';
