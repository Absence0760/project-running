/// The soft-reservation hold and the two values Stripe's idempotency contract
/// is joint over: the key and the whole request body.
///
/// § 776's defect was not that the key was absent — it was that nothing tied
/// the key to the body it is replayed against. Stripe rejects a reused key
/// carrying a changed body with `idempotency_error` and never replays it, so
/// "the key is stable" and "the body is stable" are one property and have to be
/// asserted together. Every case below therefore compares a whole params object
/// built twice, not just the key.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/events-checkout/hold_invariants.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildCheckoutSessionParams,
  capacityDecision,
  checkoutExpiresAtUnix,
  checkoutIdempotencyKey,
  computeApplicationFeeCents,
  isSalesWindowOpen,
  type PendingOrderRow,
  reservationExpiry,
  resolveHold,
} from './lib.ts';

const MIN = 60_000;
const NOW = Date.parse('2026-06-01T10:00:00Z');

const order = (over: Partial<PendingOrderRow> = {}): PendingOrderRow => ({
  id: 'ord_1',
  created_at: new Date(NOW - 5 * MIN).toISOString(),
  reserved_until: new Date(NOW + 10 * MIN).toISOString(),
  stripe_checkout_session_id: 'cs_1',
  ...over,
});

/// The whole request body a hold would produce, so a comparison is over
/// everything Stripe joins the key to rather than over the key alone.
function bodyFor(orderId: string, anchorMs: number) {
  return {
    key: checkoutIdempotencyKey(orderId),
    params: buildCheckoutSessionParams({
      amountCents: 5000,
      currency: 'usd',
      productName: 'Hill reps',
      applicationFeeCents: 125,
      hostAccountId: 'acct_1',
      successUrl: 'https://threkir.com/ok',
      cancelUrl: 'https://threkir.com/no',
      metadata: {
        event_id: 'e1',
        instance_start: '2026-06-08T10:00:00Z',
        buyer_user_id: 'u1',
        order_id: orderId,
      },
      expiresAtUnix: checkoutExpiresAtUnix(anchorMs),
    }),
  };
}

Deno.test('resolveHold — a reservation is live only STRICTLY in the future', () => {
  // At the boundary the hold has lapsed. Reusing it there would hand Stripe an
  // `expires_at` derived from an order the local reservation no longer covers.
  const at = (reservedUntilMs: number, nowMs: number) =>
    resolveHold(order({ reserved_until: new Date(reservedUntilMs).toISOString() }), nowMs);
  assertEquals(at(NOW + 1, NOW).orderId, 'ord_1');
  assertEquals(at(NOW, NOW).orderId, null, 'exactly at the expiry is lapsed');
  assertEquals(at(NOW - 1, NOW).orderId, null);
});

Deno.test('resolveHold — every unusable reservation supersedes rather than reuses', () => {
  const unusable: Array<string | null> = [
    null,
    '',
    'soon',
    'NaN',
    '2026-13-45T99:99:99Z',
  ];
  for (const reserved of unusable) {
    const plan = resolveHold(order({ reserved_until: reserved }), NOW);
    assertEquals(plan.orderId, null, JSON.stringify(reserved));
    assertEquals(plan.anchorMs, null);
    assertEquals(plan.supersedeSessionId, 'cs_1', 'the stale session must still be expired');
  }
});

Deno.test('resolveHold — a live reservation with an unreadable anchor is superseded, not reused', () => {
  // The anchor is what both the key and `expires_at` are reproduced from. A
  // hold that cannot reproduce them is not a hold that can be replayed, so it
  // must be replaced even though its reservation has not lapsed.
  const plan = resolveHold(order({ created_at: 'not a date' }), NOW);
  assertEquals(plan.orderId, null);
  assertEquals(plan.anchorMs, null);
  assertEquals(plan.supersedeSessionId, 'cs_1');
});

Deno.test('resolveHold — no order at all supersedes nothing', () => {
  assertEquals(resolveHold(null, NOW), {
    orderId: null,
    anchorMs: null,
    supersedeSessionId: null,
  });
});

Deno.test('resolveHold — a lapsed hold that never reached Stripe leaves nothing to expire', () => {
  const plan = resolveHold(
    order({ reserved_until: new Date(NOW - MIN).toISOString(), stripe_checkout_session_id: null }),
    NOW,
  );
  assertEquals(plan.orderId, null);
  assertEquals(plan.supersedeSessionId, null);
});

Deno.test('a double-click anywhere inside the live hold replays the WHOLE body, not just the key', () => {
  // The clock moves between the two clicks and the body must not. Sampling the
  // wall clock anywhere in the params — which is what `expires_at` did before
  // § 776 — turns the second click into an `idempotency_error` rather than a
  // replay, and every retry 502s for the ~24 h Stripe retains the key.
  const row = order();
  const first = resolveHold(row, NOW);
  const second = resolveHold(row, NOW + 9 * MIN);
  assertEquals(first.orderId, 'ord_1');
  assertEquals(second.orderId, 'ord_1');
  assertEquals(first.anchorMs, second.anchorMs);
  assertEquals(
    bodyFor(first.orderId!, first.anchorMs!),
    bodyFor(second.orderId!, second.anchorMs!),
  );
});

Deno.test('a replacement hold shares no part of the superseded one', () => {
  // Reusing the lapsed order's key against a fresh expiry is the same
  // `idempotency_error`, pointing the other way. A new order id is what makes
  // the new key safe.
  const lapsed = order({ reserved_until: new Date(NOW - MIN).toISOString() });
  assertEquals(resolveHold(lapsed, NOW).orderId, null);
  const replacement = bodyFor('ord_2', NOW);
  const superseded = bodyFor(lapsed.id, Date.parse(lapsed.created_at));
  assert(replacement.key !== superseded.key);
  assert(replacement.params.expires_at !== superseded.params.expires_at);
});

Deno.test('checkoutIdempotencyKey — the order id is the whole of the key, namespaced', () => {
  assertEquals(checkoutIdempotencyKey('ord_1'), 'events-checkout:ord_1');
  // Distinct orders never collide, and the same order never differs.
  const keys = new Set(['a', 'b', 'c'].map(checkoutIdempotencyKey));
  assertEquals(keys.size, 3);
  assertEquals(checkoutIdempotencyKey('a'), checkoutIdempotencyKey('a'));
  // The namespace is what stops it colliding with the donation rail's key for
  // an id that happened to be the same uuid.
  assert(checkoutIdempotencyKey('x').startsWith('events-checkout:'));
});

Deno.test('checkoutExpiresAtUnix — anchored on the order and nowhere near the clock', () => {
  const anchor = Date.parse('2026-06-01T10:00:00Z');
  assertEquals(checkoutExpiresAtUnix(anchor), anchor / 1000 + 1800);
  assertEquals(checkoutExpiresAtUnix(anchor, 45), anchor / 1000 + 2700);
  // Sub-second jitter in the anchor must not move the answer, or two reads of
  // the same order could disagree.
  assertEquals(checkoutExpiresAtUnix(anchor + 999), checkoutExpiresAtUnix(anchor));
  // Stripe requires at least 30 minutes ahead at create time, and the default
  // is exactly that measured from the order — not from now.
  assertEquals(checkoutExpiresAtUnix(anchor) - anchor / 1000, 30 * 60);
});

Deno.test('reservationExpiry — 15 minutes by default, and it is shorter than the Stripe session', () => {
  assertEquals(reservationExpiry(NOW).getTime(), NOW + 15 * MIN);
  assertEquals(reservationExpiry(NOW, 5).getTime(), NOW + 5 * MIN);
  // The local hold must lapse FIRST: the webhook's `checkout.session.expired`
  // is what releases the slot definitively, and a local hold outliving the
  // session would keep a seat nothing will ever free.
  assert(reservationExpiry(NOW).getTime() < checkoutExpiresAtUnix(NOW) * 1000);
});

Deno.test('computeApplicationFeeCents — floors, clamps, and never invents a fee', () => {
  assertEquals(computeApplicationFeeCents(5000, 250), 125);
  assertEquals(computeApplicationFeeCents(999, 250), 24, 'floors the fractional cent');
  assertEquals(computeApplicationFeeCents(5000, 0), 0);
  assertEquals(computeApplicationFeeCents(0, 250), 0);
  assertEquals(computeApplicationFeeCents(-100, 250), 0, 'a negative amount earns no fee');
  assertEquals(computeApplicationFeeCents(5000, -250), 0, 'a negative rate is not a rebate');
  assertEquals(computeApplicationFeeCents(5000, 10000), 5000, '100 % is capped at the amount');
  assertEquals(computeApplicationFeeCents(5000, 999999), 5000, 'and so is a misconfiguration');
  // The fee can never exceed the amount at any rate, which is what stops a
  // destination charge being created with a transfer of less than nothing.
  for (const bps of [1, 250, 5000, 9999, 10000, 20000]) {
    assert(computeApplicationFeeCents(5000, bps) <= 5000, `${bps}`);
    assert(computeApplicationFeeCents(5000, bps) >= 0, `${bps}`);
  }
});

Deno.test('capacityDecision — the boundary is the cap itself, and unlimited is only null', () => {
  assertEquals(capacityDecision(0, 0, null), 'available');
  assertEquals(capacityDecision(9999, 9999, null), 'available');
  assertEquals(capacityDecision(0, 0, 0), 'full', 'a capacity of zero sells nothing');
  assertEquals(capacityDecision(9, 0, 10), 'available');
  assertEquals(capacityDecision(10, 0, 10), 'full', 'exactly at the cap is full');
  assertEquals(capacityDecision(11, 0, 10), 'full');
  // A pending soft reservation counts toward the cap; that is the whole of the
  // never-oversell invariant, and dropping the second term is how it breaks.
  assertEquals(capacityDecision(5, 5, 10), 'full');
  assertEquals(capacityDecision(5, 4, 10), 'available');
  assertEquals(capacityDecision(0, 10, 10), 'full');
});

Deno.test('isSalesWindowOpen — closed at the boundary, and a negative offset sells past the start', () => {
  const start = NOW;
  assertEquals(isSalesWindowOpen(start, 0, start - 1), true);
  assertEquals(isSalesWindowOpen(start, 0, start), false, 'a 0-offset class is unbuyable at start');
  assertEquals(isSalesWindowOpen(start, 60, start - 60 * MIN - 1), true);
  assertEquals(isSalesWindowOpen(start, 60, start - 60 * MIN), false);
  assertEquals(isSalesWindowOpen(start, -30, start + 30 * MIN - 1), true, 'late registration');
  assertEquals(isSalesWindowOpen(start, -30, start + 30 * MIN), false);
});

Deno.test('buildCheckoutSessionParams — the exact key set, so a stray param cannot ride along', () => {
  const params = bodyFor('ord_1', NOW).params;
  assertEquals(Object.keys(params).sort(), [
    'cancel_url',
    'expires_at',
    'line_items',
    'metadata',
    'mode',
    'payment_intent_data',
    'success_url',
  ]);
  assertEquals(Object.keys(params.payment_intent_data).sort(), [
    'application_fee_amount',
    'transfer_data',
  ]);
  // `on_behalf_of` is deliberately absent: it makes the host the merchant of
  // record, which moves settlement currency and card-statement identity and is
  // a live sign-off question rather than an oversight (§ 769). Its arrival
  // should be a decision, not a diff nobody reads.
  assert(!('on_behalf_of' in params.payment_intent_data));
  assertEquals(params.mode, 'payment');
  assertEquals(params.payment_intent_data.transfer_data.destination, 'acct_1');
  assertEquals(params.line_items[0].price_data.unit_amount, 5000);
  assertEquals(params.line_items[0].quantity, 1);
});

Deno.test('buildCheckoutSessionParams — the order id reaches the metadata the webhook seats from', () => {
  // `attendeeRowFromSession` requires all four keys, and the webhook is the
  // sole writer of the attendee row. A params builder that dropped one would
  // charge the card and seat nobody.
  const params = bodyFor('ord_9', NOW).params;
  assertEquals(Object.keys(params.metadata).sort(), [
    'buyer_user_id',
    'event_id',
    'instance_start',
    'order_id',
  ]);
  assertEquals(params.metadata.order_id, 'ord_9');
});
