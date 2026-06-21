-- Buyer self-cancel + automated refund coupling (slice P2 of
-- docs/features/club_events.md).
--
-- P1 left refunds MANUAL via the Stripe dashboard. P2 adds the buyer
-- self-cancel path: a buyer cancels their own paid/pending registration on
-- the event-detail page, the events-cancel Edge Function initiates a Stripe
-- refund (paid order) or releases the soft reservation (pending order), and
-- the stripe-events-webhook charge.refunded handler — still the SOLE,
-- idempotent, service-role-only writer of event_orders.status — CAS's the
-- order paid->refunded and releases the buyer's seat.
--
-- This migration adds the bookkeeping the async gap needs (the refund is
-- INITIATED by the EF but only CONFIRMED later by the webhook):
--   * event_orders.refund_initiated_at — stamped when events-cancel calls
--     Stripe's refund API, so the UI can show "refund in progress" before the
--     charge.refunded webhook lands. NOT a status write (status stays 'paid'
--     until the webhook confirms — the sole-writer invariant is preserved).
--   * a refund-initiation write is the ONE event_orders mutation a buyer may
--     make: lock_event_order_status already blocks every non-service-role
--     status write; we extend it to also block a non-service-role write of any
--     other column EXCEPT refund_initiated_at on the caller's OWN paid order,
--     and add a buyer UPDATE policy scoped to that single column transition.
--
-- No new status VALUE — 'refunded' / 'canceled' already exist
-- (20261229_001). The CHECK ↔ TS union pair is unchanged.

-- ───────────────── 1. refund_initiated_at bookkeeping column ─────────────────
alter table event_orders add column refund_initiated_at timestamptz;

-- ───────────────── 2. buyer may initiate a refund on their OWN paid order ────
-- The buyer-facing cancel writes refund_initiated_at (and nothing else) on a
-- paid order they own. event_orders has no client write policy today (writes
-- are service-role only). Add a tightly-scoped buyer UPDATE policy: the buyer
-- owns the row and it is currently paid. The column-level guard (the trigger
-- below) ensures the buyer can ONLY touch refund_initiated_at — never status,
-- amount, fee, etc. Combined, a buyer can stamp "refund requested" but cannot
-- forge a paid/refunded status or alter the ledger amounts.
create policy "buyer initiates refund on own paid order"
  on event_orders for update
  using (buyer_user_id = auth.uid() and status = 'paid')
  with check (buyer_user_id = auth.uid() and status = 'paid');

-- ───────────────── 3. extend the status lock to a column lock ────────────────
-- 20261229_001's lock_event_order_status blocked any non-service-role INSERT
-- and any non-service-role status CHANGE. P2 lets a buyer write exactly one
-- column (refund_initiated_at) on their own paid order; every other column
-- (and status itself) stays service-role-only. Re-emit the COMPLETE body
-- (create-or-replace replaces the whole function — see apps/backend/CLAUDE.md
-- "Bare-body create or replace strips prior fixes") with the P1 behaviour plus
-- the new column allowance.
create or replace function lock_event_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  -- Trusted callers, identical to P1: the REST service role (the webhook), or
  -- genuine direct SQL (migrations + seed) which reach here with an empty role
  -- claim AND a privileged session_user. PostgREST authenticates every request
  -- as the `authenticator` login role, so an end-user request can never present
  -- session_user = postgres.
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    raise exception 'event_orders is service-role-only (webhook is the sole writer)'
      using errcode = '42501';
  end if;

  -- A non-service-role UPDATE may touch ONLY refund_initiated_at (the buyer
  -- self-cancel "refund requested" stamp), and only on a paid order. Any other
  -- column change — status above all — is rejected. This keeps the webhook the
  -- sole writer of status while letting the buyer record their cancel intent.
  if old.status is distinct from new.status then
    raise exception 'event_orders.status is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  if old.event_id is distinct from new.event_id
     or old.instance_start is distinct from new.instance_start
     or old.buyer_user_id is distinct from new.buyer_user_id
     or old.host_user_id is distinct from new.host_user_id
     or old.stripe_checkout_session_id is distinct from new.stripe_checkout_session_id
     or old.stripe_payment_intent_id is distinct from new.stripe_payment_intent_id
     or old.amount_cents is distinct from new.amount_cents
     or old.currency is distinct from new.currency
     or old.platform_fee_cents is distinct from new.platform_fee_cents
     or old.created_at is distinct from new.created_at
     or old.paid_at is distinct from new.paid_at
     or old.refunded_at is distinct from new.refunded_at
     or old.reserved_until is distinct from new.reserved_until then
    raise exception 'event_orders is service-role-only except the buyer refund stamp'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
