/// Run with `cd apps/backend && deno test supabase/functions/events-checkout/lib.test.ts`.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildCheckoutSessionParams,
  capacityDecision,
  checkoutIdempotencyKey,
  computeApplicationFeeCents,
  isSalesWindowOpen,
  reservationExpiry,
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

Deno.test('checkoutIdempotencyKey — deterministic for same inputs', () => {
  const a = checkoutIdempotencyKey('buyer1', 'event1', '2026-06-11T18:00:00Z');
  const b = checkoutIdempotencyKey('buyer1', 'event1', '2026-06-11T18:00:00Z');
  assertStrictEquals(a, b);
});

Deno.test('checkoutIdempotencyKey — differs by buyer / event / instance', () => {
  const base = checkoutIdempotencyKey('buyer1', 'event1', '2026-06-11T18:00:00Z');
  assertStrictEquals(base === checkoutIdempotencyKey('buyer2', 'event1', '2026-06-11T18:00:00Z'), false);
  assertStrictEquals(base === checkoutIdempotencyKey('buyer1', 'event2', '2026-06-11T18:00:00Z'), false);
  assertStrictEquals(base === checkoutIdempotencyKey('buyer1', 'event1', '2026-06-18T18:00:00Z'), false);
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
