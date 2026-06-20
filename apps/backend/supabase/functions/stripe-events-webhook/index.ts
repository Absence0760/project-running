/// Stripe Connect events webhook — the ONE idempotent writer of order
/// status (club_events.md slice P1).
///
/// Handles exactly three event types; everything else is 200-ignored:
///   checkout.session.completed -> CAS pending->paid, confirm-time
///     capacity recheck, seat the 'going' attendee with order_id. If the
///     class filled via another path, the order is left paid + logged +
///     flagged for MANUAL refund (P1 has no automated refund).
///   checkout.session.expired   -> CAS pending->canceled, releasing the
///     soft reservation (the pending row stops counting toward capacity).
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

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { readTextWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { capacityDecision } from '../events-checkout/lib.ts';
import {
  attendeeRowFromSession,
  donationIdFromSession,
  donationStatusTransition,
  isDonationSession,
  orderStatusTransition,
  parseStripeEventEnvelope,
  verifyStripeSignature,
} from './lib.ts';

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

  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
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

  const obj = event.data.object;

  if (event.type === 'checkout.session.completed') {
    // One webhook, one secret. A donation session (metadata.kind='donation')
    // confirms a donations row; a seat session confirms an event_orders row.
    return isDonationSession(obj)
      ? await handleDonationCompleted(service, obj)
      : await handleCompleted(service, obj);
  }
  if (event.type === 'checkout.session.expired') {
    return isDonationSession(obj)
      ? await handleDonationExpired(service, obj)
      : await handleExpired(service, obj);
  }
  if (event.type === 'account.updated') {
    return await handleAccountUpdated(service, obj);
  }
  if (event.type === 'charge.refunded') {
    // Donations only — a paid-event refund is manual via the Stripe dashboard
    // in P1 (no event_orders refund path). The donation row CAS paid->refunded.
    return await handleDonationRefunded(service, obj);
  }

  // Unhandled types — recorded (dedupe) but no side effect.
  return Response.json({ ok: true, ignored: event.type });
}));

type Service = ReturnType<typeof createClient>;

// ── donation handlers (fundraising.md) ─────────────────────────────────────
// The donation ledger mirrors event_orders: status is CAS-only, the webhook is
// the sole writer. A donation has no seat, so the completed handler just marks
// it paid (no capacity recheck, no attendee seat).

async function handleDonationCompleted(
  service: Service,
  session: Record<string, unknown>,
): Promise<Response> {
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

  if (donationStatusTransition(donation.status as string, 'checkout.session.completed') === null) {
    return Response.json({ ok: true, skipped: 'no_transition' });
  }

  const paymentIntent = typeof session.payment_intent === 'string' ? session.payment_intent : null;

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

async function handleDonationExpired(
  service: Service,
  session: Record<string, unknown>,
): Promise<Response> {
  const donationId = donationIdFromSession(session);
  if (!donationId) {
    return Response.json({ ok: true, skipped: 'missing_donation_id' });
  }
  const { data: donation } = await service
    .from('donations')
    .select('status')
    .eq('id', donationId)
    .maybeSingle();
  if (!donation) {
    return Response.json({ ok: true, skipped: 'unknown_donation' });
  }
  if (donationStatusTransition(donation.status as string, 'checkout.session.expired') === null) {
    return Response.json({ ok: true, skipped: 'no_transition' });
  }
  const { error: updErr } = await service
    .from('donations')
    .update({ status: 'canceled' })
    .eq('id', donationId)
    .eq('status', 'pending');
  if (updErr) {
    console.error('donation cancel update failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'donation_update_failed' }, { status: 500 });
  }
  return Response.json({ ok: true, donation_canceled: true });
}

async function handleDonationRefunded(
  service: Service,
  charge: Record<string, unknown>,
): Promise<Response> {
  // A charge.refunded object carries the payment_intent; resolve the donation
  // through stripe_payment_intent_id (set when the donation was marked paid).
  const paymentIntent = typeof charge.payment_intent === 'string' ? charge.payment_intent : null;
  if (!paymentIntent) {
    return Response.json({ ok: true, skipped: 'missing_payment_intent' });
  }
  const { data: donation } = await service
    .from('donations')
    .select('id, status')
    .eq('stripe_payment_intent_id', paymentIntent)
    .maybeSingle();
  if (!donation) {
    // Not a donation charge (could be a paid-event charge — manual refund in P1).
    return Response.json({ ok: true, skipped: 'no_donation_for_charge' });
  }
  if (donationStatusTransition(donation.status as string, 'charge.refunded') === null) {
    return Response.json({ ok: true, skipped: 'no_transition' });
  }
  const { error: updErr } = await service
    .from('donations')
    .update({ status: 'refunded', refunded_at: new Date().toISOString() })
    .eq('id', donation.id)
    .eq('status', 'paid');
  if (updErr) {
    console.error('donation refund update failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'donation_update_failed' }, { status: 500 });
  }
  return Response.json({ ok: true, donation_refunded: true, donation_id: donation.id });
}

async function handleCompleted(
  service: Service,
  session: Record<string, unknown>,
): Promise<Response> {
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

  const next = orderStatusTransition(order.status as string, 'checkout.session.completed');
  if (next === null) {
    // Already paid / terminal — idempotent no-op.
    return Response.json({ ok: true, skipped: 'no_transition' });
  }

  const paymentIntent = typeof session.payment_intent === 'string'
    ? session.payment_intent
    : null;

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
  const capacity = (event?.capacity as number | null) ?? null;

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

async function handleExpired(
  service: Service,
  session: Record<string, unknown>,
): Promise<Response> {
  const orderId = readMetadataString(session, 'order_id');
  if (!orderId) {
    return Response.json({ ok: true, skipped: 'missing_order_id' });
  }

  const { data: order } = await service
    .from('event_orders')
    .select('status')
    .eq('id', orderId)
    .maybeSingle();
  if (!order) {
    return Response.json({ ok: true, skipped: 'unknown_order' });
  }
  const next = orderStatusTransition(order.status as string, 'checkout.session.expired');
  if (next === null) {
    return Response.json({ ok: true, skipped: 'no_transition' });
  }

  // CAS pending->canceled; releasing the soft reservation (a canceled
  // order no longer counts toward capacity — the sweep index keys on
  // status='pending').
  const { error: updErr } = await service
    .from('event_orders')
    .update({ status: 'canceled' })
    .eq('id', orderId)
    .eq('status', 'pending');
  if (updErr) {
    console.error('order cancel update failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'order_update_failed' }, { status: 500 });
  }
  return Response.json({ ok: true, canceled: true });
}

async function handleAccountUpdated(
  service: Service,
  account: Record<string, unknown>,
): Promise<Response> {
  const accountId = typeof account.id === 'string' ? account.id : null;
  if (!accountId) {
    return Response.json({ ok: true, skipped: 'missing_account_id' });
  }
  const patch: Record<string, unknown> = {
    charges_enabled: account.charges_enabled === true,
    payouts_enabled: account.payouts_enabled === true,
    details_submitted: account.details_submitted === true,
    updated_at: new Date().toISOString(),
  };
  if (account.details_submitted === true) {
    patch.onboarded_at = new Date().toISOString();
  }

  const { error: updErr } = await service
    .from('instructor_payout_accounts')
    .update(patch)
    .eq('stripe_connect_account_id', accountId);
  if (updErr) {
    console.error('account.updated sync failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'account_sync_failed' }, { status: 500 });
  }
  return Response.json({ ok: true, account_synced: true });
}

function readMetadataString(obj: Record<string, unknown>, key: string): string | null {
  const md = obj.metadata;
  if (typeof md !== 'object' || md === null) return null;
  const v = (md as Record<string, unknown>)[key];
  return typeof v === 'string' ? v : null;
}
