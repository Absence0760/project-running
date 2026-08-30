-- Give the order ledger a way to say that a refund did not happen after all.
--
-- `charge.refunded` fires when a refund is CREATED, including one created
-- `pending` against a delayed-notification payment method, and Stripe
-- increments `charge.amount_refunded` optimistically with it. The webhook has
-- always taken that as final: CAS `paid -> refunded`, stamp `refunded_at`,
-- delete the buyer's `going` row — which fires `promote_event_waitlist` and
-- hands the mat to the next person in line. When the bank then REJECTS the
-- refund, the money comes back to our balance and Stripe walks
-- `charge.amount_refunded` down again, and the buyer is left with no seat, no
-- money back, and a ledger row saying they were refunded.
--
-- `refunded` cannot express that, and neither can `paid`: every seat predicate
-- (`enforce_paid_order_for_priced_event`, 20270522_001) reads `paid` as
-- BACKING a registration, so reverting would describe a seat that no longer
-- exists and let the buyer be marked attended for a class they cannot enter.
-- `refund_failed` is the state that is true of both halves — the money is
-- ours, the seat is gone — and it is the reconciliation query an operator
-- runs:
--
--     select id, event_id, buyer_user_id, amount_cents, refund_initiated_at
--       from event_orders where status = 'refund_failed';
--
-- It is not terminal. A re-issued refund's `charge.refunded` moves it on to
-- `refunded` (decisions § 789); a partial retry does not, because the seat is
-- already gone and `partially_refunded` reads as a held one.
--
-- No new predicate anywhere reads it, deliberately. The two places that
-- enumerate order statuses both mean "does this order back a seat / can this
-- buyer still cancel", and the answer for `refund_failed` is no in both:
-- `enforce_paid_order_for_priced_event` accepts `('paid',
-- 'partially_refunded')` and the buyer UPDATE policy admits the same two, so
-- both already exclude it by construction rather than by an edit here.
--
-- Online-safety (docs/backend/migration_locks.md): `event_orders` is not in
-- the guarded high-volume set, but this takes the online form anyway, exactly
-- as 20270620_001 did for the donation twin. Widening an IN-list can only
-- admit rows, so every existing row already satisfies the wider set and the
-- validation scan finds nothing — but a single-step DROP + ADD takes it under
-- ACCESS EXCLUSIVE regardless, so it is split.

alter table event_orders drop constraint event_orders_status_check;

alter table event_orders
  add constraint event_orders_status_check
  check (status in (
    'pending', 'paid', 'refunded', 'refund_failed', 'partially_refunded',
    'failed', 'canceled'
  ))
  not valid;

alter table event_orders validate constraint event_orders_status_check;

comment on column event_orders.status is
  'Order lifecycle, written ONLY by the stripe-events webhook (service role). '
  '`refund_failed` means a refund was announced by charge.refunded, the seat '
  'was released, and the refund was then rejected — the money is with us and '
  'the buyer has no seat. It is an operator reconciliation queue, not an end '
  'state: a re-issued full refund moves it to `refunded`.';
