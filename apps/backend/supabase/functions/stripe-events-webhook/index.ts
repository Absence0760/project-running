/// Stripe Connect events webhook — the ONE idempotent writer of order
/// status (club_events.md slice P1).
///
/// Handles six event types; everything else is 200-ignored:
///   checkout.session.completed -> only once `payment_status` says the money
///     arrived: CAS pending->paid, confirm-time capacity recheck, seat the
///     'going' attendee with order_id. If the class filled via another path,
///     the order is left paid + logged + flagged for MANUAL refund (P1 has no
///     automated refund).
///   checkout.session.async_payment_succeeded -> the same path, for the
///     delayed-notification methods whose money arrives days after the
///     Session completes.
///   checkout.session.async_payment_failed    -> CAS pending->failed; the
///     money never came, and no seat was ever issued for it.
///   checkout.session.expired   -> CAS pending->canceled, releasing the
///     soft reservation (the pending row stops counting toward capacity).
///   charge.refunded            -> CAS the donation or the order, releasing
///     the seat only on a full refund.
///   account.updated            -> mirror charges_enabled / payouts_enabled
///     / details_submitted into instructor_payout_accounts.
///
/// Auth: config.toml verify_jwt = false (Stripe presents no Supabase
/// JWT). The request is authenticated by HMAC over the RAW body
/// (Stripe-Signature header, STRIPE_EVENTS_WEBHOOK_SECRET) — verified on
/// the wire bytes, never a re-stringified parse.
///
/// Idempotency, defence in depth:
///   1. insert-first into webhook_events (provider='stripe', event.id);
///      a duplicate raises 23505 -> 200 ok-skipped (Stripe retries
///      non-2xx).
///   2. orderStatusTransition is a CAS guard (only pending->X), so even
///      if dedupe were bypassed a replayed completed can't re-grant a
///      slot or double-count revenue.
///
/// TEST MODE ONLY in P1. Fails closed (503) if the secret is unset.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database, DbClient } from '../_shared/database.ts';
import { readTextWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { capacityDecision } from '../events-checkout/lib.ts';
import {
  attendeeRowFromSession,
  type Charge,
  type CheckoutSession,
  type ConnectAccount,
  donationIdFromSession,
  donationStatusTransition,
  isDonationSession,
  isPaymentSettled,
  orderStatusTransition,
  parseStripeEventEnvelope,
  readCharge,
  readCheckoutSession,
  readConnectAccount,
  refundedCentsOfCharge,
  refundScopeOfCharge,
  shouldReleaseDedupe,
  STRIPE_EVENT,
  type StripeEventEnvelope,
  verifyStripeSignature,
} from './lib.ts';
import { secretKey } from '../_shared/api_keys.ts';

const WEBHOOK_PROVIDER = 'stripe';

Deno.serve(withSentry('stripe-events-webhook', async (req: Request) => {
  if (req.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  // HMAC must run on the raw wire bytes — JSON.parse won't round-trip.
  const guarded = await readTextWithLimit(req, 64 * 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;
  const rawBody = guarded.text;

  const secret = Deno.env.get('STRIPE_EVENTS_WEBHOOK_SECRET');
  if (!secret) {
    return Response.json({ error: 'webhook_not_configured' }, { status: 503 });
  }

  const sigHeader = req.headers.get('stripe-signature');
  const valid = await verifyStripeSignature(rawBody, sigHeader, secret, Date.now());
  if (!valid) {
    return Response.json({ error: 'bad_signature' }, { status: 401 });
  }

  const event = parseStripeEventEnvelope(rawBody);
  if (!event) {
    return Response.json({ error: 'invalid_event' }, { status: 400 });
  }

  const service = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    secretKey(),
  );

  // Insert-first dedupe. A replayed delivery raises 23505 -> 200 skip.
  const { error: dedupeErr } = await service
    .from('webhook_events')
    .insert({ provider: WEBHOOK_PROVIDER, event_id: event.id });
  if (dedupeErr) {
    if (dedupeErr.code === '23505') {
      return Response.json({ ok: true, skipped: 'duplicate_event' });
    }
    console.error('webhook dedupe insert failed (code):', dedupeErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'dedupe_failed' }, { status: 500 });
  }

  // Dispatch behind a dedupe release. The dedupe row is inserted BEFORE the
  // side effect (so two concurrent deliveries can't both act), which means a
  // handler that fails must give the row back — otherwise Stripe's retry hits
  // the 23505 path above, answers 200 'duplicate_event', and closes the
  // delivery for good. For checkout.session.completed that leaves a charged
  // card with the order stuck `pending`, no seat, and no corrective event
  // coming: nothing sweeps a lapsed reservation. strava-webhook already does
  // this rollback for the same reason.
  let res: Response;
  try {
    res = await dispatchStripeEvent(service, event);
  } catch (err) {
    await releaseDedupe(service, event.id);
    throw err;
  }
  if (shouldReleaseDedupe(res.status)) {
    await releaseDedupe(service, event.id);
  }
  return res;
}));

/// Give back the insert-first dedupe row so Stripe's retry is processed
/// instead of being swallowed as a duplicate. Best-effort: if this fails the
/// event is stuck either way, and logging is all we can usefully do.
async function releaseDedupe(service: DbClient, eventId: string): Promise<void> {
  const { error } = await service
    .from('webhook_events')
    .delete()
    .eq('provider', WEBHOOK_PROVIDER)
    .eq('event_id', eventId);
  if (error) {
    console.error('failed to release dedupe row before retry (code):', error?.code ?? 'unknown');
  }
}

async function dispatchStripeEvent(
  service: DbClient,
  event: StripeEventEnvelope,
): Promise<Response> {
  const obj = event.data.object;

  if (
    event.type === STRIPE_EVENT.checkoutCompleted ||
    event.type === STRIPE_EVENT.checkoutAsyncPaid
  ) {
    // One webhook, one secret. A donation session (metadata.kind='donation')
    // confirms a donations row; a seat session confirms an event_orders row.
    // The two event types share a handler because they mean the same thing —
    // this Session's money has arrived — and `isPaymentSettled` is what
    // decides whether it has, not which of them delivered the news.
    const session = readCheckoutSession(obj);
    return isDonationSession(session)
      ? await handleDonationCompleted(service, session, event.type)
      : await handleCompleted(service, session, event.type);
  }
  if (
    event.type === STRIPE_EVENT.checkoutExpired ||
    event.type === STRIPE_EVENT.checkoutAsyncFailed
  ) {
    const session = readCheckoutSession(obj);
    return isDonationSession(session)
      ? await handleDonationNotPaid(service, session, event.type)
      : await handleNotPaid(service, session, event.type);
  }
  if (event.type === STRIPE_EVENT.accountUpdated) {
    return await handleAccountUpdated(service, readConnectAccount(obj));
  }
  if (event.type === STRIPE_EVENT.chargeRefunded) {
    // One charge.refunded handler for both ledgers, resolved by payment
    // intent. A donation refund CAS's the donations row (fundraising.md); a
    // paid-event refund (P2 buyer self-cancel) CAS's the event_orders row and
    // releases the seat. Try the donation ledger first; null = "this charge is
    // not a donation" -> fall through to the event-order refund path.
    const charge = readCharge(obj);
    const donationRes = await handleDonationRefunded(service, charge);
    return donationRes ?? await handleOrderRefunded(service, charge);
  }

  // Unhandled types — recorded (dedupe) but no side effect.
  return Response.json({ ok: true, ignored: event.type });
}

// ── donation handlers (fundraising.md) ─────────────────────────────────────
// The donation ledger mirrors event_orders: status is CAS-only, the webhook is
// the sole writer. A donation has no seat, so the completed handler just marks
// it paid (no capacity recheck, no attendee seat).

async function handleDonationCompleted(
  service: DbClient,
  session: CheckoutSession,
  eventType: string,
): Promise<Response> {
  if (!isPaymentSettled(session.paymentStatus)) {
    // A delayed-notification method: the Session completed, the money has not
    // arrived. Recording the donation as paid here would put it on the
    // charity's thermometer before it exists, and if the payment then fails
    // nothing takes it back off.
    console.error(
      'donation checkout session completed unpaid; awaiting async outcome. payment_status:',
      session.paymentStatus ?? 'absent',
    );
    return Response.json({ ok: true, skipped: 'payment_not_settled' });
  }

  const donationId = donationIdFromSession(session);
  if (!donationId) {
    console.error('donation checkout.session.completed missing donation_id');
    return Response.json({ ok: true, skipped: 'missing_metadata' });
  }

  const { data: donation, error: readErr } = await service
    .from('donations')
    .select('id, status')
    .eq('id', donationId)
    .maybeSingle();
  if (readErr) {
    console.error('donation read failed (code):', readErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'donation_read_failed' }, { status: 500 });
  }
  if (!donation) {
    console.error('donation checkout.session.completed for unknown donation');
    return Response.json({ ok: true, skipped: 'unknown_donation' });
  }

  if (donationStatusTransition(donation.status, eventType) === null) {
    return Response.json({ ok: true, skipped: 'no_transition' });
  }

  const paymentIntent = session.paymentIntentId;

  // Compound match on status='pending' makes the UPDATE itself the CAS — a
  // replayed delivery can't double-count.
  const { data: updated, error: updErr } = await service
    .from('donations')
    .update({
      status: 'paid',
      paid_at: new Date().toISOString(),
      stripe_payment_intent_id: paymentIntent,
    })
    .eq('id', donationId)
    .eq('status', 'pending')
    .select('id')
    .maybeSingle();
  if (updErr) {
    console.error('donation paid update failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'donation_update_failed' }, { status: 500 });
  }
  if (!updated) {
    // Lost the CAS race to a concurrent delivery — that one recorded it.
    return Response.json({ ok: true, skipped: 'cas_lost' });
  }
  return Response.json({ ok: true, donation_paid: true, donation_id: donationId });
}

async function handleDonationNotPaid(
  service: DbClient,
  session: CheckoutSession,
  eventType: string,
): Promise<Response> {
  const donationId = donationIdFromSession(session);
  if (!donationId) {
    return Response.json({ ok: true, skipped: 'missing_donation_id' });
  }
  const { data: donation, error: readErr } = await service
    .from('donations')
    .select('status')
    .eq('id', donationId)
    .maybeSingle();
  if (readErr) {
    // A failed read is not "no such donation". Reporting 200 here closed the
    // delivery for good and left the donation `pending` forever, because
    // nothing sweeps a lapsed donation reservation.
    console.error('donation expiry read failed (code):', readErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'donation_read_failed' }, { status: 500 });
  }
  if (!donation) {
    return Response.json({ ok: true, skipped: 'unknown_donation' });
  }
  const next = donationStatusTransition(donation.status, eventType);
  if (next === null) {
    return Response.json({ ok: true, skipped: 'no_transition' });
  }
  const { error: updErr } = await service
    .from('donations')
    .update({ status: next })
    .eq('id', donationId)
    .eq('status', 'pending');
  if (updErr) {
    console.error('donation cancel update failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'donation_update_failed' }, { status: 500 });
  }
  return Response.json({ ok: true, donation_status: next });
}

/// Returns a Response when the charge IS a donation (handled, terminally),
/// or `null` when the charge is not a donation — the dispatcher then falls
/// through to handleOrderRefunded. (A missing payment_intent is a donation-
/// ledger no-op AND an event-ledger no-op, so it's terminal here too.)
async function handleDonationRefunded(
  service: DbClient,
  charge: Charge,
): Promise<Response | null> {
  // A charge.refunded object carries the payment_intent; resolve the donation
  // through stripe_payment_intent_id (set when the donation was marked paid).
  const paymentIntent = charge.paymentIntentId;
  if (!paymentIntent) {
    return Response.json({ ok: true, skipped: 'missing_payment_intent' });
  }
  const { data: donation, error: readErr } = await service
    .from('donations')
    .select('id, status, amount_cents')
    .eq('stripe_payment_intent_id', paymentIntent)
    .maybeSingle();
  if (readErr) {
    // A failed read is not "not a donation". Falling through on it handed the
    // charge to the event-order path, which found no order either and answered
    // 200 — so a transient database error looked to Stripe like a refund we had
    // processed, and no retry ever came.
    console.error('donation refund read failed (code):', readErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'donation_read_failed' }, { status: 500 });
  }
  if (!donation) {
    // Not a donation charge — fall through to the paid-event refund path.
    return null;
  }
  const scope = refundScopeOfCharge(charge);
  const nextStatus = donationStatusTransition(donation.status, STRIPE_EVENT.chargeRefunded, scope);
  if (nextStatus === null) {
    return Response.json({ ok: true, skipped: 'no_transition' });
  }
  const refundedCents = refundedCentsOfCharge(charge, donation.amount_cents, scope);
  if (refundedCents === null) {
    // The charge reports no amount this column can hold. Recording the status
    // without the amount would state that money came back and then count all
    // of it as raised, which is the § 769 overstatement again.
    console.error(
      'donation refund carried no usable amount; nothing recorded. donation:',
      donation.id,
    );
    return Response.json({ ok: true, skipped: 'unreadable_refund_amount' });
  }

  // Compound CAS. `.eq('status', …)` is the status we READ, not a hardcoded
  // 'paid', so a completing refund can move a partially-refunded donation on.
  // `.lte('refunded_cents', …)` is the second half and it is what makes two
  // instalments order-insensitive: `amount_refunded` is a running total, so a
  // delivery carrying a SMALLER total than the ledger already holds is a stale
  // one and must not walk the figure back.
  const { data: updated, error: updErr } = await service
    .from('donations')
    .update({
      status: nextStatus,
      refunded_cents: refundedCents,
      refunded_at: new Date().toISOString(),
    })
    .eq('id', donation.id)
    .eq('status', donation.status)
    .lte('refunded_cents', refundedCents)
    .select('id')
    .maybeSingle();
  if (updErr) {
    console.error('donation refund update failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'donation_update_failed' }, { status: 500 });
  }
  if (!updated) {
    // Either a concurrent delivery recorded it, or this one arrived out of
    // order carrying a smaller cumulative total than the ledger already holds.
    return Response.json({ ok: true, skipped: 'cas_lost' });
  }
  if (nextStatus === 'partially_refunded') {
    return Response.json({
      ok: true,
      donation_partially_refunded: true,
      donation_id: donation.id,
    });
  }
  return Response.json({ ok: true, donation_refunded: true, donation_id: donation.id });
}

/// Paid-event refund coupling (P2). A charge.refunded for a paid event order
/// (resolved by payment intent): CAS the order paid->refunded, stamp
/// refunded_at, and DELETE the buyer's going seat so the freed mat is
/// available for waitlist promotion (the enforce_event_capacity machinery
/// promotes a waitlisted attendee when a going row is removed). The webhook
/// stays the sole, idempotent status writer: a replayed charge.refunded finds
/// the order already `refunded` (orderStatusTransition -> null) and no-ops, so
/// it can't double-release a seat or double-promote the waitlist.
async function handleOrderRefunded(
  service: DbClient,
  charge: Charge,
): Promise<Response> {
  const paymentIntent = charge.paymentIntentId;
  if (!paymentIntent) {
    return Response.json({ ok: true, skipped: 'missing_payment_intent' });
  }
  const { data: order, error: readErr } = await service
    .from('event_orders')
    .select('id, status, event_id, instance_start, buyer_user_id')
    .eq('stripe_payment_intent_id', paymentIntent)
    .maybeSingle();
  if (readErr) {
    console.error('order refund read failed (code):', readErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'order_read_failed' }, { status: 500 });
  }
  if (!order) {
    // Neither a donation nor a known event order — log + 200 so Stripe stops
    // retrying (a refund issued from the dashboard for an unknown charge).
    return Response.json({ ok: true, skipped: 'no_order_for_charge' });
  }
  // Stripe emits charge.refunded for a PARTIAL refund too. A partial refund
  // keeps the registration: the buyer is still going, so the seat must not be
  // released to the waitlist.
  const scope = refundScopeOfCharge(charge);
  const nextStatus = orderStatusTransition(order.status, STRIPE_EVENT.chargeRefunded, scope);
  if (nextStatus === null) {
    // Not paid (already refunded / canceled) — idempotent no-op.
    return Response.json({ ok: true, skipped: 'no_transition' });
  }

  // CAS paid->refunded (compound match on status='paid' makes the UPDATE the
  // CAS — a replayed delivery can't re-run the seat release).
  // CAS on the status we READ, not a hardcoded 'paid' — a completing refund
  // transitions from 'partially_refunded', and matching only 'paid' would make
  // the seat unreleasable once any partial refund had landed.
  const { data: updated, error: updErr } = await service
    .from('event_orders')
    .update({ status: nextStatus, refunded_at: new Date().toISOString() })
    .eq('id', order.id)
    .eq('status', order.status)
    .select('id')
    .maybeSingle();
  if (updErr) {
    console.error('order refund update failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'order_update_failed' }, { status: 500 });
  }
  if (!updated) {
    // Lost the CAS race to a concurrent delivery — that one released the seat.
    return Response.json({ ok: true, skipped: 'cas_lost' });
  }

  if (nextStatus === 'partially_refunded') {
    // Money came back but the registration stands — keep the seat.
    return Response.json({
      ok: true,
      order_partially_refunded: true,
      order_id: order.id,
    });
  }

  // Release the seat: delete the buyer's attendee row for this instance that
  // points at this order. Deleting the going row frees capacity and triggers
  // waitlist promotion (enforce_event_capacity / promote_event_waitlist).
  // Scoped by order_id so we only remove the seat THIS order granted.
  const { error: seatErr } = await service
    .from('event_attendees')
    .delete()
    .eq('event_id', order.event_id)
    .eq('user_id', order.buyer_user_id)
    .eq('instance_start', order.instance_start)
    .eq('order_id', order.id);
  if (seatErr) {
    // The order is refunded but the seat removal failed — log for
    // reconciliation. Don't 500 (Stripe would retry and the CAS would no-op,
    // never re-attempting the delete). A stale going row on a refunded order
    // is a reconciliation item, not a money error.
    console.error('seat release after refund failed (code):', seatErr?.code ?? 'unknown', 'order:', order.id);
  }

  return Response.json({ ok: true, order_refunded: true, order_id: order.id });
}

async function handleCompleted(
  service: DbClient,
  session: CheckoutSession,
  eventType: string,
): Promise<Response> {
  if (!isPaymentSettled(session.paymentStatus)) {
    // `checkout.session.completed` is not a payment. For a delayed-
    // notification method the money is still in flight and the outcome lands
    // days later as async_payment_succeeded / _failed. Seating here gives a
    // place away for money that may never arrive — and once seated there is
    // no event that takes it back, because the failure arm below transitions
    // out of `pending`, not out of `paid`.
    console.error(
      'checkout session completed unpaid; awaiting async outcome. payment_status:',
      session.paymentStatus ?? 'absent',
    );
    return Response.json({ ok: true, skipped: 'payment_not_settled' });
  }

  const attendee = attendeeRowFromSession(session);
  if (!attendee) {
    // No metadata to seat against — record + 200 so Stripe stops
    // retrying; logged for reconciliation.
    console.error('checkout.session.completed missing metadata');
    return Response.json({ ok: true, skipped: 'missing_metadata' });
  }

  // Resolve the order and CAS its status. Only pending->paid transitions.
  const { data: order, error: orderErr } = await service
    .from('event_orders')
    .select('id, status, event_id, instance_start, buyer_user_id, stripe_payment_intent_id')
    .eq('id', attendee.order_id)
    .maybeSingle();
  if (orderErr) {
    console.error('order read failed (code):', orderErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'order_read_failed' }, { status: 500 });
  }
  if (!order) {
    console.error('checkout.session.completed for unknown order');
    return Response.json({ ok: true, skipped: 'unknown_order' });
  }

  const next = orderStatusTransition(order.status, eventType);
  if (next === null) {
    // Already paid / terminal — idempotent no-op.
    return Response.json({ ok: true, skipped: 'no_transition' });
  }

  const paymentIntent = session.paymentIntentId;

  // Mark the order paid (compound match on status='pending' makes the
  // UPDATE itself a CAS — a concurrent webhook can't both flip it).
  const { data: updated, error: updErr } = await service
    .from('event_orders')
    .update({
      status: 'paid',
      paid_at: new Date().toISOString(),
      stripe_payment_intent_id: paymentIntent,
    })
    .eq('id', order.id)
    .eq('status', 'pending')
    .select('id')
    .maybeSingle();
  if (updErr) {
    console.error('order paid update failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'order_update_failed' }, { status: 500 });
  }
  if (!updated) {
    // Lost the CAS race to a concurrent delivery — that one seated it.
    return Response.json({ ok: true, skipped: 'cas_lost' });
  }

  // Confirm-time capacity recheck against the event's hard cap.
  const { data: event } = await service
    .from('events')
    .select('capacity')
    .eq('id', attendee.event_id)
    .maybeSingle();
  const capacity = event?.capacity ?? null;

  if (capacity !== null) {
    const { count: goingCount } = await service
      .from('event_attendees')
      .select('event_id', { count: 'exact', head: true })
      .eq('event_id', attendee.event_id)
      .eq('instance_start', attendee.instance_start)
      .eq('status', 'going')
      .neq('user_id', attendee.user_id);
    // Best-effort fast path only. This recheck is NOT authoritative: it counts
    // only seated 'going' rows and holds no lock, so a competing paid order
    // that hasn't seated yet is invisible and N webhooks racing the last seat
    // all read 'available'. The advisory-locked enforce_event_capacity trigger
    // below is the real never-oversell guard; this just shortcuts the obvious
    // already-full case.
    if (capacityDecision(goingCount ?? 0, 0, capacity) === 'full') {
      // Oversold against another path. P1 has NO automated refund: leave
      // the order paid, do NOT seat, and flag for a manual Stripe-
      // dashboard refund. Logged with the order id so ops can act.
      console.error(
        'OVERSOLD: paid order seats no slot, flag for manual refund. order:',
        order.id,
      );
      return Response.json({ ok: true, oversold: true, order_id: order.id });
    }
  }

  // Seat the attendee (the paid order_id satisfies the
  // enforce_paid_order_for_priced_event trigger). Upsert on the PK so a
  // retry is idempotent. Read the PERSISTED status back: the advisory-locked
  // enforce_event_capacity BEFORE trigger silently rewrites NEW.status to
  // 'waitlisted' when the seat is over capacity (it demotes rather than
  // raising), and that trigger — not the lock-free recheck above — is the
  // authoritative guard. RETURNING reflects the BEFORE-trigger mutation.
  const { data: seated, error: seatErr } = await service
    .from('event_attendees')
    .upsert({
      event_id: attendee.event_id,
      user_id: attendee.user_id,
      instance_start: attendee.instance_start,
      status: 'going',
      order_id: attendee.order_id,
    }, { onConflict: 'event_id,user_id,instance_start' })
    .select('status')
    .maybeSingle();
  if (seatErr) {
    console.error('attendee seat failed (code):', seatErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'seat_failed' }, { status: 500 });
  }

  // The buyer paid but the capacity trigger demoted them to the waitlist
  // (lost the last seat to a concurrent paid order the recheck couldn't see).
  // P1 has no automated refund — report oversold + order_id so ops can refund,
  // instead of falsely telling the caller the seat was confirmed.
  if (seated?.status === 'waitlisted') {
    console.error(
      'OVERSOLD: paid order demoted to waitlist by capacity trigger, flag for manual refund. order:',
      order.id,
    );
    return Response.json({
      ok: true,
      oversold: true,
      waitlisted: true,
      order_id: order.id,
    });
  }

  return Response.json({ ok: true, seated: true, order_id: order.id });
}

async function handleNotPaid(
  service: DbClient,
  session: CheckoutSession,
  eventType: string,
): Promise<Response> {
  const orderId = session.metadata.order_id ?? null;
  if (!orderId) {
    return Response.json({ ok: true, skipped: 'missing_order_id' });
  }

  const { data: order, error: readErr } = await service
    .from('event_orders')
    .select('status')
    .eq('id', orderId)
    .maybeSingle();
  if (readErr) {
    // A failed read is not "no such order". Answering 200 here closed the
    // delivery for good and left the order `pending` forever, holding a seat
    // nobody bought — nothing sweeps a lapsed reservation. The donation twin
    // of this read was hardened; this one was left.
    console.error('order expiry read failed (code):', readErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'order_read_failed' }, { status: 500 });
  }
  if (!order) {
    return Response.json({ ok: true, skipped: 'unknown_order' });
  }
  const next = orderStatusTransition(order.status, eventType);
  if (next === null) {
    return Response.json({ ok: true, skipped: 'no_transition' });
  }

  // CAS pending->canceled (expired) or pending->failed (the async payment
  // never landed); either releases the soft reservation, since the sweep
  // index and the capacity count both key on status='pending'.
  const { error: updErr } = await service
    .from('event_orders')
    .update({ status: next })
    .eq('id', orderId)
    .eq('status', 'pending');
  if (updErr) {
    console.error('order cancel update failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'order_update_failed' }, { status: 500 });
  }
  return Response.json({ ok: true, order_status: next });
}

async function handleAccountUpdated(
  service: DbClient,
  account: ConnectAccount,
): Promise<Response> {
  const accountId = account.id;
  if (!accountId) {
    return Response.json({ ok: true, skipped: 'missing_account_id' });
  }

  // account.updated fires on ANY connected-account change (a new bank, a
  // capability flip, a periodic refresh) — so the capability flags are
  // re-mirrored on every delivery to reflect Stripe's latest.
  const { error: updErr } = await service
    .from('instructor_payout_accounts')
    .update({
      charges_enabled: account.chargesEnabled,
      payouts_enabled: account.payoutsEnabled,
      details_submitted: account.detailsSubmitted,
      updated_at: new Date().toISOString(),
    })
    .eq('stripe_connect_account_id', accountId);
  if (updErr) {
    console.error('account.updated sync failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'account_sync_failed' }, { status: 500 });
  }

  // onboarded_at is set-once: the FIRST time details_submitted is true and
  // never again. Because account.updated re-fires on later account edits, an
  // unconditional stamp would keep rewriting "onboarded at" to now(). The
  // `.is('onboarded_at', null)` filter makes the UPDATE itself the guard — a
  // later delivery finds it non-null and no-ops, and a second concurrent
  // first-onboarding delivery can't race it either.
  if (account.detailsSubmitted) {
    const { error: stampErr } = await service
      .from('instructor_payout_accounts')
      .update({ onboarded_at: new Date().toISOString() })
      .eq('stripe_connect_account_id', accountId)
      .is('onboarded_at', null);
    if (stampErr) {
      console.error('account.updated onboarded_at stamp failed (code):', stampErr?.code ?? 'unknown');
      return Response.json({ ok: false, error: 'account_sync_failed' }, { status: 500 });
    }
  }

  return Response.json({ ok: true, account_synced: true });
}

