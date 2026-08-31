/// The two ledgers, stated as WHOLE tables rather than as a sample of arms.
///
/// Every test beside this one names one transition. That leaves the shape of
/// the defect these tables exist to prevent invisible: an ARM NOBODY ASKED FOR.
/// A `paid + charge.refunded -> refunded` case cannot see a stray
/// `failed + charge.refunded -> refunded` sitting next to it, and on the sole
/// writer of `event_orders.status` a stray arm is a seat released, a waitlist
/// promoted, and money moved. So both tables are enumerated over the full cross
/// product of (status x event x refund scope) and compared against a literal
/// map: a new arm fails as an unexpected transition, a deleted arm fails as a
/// missing one.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/stripe-events-webhook/ledger_invariants.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  type Charge,
  type DonationStatus,
  donationStatusTransition,
  type OrderStatus,
  orderStatusTransition,
  type RefundScope,
  refundedCentsOfCharge,
  refundReversed,
  refundScopeOfCharge,
  shouldReleaseDedupe,
  STRIPE_EVENT,
} from './lib.ts';

/// Every status either ledger's CHECK constraint can hold, plus two values
/// neither can. The impossible pair is deliberate: `orderStatusTransition`
/// takes a bare `string`, so the ledger's guarantee is only worth what the
/// function does with a value the database never wrote, and "nothing" is the
/// only safe answer.
const ALL_STATUSES = [
  'pending',
  'paid',
  'partially_refunded',
  'refunded',
  'refund_failed',
  'failed',
  'canceled',
  '',
  'Paid',
] as const;

/// Every event type the dispatcher spells, plus three it never will. The
/// deprecated `charge.refund.updated` and the general `refund.updated` are in
/// the list on purpose: they reach the transition tables only after
/// `refundReversed` has normalised them onto `refund.failed`, so the tables
/// themselves must answer null for both.
const ALL_EVENTS = [
  STRIPE_EVENT.checkoutCompleted,
  STRIPE_EVENT.checkoutAsyncPaid,
  STRIPE_EVENT.checkoutAsyncFailed,
  STRIPE_EVENT.checkoutExpired,
  STRIPE_EVENT.chargeRefunded,
  STRIPE_EVENT.refundFailed,
  STRIPE_EVENT.refundUpdated,
  STRIPE_EVENT.chargeRefundUpdated,
  STRIPE_EVENT.accountUpdated,
  'charge.succeeded',
  'payment_intent.succeeded',
  '',
] as const;

const SCOPES: readonly RefundScope[] = ['full', 'partial'];

const key = (status: string, event: string, scope: RefundScope) => `${status}|${event}|${scope}`;

/// The complete order table. A key absent from this map must answer null.
const ORDER_ARMS: Readonly<Record<string, OrderStatus>> = {
  [key('pending', STRIPE_EVENT.checkoutCompleted, 'full')]: 'paid',
  [key('pending', STRIPE_EVENT.checkoutCompleted, 'partial')]: 'paid',
  [key('pending', STRIPE_EVENT.checkoutAsyncPaid, 'full')]: 'paid',
  [key('pending', STRIPE_EVENT.checkoutAsyncPaid, 'partial')]: 'paid',
  [key('pending', STRIPE_EVENT.checkoutExpired, 'full')]: 'canceled',
  [key('pending', STRIPE_EVENT.checkoutExpired, 'partial')]: 'canceled',
  [key('pending', STRIPE_EVENT.checkoutAsyncFailed, 'full')]: 'failed',
  [key('pending', STRIPE_EVENT.checkoutAsyncFailed, 'partial')]: 'failed',
  [key('paid', STRIPE_EVENT.chargeRefunded, 'full')]: 'refunded',
  [key('paid', STRIPE_EVENT.chargeRefunded, 'partial')]: 'partially_refunded',
  [key('partially_refunded', STRIPE_EVENT.chargeRefunded, 'full')]: 'refunded',
  [key('refunded', STRIPE_EVENT.refundFailed, 'full')]: 'refund_failed',
  [key('refunded', STRIPE_EVENT.refundFailed, 'partial')]: 'refund_failed',
  [key('refund_failed', STRIPE_EVENT.chargeRefunded, 'full')]: 'refunded',
};

/// The complete donation table. It differs from the order table in exactly two
/// places, and both are load-bearing: `partially_refunded + partial` is a
/// self-transition here (a donation records an AMOUNT, so a second instalment
/// has something to write) and `paid + partial` lands on the same status.
const DONATION_ARMS: Readonly<Record<string, DonationStatus>> = {
  [key('pending', STRIPE_EVENT.checkoutCompleted, 'full')]: 'paid',
  [key('pending', STRIPE_EVENT.checkoutCompleted, 'partial')]: 'paid',
  [key('pending', STRIPE_EVENT.checkoutAsyncPaid, 'full')]: 'paid',
  [key('pending', STRIPE_EVENT.checkoutAsyncPaid, 'partial')]: 'paid',
  [key('pending', STRIPE_EVENT.checkoutExpired, 'full')]: 'canceled',
  [key('pending', STRIPE_EVENT.checkoutExpired, 'partial')]: 'canceled',
  [key('pending', STRIPE_EVENT.checkoutAsyncFailed, 'full')]: 'failed',
  [key('pending', STRIPE_EVENT.checkoutAsyncFailed, 'partial')]: 'failed',
  [key('paid', STRIPE_EVENT.chargeRefunded, 'full')]: 'refunded',
  [key('paid', STRIPE_EVENT.chargeRefunded, 'partial')]: 'partially_refunded',
  [key('partially_refunded', STRIPE_EVENT.chargeRefunded, 'full')]: 'refunded',
  [key('partially_refunded', STRIPE_EVENT.chargeRefunded, 'partial')]: 'partially_refunded',
  [key('refunded', STRIPE_EVENT.refundFailed, 'full')]: 'refund_failed',
  [key('refunded', STRIPE_EVENT.refundFailed, 'partial')]: 'refund_failed',
  [key('refund_failed', STRIPE_EVENT.chargeRefunded, 'full')]: 'refunded',
};

function sweep(
  table: Readonly<Record<string, string>>,
  transition: (status: string, event: string, scope: RefundScope) => string | null,
): { unexpected: string[]; missing: string[]; wrong: string[]; arms: number } {
  const unexpected: string[] = [];
  const missing: string[] = [];
  const wrong: string[] = [];
  let arms = 0;
  for (const status of ALL_STATUSES) {
    for (const event of ALL_EVENTS) {
      for (const scope of SCOPES) {
        const k = key(status, event, scope);
        const got = transition(status, event, scope);
        const want = table[k] ?? null;
        if (got !== null) arms++;
        if (got !== null && want === null) unexpected.push(`${k} -> ${got}`);
        else if (got === null && want !== null) missing.push(`${k} -> expected ${want}`);
        else if (got !== want) wrong.push(`${k} -> got ${got}, want ${want}`);
      }
    }
  }
  return { unexpected, missing, wrong, arms };
}

Deno.test('orderStatusTransition — the WHOLE table, so a stray arm cannot hide beside a right one', () => {
  const r = sweep(ORDER_ARMS, orderStatusTransition);
  assertEquals(r.unexpected, []);
  assertEquals(r.missing, []);
  assertEquals(r.wrong, []);
  // Count the arms as well as their contents: a table that answered null for
  // everything would satisfy the three empty lists above.
  assertEquals(r.arms, Object.keys(ORDER_ARMS).length);
  assertEquals(r.arms, 14);
});

Deno.test('donationStatusTransition — the WHOLE table, including its two deliberate divergences', () => {
  const r = sweep(DONATION_ARMS, donationStatusTransition);
  assertEquals(r.unexpected, []);
  assertEquals(r.missing, []);
  assertEquals(r.wrong, []);
  assertEquals(r.arms, Object.keys(DONATION_ARMS).length);
  assertEquals(r.arms, 15);
});

Deno.test('the two ledgers differ in exactly one cell, and it is the second instalment', () => {
  const differing: string[] = [];
  for (const status of ALL_STATUSES) {
    for (const event of ALL_EVENTS) {
      for (const scope of SCOPES) {
        const a = orderStatusTransition(status, event, scope);
        const b = donationStatusTransition(status, event, scope);
        if (a !== b) differing.push(`${key(status, event, scope)}: order=${a} donation=${b}`);
      }
    }
  }
  assertEquals(differing, [
    `${key('partially_refunded', STRIPE_EVENT.chargeRefunded, 'partial')}: order=null donation=partially_refunded`,
  ]);
});

Deno.test('every status a ledger can reach is one its own CHECK admits', () => {
  // A transition to a value the column cannot hold is a 23514 on the write and
  // an order stuck at whatever it was. The tables above are literals, so this
  // asserts the literals themselves are legal rather than re-reading the code.
  const orderCheck = new Set<string>([
    'pending',
    'paid',
    'refunded',
    'partially_refunded',
    'refund_failed',
    'failed',
    'canceled',
  ]);
  const donationCheck = new Set<string>([
    'pending',
    'paid',
    'partially_refunded',
    'refunded',
    'refund_failed',
    'failed',
    'canceled',
  ]);
  for (const status of ALL_STATUSES) {
    for (const event of ALL_EVENTS) {
      for (const scope of SCOPES) {
        const a = orderStatusTransition(status, event, scope);
        if (a !== null) assert(orderCheck.has(a), `order ledger produced ${a}`);
        const b = donationStatusTransition(status, event, scope);
        if (b !== null) assert(donationCheck.has(b), `donation ledger produced ${b}`);
      }
    }
  }
});

Deno.test('a status the database never wrote transitions on nothing', () => {
  // Case matters and an empty string is not `pending`: both tables compare
  // against literals, and a caller handing over a value from anywhere but the
  // column must not fall into an arm.
  for (const bogus of ['Paid', 'PENDING', ' pending', 'pending ', '', 'refund-failed', 'null']) {
    for (const event of ALL_EVENTS) {
      assertEquals(orderStatusTransition(bogus, event, 'full'), null, `order ${bogus} ${event}`);
      assertEquals(
        donationStatusTransition(bogus, event, 'full'),
        null,
        `donation ${bogus} ${event}`,
      );
    }
  }
});

Deno.test('a seat-bearing status is never moved by a refund that failed', () => {
  // `partially_refunded` backs a live registration on
  // `enforce_paid_order_for_priced_event` and on the buyer-cancel policy, so a
  // failed refund must leave it exactly where it is on both ledgers. On the
  // donation side the same arm would also drop the part that was never
  // refunded off `fundraiser_totals`.
  for (const scope of SCOPES) {
    assertEquals(orderStatusTransition('paid', STRIPE_EVENT.refundFailed, scope), null);
    assertEquals(
      orderStatusTransition('partially_refunded', STRIPE_EVENT.refundFailed, scope),
      null,
    );
    assertEquals(donationStatusTransition('paid', STRIPE_EVENT.refundFailed, scope), null);
    assertEquals(
      donationStatusTransition('partially_refunded', STRIPE_EVENT.refundFailed, scope),
      null,
    );
  }
});

Deno.test('refund_failed is terminal against everything except the refund landing', () => {
  for (const event of ALL_EVENTS) {
    for (const scope of SCOPES) {
      const expected = event === STRIPE_EVENT.chargeRefunded && scope === 'full' ? 'refunded' : null;
      assertEquals(
        orderStatusTransition('refund_failed', event, scope),
        expected,
        `order refund_failed + ${event} (${scope})`,
      );
      assertEquals(
        donationStatusTransition('refund_failed', event, scope),
        expected,
        `donation refund_failed + ${event} (${scope})`,
      );
    }
  }
});

Deno.test('the two update-era refund events never reach a table arm of their own', () => {
  // `refund.updated` fires when Stripe attaches an acquirer reference number to
  // a perfectly good refund. A table arm keyed on the event type would walk a
  // correctly refunded order back the moment that happened; the dispatcher
  // normalises onto `refund.failed` only after `refundReversed` said so.
  for (const event of [STRIPE_EVENT.refundUpdated, STRIPE_EVENT.chargeRefundUpdated]) {
    for (const status of ALL_STATUSES) {
      for (const scope of SCOPES) {
        assertEquals(orderStatusTransition(status, event, scope), null, `${status} ${event}`);
        assertEquals(donationStatusTransition(status, event, scope), null, `${status} ${event}`);
      }
    }
  }
});

const charge = (over: Partial<Charge> = {}): Charge => ({
  paymentIntentId: 'pi_1',
  refunded: null,
  amountCents: null,
  amountRefundedCents: null,
  ...over,
});

Deno.test('refundScopeOfCharge — the whole decision table, including the over-refund', () => {
  const cases: Array<[Partial<Charge>, RefundScope, string]> = [
    [{ refunded: true }, 'full', 'the flag alone settles it'],
    [{ refunded: true, amountCents: 5000, amountRefundedCents: 500 }, 'full', 'flag outranks maths'],
    [{ refunded: false, amountCents: 5000, amountRefundedCents: 500 }, 'partial', 'goodwill part'],
    [{ refunded: false, amountCents: 5000, amountRefundedCents: 5000 }, 'partial', 'flag is truth'],
    [{ refunded: false, amountRefundedCents: 0 }, 'full', 'nothing moved is not a partial'],
    [{ refunded: false, amountRefundedCents: null }, 'full', 'no figure is not a partial'],
    [{ refunded: false, amountRefundedCents: -1 }, 'full', 'a negative is not money moving'],
    [{ amountCents: 5000, amountRefundedCents: 500 }, 'partial', 'maths with no flag'],
    [{ amountCents: 5000, amountRefundedCents: 5000 }, 'full', 'equal is whole'],
    [{ amountCents: 5000, amountRefundedCents: 5001 }, 'full', 'more than the charge is whole'],
    [{ amountCents: 5000, amountRefundedCents: 0 }, 'full', 'zero refunded is not partial'],
    [{ amountCents: null, amountRefundedCents: 500 }, 'full', 'no charge total to compare'],
    [{ amountCents: 5000, amountRefundedCents: null }, 'full', 'no refunded total to compare'],
    [{ amountCents: 0, amountRefundedCents: 0 }, 'full', 'a zero charge'],
  ];
  for (const [over, want, why] of cases) {
    assertEquals(refundScopeOfCharge(charge(over)), want, why);
  }
});

Deno.test('refundScopeOfCharge — the unknown case falls to full, which loses the seat and not the money', () => {
  // Stated as its own case because the direction is the whole design: a charge
  // this build cannot read is answered in the BUYER's favour. Flipping the
  // fallback to `partial` would leave a fully refunded buyer holding a seat
  // they have been paid back for.
  assertEquals(refundScopeOfCharge(charge()), 'full');
  assertEquals(refundScopeOfCharge(charge({ amountCents: 5000 })), 'full');
});

Deno.test('refundedCentsOfCharge — a full refund is the ledger\'s own figure at every input', () => {
  for (const cumulative of [null, 0, 1, 4999, 5000, 999_999]) {
    assertEquals(
      refundedCentsOfCharge(charge({ amountRefundedCents: cumulative }), 5000, 'full'),
      5000,
      `cumulative ${cumulative}`,
    );
  }
});

Deno.test('refundedCentsOfCharge — a partial can never exceed the donation it refunds', () => {
  // `refunded_cents <= amount_cents` is stated against OUR column, so a charge
  // total that disagrees with ours (a currency or capture discrepancy) must be
  // clamped rather than written through.
  assertEquals(refundedCentsOfCharge(charge({ amountRefundedCents: 9999 }), 5000, 'partial'), 5000);
  assertEquals(refundedCentsOfCharge(charge({ amountRefundedCents: 5000 }), 5000, 'partial'), 5000);
  assertEquals(refundedCentsOfCharge(charge({ amountRefundedCents: 1 }), 5000, 'partial'), 1);
});

Deno.test('refundedCentsOfCharge — every unusable figure is null, on both arms', () => {
  const unusable = [null, 0, -1, -5000, 12.5, Number.NaN, Number.POSITIVE_INFINITY];
  for (const bad of unusable) {
    assertEquals(
      refundedCentsOfCharge(charge({ amountRefundedCents: bad }), 5000, 'partial'),
      null,
      `partial with ${bad}`,
    );
  }
  for (const badAmount of [-1, 12.5, Number.NaN, Number.POSITIVE_INFINITY]) {
    assertEquals(
      refundedCentsOfCharge(charge({ amountRefundedCents: 100 }), badAmount, 'partial'),
      null,
      `donation amount ${badAmount}`,
    );
    assertEquals(
      refundedCentsOfCharge(charge({ amountRefundedCents: 100 }), badAmount, 'full'),
      null,
      `donation amount ${badAmount} on the full arm`,
    );
  }
  // A zero donation is a legal integer and answers 0 rather than null: the
  // guard is on the SHAPE of the figure, not on it being interesting.
  assertEquals(refundedCentsOfCharge(charge(), 0, 'full'), 0);
});

Deno.test('refundReversed — the accepted set is exactly two, matched case-sensitively', () => {
  const reversed = ['failed', 'canceled'];
  const inFlightOrSettled = [
    'pending',
    'requires_action',
    'succeeded',
    'cancelled',
    'Failed',
    'FAILED',
    'CANCELED',
    '',
    'refund_failed',
  ];
  for (const status of reversed) {
    assertEquals(
      refundReversed({ id: 're_1', paymentIntentId: 'pi_1', status, failureReason: null }),
      true,
      status,
    );
  }
  for (const status of inFlightOrSettled) {
    assertEquals(
      refundReversed({ id: 're_1', paymentIntentId: 'pi_1', status, failureReason: null }),
      false,
      status,
    );
  }
  assertEquals(
    refundReversed({ id: 're_1', paymentIntentId: 'pi_1', status: null, failureReason: null }),
    false,
    'an unreadable status says nothing',
  );
});

Deno.test('shouldReleaseDedupe — the boundary is 500 exactly, and every 5xx is above it', () => {
  for (const status of [100, 200, 201, 204, 302, 400, 401, 403, 404, 409, 422, 429, 499]) {
    assertEquals(shouldReleaseDedupe(status), false, `${status}`);
  }
  for (const status of [500, 501, 502, 503, 504, 599]) {
    assertEquals(shouldReleaseDedupe(status), true, `${status}`);
  }
});
