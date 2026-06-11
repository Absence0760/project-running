/// Buyer checkout for a paid in-person event (club_events.md slice P1).
///
/// Validates, then opens a Stripe-hosted Checkout Session as a
/// DESTINATION charge against the host's connected account, and inserts a
/// `pending` event_orders row that holds a soft capacity reservation for
/// ~15 min. The webhook (stripe-events-webhook) confirms the order and
/// seats the attendee on checkout.session.completed; expiry releases the
/// slot.
///
/// Validation gates (each fails closed):
///   - caller is signed in (JWT-gated; a logged-out stranger is 401'd —
///     "sign up before paying"),
///   - the event is visible to the caller,
///   - there is event_pricing for (event, instance) with modality
///     'in_person' (a 'virtual' price is reserved for P4 -> 400),
///   - the instance is not a cancelled occurrence (event_exceptions),
///   - the sales window is still open,
///   - the host has a charges-enabled payout account (else 409),
///   - capacity is not already full counting going + non-expired pending.
///
/// PCI: Checkout is fully Stripe-hosted — SAQ A. No card form here.
/// Idempotency: the Stripe create call carries a stable idempotency key
/// derived from (buyer, event, instance) so a double-click reuses the
/// same session instead of opening a second hold.
///
/// TEST MODE ONLY in P1: STRIPE_SECRET_KEY must be an sk_test_ key.

import Stripe from 'https://esm.sh/stripe@17.5.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import {
  buildCheckoutSessionParams,
  capacityDecision,
  checkoutIdempotencyKey,
  computeApplicationFeeCents,
  isSalesWindowOpen,
  reservationExpiry,
} from './lib.ts';
import { validateReturnUrl } from '../events-connect-onboard/lib.ts';

interface CheckoutBody {
  event_id?: string;
  instance_start?: string;
  success_url?: string;
  cancel_url?: string;
}

Deno.serve(withSentry('events-checkout', async (req: Request) => {
  if (req.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  const secretKey = Deno.env.get('STRIPE_SECRET_KEY');
  if (!secretKey) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }
  const allowlist = (Deno.env.get('STRIPE_EVENTS_ALLOWED_REDIRECTS') ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (allowlist.length === 0) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }

  const guarded = await readJsonWithLimit<CheckoutBody>(req, 4 * 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;
  const body = guarded.body ?? {};
  const eventId = typeof body.event_id === 'string' ? body.event_id : null;
  const instanceStart = typeof body.instance_start === 'string' ? body.instance_start : null;
  if (!eventId || !instanceStart) {
    return Response.json({ error: 'missing_event_or_instance' }, { status: 400 });
  }
  const instanceMs = Date.parse(instanceStart);
  if (!Number.isFinite(instanceMs)) {
    return Response.json({ error: 'invalid_instance_start' }, { status: 400 });
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
    'events-checkout',
    20,
    3600,
    { failClosed: true },
  );
  if (denied) return denied;

  // Visibility gate AS THE USER (RLS): a non-visible event reads as
  // not-found. Select only a column-granted field — `events` is
  // column-locked and `host_user_id` is REVOKED from authenticated
  // (20261228_001), so the user client may not read it.
  const { data: visible, error: visibleErr } = await userClient
    .from('events')
    .select('id')
    .eq('id', eventId)
    .maybeSingle();
  if (visibleErr) {
    console.error('event visibility read failed (code):', visibleErr?.code ?? 'unknown');
    return Response.json({ error: 'checkout_failed' }, { status: 500 });
  }
  if (!visible) {
    return Response.json({ error: 'event_not_found' }, { status: 404 });
  }

  // The gating columns (host_user_id is revoked from client roles) are
  // read via the service role, scoped to the already-visibility-checked
  // event id.
  const { data: event, error: eventErr } = await service
    .from('events')
    .select('host_user_id, capacity, starts_at, title')
    .eq('id', eventId)
    .maybeSingle();
  if (eventErr || !event) {
    console.error('event detail read failed (code):', eventErr?.code ?? 'missing');
    return Response.json({ error: 'checkout_failed' }, { status: 500 });
  }
  const hostUserId = event.host_user_id as string | null;
  if (!hostUserId) {
    return Response.json({ error: 'event_has_no_host' }, { status: 409 });
  }

  // Pricing for this (event, instance): per-instance override wins, else
  // the series default (instance_start is null). Read as the user (RLS
  // allows reading pricing with the event).
  const { data: pricingRows, error: pricingErr } = await userClient
    .from('event_pricing')
    .select('instance_start, price_cents, currency, modality, platform_fee_bps, sales_close_offset_minutes')
    .eq('event_id', eventId);
  if (pricingErr) {
    console.error('pricing read failed (code):', pricingErr?.code ?? 'unknown');
    return Response.json({ error: 'checkout_failed' }, { status: 500 });
  }
  const rows = (pricingRows ?? []) as Array<{
    instance_start: string | null;
    price_cents: number;
    currency: string;
    modality: string;
    platform_fee_bps: number;
    sales_close_offset_minutes: number;
  }>;
  const pricing = rows.find((r) => r.instance_start === instanceStart)
    ?? rows.find((r) => r.instance_start === null);
  if (!pricing) {
    return Response.json({ error: 'event_not_priced' }, { status: 404 });
  }
  if (pricing.modality !== 'in_person') {
    // 'virtual' is reserved for P4 (digital-good IAP decision).
    return Response.json({ error: 'modality_not_supported' }, { status: 400 });
  }

  // Cancelled-occurrence guard: a cancelled instance is un-buyable.
  const { data: exception } = await userClient
    .from('event_exceptions')
    .select('event_id')
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .maybeSingle();
  if (exception) {
    return Response.json({ error: 'instance_cancelled' }, { status: 409 });
  }

  // Sales window.
  if (!isSalesWindowOpen(
    Date.parse(event.starts_at as string),
    pricing.sales_close_offset_minutes,
    Date.now(),
  )) {
    return Response.json({ error: 'sales_closed' }, { status: 409 });
  }

  // Host capability — block a charge the host can't receive (a stale
  // charges_enabled would create money the host can't be paid).
  const { data: canTake, error: canTakeErr } = await service.rpc(
    'host_can_take_payment',
    { p_user_id: hostUserId },
  );
  if (canTakeErr) {
    console.error('host_can_take_payment failed (code):', canTakeErr?.code ?? 'unknown');
    return Response.json({ error: 'checkout_failed' }, { status: 500 });
  }
  if (canTake !== true) {
    return Response.json({ error: 'host_cannot_take_payment' }, { status: 409 });
  }
  const { data: hostAccount, error: hostAccountErr } = await service
    .from('instructor_payout_accounts')
    .select('stripe_connect_account_id')
    .eq('user_id', hostUserId)
    .maybeSingle();
  if (hostAccountErr || !hostAccount?.stripe_connect_account_id) {
    console.error('host account read failed (code):', hostAccountErr?.code ?? 'missing');
    return Response.json({ error: 'host_cannot_take_payment' }, { status: 409 });
  }
  const hostAccountId = hostAccount.stripe_connect_account_id as string;

  // Capacity precheck (service role — counts every buyer's pending
  // reservation, not just the caller's). going + non-expired pending.
  const capacityOutcome = await precheckCapacity(
    service,
    eventId,
    instanceStart,
    (event.capacity as number | null) ?? null,
  );
  if (capacityOutcome === 'full') {
    return Response.json({ error: 'event_full' }, { status: 409 });
  }

  // Idempotent order insert: a retried checkout for the same
  // (buyer, event, instance) reuses the existing live pending order
  // rather than stacking a second hold.
  const nowMs = Date.now();
  const reservedUntil = reservationExpiry(nowMs);
  const { data: livePending } = await service
    .from('event_orders')
    .select('id, stripe_checkout_session_id')
    .eq('buyer_user_id', user.id)
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .eq('status', 'pending')
    .gt('reserved_until', new Date(nowMs).toISOString())
    .maybeSingle();

  const orderId = livePending?.id as string | undefined ?? crypto.randomUUID();
  const applicationFee = computeApplicationFeeCents(pricing.price_cents, pricing.platform_fee_bps);

  const successUrl = body.success_url && validateReturnUrl(body.success_url, allowlist)
    ? body.success_url
    : `${new URL(allowlist[0]).origin}/clubs?checkout=success`;
  const cancelUrl = body.cancel_url && validateReturnUrl(body.cancel_url, allowlist)
    ? body.cancel_url
    : `${new URL(allowlist[0]).origin}/clubs?checkout=cancel`;

  const stripe = new Stripe(secretKey, {
    httpClient: Stripe.createFetchHttpClient(),
  });

  let session;
  try {
    session = await stripe.checkout.sessions.create(
      buildCheckoutSessionParams({
        amountCents: pricing.price_cents,
        currency: pricing.currency,
        productName: (event.title as string) ?? 'Event registration',
        applicationFeeCents: applicationFee,
        hostAccountId,
        successUrl,
        cancelUrl,
        metadata: {
          event_id: eventId,
          instance_start: instanceStart,
          buyer_user_id: user.id,
          order_id: orderId,
        },
        // Stripe requires expires_at >= now + 30 min; the local
        // reservation is tighter (15 min) and the webhook releases on
        // the definitive checkout.session.expired.
        expiresAtUnix: Math.floor(nowMs / 1000) + 30 * 60,
      }),
      { idempotencyKey: checkoutIdempotencyKey(user.id, eventId, instanceStart) },
    );
  } catch (e) {
    console.error('stripe checkout create failed:', e instanceof Error ? e.message : 'unknown');
    return Response.json({ error: 'stripe_checkout_failed' }, { status: 502 });
  }

  if (livePending) {
    // Refresh the existing hold's session id + extend the reservation.
    const { error: updErr } = await service
      .from('event_orders')
      .update({
        stripe_checkout_session_id: session.id,
        reserved_until: reservedUntil.toISOString(),
      })
      .eq('id', orderId);
    if (updErr) {
      console.error('order refresh failed (code):', updErr?.code ?? 'unknown');
    }
  } else {
    const { error: insErr } = await service
      .from('event_orders')
      .insert({
        id: orderId,
        event_id: eventId,
        instance_start: instanceStart,
        buyer_user_id: user.id,
        host_user_id: hostUserId,
        stripe_checkout_session_id: session.id,
        amount_cents: pricing.price_cents,
        currency: pricing.currency,
        platform_fee_cents: applicationFee,
        status: 'pending',
        reserved_until: reservedUntil.toISOString(),
      });
    if (insErr) {
      console.error('order insert failed (code):', insErr?.code ?? 'unknown');
      return Response.json({ error: 'checkout_failed' }, { status: 500 });
    }
  }

  return Response.json({ checkout_url: session.url, order_id: orderId });
}));

/// going + non-expired-pending count against capacity, the single shared
/// decision. Pending orders whose reserved_until has lapsed do not count
/// (they're swept / released on expiry).
async function precheckCapacity(
  service: ReturnType<typeof createClient>,
  eventId: string,
  instanceStart: string,
  capacity: number | null,
): Promise<'available' | 'full'> {
  if (capacity === null) return 'available';

  const { count: goingCount } = await service
    .from('event_attendees')
    .select('event_id', { count: 'exact', head: true })
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .eq('status', 'going');

  const { count: pendingCount } = await service
    .from('event_orders')
    .select('id', { count: 'exact', head: true })
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .eq('status', 'pending')
    .gt('reserved_until', new Date().toISOString());

  return capacityDecision(goingCount ?? 0, pendingCount ?? 0, capacity);
}
