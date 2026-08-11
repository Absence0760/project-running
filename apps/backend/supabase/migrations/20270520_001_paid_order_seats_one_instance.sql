-- One paid order could seat a buyer at EVERY instance of a recurring priced
-- event, and an attendee could forge their own attendance on the way in.
--
-- Two independent gaps that compose into one exploit.
--
-- (1) `enforce_paid_order_for_priced_event()` (20261229_001) validates the
-- cited order on `id`, `buyer_user_id`, `event_id` and `status = 'paid'` — but
-- never on `instance_start`, even though `event_orders.instance_start` is NOT
-- NULL and `events-checkout` creates exactly one order per instance. So an
-- order bought for one Wednesday satisfies the gate for every other Wednesday.
--
-- (2) `20270102_001` deliberately locked `attendance` and `order_id` out of
-- client writes — "order_id stays service-role-only (paid path)" — but it only
-- rewrote the **UPDATE** grant. The table-level INSERT grant was never split,
-- and a table grant implies every column, so both stayed client-writable on
-- INSERT. Verified before this migration:
--
--     INSERT | attendance, event_id, instance_start, joined_at, order_id, status, user_id
--     UPDATE | event_id, instance_start, status, user_id
--
-- Reproduced end-to-end on the local stack, as the buyer's own JWT, against a
-- weekly priced event with ONE paid order for the 07-01 instance:
--
--      instance_start     | order_tail | attendance
--     --------------------+------------+-----------
--      2026-07-01 18:00   | 0001       | -
--      2026-07-08 18:00   | 0001       | attended     <-- never paid for
--
-- i.e. a $22 drop-in buys the whole 52-week term, and the attendee writes
-- themselves onto the instructor's roster as having attended. The attendance
-- half is exactly the invariant `event_attendance_test.sql` pins against a
-- direct UPDATE, reachable through INSERT instead — and re-forgeable after an
-- organiser correction by DELETE + re-INSERT, since both are own-row verbs.
--
-- The seat half is worse than one free class: a refund releases only the
-- order's own `instance_start` seat, so the stolen seats outlive the refund,
-- and they consume real capacity the host could have sold.
--
-- Fixes, in the order they close the exploit:
--
--   * Bind the order to the instance it was bought for.
--   * Split the INSERT grant the way 20270102_001 split UPDATE. The legitimate
--     paid path is unaffected: the seat is written by the SERVICE ROLE in
--     stripe-events-webhook (which holds the table grant), never by the client
--     — the client's own INSERT is the free-RSVP path, which leaves order_id
--     null. `joined_at` keeps its grant (it has a default but the client may
--     set it); `attendance` and `order_id` do not.
--   * A unique index so one order can back at most one seat. With the instance
--     check plus the (event_id, user_id, instance_start) primary key this is
--     already implied, but it states the "one order, one seat" invariant at the
--     schema level so a future path that forgets the instance check cannot
--     silently re-open the hole.

create or replace function enforce_paid_order_for_priced_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_priced boolean;
begin
  if new.status not in ('going', 'waitlisted') then
    return new;
  end if;

  select exists (
    select 1 from event_pricing p
    where p.event_id = new.event_id
      and (p.instance_start = new.instance_start or p.instance_start is null)
  ) into v_priced;

  if not v_priced then
    return new;  -- free event: order_id stays null, no gate
  end if;

  if new.order_id is null then
    raise exception 'a paid order is required to register for priced event % (instance %)', new.event_id, new.instance_start
      using errcode = 'check_violation';
  end if;

  -- `o.instance_start = new.instance_start` is the load-bearing addition: an
  -- order is bought for ONE occurrence and may only seat that occurrence.
  if not exists (
    select 1 from event_orders o
    where o.id = new.order_id
      and o.buyer_user_id = new.user_id
      and o.event_id = new.event_id
      and o.instance_start = new.instance_start
      and o.status = 'paid'
  ) then
    raise exception 'order % is not a paid order belonging to this buyer for this event instance', new.order_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

-- Mirror of 20270102_001's UPDATE lockdown, for INSERT. A single-column
-- `revoke insert (order_id)` would be a no-op while a TABLE-level INSERT grant
-- exists, so drop the table grant and re-grant per-column.
revoke insert on event_attendees from authenticated, anon;
grant insert (event_id, user_id, status, instance_start, joined_at)
  on event_attendees to authenticated;

-- One order backs at most one seat. Partial so the free-RSVP path (order_id
-- null) is untouched — many rows there.
create unique index if not exists event_attendees_one_seat_per_order
  on event_attendees (order_id)
  where order_id is not null;
