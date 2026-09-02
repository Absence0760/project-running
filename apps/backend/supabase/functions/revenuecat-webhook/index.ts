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

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database, DbClient, TablesUpdate } from '../_shared/database.ts';
import { readTextWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { isValidUuid } from '../_shared/input_validation.ts';
import {
  hmacHex,
  isAnonymousAppUserId,
  shouldReleaseDedupe,
  timingSafeEqual,
  validateFreshness,
} from '../_shared/webhook_security.ts';
import {
  ACTIVATING_EVENTS,
  DEACTIVATING_EVENTS,
  mapEventToBillingIssue,
  mapEventToTier,
  tierEventGuardFilter,
} from './lib.ts';
import { secretKey } from '../_shared/api_keys.ts';

Deno.serve(withSentry('revenuecat-webhook', async (req: Request) => {
  if (req.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  // RevenueCat webhook payloads are typically 2-4 KB. 32 KB is a
  // generous ceiling that still rejects anything pathological before
  // we run the HMAC over it. The streamed reader closes the chunked-
  // transfer-encoding bypass that the bare header check left open.
  const guarded = await readTextWithLimit(req, 32 * 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;
  const body = guarded.text;

  const secret = Deno.env.get('REVENUECAT_WEBHOOK_SECRET');
  if (!secret) {
    return Response.json({ error: 'webhook_not_configured' }, { status: 503 });
  }

  // Verify HMAC signature with a constant-time compare so an attacker
  // can't tease the digest out one byte at a time via response-timing
  // (low practical risk over a network, but free to do correctly).
  const sig = req.headers.get('x-revenuecat-hmac');
  if (!sig) {
    return Response.json({ error: 'missing_signature' }, { status: 401 });
  }
  const expected = await hmacHex(secret, body);
  if (!timingSafeEqual(sig, expected)) {
    return Response.json({ error: 'bad_signature' }, { status: 401 });
  }

  let event: RevenueCatEvent;
  try {
    event = JSON.parse(body).event;
  } catch {
    return Response.json({ error: 'invalid_json' }, { status: 400 });
  }
  // A body that parses but carries no `event` object is not a 500. `{}`
  // parses fine and leaves `event` undefined, and the first field read below
  // then threw a TypeError past the handler into withSentry's 500 — which
  // RevenueCat treats as a delivery failure and retries for three days, on a
  // payload that can never succeed.
  if (typeof event !== 'object' || event === null) {
    return Response.json({ error: 'missing_event' }, { status: 400 });
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

  const supabase = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    secretKey(),
  );

  // Reserve the event-id row before doing any tier work. The unique
  // constraint on (provider, event_id) means a replayed delivery
  // raises 23505 which we map to a 200 (RevenueCat retries on
  // non-2xx). Insert-first means the side effect can't run twice even
  // if the function crashes between the insert and the update; the
  // release below is what keeps that from also meaning it can never
  // run at all.
  const { error: dedupeErr } = await supabase
    .from('webhook_events')
    .insert({ provider: 'revenuecat', event_id: eventId });
  if (dedupeErr) {
    if (dedupeErr.code === '23505') {
      return Response.json({ ok: true, skipped: 'duplicate_event' });
    }
    // Log the SQLSTATE code only — a PostgREST `.message` (and the
    // `details`/`hint` it travels with) can echo row values into the
    // shared function-log aggregator. /audit/all edge-functions
    // 2026-05-30 Low.
    console.error('Webhook dedupe insert failed (code):', dedupeErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'dedupe_failed' }, { status: 500 });
  }

  // Apply behind a dedupe release. The dedupe row is written BEFORE the tier
  // work (so two concurrent deliveries of one event can't both act), which
  // means an application that fails owes the row back: RevenueCat retries on a
  // non-2xx, and the retry would hit the 23505 path above, answer 200
  // 'duplicate_event', and close the delivery for good. "The next renewal
  // corrects it" was the reasoning for not doing this, and it does not hold for
  // a NON_RENEWING_PURCHASE: a lifetime buyer has no later event, so a single
  // transient failure on the profile write leaves them paid-up and on `free`
  // permanently. stripe-events-webhook and strava-webhook both give the row
  // back for the same reason.
  let res: Response;
  try {
    res = await applyRevenueCatEvent(supabase, event, userId, eventTsMs);
  } catch (err) {
    await releaseDedupe(supabase, eventId);
    throw err;
  }
  if (shouldReleaseDedupe(res.status)) {
    await releaseDedupe(supabase, eventId);
  }
  return res;
}));

/// Give back the insert-first dedupe row so RevenueCat's retry is processed
/// instead of being swallowed as a duplicate. Best-effort: if this fails the
/// event is stuck either way, and logging is all we can usefully do.
async function releaseDedupe(supabase: DbClient, eventId: string): Promise<void> {
  const { error } = await supabase
    .from('webhook_events')
    .delete()
    .eq('provider', 'revenuecat')
    .eq('event_id', eventId);
  if (error) {
    console.error('failed to release dedupe row before retry (code):', error?.code ?? 'unknown');
  }
}

async function applyRevenueCatEvent(
  supabase: DbClient,
  event: RevenueCatEvent,
  userId: string,
  eventTsMs: number,
): Promise<Response> {
  // Resolve the user's current tier so the tier mapper can avoid demoting a
  // `lifetime` holder — for EVERY event that can move the tier, not only the
  // deactivating ones and PRODUCT_CHANGE. "Other activating events always
  // grant at least pro" was the reasoning for skipping the read, and it is
  // wrong in one direction: lifetime outranks pro. A lifetime owner carrying
  // a parallel monthly sub gets a RENEWAL on that sub every month, and each
  // one reached `mapEventToTier` with `currentTier: null`, wrote `pro` over
  // `lifetime`, and made the guard in the mapper unreachable for four of the
  // five activating types. The monthly's eventual EXPIRATION then read `pro`
  // and finished the job at `free`.
  let currentTier: string | null = null;
  if (
    (DEACTIVATING_EVENTS as readonly string[]).includes(event.type) ||
    (ACTIVATING_EVENTS as readonly string[]).includes(event.type)
  ) {
    const { data } = await supabase
      .from('user_profiles')
      .select('subscription_tier')
      .eq('id', userId)
      .single();
    currentTier = data?.subscription_tier ?? null;
  }

  const newTier = mapEventToTier(event.type, event.product_id ?? null, currentTier);
  const billingIssueAt = mapEventToBillingIssue(event.type);

  // Build the patch — at most one round trip per webhook. Tier and
  // billing flag are decoupled (BILLING_ISSUE writes the flag without
  // touching tier; RENEWAL / EXPIRATION write both). `undefined` means
  // "this event doesn't move that field".
  //
  // A tier change also stamps `tier_updated_event_ts` and gates the write
  // on it: RevenueCat can deliver events out of order, and the event-id
  // dedupe only stops replays of the same event — so without this an old
  // EXPIRATION arriving after a newer re-subscribe would map to 'free' and
  // silently downgrade a paying user. The conditional UPDATE applies the
  // change only when this event is at least as recent as the one that last
  // moved the tier; a stale deactivation matches zero rows atomically (no
  // read-then-write race) and the tier is left as-is. A billing-issue-only
  // write stays unconditional — it doesn't move the tier dimension.
  const patch: TablesUpdate<'user_profiles'> = {};
  if (newTier !== null) {
    patch.subscription_tier = newTier;
    patch.tier_updated_event_ts = eventTsMs;
  }
  if (billingIssueAt !== undefined) patch.billing_issue_at = billingIssueAt;

  if (Object.keys(patch).length > 0) {
    let query = supabase
      .from('user_profiles')
      .update(patch)
      .eq('id', userId);
    if (newTier !== null) {
      query = query.or(tierEventGuardFilter(eventTsMs));
    }
    const { error } = await query;
    if (error) {
      console.error('user_profiles patch failed (code):', error?.code ?? 'unknown');
      return Response.json({ ok: false, error: 'profile update failed' }, { status: 500 });
    }
  }

  return Response.json({
    ok: true,
    new_tier: newTier,
    billing_issue_at: billingIssueAt ?? undefined,
  });
}


interface RevenueCatEvent {
  type: string;
  app_user_id: string;
  product_id?: string;
  id?: string;
  event_timestamp_ms?: number;
  [key: string]: unknown;
}

