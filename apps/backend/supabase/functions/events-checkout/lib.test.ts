/// Run with `cd apps/backend && deno test supabase/functions/events-checkout/lib.test.ts`.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
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

const HOUR = 60 * 60 * 1000;

Deno.test('isSalesWindowOpen — open well before close', () => {
  const startsAt = 1_000_000_000_000;
  // close offset 60 min; now is 2h before start -> open.
  assertStrictEquals(isSalesWindowOpen(startsAt, 60, startsAt - 2 * HOUR), true);
});

Deno.test('isSalesWindowOpen — closed at/after the close boundary', () => {
  const startsAt = 1_000_000_000_000;
  const closeAt = startsAt - 60 * 60 * 1000; // 60 min before
  assertStrictEquals(isSalesWindowOpen(startsAt, 60, closeAt), false); // exactly at boundary
  assertStrictEquals(isSalesWindowOpen(startsAt, 60, closeAt + 1), false); // past boundary
});

Deno.test('isSalesWindowOpen — zero offset closes exactly at start', () => {
  const startsAt = 1_000_000_000_000;
  assertStrictEquals(isSalesWindowOpen(startsAt, 0, startsAt - 1), true);
  assertStrictEquals(isSalesWindowOpen(startsAt, 0, startsAt), false);
});

Deno.test('computeApplicationFeeCents — floors the fractional cent', () => {
  // 2.5% of 2200 = 55 exactly.
  assertEquals(computeApplicationFeeCents(2200, 250), 55);
  // 2.9% of 999 = 28.971 -> floor 28.
  assertEquals(computeApplicationFeeCents(999, 290), 28);
});

Deno.test('computeApplicationFeeCents — 0 bps -> 0', () => {
  assertEquals(computeApplicationFeeCents(2200, 0), 0);
});

Deno.test('computeApplicationFeeCents — never exceeds the amount', () => {
  // 10000 bps = 100% -> equals amount, never above.
  assertEquals(computeApplicationFeeCents(2200, 10000), 2200);
  // Degenerate non-positive amount -> 0.
  assertEquals(computeApplicationFeeCents(0, 250), 0);
});

Deno.test('reservationExpiry — now + 15 min default', () => {
  const now = 1_700_000_000_000;
  assertEquals(reservationExpiry(now).getTime(), now + 15 * 60 * 1000);
  assertEquals(reservationExpiry(now, 30).getTime(), now + 30 * 60 * 1000);
});

Deno.test('capacityDecision — null capacity is always available (unlimited)', () => {
  assertEquals(capacityDecision(1000, 1000, null), 'available');
});

Deno.test('capacityDecision — going + pending below cap -> available', () => {
  assertEquals(capacityDecision(8, 1, 10), 'available');
});

Deno.test('capacityDecision — going + pending at/over cap -> full', () => {
  assertEquals(capacityDecision(9, 1, 10), 'full'); // exactly at cap
  assertEquals(capacityDecision(10, 0, 10), 'full');
  assertEquals(capacityDecision(7, 5, 10), 'full'); // over cap
});

Deno.test('checkoutIdempotencyKey — keyed on the order, one key per hold', () => {
  assertStrictEquals(checkoutIdempotencyKey('order1'), 'events-checkout:order1');
  assertStrictEquals(checkoutIdempotencyKey('order1'), checkoutIdempotencyKey('order1'));
  assertStrictEquals(checkoutIdempotencyKey('order1') === checkoutIdempotencyKey('order2'), false);
});

Deno.test('checkoutExpiresAtUnix — anchored on the order, never on the clock', () => {
  const createdAtMs = Date.parse('2026-06-11T17:00:00.000Z');
  assertEquals(checkoutExpiresAtUnix(createdAtMs), createdAtMs / 1000 + 30 * 60);
  // The same order read again eight minutes later derives the same value —
  // this is the property the reused idempotency key depends on.
  assertEquals(checkoutExpiresAtUnix(createdAtMs), checkoutExpiresAtUnix(createdAtMs));
  assertEquals(checkoutExpiresAtUnix(createdAtMs, 45), createdAtMs / 1000 + 45 * 60);
});

Deno.test('buildCheckoutSessionParams — destination charge + fee + expires + metadata present', () => {
  const params = buildCheckoutSessionParams({
    amountCents: 2200,
    currency: 'usd',
    productName: 'Reformer Pilates',
    applicationFeeCents: 55,
    hostAccountId: 'acct_host',
    successUrl: 'https://app.example.com/clubs?checkout=success',
    cancelUrl: 'https://app.example.com/clubs?checkout=cancel',
    metadata: {
      event_id: 'e1',
      instance_start: '2026-06-11T18:00:00Z',
      buyer_user_id: 'b1',
      order_id: 'o1',
    },
    expiresAtUnix: 1_700_000_900,
  });
  assertEquals(params.mode, 'payment');
  assertEquals(params.payment_intent_data.transfer_data.destination, 'acct_host');
  assertEquals(params.payment_intent_data.application_fee_amount, 55);
  assertEquals(params.expires_at, 1_700_000_900);
  assertEquals(params.line_items[0].price_data.unit_amount, 2200);
  assertEquals(params.line_items[0].price_data.currency, 'usd');
  assertEquals(params.line_items[0].price_data.product_data.name, 'Reformer Pilates');
  assertEquals(params.metadata.event_id, 'e1');
  assertEquals(params.metadata.instance_start, '2026-06-11T18:00:00Z');
  assertEquals(params.metadata.buyer_user_id, 'b1');
  assertEquals(params.metadata.order_id, 'o1');
});

const HOLD: PendingOrderRow = {
  id: 'order-1',
  created_at: '2026-06-11T17:00:00.000Z',
  reserved_until: '2026-06-11T17:15:00.000Z',
  stripe_checkout_session_id: 'cs_first',
};
const HOLD_CREATED_MS = Date.parse(HOLD.created_at);

Deno.test('resolveHold — no pending order opens a fresh hold', () => {
  assertEquals(resolveHold(null, HOLD_CREATED_MS), {
    orderId: null,
    anchorMs: null,
    supersedeSessionId: null,
  });
});

Deno.test('resolveHold — a live reservation is reused, anchored on its creation', () => {
  assertEquals(resolveHold(HOLD, HOLD_CREATED_MS + 8 * 60 * 1000), {
    orderId: 'order-1',
    anchorMs: HOLD_CREATED_MS,
    supersedeSessionId: null,
  });
});

Deno.test('resolveHold — a lapsed reservation is superseded, not reused', () => {
  // Its Checkout Session stays payable ~15 min after the seat was released,
  // so opening a replacement alongside it would let one buyer be charged
  // twice for one registration. It is expired at Stripe first.
  assertEquals(resolveHold(HOLD, HOLD_CREATED_MS + 20 * 60 * 1000), {
    orderId: null,
    anchorMs: null,
    supersedeSessionId: 'cs_first',
  });
});

Deno.test('resolveHold — an unparseable or absent reservation is never treated as live', () => {
  assertEquals(
    resolveHold({ ...HOLD, reserved_until: null }, HOLD_CREATED_MS).orderId,
    null,
  );
  assertEquals(
    resolveHold({ ...HOLD, reserved_until: 'whenever' }, HOLD_CREATED_MS).orderId,
    null,
  );
});

/// The invariant the 502-for-24-hours bug violated: Stripe's idempotency is
/// JOINT — a key replayed with a body that has moved is answered with
/// `idempotency_error`, not with the original session, and the key is held
/// for ~24 h. So every attempt that reuses a key must reproduce the request
/// byte for byte. Composing the helpers the way index.ts does is the only
/// place that property is visible, so it is asserted here.
function attempt(order: PendingOrderRow | null, nowMs: number) {
  const hold = resolveHold(order, nowMs);
  const orderId = hold.orderId ?? 'freshly-minted-uuid';
  const anchorMs = hold.anchorMs ?? nowMs;
  return {
    key: checkoutIdempotencyKey(orderId),
    body: buildCheckoutSessionParams({
      amountCents: 2200,
      currency: 'usd',
      productName: 'Reformer Pilates',
      applicationFeeCents: 55,
      hostAccountId: 'acct_host',
      successUrl: 'https://app.example.com/clubs?checkout=success',
      cancelUrl: 'https://app.example.com/clubs?checkout=cancel',
      metadata: {
        event_id: 'e1',
        instance_start: '2026-06-11T18:00:00Z',
        buyer_user_id: 'b1',
        order_id: orderId,
      },
      expiresAtUnix: checkoutExpiresAtUnix(anchorMs),
    }),
  };
}

Deno.test('a double-click inside the live hold replays byte-identically', () => {
  const first = attempt(HOLD, HOLD_CREATED_MS + 1_000);
  const second = attempt(HOLD, HOLD_CREATED_MS + 8 * 60 * 1000);
  assertStrictEquals(first.key, second.key);
  assertEquals(
    JSON.stringify(first.body),
    JSON.stringify(second.body),
    'same idempotency key with a different body is an idempotency_error at ' +
      'Stripe, not a replay — the second attempt would 502 for ~24 h',
  );
});

Deno.test('a replacement hold never reuses the superseded hold\'s key', () => {
  const inHold = attempt(HOLD, HOLD_CREATED_MS + 60_000);
  const afterLapse = attempt(HOLD, HOLD_CREATED_MS + 20 * 60 * 1000);
  assertStrictEquals(inHold.key === afterLapse.key, false);
  assertStrictEquals(afterLapse.body.metadata.order_id === 'order-1', false);
});
