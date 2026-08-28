/// Run with `cd apps/backend && deno test supabase/functions/events-cancel/lib.test.ts`.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { buildRefundParams, cancelAction, resolveRefundEligibility } from './lib.ts';

const HOUR = 60 * 60 * 1000;
const START = Date.parse('2026-07-01T18:00:00Z');
const START_ISO = '2026-07-01T18:00:00Z';

Deno.test('resolveRefundEligibility — no_refund is never eligible', () => {
  // Even well before the start.
  assertEquals(resolveRefundEligibility('no_refund', START - 10 * HOUR, START_ISO), {
    eligible: false,
    fullRefund: false,
  });
});

Deno.test('resolveRefundEligibility — full_until_start eligible before start, not after', () => {
  assertEquals(resolveRefundEligibility('full_until_start', START - 1, START_ISO), {
    eligible: true,
    fullRefund: true,
  });
  // Exactly at start -> not eligible (now < cutoff is strict).
  assertEquals(resolveRefundEligibility('full_until_start', START, START_ISO), {
    eligible: false,
    fullRefund: false,
  });
  assertEquals(resolveRefundEligibility('full_until_start', START + 1, START_ISO), {
    eligible: false,
    fullRefund: false,
  });
});

Deno.test('resolveRefundEligibility — full_until_24h cutoff is 24h before start', () => {
  const cutoff = START - 24 * HOUR;
  assertStrictEquals(
    resolveRefundEligibility('full_until_24h', cutoff - 1, START_ISO).eligible,
    true,
  );
  // Exactly at the 24h boundary -> not eligible.
  assertStrictEquals(
    resolveRefundEligibility('full_until_24h', cutoff, START_ISO).eligible,
    false,
  );
  // 12h before start (inside the no-refund window) -> not eligible.
  assertStrictEquals(
    resolveRefundEligibility('full_until_24h', START - 12 * HOUR, START_ISO).eligible,
    false,
  );
});

Deno.test('resolveRefundEligibility — unparseable instance start fails closed', () => {
  assertEquals(resolveRefundEligibility('full_until_start', START, 'not-a-date'), {
    eligible: false,
    fullRefund: false,
  });
});

Deno.test('resolveRefundEligibility — unknown policy fails closed', () => {
  assertEquals(
    resolveRefundEligibility('weird' as never, START - 10 * HOUR, START_ISO),
    { eligible: false, fullRefund: false },
  );
});

Deno.test('cancelAction — pending always releases the reservation (no charge)', () => {
  assertStrictEquals(cancelAction('pending', false), 'release_reservation');
  assertStrictEquals(cancelAction('pending', true), 'release_reservation');
});

Deno.test('cancelAction — paid + eligible refunds, paid + not eligible is policy_no_refund', () => {
  assertStrictEquals(cancelAction('paid', true), 'refund');
  assertStrictEquals(cancelAction('paid', false), 'policy_no_refund');
});

Deno.test('cancelAction — terminal statuses no-op', () => {
  // `partially_refunded` is deliberately NOT in this list: it is a held seat,
  // not a finished order. See the test below.
  for (const s of ['refunded', 'canceled', 'failed']) {
    assertStrictEquals(cancelAction(s, true), 'noop');
    assertStrictEquals(cancelAction(s, false), 'noop');
  }
});

Deno.test('cancelAction — a partially-refunded order decides exactly as a paid one', () => {
  // The buyer kept the seat when part of the money came back, so they must
  // still be able to give it up. Reading this as terminal made the whole
  // cancel path a silent no-op for such an order: index.ts already selects it,
  // the 20270522_001 buyer policy already admits it, and the web toast reports
  // "reservation released" on the `noop` it got back — while no refund is
  // created and the seat is never released. decisions § 769.
  assertStrictEquals(cancelAction('partially_refunded', true), 'refund');
  assertStrictEquals(cancelAction('partially_refunded', false), 'policy_no_refund');
  // Same answer as `paid` for both eligibilities — that identity is the point.
  assertStrictEquals(
    cancelAction('partially_refunded', true),
    cancelAction('paid', true),
  );
  assertStrictEquals(
    cancelAction('partially_refunded', false),
    cancelAction('paid', false),
  );
});

Deno.test('buildRefundParams — a destination-charge refund reverses the transfer', () => {
  // Stripe: "by default the destination account keeps the funds that were
  // transferred to it, leaving the platform account to cover the negative
  // balance from the refund", and "If you refund the application fee for a
  // destination charge, you must also reverse the transfer." Sending
  // refund_application_fee alone — which this call did — pays the host our fee
  // ON TOP of the ticket they keep, so the platform funds the whole
  // cancellation twice over. decisions § 769.
  assertEquals(buildRefundParams('pi_123'), {
    payment_intent: 'pi_123',
    refund_application_fee: true,
    reverse_transfer: true,
  });
});

Deno.test('buildRefundParams — sends no amount, so Stripe refunds what is still owed', () => {
  // The whole remaining unrefunded balance: the entire ticket for a `paid`
  // order, and only the outstanding part for a `partially_refunded` one. An
  // explicit amount would over-refund the second (Stripe errors) or would have
  // to be reconstructed from a ledger this EF does not hold.
  assertStrictEquals('amount' in buildRefundParams('pi_123'), false);
});
