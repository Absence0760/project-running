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
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.105.1';
import { hmac } from 'https://deno.land/x/hmac@v2.0.1/mod.ts';
import { enforceBodyLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import {
  isAnonymousAppUserId,
  isValidUuid,
  timingSafeEqual,
  validateFreshness,
} from '../_shared/webhook_security.ts';
import {
  DEACTIVATING_EVENTS,
  mapEventToTier,
} from './lib.ts';

serve(withSentry('revenuecat-webhook', async (req: Request) => {
  if (req.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  // RevenueCat webhook payloads are typically 2-4 KB. 32 KB is a
  // generous ceiling that still rejects anything pathological before
  // we run the HMAC over it.
  const tooBig = enforceBodyLimit(req, 32 * 1024);
  if (tooBig) return tooBig;

  const secret = Deno.env.get('REVENUECAT_WEBHOOK_SECRET');
  if (!secret) {
    return Response.json({ error: 'webhook_not_configured' }, { status: 503 });
  }

  // Verify HMAC signature with a constant-time compare so an attacker
  // can't tease the digest out one byte at a time via response-timing
  // (low practical risk over a network, but free to do correctly).
  const body = await req.text();
  const sig = req.headers.get('x-revenuecat-hmac');
  if (!sig) {
    return Response.json({ error: 'missing_signature' }, { status: 401 });
  }
  const expected = hmac('sha256', secret, body, 'utf8', 'hex');
  if (!timingSafeEqual(sig, expected)) {
    return Response.json({ error: 'bad_signature' }, { status: 401 });
  }

  let event: RevenueCatEvent;
  try {
    event = JSON.parse(body).event;
  } catch {
    return Response.json({ error: 'invalid_json' }, { status: 400 });
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
  const eventTsMs = typeof event.event_timestamp_ms === 'number'
    ? event.event_timestamp_ms
    : null;
  if (eventTsMs === null) {
    return Response.json({ error: 'missing_event_timestamp_ms' }, { status: 400 });
  }
  if (validateFreshness(eventTsMs, Date.now()) !== 'ok') {
    return Response.json({ error: 'event_outside_freshness_window' }, { status: 400 });
  }
  const eventId = typeof event.id === 'string' ? event.id : null;
  if (!eventId) {
    return Response.json({ error: 'missing_event_id' }, { status: 400 });
  }

  // The `app_user_id` RevenueCat sends is the Supabase user id — we
  // set it on the client when configuring the RevenueCat SDK.
  const userId = event.app_user_id;
  if (!userId || isAnonymousAppUserId(userId)) {
    return Response.json({ ok: true, skipped: 'anonymous_user' });
  }
  if (!isValidUuid(userId)) {
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

  // Resolve the user's current tier so the deactivating-event branch
  // can avoid demoting a `lifetime` holder. We look it up only when
  // the event is deactivating; activating events don't need it.
  let currentTier: string | null = null;
  if ((DEACTIVATING_EVENTS as readonly string[]).includes(event.type)) {
    const { data } = await supabase
      .from('user_profiles')
      .select('subscription_tier')
      .eq('id', userId)
      .single();
    currentTier = (data?.subscription_tier as string | null) ?? null;
  }

  const newTier = mapEventToTier(event.type, event.product_id ?? null, currentTier);

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

