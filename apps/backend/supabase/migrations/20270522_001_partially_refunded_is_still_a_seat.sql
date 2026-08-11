-- `partially_refunded` was introduced as a WRITTEN order state by the
-- stripe-events-webhook change in #758, and nothing downstream recognises it.
--
-- Before that change the status was unreachable — the CHECK constraint carried
-- it but no code ever wrote it — so every "does this buyer hold a valid seat?"
-- predicate said `status = 'paid'` and was correct. The moment a partial refund
-- can land, those predicates start rejecting a registration that is still
-- overwhelmingly paid and whose seat was deliberately KEPT.
--
-- Verified on the local stack: a $50 workshop, a $5 goodwill refund, and then
--
--     update event_attendees set attendance = 'attended' where order_id = …
--     ERROR: order … is not a paid order belonging to this buyer for this
--            event instance
--     CONTEXT: PL/pgSQL function enforce_paid_order_for_priced_event()
--
-- i.e. the instructor can no longer mark that attendee present, for the rest
-- of the term. The trigger is `before insert or update` with no WHEN clause, so
-- it re-validates on any UPDATE of the row — including `mark_attendance`'s
-- attendance-only write, and including `promote_event_waitlist`'s promotion of
-- a DIFFERENT attendee to 'going'. The latter is worse than a failed roster
-- write: promotion runs in an AFTER-DELETE trigger, so the raise rolls back the
-- seat release that provoked it.
--
-- The fix is to say what was always meant: a seat is backed by an order that
-- has been paid and not fully returned.

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

  -- `instance_start` binds the order to the ONE occurrence it was bought for
  -- (20270520_001). `partially_refunded` counts as backing the seat: the buyer
  -- got some money back and kept the registration, which is exactly what the
  -- webhook's partial-refund branch decides. A FULL refund moves the order to
  -- `refunded` and deletes the seat outright, so it never reaches here.
  if not exists (
    select 1 from event_orders o
    where o.id = new.order_id
      and o.buyer_user_id = new.user_id
      and o.event_id = new.event_id
      and o.instance_start = new.instance_start
      and o.status in ('paid', 'partially_refunded')
  ) then
    raise exception 'order % is not a paid order belonging to this buyer for this event instance', new.order_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

-- The buyer may still self-cancel a partially-refunded registration. Without
-- this the RLS policy hides their own order from the UPDATE that stamps
-- refund_initiated_at, so events-cancel 404s and the seat can never be given
-- up — a registration that can be neither attended nor cancelled.
drop policy if exists "buyer initiates refund on own paid order" on event_orders;
create policy "buyer initiates refund on own paid order"
  on event_orders for update
  to authenticated
  using (buyer_user_id = (select auth.uid()) and status in ('paid', 'partially_refunded'))
  with check (buyer_user_id = (select auth.uid()) and status in ('paid', 'partially_refunded'));
