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
    return await handleCompleted(service, obj);
  }
  if (event.type === 'checkout.session.expired') {
    return await handleExpired(service, obj);
  }
  if (event.type === 'account.updated') {
    return await handleAccountUpdated(service, obj);
  }

  // Unhandled types — recorded (dedupe) but no side effect.
  return Response.json({ ok: true, ignored: event.type });
}));

type Service = ReturnType<typeof createClient>;

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
    // The just-paid order is confirmed; it does not count as a competing
    // pending hold. Recheck going against capacity (pending excluded — a
    // pending hold does not yet occupy a seat at confirm time).
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
  // retry is idempotent.
  const { error: seatErr } = await service
    .from('event_attendees')
    .upsert({
      event_id: attendee.event_id,
      user_id: attendee.user_id,
      instance_start: attendee.instance_start,
      status: 'going',
      order_id: attendee.order_id,
    }, { onConflict: 'event_id,user_id,instance_start' });
  if (seatErr) {
    console.error('attendee seat failed (code):', seatErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'seat_failed' }, { status: 500 });
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
