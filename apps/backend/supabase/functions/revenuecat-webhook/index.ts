/// RevenueCat server-to-server webhook receiver.
///
/// RevenueCat fires events for INITIAL_PURCHASE, RENEWAL,
/// CANCELLATION, EXPIRATION, and more. We care about the transition
/// between "has an active entitlement" and "doesn't", and map that to
/// `user_profiles.subscription_tier`.
///
/// Auth: the webhook request is verified via HMAC (the shared secret is
/// the REVENUECAT_WEBHOOK_SECRET env var). The function runs with the
/// Supabase service role so it can update any user's tier.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { hmac } from 'https://deno.land/x/hmac@v2.0.1/mod.ts';
import { enforceBodyLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';

serve(withSentry('revenuecat-webhook', async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // RevenueCat webhook payloads are typically 2-4 KB. 32 KB is a
  // generous ceiling that still rejects anything pathological before
  // we run the HMAC over it.
  const tooBig = enforceBodyLimit(req, 32 * 1024);
  if (tooBig) return tooBig;

  const secret = Deno.env.get('REVENUECAT_WEBHOOK_SECRET');
  if (!secret) {
    return new Response('Webhook not configured', { status: 503 });
  }

  // Verify HMAC signature with a constant-time compare so an attacker
  // can't tease the digest out one byte at a time via response-timing
  // (low practical risk over a network, but free to do correctly).
  const body = await req.text();
  const sig = req.headers.get('x-revenuecat-hmac');
  if (!sig) {
    return new Response('Missing signature', { status: 401 });
  }
  const expected = hmac('sha256', secret, body, 'utf8', 'hex');
  if (!timingSafeEqual(sig, expected)) {
    return new Response('Bad signature', { status: 401 });
  }

  let event: RevenueCatEvent;
  try {
    event = JSON.parse(body).event;
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  // Replay protection. HMAC authenticates the body but nothing
  // sequences requests, so a captured POST can be replayed at any
  // future time. Two gates:
  //   1. Freshness — reject events whose event_timestamp_ms is more
  //      than REPLAY_WINDOW_MS old or more than CLOCK_SKEW_MS in the
  //      future. Catches captures that have been sitting on a flash
  //      drive.
  //   2. Event-id dedupe — first writer to webhook_events wins; a
  //      duplicate insert (23505 unique_violation) means we've
  //      already processed this delivery, so skip the side effect
  //      and return 200 so RevenueCat doesn't keep retrying.
  //
  // The freshness window must be wider than RC's retry envelope
  // (~3 days of exponential backoff while the original
  // event_timestamp_ms is preserved on retry) AND narrower than the
  // dedupe-row TTL (30 days, set by the cleanup-stale-webhook-events
  // cron in 20260623_001). 7 days threads both: a delivery that
  // failed for ~6 days of cold-start outage still ingests cleanly,
  // and an attacker can't replay a captured event past the dedupe
  // table's pruning horizon. Without the dedupe table this would
  // need to be much tighter; with it, the window only has to bound
  // the replay-after-prune window. CLOCK_SKEW_MS handles a future-
  // dated event_timestamp_ms from clock drift.
  const REPLAY_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
  const CLOCK_SKEW_MS = 60 * 1000;
  const eventTsMs = typeof event.event_timestamp_ms === 'number'
    ? event.event_timestamp_ms
    : null;
  if (eventTsMs === null) {
    return new Response('Missing event_timestamp_ms', { status: 400 });
  }
  const ageMs = Date.now() - eventTsMs;
  if (ageMs > REPLAY_WINDOW_MS || ageMs < -CLOCK_SKEW_MS) {
    return new Response('Event outside freshness window', { status: 400 });
  }
  const eventId = typeof event.id === 'string' ? event.id : null;
  if (!eventId) {
    return new Response('Missing event id', { status: 400 });
  }

  // The `app_user_id` RevenueCat sends is the Supabase user id — we
  // set it on the client when configuring the RevenueCat SDK.
  const userId = event.app_user_id;
  if (!userId || (typeof userId === 'string' && userId.startsWith('$RCAnonymousID'))) {
    // Anonymous users can't map to a Supabase profile. This happens
    // when someone subscribes before signing in; RevenueCat will fire
    // another event when they log in and the alias resolves.
    return Response.json({ ok: true, skipped: 'anonymous_user' });
  }
  // RevenueCat won't normally send a malformed app_user_id, but if a
  // misconfiguration ships their Customer-ID format here it would
  // become a Postgres `22P02 invalid_input_syntax` on the .eq lookup
  // below and bounce as a 500, sending RC into retry storms. Validate
  // the UUID shape and skip cleanly so RC stops retrying.
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (typeof userId !== 'string' || !UUID_RE.test(userId)) {
    return Response.json({ ok: true, skipped: 'invalid_app_user_id' });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Reserve the event-id row before doing any tier work. The unique
  // constraint on (provider, event_id) means a replayed delivery
  // raises 23505 which we map to a 200 (RevenueCat retries on
  // non-2xx). Insert-first means the side effect can't run twice
  // even if the function crashes between the insert and the update —
  // the worst case is a missed update, which RC's next renewal/state
  // event corrects.
  const { error: dedupeErr } = await supabase
    .from('webhook_events')
    .insert({ provider: 'revenuecat', event_id: eventId });
  if (dedupeErr) {
    if (dedupeErr.code === '23505') {
      return Response.json({ ok: true, skipped: 'duplicate_event' });
    }
    console.error('Webhook dedupe insert failed:', dedupeErr);
    return Response.json({ ok: false, error: 'dedupe failed' }, { status: 500 });
  }

  // Map event type to a tier change. RevenueCat's event taxonomy:
  // https://www.revenuecat.com/docs/integrations/webhooks/event-types
  const activating = [
    'INITIAL_PURCHASE',
    'RENEWAL',
    'UNCANCELLATION',
    'NON_RENEWING_PURCHASE',
    'PRODUCT_CHANGE',
  ];
  const deactivating = [
    'EXPIRATION',
    'CANCELLATION',  // at the end of the billing period
  ];

  let newTier: string | null = null;

  if (activating.includes(event.type)) {
    // A non-renewing purchase with a product-id containing "lifetime"
    // maps to the `lifetime` tier rather than `pro`. Everything else
    // is monthly/annual → `pro`.
    const productId = event.product_id ?? '';
    newTier = productId.includes('lifetime') ? 'lifetime' : 'pro';
  } else if (deactivating.includes(event.type)) {
    // Only downgrade to `free` if the user doesn't have `lifetime`.
    // A lifetime holder might also have had a monthly sub for another
    // entitlement; cancelling that shouldn't reset them.
    const { data } = await supabase
      .from('user_profiles')
      .select('subscription_tier')
      .eq('id', userId)
      .single();
    if (data?.subscription_tier !== 'lifetime') {
      newTier = 'free';
    }
  }

  if (newTier !== null) {
    const { error } = await supabase
      .from('user_profiles')
      .update({ subscription_tier: newTier })
      .eq('id', userId);
    if (error) {
      console.error('Tier update failed:', error);
      return Response.json({ ok: false, error: 'tier update failed' }, { status: 500 });
    }
  }

  return Response.json({ ok: true, new_tier: newTier });
}));

interface RevenueCatEvent {
  type: string;
  app_user_id: string;
  product_id?: string;
  id?: string;
  event_timestamp_ms?: number;
  [key: string]: unknown;
}

/// Constant-time string compare. Returns false on length mismatch
/// without short-circuiting on content. The length check itself is
/// observable, but the digest length is fixed (sha256 hex = 64 chars)
/// and known to anyone reading this source — no new information.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}
