-- A refund that FAILS leaves the ledger claiming money went back that did not.
--
-- Both ledgers move on `charge.refunded`, which Stripe emits the moment a
-- refund is CREATED — including a refund whose status is still `pending`. On a
-- delayed-notification rail the bank can reject it days later, at which point
-- the money returns to our Stripe balance and the refund's status becomes
-- `failed` (or `canceled`, which Stripe documents as "a type of refund
-- failure"). Nothing consumed that outcome, so:
--
--   * event_orders sat at `refunded` with the buyer's `going` row already
--     deleted and promote_event_waitlist having handed the mat to the next
--     person. We hold the money, the buyer holds neither money nor a seat.
--   * donations sat at `refunded`, excluded from fundraiser_totals, with
--     `refunded_cents` stating an amount that never left.
--
-- `refund_failed` is the state that says exactly that: the payment was
-- reversed as far as the registration is concerned, and the money did not
-- reach the payer. It is NOT `paid` — a `paid` order is one that backs a live
-- seat (enforce_paid_order_for_priced_event) and whose buyer can still
-- self-cancel, and this order has no seat and a buyer who already cancelled.
-- It is NOT `refunded` either, because that is a claim about money.
--
-- It is deliberately reachable only from `refunded`, the one state that claims
-- the WHOLE payment came back. `partially_refunded` is a seat-BEARING state on
-- both the capacity trigger and the buyer-cancel RLS policy (20270522_001), so
-- moving a partly-refunded order out of it on a failure would strip a buyer
-- who is still attending of both their roster entry and their ability to
-- cancel — a bigger lie than the one being fixed. A failed partial refund is
-- logged for reconciliation instead. decisions § 789.
--
-- Operator worklist: `select * from event_orders where status = 'refund_failed'`
-- (and the same on donations). Stripe's own guidance for a failed refund is to
-- "arrange an alternative way to provide your customer with a refund", which is
-- a human action on a payout rail this tier does not automate — so the terminal
-- state exists to be QUERIED, not to be resolved by another webhook.
--
-- Online-safety (docs/backend/migration_locks.md): neither table is in the
-- guarded high-volume set, but both statements take the online form anyway.
-- Widening an IN-list can reject no existing row, so the re-validation scan is
-- pure waste — NOT VALID + VALIDATE, per the playbook.

-- ───────────────────────── event_orders ──────────────────────────────────────
alter table event_orders drop constraint event_orders_status_check;

alter table event_orders
  add constraint event_orders_status_check
  check (status in ('pending', 'paid', 'refunded', 'partially_refunded', 'refund_failed', 'failed', 'canceled'))
  not valid;

alter table event_orders validate constraint event_orders_status_check;

comment on column event_orders.status is
  'Order ledger lifecycle, written only by the stripe-events webhook (service '
  'role). `paid` and `partially_refunded` back a live seat; `refunded` means '
  'the whole payment went back and the seat was released; `refund_failed` '
  'means that refund was reversed by the bank, so the seat is gone but the '
  'money is still ours and the buyer is owed a payout by another route.';

-- ───────────────────────── donations ─────────────────────────────────────────
alter table donations drop constraint donations_status_check;

alter table donations
  add constraint donations_status_check
  check (status in ('pending', 'paid', 'partially_refunded', 'refunded', 'refund_failed', 'failed', 'canceled'))
  not valid;

alter table donations validate constraint donations_status_check;

-- fundraiser_totals and fundraiser_feed filter on ('paid', 'partially_refunded'),
-- so `refund_failed` is excluded from the thermometer without touching either
-- function — which is the right answer: the money is owed back out, not raised.
comment on column donations.status is
  'Donation ledger lifecycle, written only by the stripe-events webhook '
  '(service role). `refund_failed` is a `refunded` donation whose refund the '
  'bank reversed: excluded from fundraiser_totals like `refunded`, because the '
  'money is owed back to the donor rather than raised for the charity.';

comment on column donations.refunded_cents is
  'Cumulative cents refunded on this donation''s charge, as last reported by '
  'Stripe (charge.amount_refunded). Written only by the stripe-events webhook. '
  '0 on a row that predates 20270620_001 — for a `refunded` row that means the '
  'amount was never recorded, not that nothing came back. On a `refund_failed` '
  'row it is the amount that came BACK to us and is owed to the donor.';
