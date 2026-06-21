/// Buyer self-cancel of a paid in-person event registration
/// (club_events.md slice P2).
///
/// The buyer cancels their OWN order for an instance on the event-detail
/// page. This EF only INITIATES the cancel; the stripe-events-webhook —
/// still the SOLE, idempotent, service-role-only writer of
/// event_orders.status — performs the actual status transition + seat
/// release when Stripe delivers the resulting event:
///
///   pending order -> expire the Checkout Session at Stripe. Stripe fires
///     `checkout.session.expired` -> the webhook CAS's pending->canceled,
///     releasing the soft reservation (no charge was captured).
///   paid order, refund-eligible per event_pricing.refund_policy -> create
///     a Stripe refund (refund_application_fee: true, so the platform fee
///     is clawed back — we don't profit on a cancelled class). Stripe fires
///     `charge.refunded` -> the webhook CAS's paid->refunded, deletes the
///     buyer's seat (freeing it for waitlist promotion), and reverses the
///     reservation. We stamp event_orders.refund_initiated_at here so the UI
///     can show "refund in progress" during the async gap.
///   paid order, NOT refund-eligible (inside the no-refund window) -> 409
///     policy_no_refund; the buyer keeps the seat (we never free a seat
///     without refunding the money).
///
/// Validation gates (each fails closed):
///   - caller is signed in (JWT-gated),
///   - Stripe is configured (else 503, exactly like P1's checkout),
///   - the caller owns a cancelable order for (event, instance).
///
/// Mirrors events-checkout's auth + rate-limit shape. SAQ A — no card data.
/// TEST MODE ONLY in P1/P2: STRIPE_SECRET_KEY must be an sk_test_ key.

import Stripe from 'https://esm.sh/stripe@17.5.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { cancelAction, resolveRefundEligibility, type RefundPolicy } from './lib.ts';

interface CancelBody {
  event_id?: string;
  instance_start?: string;
}

Deno.serve(withSentry('events-cancel', async (req: Request) => {
  if (req.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  const secretKey = Deno.env.get('STRIPE_SECRET_KEY');
  if (!secretKey) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }

  const guarded = await readJsonWithLimit<CancelBody>(req, 4 * 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;
  const body = guarded.body ?? {};
  const eventId = typeof body.event_id === 'string' ? body.event_id : null;
  const instanceStart = typeof body.instance_start === 'string' ? body.instance_start : null;
  if (!eventId || !instanceStart) {
    return Response.json({ error: 'missing_event_or_instance' }, { status: 400 });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }
  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }

  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  const denied = await checkRateLimit(
    service,
    user.id,
    'events-cancel',
    20,
    3600,
    { failClosed: true },
  );
  if (denied) return denied;

  // The buyer's most recent cancelable order for this instance. RLS would
  // also scope this to the caller, but we run it via the service role and
  // pin buyer_user_id explicitly so the lookup is unambiguous.
  const { data: order, error: orderErr } = await service
    .from('event_orders')
    .select('id, status, stripe_checkout_session_id, stripe_payment_intent_id, refund_initiated_at')
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .eq('buyer_user_id', user.id)
    .in('status', ['pending', 'paid'])
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (orderErr) {
    console.error('order read failed (code):', orderErr?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }
  if (!order) {
    return Response.json({ error: 'no_cancelable_order' }, { status: 404 });
  }

  // Pricing for the refund policy. Per-instance override wins, else the
  // series default (instance_start is null). Read as the user (RLS lets the
  // buyer read pricing with the event).
  const { data: pricingRows, error: pricingErr } = await userClient
    .from('event_pricing')
    .select('instance_start, refund_policy')
    .eq('event_id', eventId);
  if (pricingErr) {
    console.error('pricing read failed (code):', pricingErr?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }
  const rows = (pricingRows ?? []) as Array<{ instance_start: string | null; refund_policy: string }>;
  const pricing = rows.find((r) => r.instance_start === instanceStart)
    ?? rows.find((r) => r.instance_start === null);
  const refundPolicy = (pricing?.refund_policy ?? 'no_refund') as RefundPolicy;

  const eligibility = resolveRefundEligibility(refundPolicy, Date.now(), instanceStart);
  const action = cancelAction(order.status as string, eligibility.eligible);

  const stripe = new Stripe(secretKey, {
    httpClient: Stripe.createFetchHttpClient(),
  });

  if (action === 'release_reservation') {
    // Expire the Checkout Session at Stripe; the resulting
    // checkout.session.expired webhook CAS's the pending order ->canceled
    // (the webhook stays the sole status writer). If there's no session id
    // (an order that never reached Stripe), there's nothing to expire — the
    // soft reservation lapses on its own reserved_until.
    const sessionId = order.stripe_checkout_session_id as string | null;
    if (sessionId) {
      try {
        await stripe.checkout.sessions.expire(sessionId);
      } catch (e) {
        // Already expired / completed concurrently — the webhook reconciles
        // the true state. Don't 500 the buyer over a benign race.
        console.error('checkout session expire failed:', e instanceof Error ? e.message : 'unknown');
      }
    }
    return Response.json({ ok: true, action: 'reservation_released' });
  }

  if (action === 'policy_no_refund') {
    return Response.json({ error: 'policy_no_refund' }, { status: 409 });
  }

  if (action === 'noop') {
    // Terminal order (already refunded / canceled / failed) — idempotent.
    return Response.json({ ok: true, action: 'noop' });
  }

  // action === 'refund'. Need the payment intent to refund against.
  const paymentIntent = order.stripe_payment_intent_id as string | null;
  if (!paymentIntent) {
    console.error('paid order missing payment_intent; cannot refund. order:', order.id);
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }

  // Stamp refund_initiated_at first so the UI reflects "refund in progress"
  // even if the charge.refunded webhook is slow. NOT a status write — status
  // stays 'paid' until the webhook confirms (sole-writer invariant).
  const { error: stampErr } = await service
    .from('event_orders')
    .update({ refund_initiated_at: new Date().toISOString() })
    .eq('id', order.id)
    .eq('status', 'paid');
  if (stampErr) {
    console.error('refund stamp failed (code):', stampErr?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }

  try {
    await stripe.refunds.create(
      {
        payment_intent: paymentIntent,
        // Claw back the platform application fee — the platform doesn't
        // profit on a cancelled class (club_events.md § Refunds).
        refund_application_fee: true,
      },
      // Stable idempotency key: a buyer double-click or a retried cancel
      // must not create a second refund.
      { idempotencyKey: `events-cancel:${order.id}` },
    );
  } catch (e) {
    // The refund call failed at Stripe. Clear the optimistic stamp so the UI
    // doesn't falsely show "refund in progress" forever, and surface the
    // failure so the buyer can retry (the order is untouched — status stays
    // paid, the seat is held).
    await service
      .from('event_orders')
      .update({ refund_initiated_at: null })
      .eq('id', order.id)
      .eq('status', 'paid');
    console.error('stripe refund create failed:', e instanceof Error ? e.message : 'unknown');
    return Response.json({ error: 'stripe_refund_failed' }, { status: 502 });
  }

  // The refund succeeded at Stripe; charge.refunded will flip the order
  // ->refunded and release the seat. Report refund_initiated so the UI polls.
  return Response.json({ ok: true, action: 'refund_initiated', order_id: order.id });
}));
