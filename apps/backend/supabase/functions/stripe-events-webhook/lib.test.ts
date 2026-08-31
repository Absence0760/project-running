/// Run with `cd apps/backend && deno test supabase/functions/stripe-events-webhook/lib.test.ts`.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { hmacHex } from '../_shared/webhook_security.ts';
import {
  attendeeRowFromSession,
  capacityDecision,
  donationIdFromSession,
  donationStatusTransition,
  isDonationSession,
  orderStatusTransition,
  isPaymentSettled,
  parseStripeEventEnvelope,
  isRefundLifecycleEvent,
  knownRefundStatus,
  paymentRefundRecord,
  readCharge,
  readCheckoutSession,
  readConnectAccount,
  readRefund,
  REFUND_LIFECYCLE_EVENTS,
  REFUND_STATUSES,
  refundedCentsOfCharge,
  refundReversed,
  REVERSED_REFUND_STATUSES,
  refundScopeOfCharge,
  shouldReleaseDedupe,
  STRIPE_EVENT,
  verifyStripeSignature,
} from './lib.ts';

const SECRET = 'whsec_testsecret';

/// Build a valid Stripe-Signature header for a body + timestamp, the way
/// Stripe signs: HMAC-SHA256 over `${t}.${body}` keyed by the secret.
async function signHeader(body: string, tSec: number, secret = SECRET): Promise<string> {
  const v1 = await hmacHex(secret, `${tSec}.${body}`);
  return `t=${tSec},v1=${v1}`;
}

Deno.test('verifyStripeSignature — valid signature within tolerance passes', async () => {
  const body = '{"id":"evt_1","type":"checkout.session.completed"}';
  const nowMs = 1_700_000_000_000;
  const tSec = Math.floor(nowMs / 1000);
  const header = await signHeader(body, tSec);
  assertStrictEquals(await verifyStripeSignature(body, header, SECRET, nowMs), true);
});

Deno.test('verifyStripeSignature — tampered body fails', async () => {
  const body = '{"id":"evt_1","type":"checkout.session.completed"}';
  const nowMs = 1_700_000_000_000;
  const tSec = Math.floor(nowMs / 1000);
  const header = await signHeader(body, tSec);
  // Verify against a different body than was signed.
  const tampered = body.replace('evt_1', 'evt_2');
  assertStrictEquals(await verifyStripeSignature(tampered, header, SECRET, nowMs), false);
});

Deno.test('verifyStripeSignature — stale timestamp past tolerance fails (replay gate)', async () => {
  const body = '{"id":"evt_1"}';
  const signedMs = 1_700_000_000_000;
  const tSec = Math.floor(signedMs / 1000);
  const header = await signHeader(body, tSec);
  // 10 min later, default tolerance 5 min -> rejected even though HMAC is valid.
  const nowMs = signedMs + 10 * 60 * 1000;
  assertStrictEquals(await verifyStripeSignature(body, header, SECRET, nowMs), false);
});

Deno.test('verifyStripeSignature — future-dated past tolerance fails', async () => {
  const body = '{"id":"evt_1"}';
  const signedMs = 1_700_000_000_000 + 10 * 60 * 1000;
  const tSec = Math.floor(signedMs / 1000);
  const header = await signHeader(body, tSec);
  const nowMs = 1_700_000_000_000;
  assertStrictEquals(await verifyStripeSignature(body, header, SECRET, nowMs), false);
});

Deno.test('verifyStripeSignature — wrong secret fails', async () => {
  const body = '{"id":"evt_1"}';
  const nowMs = 1_700_000_000_000;
  const tSec = Math.floor(nowMs / 1000);
  const header = await signHeader(body, tSec, 'whsec_other');
  assertStrictEquals(await verifyStripeSignature(body, header, SECRET, nowMs), false);
});

Deno.test('verifyStripeSignature — missing v1 fails', async () => {
  const body = '{"id":"evt_1"}';
  const nowMs = 1_700_000_000_000;
  const tSec = Math.floor(nowMs / 1000);
  assertStrictEquals(await verifyStripeSignature(body, `t=${tSec}`, SECRET, nowMs), false);
});

Deno.test('verifyStripeSignature — malformed / missing / empty header fails', async () => {
  const body = '{"id":"evt_1"}';
  const nowMs = 1_700_000_000_000;
  assertStrictEquals(await verifyStripeSignature(body, null, SECRET, nowMs), false);
  assertStrictEquals(await verifyStripeSignature(body, '', SECRET, nowMs), false);
  assertStrictEquals(await verifyStripeSignature(body, 'garbage', SECRET, nowMs), false);
  assertStrictEquals(await verifyStripeSignature(body, 'v1=abc', SECRET, nowMs), false); // no t
});

Deno.test('verifyStripeSignature — empty secret fails closed', async () => {
  const body = '{"id":"evt_1"}';
  const nowMs = 1_700_000_000_000;
  const tSec = Math.floor(nowMs / 1000);
  const header = await signHeader(body, tSec);
  assertStrictEquals(await verifyStripeSignature(body, header, '', nowMs), false);
});

Deno.test('verifyStripeSignature — dual v1 signatures (rotation), one valid -> passes', async () => {
  const body = '{"id":"evt_1"}';
  const nowMs = 1_700_000_000_000;
  const tSec = Math.floor(nowMs / 1000);
  const goodV1 = await hmacHex(SECRET, `${tSec}.${body}`);
  const header = `t=${tSec},v1=deadbeef,v1=${goodV1}`;
  assertStrictEquals(await verifyStripeSignature(body, header, SECRET, nowMs), true);
});

Deno.test('parseStripeEventEnvelope — well-formed', () => {
  const env = parseStripeEventEnvelope(
    JSON.stringify({ id: 'evt_1', type: 'account.updated', data: { object: { id: 'acct_1' } } }),
  );
  assertEquals(env?.id, 'evt_1');
  assertEquals(env?.type, 'account.updated');
  assertEquals(env?.data.object.id, 'acct_1');
});

Deno.test('parseStripeEventEnvelope — garbage / missing fields -> null', () => {
  assertStrictEquals(parseStripeEventEnvelope('not json'), null);
  assertStrictEquals(parseStripeEventEnvelope('null'), null);
  assertStrictEquals(parseStripeEventEnvelope('123'), null);
  assertStrictEquals(parseStripeEventEnvelope(JSON.stringify({ id: 'x' })), null); // no type/data
  assertStrictEquals(parseStripeEventEnvelope(JSON.stringify({ id: 'x', type: 't' })), null); // no data
  assertStrictEquals(
    parseStripeEventEnvelope(JSON.stringify({ id: 'x', type: 't', data: {} })),
    null,
  ); // no data.object
});

Deno.test('orderStatusTransition — pending + completed -> paid', () => {
  assertStrictEquals(orderStatusTransition('pending', 'checkout.session.completed'), 'paid');
});

Deno.test('orderStatusTransition — pending + expired -> canceled', () => {
  assertStrictEquals(orderStatusTransition('pending', 'checkout.session.expired'), 'canceled');
});

Deno.test('orderStatusTransition — paid + completed -> null (no double-grant)', () => {
  // The idempotency backbone: a replayed completed finds the order
  // already paid and gets null, so it cannot re-seat or double-count.
  assertStrictEquals(orderStatusTransition('paid', 'checkout.session.completed'), null);
});

Deno.test('orderStatusTransition — paid + charge.refunded -> refunded (P2 refund coupling)', () => {
  assertStrictEquals(orderStatusTransition('paid', 'charge.refunded'), 'refunded');
});

Deno.test('orderStatusTransition — a refunded order is immovable on a replayed refund (no double-release)', () => {
  // The refund idempotency backbone: a replayed charge.refunded finds the
  // order already refunded and gets null, so it can't double-release a seat.
  assertStrictEquals(orderStatusTransition('refunded', 'charge.refunded'), null);
});

Deno.test('orderStatusTransition — pending does not refund (no charge to reverse)', () => {
  assertStrictEquals(orderStatusTransition('pending', 'charge.refunded'), null);
});

Deno.test('orderStatusTransition — terminal source states never transition', () => {
  // `partially_refunded` is deliberately NOT in this list. It was, back when
  // nothing could write it; now that the webhook does, the order still holds a
  // seat and the REST of the money can come back later — so a completing refund
  // has to be able to move it on and release that seat. See the arm below.
  for (const s of ['refunded', 'failed', 'canceled']) {
    assertStrictEquals(orderStatusTransition(s, 'checkout.session.completed'), null);
    assertStrictEquals(orderStatusTransition(s, 'checkout.session.expired'), null);
    assertStrictEquals(orderStatusTransition(s, 'charge.refunded'), null);
  }
  // paid is terminal for the SESSION events, but the refund arm moves it.
  assertStrictEquals(orderStatusTransition('paid', 'checkout.session.completed'), null);
  assertStrictEquals(orderStatusTransition('paid', 'checkout.session.expired'), null);
});

Deno.test('orderStatusTransition — unknown event type -> null', () => {
  assertStrictEquals(orderStatusTransition('pending', 'account.updated'), null);
  assertStrictEquals(orderStatusTransition('paid', 'account.updated'), null);
  assertStrictEquals(orderStatusTransition('pending', ''), null);
});

Deno.test('attendeeRowFromSession — metadata -> row', () => {
  const row = attendeeRowFromSession(readCheckoutSession({
    metadata: {
      event_id: 'e1',
      buyer_user_id: 'b1',
      instance_start: '2026-06-11T18:00:00Z',
      order_id: 'o1',
    },
  }));
  assertEquals(row, {
    event_id: 'e1',
    user_id: 'b1',
    instance_start: '2026-06-11T18:00:00Z',
    order_id: 'o1',
  });
});

Deno.test('attendeeRowFromSession — missing metadata / keys -> null', () => {
  assertStrictEquals(attendeeRowFromSession(readCheckoutSession({})), null);
  assertStrictEquals(attendeeRowFromSession(readCheckoutSession({ metadata: null })), null);
  assertStrictEquals(
    attendeeRowFromSession(readCheckoutSession({ metadata: { event_id: 'e1', buyer_user_id: 'b1' } })),
    null,
  ); // missing instance_start + order_id
});

Deno.test('capacityDecision — re-exported from the shared helper', () => {
  // Pinning that the webhook uses the SAME math as checkout (single
  // source) — divergence here is an oversell bug.
  assertEquals(capacityDecision(9, 1, 10), 'full');
  assertEquals(capacityDecision(0, 0, null), 'available');
});

// ── donation branch (fundraising.md) ───────────────────────────────────────

Deno.test('isDonationSession — keyed on metadata.kind', () => {
  assertStrictEquals(isDonationSession(readCheckoutSession({ metadata: { kind: 'donation' } })), true);
  // an event seat session has no kind
  assertStrictEquals(isDonationSession(readCheckoutSession({ metadata: { order_id: 'o1' } })), false);
  assertStrictEquals(isDonationSession(readCheckoutSession({})), false);
  assertStrictEquals(isDonationSession(readCheckoutSession({ metadata: null })), false);
});

Deno.test('donationIdFromSession — extracts donation_id, null when absent', () => {
  assertStrictEquals(
    donationIdFromSession(readCheckoutSession({ metadata: { kind: 'donation', donation_id: 'd1' } })),
    'd1',
  );
  assertStrictEquals(donationIdFromSession(readCheckoutSession({ metadata: { kind: 'donation' } })), null);
  assertStrictEquals(donationIdFromSession(readCheckoutSession({})), null);
});

Deno.test('donationStatusTransition — pending confirms to paid', () => {
  assertStrictEquals(donationStatusTransition('pending', 'checkout.session.completed'), 'paid');
});

Deno.test('donationStatusTransition — a replayed completed on a paid donation is null (no double-count)', () => {
  assertStrictEquals(donationStatusTransition('paid', 'checkout.session.completed'), null);
});

Deno.test('donationStatusTransition — pending expires to canceled', () => {
  assertStrictEquals(donationStatusTransition('pending', 'checkout.session.expired'), 'canceled');
});

Deno.test('donationStatusTransition — a PARTIAL refund does not erase the donation', () => {
  // `fundraiser_totals` sums amount_cents filtered on status = 'paid', so
  // flipping a partly-returned donation to `refunded` took its WHOLE amount off
  // the charity's thermometer: 5 USD back on a 500 USD donation erased 500 USD.
  // Before 20270620_001 the ledger had no partially-refunded state, so the
  // honest answer was to leave the status alone (decisions § 769); it has one
  // now, and the donation lands there instead of nowhere.
  assertStrictEquals(
    donationStatusTransition('paid', 'charge.refunded', 'partial'),
    'partially_refunded',
  );
  // The completing refund still moves it on, so the seat-less donation ledger
  // reaches the same terminal state once the whole charge is back.
  assertStrictEquals(donationStatusTransition('paid', 'charge.refunded', 'full'), 'refunded');
});

Deno.test('donationStatusTransition — a second instalment is a self-transition, unlike an order', () => {
  // The one deliberate divergence from orderStatusTransition. An order records
  // a seat, so a second partial has nothing to write and must not release it.
  // A donation records an AMOUNT, so the second instalment does have something
  // to write — returning null would leave the thermometer overstating by it.
  assertStrictEquals(
    donationStatusTransition('partially_refunded', 'charge.refunded', 'partial'),
    'partially_refunded',
  );
  assertStrictEquals(
    orderStatusTransition('partially_refunded', 'charge.refunded', 'partial'),
    null,
  );
});

Deno.test('donationStatusTransition — the completing refund moves a partially refunded donation on', () => {
  assertStrictEquals(
    donationStatusTransition('partially_refunded', 'charge.refunded', 'full'),
    'refunded',
  );
  // …and nothing else can move it. A partially refunded donation is not a
  // pending one: it can neither be confirmed nor expired.
  assertStrictEquals(
    donationStatusTransition('partially_refunded', 'checkout.session.completed'),
    null,
  );
  assertStrictEquals(
    donationStatusTransition('partially_refunded', 'checkout.session.expired'),
    null,
  );
});

Deno.test('donationStatusTransition — a refunded donation is terminal', () => {
  assertStrictEquals(donationStatusTransition('refunded', 'charge.refunded', 'full'), null);
  assertStrictEquals(donationStatusTransition('refunded', 'charge.refunded', 'partial'), null);
  assertStrictEquals(donationStatusTransition('canceled', 'charge.refunded'), null);
  assertStrictEquals(donationStatusTransition('failed', 'charge.refunded'), null);
});

Deno.test('refundedCentsOfCharge — a full refund is the DONATION\'s amount, not the charge\'s', () => {
  // `refunded` means the whole donation came back, and `refunded_cents <=
  // amount_cents` is stated against our own column. A charge whose total
  // disagrees with ours must not be able to write a refund larger than the
  // donation it is refunding.
  assertStrictEquals(
    refundedCentsOfCharge(readCharge({ amount: 60000, amount_refunded: 60000, refunded: true }), 50000, 'full'),
    50000,
  );
  // …and it does not depend on the charge saying anything at all.
  assertStrictEquals(refundedCentsOfCharge(readCharge({}), 50000, 'full'), 50000);
});

Deno.test('refundedCentsOfCharge — a partial refund is the charge\'s CUMULATIVE amount', () => {
  // amount_refunded is a running total across every refund on the charge, not
  // the size of the one that raised this event — which is what makes the write
  // idempotent and order-insensitive.
  assertStrictEquals(
    refundedCentsOfCharge(readCharge({ amount: 50000, amount_refunded: 500, refunded: false }), 50000, 'partial'),
    500,
  );
  assertStrictEquals(
    refundedCentsOfCharge(readCharge({ amount: 50000, amount_refunded: 1500, refunded: false }), 50000, 'partial'),
    1500,
  );
  // Clamped to the donation: the CHECK refuses more coming back than went in,
  // and a 23514 from the webhook is a delivery Stripe retries forever.
  assertStrictEquals(
    refundedCentsOfCharge(readCharge({ amount_refunded: 99999 }), 50000, 'partial'),
    50000,
  );
});

Deno.test('refundedCentsOfCharge — an unusable amount is null, never a guess', () => {
  for (const bad of [undefined, null, '500', Number.NaN, 12.5, 0, -100]) {
    assertStrictEquals(
      refundedCentsOfCharge(readCharge({ amount_refunded: bad }), 50000, 'partial'),
      null,
      `amount_refunded=${String(bad)} must not reach a money column`,
    );
  }
  // A donation amount that is not a whole number of cents is not a bound to
  // clamp against either — both directions fail closed.
  assertStrictEquals(refundedCentsOfCharge(readCharge({ amount_refunded: 500 }), 12.5, 'partial'), null);
  assertStrictEquals(refundedCentsOfCharge(readCharge({}), -1, 'full'), null);
});

Deno.test('donationStatusTransition — the scope default is full, matching the event ledger', () => {
  // Same default as orderStatusTransition: a caller that cannot read a scope
  // treats the refund as whole, which is the direction that never overstates
  // what a charity has raised.
  assertStrictEquals(donationStatusTransition('paid', 'charge.refunded'), 'refunded');
  assertStrictEquals(donationStatusTransition('paid', 'charge.refunded', 'full'), 'refunded');
});

Deno.test('donationStatusTransition — paid refunds, pending does not', () => {
  assertStrictEquals(donationStatusTransition('paid', 'charge.refunded'), 'refunded');
  assertStrictEquals(donationStatusTransition('pending', 'charge.refunded'), null);
});

Deno.test('donationStatusTransition — a terminal donation is immovable', () => {
  assertStrictEquals(donationStatusTransition('refunded', 'charge.refunded'), null);
  assertStrictEquals(donationStatusTransition('canceled', 'checkout.session.completed'), null);
});

Deno.test('shouldReleaseDedupe — a 5xx gives the dedupe row back so Stripe can retry', () => {
  // Every "we could not complete this" path in the handlers returns 500.
  // Without the release, Stripe's retry hits the insert-first 23505 branch,
  // answers 200 duplicate_event, and the delivery is closed for good — a
  // charged card with a pending order and no seat.
  for (const status of [500, 502, 503, 504]) {
    assertEquals(shouldReleaseDedupe(status), true, `status ${status}`);
  }
});

Deno.test('shouldReleaseDedupe — a successful or deliberately-final response keeps it', () => {
  // The handlers answer 200 for outcomes that are genuinely final (unknown
  // donation, missing metadata, an already-terminal status). Releasing there
  // would re-open a settled event to reprocessing on any later replay.
  for (const status of [200, 201, 204]) {
    assertEquals(shouldReleaseDedupe(status), false, `status ${status}`);
  }
});

Deno.test('shouldReleaseDedupe — a 4xx is the caller\'s fault and stays deduped', () => {
  // Stripe does not retry a 4xx, and re-opening the row would let a
  // malformed replay be processed later.
  for (const status of [400, 401, 404, 409, 422]) {
    assertEquals(shouldReleaseDedupe(status), false, `status ${status}`);
  }
});

Deno.test('refundScopeOfCharge — refunded:true is a full refund', () => {
  assertStrictEquals(refundScopeOfCharge(readCharge({ refunded: true, amount: 5000, amount_refunded: 5000 })), 'full');
});

Deno.test('refundScopeOfCharge — a goodwill part-refund is partial', () => {
  // Stripe emits charge.refunded for a PARTIAL refund too; `refunded` is the
  // discriminator and is false until the whole charge is returned.
  assertStrictEquals(refundScopeOfCharge(readCharge({ refunded: false, amount: 5000, amount_refunded: 500 })), 'partial');
});

Deno.test('refundScopeOfCharge — refunded:false with nothing refunded is not a partial refund', () => {
  // Must not become a status change on the strength of a zero refund.
  assertStrictEquals(refundScopeOfCharge(readCharge({ refunded: false, amount: 5000, amount_refunded: 0 })), 'full');
});

Deno.test('refundScopeOfCharge — unknown amounts fall back to full', () => {
  // Historical behaviour, and the safe direction for the buyer.
  assertStrictEquals(refundScopeOfCharge(readCharge({})), 'full');
  assertStrictEquals(refundScopeOfCharge(readCharge({ amount: 5000 })), 'full');
});

Deno.test('orderStatusTransition — a partial refund keeps the registration', () => {
  // event_orders_status_check has carried partially_refunded since the table
  // was created and nothing ever wrote it: every charge.refunded was treated
  // as full, so a $5 goodwill refund on a $50 workshop flipped the order to
  // refunded and the handler DELETED the buyer's seat, which
  // promote_event_waitlist then handed to someone else.
  assertStrictEquals(
    orderStatusTransition('paid', 'charge.refunded', 'partial'),
    'partially_refunded',
  );
  assertStrictEquals(orderStatusTransition('paid', 'charge.refunded', 'full'), 'refunded');
});

Deno.test('orderStatusTransition — a completing refund releases a partially refunded seat', () => {
  // Refund $5 of $50, then the remaining $45. Treating partially_refunded as
  // terminal (as this test originally asserted) meant the second refund was a
  // no-op and the buyer kept the seat permanently on a fully refunded order.
  assertStrictEquals(
    orderStatusTransition('partially_refunded', 'charge.refunded', 'full'),
    'refunded',
  );
  // ...but a further INSTALMENT does not release it — still partially paid.
  assertStrictEquals(
    orderStatusTransition('partially_refunded', 'charge.refunded', 'partial'),
    null,
  );
  // The session events remain no-ops from this state.
  assertStrictEquals(
    orderStatusTransition('partially_refunded', 'checkout.session.completed'),
    null,
  );
});

/// A `charge.refunded` delivery in the shape Stripe actually sends: the charge
/// sits at `data.object`, `refunded` stays false while any balance remains,
/// and the amounts are the only honest discriminator. Pinned against the real
/// envelope because the round-2 bug was reading neither `amount` nor
/// `amount_refunded` — it decided off the event TYPE, which is identical for
/// a £5 goodwill refund and a full one.
function chargeRefundedEvent(amount: number, amountRefunded: number) {
  return JSON.stringify({
    id: 'evt_3PartialRefund',
    object: 'event',
    api_version: '2024-06-20',
    created: 1_760_000_000,
    type: 'charge.refunded',
    livemode: false,
    pending_webhooks: 1,
    data: {
      object: {
        id: 'ch_3TestCharge',
        object: 'charge',
        amount,
        amount_captured: amount,
        amount_refunded: amountRefunded,
        currency: 'gbp',
        captured: true,
        paid: true,
        refunded: amountRefunded >= amount,
        status: 'succeeded',
        payment_intent: 'pi_3TestIntent',
        refunds: {
          object: 'list',
          total_count: 1,
          data: [{
            id: 're_3TestRefund',
            object: 'refund',
            amount: amountRefunded,
            currency: 'gbp',
            charge: 'ch_3TestCharge',
            reason: 'requested_by_customer',
            status: 'succeeded',
          }],
        },
      },
    },
  });
}

Deno.test('charge.refunded envelope — a goodwill part-refund keeps the seat', () => {
  const event = parseStripeEventEnvelope(chargeRefundedEvent(5000, 500));
  assertStrictEquals(event?.type, 'charge.refunded');
  const charge = event!.data.object;
  const scope = refundScopeOfCharge(readCharge(charge));
  assertStrictEquals(scope, 'partial');
  assertStrictEquals(
    orderStatusTransition('paid', event!.type, scope),
    'partially_refunded',
  );
});

Deno.test('charge.refunded envelope — the whole charge back releases the seat', () => {
  const event = parseStripeEventEnvelope(chargeRefundedEvent(5000, 5000));
  const charge = event!.data.object;
  assertStrictEquals(refundScopeOfCharge(readCharge(charge)), 'full');
  assertStrictEquals(
    orderStatusTransition('paid', event!.type, refundScopeOfCharge(readCharge(charge))),
    'refunded',
  );
});

Deno.test('charge.refunded envelope — the balance of a part-refund completes it', () => {
  const first = parseStripeEventEnvelope(chargeRefundedEvent(5000, 500))!;
  const status = orderStatusTransition(
    'paid',
    first.type,
    refundScopeOfCharge(readCharge(first.data.object)),
  );
  const second = parseStripeEventEnvelope(chargeRefundedEvent(5000, 5000))!;
  assertStrictEquals(
    orderStatusTransition(status!, second.type, refundScopeOfCharge(readCharge(second.data.object))),
    'refunded',
  );
});

// ── the typed read of a Stripe object (decisions § 785) ────────────────────

Deno.test('readCharge — an EXPANDED payment_intent still resolves to its id', () => {
  // Stripe serialises a reference as the bare id or, on an endpoint with
  // expansions configured, as the whole object — `string | Stripe.PaymentIntent
  // | null` in the SDK's own declaration. Reading only the string form yields
  // null for the expanded one, and null on a refund is answered
  // `missing_payment_intent` with a 200: Stripe records the refund as
  // delivered, the order keeps its seat, and no retry ever comes.
  assertStrictEquals(readCharge({ payment_intent: 'pi_1' }).paymentIntentId, 'pi_1');
  assertStrictEquals(
    readCharge({ payment_intent: { id: 'pi_1', object: 'payment_intent' } }).paymentIntentId,
    'pi_1',
  );
  assertStrictEquals(readCharge({ payment_intent: null }).paymentIntentId, null);
  assertStrictEquals(readCharge({}).paymentIntentId, null);
  // An object with no id is not a reference to anything.
  assertStrictEquals(readCharge({ payment_intent: { object: 'payment_intent' } }).paymentIntentId, null);
});

Deno.test('readCheckoutSession — an EXPANDED payment_intent still resolves to its id', () => {
  assertStrictEquals(readCheckoutSession({ payment_intent: 'pi_1' }).paymentIntentId, 'pi_1');
  assertStrictEquals(
    readCheckoutSession({ payment_intent: { id: 'pi_1' } }).paymentIntentId,
    'pi_1',
  );
  // The order is stamped with whatever this returns, and the refund arm
  // resolves the order back through it — a null here is an order no refund
  // can ever find.
  assertStrictEquals(readCheckoutSession({}).paymentIntentId, null);
});

Deno.test('readCheckoutSession — metadata keeps only the string values Stripe declares', () => {
  const session = readCheckoutSession({
    metadata: { order_id: 'o1', quantity: 2, nested: { a: 1 }, missing: null },
  });
  assertStrictEquals(session.metadata.order_id, 'o1');
  assertStrictEquals(session.metadata.quantity, undefined);
  assertStrictEquals(session.metadata.nested, undefined);
  assertStrictEquals(session.metadata.missing, undefined);
  // A session with no metadata at all reads as empty, not as a throw.
  assertEquals(readCheckoutSession({}).metadata, {});
  assertEquals(readCheckoutSession({ metadata: null }).metadata, {});
});

Deno.test('attendeeRowFromSession — an EMPTY metadata value is not a seat', () => {
  // `typeof x === 'string'` accepts ''. An empty order_id then reached
  // `.eq('id', '')`, which PostgREST answers 22P02 (invalid uuid) — a 500, a
  // released dedupe row and a retry that fails identically, forever.
  assertStrictEquals(
    attendeeRowFromSession(readCheckoutSession({
      metadata: { event_id: 'e1', buyer_user_id: 'b1', instance_start: '2026-06-11T18:00:00Z', order_id: '' },
    })),
    null,
  );
});

Deno.test('readConnectAccount — an absent capability flag reads as off', () => {
  const account = readConnectAccount({
    id: 'acct_1',
    charges_enabled: true,
    details_submitted: true,
  });
  assertStrictEquals(account.id, 'acct_1');
  assertStrictEquals(account.chargesEnabled, true);
  assertStrictEquals(account.payoutsEnabled, false);
  assertStrictEquals(account.detailsSubmitted, true);
  assertStrictEquals(readConnectAccount({}).id, null);
});

Deno.test('readCheckoutSession — an unrecognised payment_status is not a settlement', () => {
  // The three values are Stripe's own union, pinned against the SDK by
  // `CheckoutSessionSourceIsStripes`. Anything else is a value this build has
  // never heard of on the money field of a payment, and seating an attendee
  // against one gives a place away for money that may never arrive.
  assertStrictEquals(readCheckoutSession({ payment_status: 'paid' }).paymentStatus, 'paid');
  assertStrictEquals(readCheckoutSession({ payment_status: 'unpaid' }).paymentStatus, 'unpaid');
  assertStrictEquals(
    readCheckoutSession({ payment_status: 'no_payment_required' }).paymentStatus,
    'no_payment_required',
  );
  assertStrictEquals(readCheckoutSession({ payment_status: 'settling' }).paymentStatus, null);
  assertStrictEquals(readCheckoutSession({}).paymentStatus, null);
});

Deno.test('STRIPE_EVENT — the dispatcher and the transition tables share one spelling', () => {
  // The values are checked against Stripe's own event union at compile time
  // (`satisfies Record<string, Stripe.Event.Type>`); this pins that the
  // transition tables are keyed on the same constants the dispatcher branches
  // on, which is what a mistyped literal in either place used to break
  // silently — nothing errors, the branch simply never matches.
  assertStrictEquals(
    orderStatusTransition('pending', STRIPE_EVENT.checkoutCompleted),
    'paid',
  );
  assertStrictEquals(
    orderStatusTransition('pending', STRIPE_EVENT.checkoutExpired),
    'canceled',
  );
  assertStrictEquals(
    donationStatusTransition('paid', STRIPE_EVENT.chargeRefunded, 'full'),
    'refunded',
  );
});

// ── delayed-notification payments (decisions § 785) ───────────────────────

Deno.test('isPaymentSettled — only an explicit settlement seats an attendee', () => {
  // `checkout.session.completed` is not a payment. For a delayed-notification
  // method (SEPA debit, Bacs, boleto, OXXO, a bank redirect) the Session
  // completes with `payment_status: 'unpaid'` and the money arrives days later
  // — or does not. The Checkout Sessions this tier opens declare no
  // `payment_method_types`, so which methods are live is a dashboard setting
  // no code here would notice changing.
  assertStrictEquals(isPaymentSettled('paid'), true);
  assertStrictEquals(isPaymentSettled('no_payment_required'), true);
  assertStrictEquals(isPaymentSettled('unpaid'), false);
  // Absent, or a value this build has never heard of: not a settlement. A
  // place given away cannot be taken back from here.
  assertStrictEquals(isPaymentSettled(null), false);
});

Deno.test('orderStatusTransition — the async outcome, not the completion, pays the order', () => {
  assertStrictEquals(
    orderStatusTransition('pending', STRIPE_EVENT.checkoutAsyncPaid),
    'paid',
  );
  assertStrictEquals(
    orderStatusTransition('pending', STRIPE_EVENT.checkoutAsyncFailed),
    'failed',
  );
  // A failed order releases its reservation the same way a canceled one does:
  // capacity and the sweep index both key on status='pending'.
  assertStrictEquals(
    orderStatusTransition('failed', STRIPE_EVENT.checkoutAsyncPaid),
    null,
  );
  // No arm out of `paid`. With the settlement gate in front of the confirm, a
  // paid order is never waiting on an async outcome — and a paid->failed arm
  // would owe a seat release this table cannot perform.
  assertStrictEquals(
    orderStatusTransition('paid', STRIPE_EVENT.checkoutAsyncFailed),
    null,
  );
});

Deno.test('donationStatusTransition — the async outcome, not the completion, pays the donation', () => {
  assertStrictEquals(
    donationStatusTransition('pending', STRIPE_EVENT.checkoutAsyncPaid),
    'paid',
  );
  assertStrictEquals(
    donationStatusTransition('pending', STRIPE_EVENT.checkoutAsyncFailed),
    'failed',
  );
  assertStrictEquals(
    donationStatusTransition('paid', STRIPE_EVENT.checkoutAsyncFailed),
    null,
  );
});

// ── the refund the bank sent back (decisions § 789) ────────────────────────
//
// Stripe fires `charge.refunded` when a refund is CREATED, including one whose
// status is still `pending`. On a delayed-notification rail the seat is
// therefore released days before the money's fate is known, and the outcome
// lands later as one of the three refund-lifecycle events.

/// A refund-lifecycle event body, the way Stripe serialises one: the Refund
/// object in `data.object`, carrying the payment intent both ledgers resolve on.
function refundEvent(
  type: string,
  status: string | null,
  extra: Record<string, unknown> = {},
): string {
  return JSON.stringify({
    id: 'evt_refund_1',
    type,
    data: {
      object: {
        id: 're_1',
        object: 'refund',
        amount: 5000,
        charge: 'ch_1',
        payment_intent: 'pi_1',
        status,
        ...extra,
      },
    },
  });
}

Deno.test('STRIPE_EVENT — the three refund-lifecycle types are spelled as Stripe sends them', () => {
  // Checked against Stripe's own event union at compile time (`satisfies
  // Record<string, Stripe.Event.Type>`), which is what proves all three exist
  // in the pinned SDK. This pins the literals themselves: a constant that
  // matches nothing does not error, the branch simply never fires, and on this
  // function that means a failed refund is never noticed at all.
  assertStrictEquals(STRIPE_EVENT.refundFailed, 'refund.failed');
  assertStrictEquals(STRIPE_EVENT.refundUpdated, 'refund.updated');
  assertStrictEquals(STRIPE_EVENT.chargeRefundUpdated, 'charge.refund.updated');
  assertEquals([...REFUND_LIFECYCLE_EVENTS].sort(), [
    'charge.refund.updated',
    'refund.failed',
    'refund.updated',
  ]);
});

Deno.test('isRefundLifecycleEvent — both eras of the event, and nothing else', () => {
  // `refund.failed` is what Stripe's own guide names, available for refunds
  // WITH a charge from API version 2024-10-28.acacia. `charge.refund.updated`
  // is deprecated in Stripe's refund-events table but is what a webhook
  // endpoint still pinned below that version receives — which version an
  // endpoint is on is dashboard configuration this repo cannot read.
  assertStrictEquals(isRefundLifecycleEvent('refund.failed'), true);
  assertStrictEquals(isRefundLifecycleEvent('refund.updated'), true);
  assertStrictEquals(isRefundLifecycleEvent('charge.refund.updated'), true);
  // `charge.refunded` is the refund being CREATED and has its own handler;
  // `refund.created` says nothing about the outcome.
  assertStrictEquals(isRefundLifecycleEvent('charge.refunded'), false);
  assertStrictEquals(isRefundLifecycleEvent('refund.created'), false);
  assertStrictEquals(isRefundLifecycleEvent('account.updated'), false);
});

Deno.test('readRefund — every field is checked, and an EXPANDED payment_intent resolves', () => {
  const event = parseStripeEventEnvelope(
    refundEvent('refund.failed', 'failed', { failure_reason: 'declined' }),
  );
  assertEquals(readRefund(event!.data.object), {
    id: 're_1',
    paymentIntentId: 'pi_1',
    status: 'failed',
    amountCents: 5000,
    failureReason: 'declined',
  });
  // The endpoint may be configured to expand the reference into the whole
  // object, which a `typeof x === 'string'` read would resolve to null — and
  // null on this path means the ledger is never found.
  assertEquals(
    readRefund({
      id: 're_2',
      payment_intent: { id: 'pi_2', object: 'payment_intent' },
      status: 'canceled',
    }),
    {
      id: 're_2',
      paymentIntentId: 'pi_2',
      status: 'canceled',
      amountCents: null,
      failureReason: null,
    },
  );
});

Deno.test('readRefund — a value that does not check reads as absent, never as a default', () => {
  assertEquals(
    readRefund({ id: 42, payment_intent: 7, status: { code: 'failed' }, amount: '5000' }),
    {
      id: null,
      paymentIntentId: null,
      status: null,
      amountCents: null,
      failureReason: null,
    },
  );
  assertEquals(readRefund({}), {
    id: null,
    paymentIntentId: null,
    status: null,
    amountCents: null,
    failureReason: null,
  });
  // A money field is an integer count of cents or it is absent. A fractional
  // or negative `amount` reaching the ledger would be a refund the CHECK
  // rejects, which 500s into an endless Stripe retry on an event that changed
  // nothing.
  assertStrictEquals(readRefund({ amount: 12.5 }).amountCents, null);
  assertStrictEquals(readRefund({ amount: -1 }).amountCents, null);
  assertStrictEquals(readRefund({ amount: 0 }).amountCents, 0);
});

Deno.test('refundReversed — only failed and canceled mean the money came back to us', () => {
  // Stripe: "As cancellations are a type of refund failure, the attributes
  // failure_reason and failure_balance_transaction are included on the Refund."
  assertStrictEquals(refundReversed(readRefund({ status: 'failed' })), true);
  assertStrictEquals(refundReversed(readRefund({ status: 'canceled' })), true);
});

Deno.test('refundReversed — an in-flight or settled refund moves nothing', () => {
  // `requires_action` is the bank handing money back for CORRECTED details:
  // Stripe re-emails the customer and the refund is still in flight, so calling
  // it a failure would walk a ledger back that is about to settle on its own.
  assertStrictEquals(refundReversed(readRefund({ status: 'pending' })), false);
  assertStrictEquals(refundReversed(readRefund({ status: 'requires_action' })), false);
  assertStrictEquals(refundReversed(readRefund({ status: 'succeeded' })), false);
  // Stripe declares `status` as a bare `string | null`, so there is no
  // compile-time union to lean on: an unheard-of value, an absent one and an
  // unreadable one all have to fail closed at runtime.
  assertStrictEquals(refundReversed(readRefund({ status: 'quiesced' })), false);
  assertStrictEquals(refundReversed(readRefund({})), false);
  assertStrictEquals(refundReversed(readRefund({ status: 'FAILED' })), false);
});

Deno.test('orderStatusTransition — a reversed refund states that the money never left', () => {
  // The seat is already gone and promote_event_waitlist may already have given
  // it away; `refunded` is now a claim about money that is provably false.
  assertStrictEquals(
    orderStatusTransition('refunded', STRIPE_EVENT.refundFailed),
    'refund_failed',
  );
});

Deno.test('orderStatusTransition — a failed refund does NOT strip a seat-bearing order', () => {
  // `partially_refunded` backs a live seat on enforce_paid_order_for_priced_event
  // and keeps the buyer's cancel affordance (20270522_001). The failure cost
  // that buyer nothing — they are still attending — so moving them to a
  // terminal status would take the roster entry and the cancel button away
  // over a discrepancy that is ours to reconcile, not theirs to absorb.
  assertStrictEquals(
    orderStatusTransition('partially_refunded', STRIPE_EVENT.refundFailed),
    null,
  );
  // Nor does it touch an order that never had a refund to fail.
  assertStrictEquals(orderStatusTransition('paid', STRIPE_EVENT.refundFailed), null);
  assertStrictEquals(orderStatusTransition('pending', STRIPE_EVENT.refundFailed), null);
  assertStrictEquals(orderStatusTransition('canceled', STRIPE_EVENT.refundFailed), null);
  assertStrictEquals(orderStatusTransition('failed', STRIPE_EVENT.refundFailed), null);
});

Deno.test('orderStatusTransition — a REPLAYED reversal cannot double-apply', () => {
  // Stripe delivers at least once. The CAS matches the status that was read,
  // and the second delivery reads `refund_failed` and transitions on nothing.
  const first = orderStatusTransition('refunded', STRIPE_EVENT.refundFailed);
  assertStrictEquals(first, 'refund_failed');
  assertStrictEquals(orderStatusTransition(first!, STRIPE_EVENT.refundFailed), null);
});

Deno.test('orderStatusTransition — the table keys on refund.failed, not on the update events', () => {
  // `refund.updated` fires whenever Stripe attaches an acquirer reference
  // number to a perfectly good refund. Keying the table on the event type
  // alone would walk a correctly refunded order back the moment that happened,
  // so the dispatcher gates on `refundReversed` and normalises onto the one
  // constant that unambiguously means a failure.
  assertStrictEquals(orderStatusTransition('refunded', STRIPE_EVENT.refundUpdated), null);
  assertStrictEquals(
    orderStatusTransition('refunded', STRIPE_EVENT.chargeRefundUpdated),
    null,
  );
});

Deno.test('orderStatusTransition — a refund paid another way settles a refund_failed order', () => {
  // `refund_failed` is terminal against everything EXCEPT the refund actually
  // landing, or the ledger would be stuck denying a refund that has happened.
  assertStrictEquals(
    orderStatusTransition('refund_failed', STRIPE_EVENT.chargeRefunded, 'full'),
    'refunded',
  );
  // A PARTIAL refund does not resurrect the seat-bearing status: there is no
  // attendee row left to bear, and `partially_refunded` would tell every seat
  // predicate and the buyer's cancel button otherwise.
  assertStrictEquals(
    orderStatusTransition('refund_failed', STRIPE_EVENT.chargeRefunded, 'partial'),
    null,
  );
  assertStrictEquals(
    orderStatusTransition('refund_failed', STRIPE_EVENT.checkoutCompleted),
    null,
  );
});

Deno.test('donationStatusTransition — the donation ledger reverses on the same terms', () => {
  assertStrictEquals(
    donationStatusTransition('refunded', STRIPE_EVENT.refundFailed),
    'refund_failed',
  );
  assertStrictEquals(
    donationStatusTransition('refund_failed', STRIPE_EVENT.refundFailed),
    null,
  );
  assertStrictEquals(
    donationStatusTransition('refund_failed', STRIPE_EVENT.chargeRefunded, 'full'),
    'refunded',
  );
  assertStrictEquals(
    donationStatusTransition('refund_failed', STRIPE_EVENT.chargeRefunded, 'partial'),
    null,
  );
});

Deno.test('donationStatusTransition — a failed PARTIAL refund leaves the thermometer alone', () => {
  // fundraiser_totals sums `amount_cents - refunded_cents` over ('paid',
  // 'partially_refunded'), so moving a partly-refunded donation to the excluded
  // `refund_failed` would drop the WHOLE donation off the charity's total
  // including the part that was never refunded. The remaining alternative —
  // subtracting this instalment from `refunded_cents` — is arithmetic on a
  // running total, which is what § 769 avoided so a redelivery cannot
  // double-apply. Understating what was raised is the smaller, safe lie.
  assertStrictEquals(
    donationStatusTransition('partially_refunded', STRIPE_EVENT.refundFailed),
    null,
  );
  assertStrictEquals(donationStatusTransition('paid', STRIPE_EVENT.refundFailed), null);
  assertStrictEquals(donationStatusTransition('pending', STRIPE_EVENT.refundFailed), null);
});

Deno.test('refund.failed envelope — end to end from the wire to the new status', () => {
  const event = parseStripeEventEnvelope(
    refundEvent('refund.failed', 'failed', { failure_reason: 'expired_or_canceled_card' }),
  );
  assertStrictEquals(isRefundLifecycleEvent(event!.type), true);
  const refund = readRefund(event!.data.object);
  assertStrictEquals(refundReversed(refund), true);
  assertStrictEquals(refund.paymentIntentId, 'pi_1');
  assertStrictEquals(
    orderStatusTransition('refunded', STRIPE_EVENT.refundFailed),
    'refund_failed',
  );
  assertStrictEquals(
    donationStatusTransition('refunded', STRIPE_EVENT.refundFailed),
    'refund_failed',
  );
});

Deno.test('refund.updated envelope — a benign reference-number update changes nothing', () => {
  // The same event type carries both "here is the ARN" and "the bank rejected
  // it". Only the refund's own status separates them.
  const benign = parseStripeEventEnvelope(refundEvent('refund.updated', 'succeeded'));
  assertStrictEquals(isRefundLifecycleEvent(benign!.type), true);
  assertStrictEquals(refundReversed(readRefund(benign!.data.object)), false);

  const reversed = parseStripeEventEnvelope(refundEvent('refund.updated', 'canceled'));
  assertStrictEquals(refundReversed(readRefund(reversed!.data.object)), true);
});

Deno.test('charge.refund.updated envelope — the deprecated event carries the same Refund', () => {
  // A webhook endpoint pinned below 2024-10-28.acacia receives this one and
  // not `refund.failed`, so both eras resolve to the same ledger row.
  const event = parseStripeEventEnvelope(refundEvent('charge.refund.updated', 'failed'));
  assertStrictEquals(isRefundLifecycleEvent(event!.type), true);
  const refund = readRefund(event!.data.object);
  assertStrictEquals(refundReversed(refund), true);
  assertStrictEquals(refund.paymentIntentId, 'pi_1');
});


// ── payment_refunds: the row a failed PARTIAL refund gets (§ 823) ────────────

Deno.test('knownRefundStatus — exactly Stripe\'s vocabulary, and nothing else', () => {
  for (const status of REFUND_STATUSES) {
    assertStrictEquals(knownRefundStatus(status), status);
  }
  // A status the CHECK does not admit must record NOTHING rather than reach
  // the insert: a 23514 there answers 500, Stripe retries, and an event that
  // changed nothing retries forever.
  for (const bogus of [null, '', 'Failed', 'succeeded ', 'reversed', 'refunded']) {
    assertStrictEquals(knownRefundStatus(bogus), null);
  }
});

Deno.test('every reversed status is a status the ledger can hold', () => {
  // The reversal set decides what fundraiser_totals subtracts; the vocabulary
  // decides what can be stored at all. A member of the first that is not a
  // member of the second is a correction that can never be recorded.
  for (const status of REVERSED_REFUND_STATUSES) {
    assertStrictEquals(REFUND_STATUSES.includes(status), true, status);
  }
});

Deno.test('paymentRefundRecord — the whole refund, or no row at all', () => {
  assertEquals(
    paymentRefundRecord(readRefund({
      id: 're_9',
      payment_intent: 'pi_9',
      status: 'failed',
      amount: 500,
      failure_reason: 'insufficient_funds',
    })),
    {
      stripe_refund_id: 're_9',
      amount_cents: 500,
      status: 'failed',
      failure_reason: 'insufficient_funds',
    },
  );
  // A refund that DELIVERED is recorded too. The row is the refund's whole
  // lifecycle, not only its worst moment — an operator reading a reversal
  // needs to see the sibling instalment that did land.
  assertEquals(
    paymentRefundRecord(readRefund({ id: 're_ok', status: 'succeeded', amount: 250 })),
    {
      stripe_refund_id: 're_ok',
      amount_cents: 250,
      status: 'succeeded',
      failure_reason: null,
    },
  );
});

Deno.test('paymentRefundRecord — fails closed on each of the three it cannot guess', () => {
  // No Stripe Refund id: no idempotency key. A row keyed on anything else
  // double-counts on the next redelivery, which is the whole reason this is a
  // child row rather than arithmetic on donations.refunded_cents (§ 789).
  assertStrictEquals(
    paymentRefundRecord(readRefund({ status: 'failed', amount: 500 })),
    null,
  );
  // No amount: nothing to correct a total by.
  assertStrictEquals(
    paymentRefundRecord(readRefund({ id: 're_1', status: 'failed' })),
    null,
  );
  // A status outside the CHECK's set.
  assertStrictEquals(
    paymentRefundRecord(readRefund({ id: 're_1', status: 'reversed', amount: 500 })),
    null,
  );
  // Each refusal reproduces the pre-table behaviour exactly: no row, the
  // thermometer still understating, the log line still there.
});

Deno.test('paymentRefundRecord — an over-long reason is clipped, never dropped', () => {
  // payment_refunds_failure_reason_len_chk caps it at 120. Refusing the whole
  // row over a cosmetic field would lose the money discrepancy; a 23514 would
  // 500 into an endless Stripe retry.
  const record = paymentRefundRecord(readRefund({
    id: 're_long',
    status: 'failed',
    amount: 500,
    failure_reason: 'x'.repeat(500),
  }));
  assertStrictEquals(record?.failure_reason?.length, 120);
  assertStrictEquals(record?.status, 'failed');
  // The longest reason Stripe documents, `charge_for_pending_refund_disputed`,
  // is well inside the cap and must survive intact.
  assertStrictEquals(
    paymentRefundRecord(readRefund({
      id: 're_doc',
      status: 'failed',
      amount: 500,
      failure_reason: 'charge_for_pending_refund_disputed',
    }))?.failure_reason,
    'charge_for_pending_refund_disputed',
  );
});
