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
  refundScopeOfCharge,
  parseStripeEventEnvelope,
  shouldReleaseDedupe,
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
  const row = attendeeRowFromSession({
    metadata: {
      event_id: 'e1',
      buyer_user_id: 'b1',
      instance_start: '2026-06-11T18:00:00Z',
      order_id: 'o1',
    },
  });
  assertEquals(row, {
    event_id: 'e1',
    user_id: 'b1',
    instance_start: '2026-06-11T18:00:00Z',
    order_id: 'o1',
  });
});

Deno.test('attendeeRowFromSession — missing metadata / keys -> null', () => {
  assertStrictEquals(attendeeRowFromSession({}), null);
  assertStrictEquals(attendeeRowFromSession({ metadata: null }), null);
  assertStrictEquals(
    attendeeRowFromSession({ metadata: { event_id: 'e1', buyer_user_id: 'b1' } }),
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
  assertStrictEquals(isDonationSession({ metadata: { kind: 'donation' } }), true);
  // an event seat session has no kind
  assertStrictEquals(isDonationSession({ metadata: { order_id: 'o1' } }), false);
  assertStrictEquals(isDonationSession({}), false);
  assertStrictEquals(isDonationSession({ metadata: null }), false);
});

Deno.test('donationIdFromSession — extracts donation_id, null when absent', () => {
  assertStrictEquals(
    donationIdFromSession({ metadata: { kind: 'donation', donation_id: 'd1' } }),
    'd1',
  );
  assertStrictEquals(donationIdFromSession({ metadata: { kind: 'donation' } }), null);
  assertStrictEquals(donationIdFromSession({}), null);
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
  // The donations ledger has no partially-refunded state, so the honest answer
  // is to leave the status alone — it is also the only one of the two that is
  // TRUE about the status. decisions § 769.
  assertStrictEquals(donationStatusTransition('paid', 'charge.refunded', 'partial'), null);
  // The completing refund still moves it on, so the seat-less donation ledger
  // reaches the same terminal state once the whole charge is back.
  assertStrictEquals(donationStatusTransition('paid', 'charge.refunded', 'full'), 'refunded');
});

Deno.test('donationStatusTransition — the scope default is full, matching the event ledger', () => {
  // Same default as orderStatusTransition: a caller that cannot read a scope
  // treats the refund as whole, which is the direction that never overstates
  // what a charity has raised.
  assertStrictEquals(
    donationStatusTransition('paid', 'charge.refunded'),
    donationStatusTransition('paid', 'charge.refunded', 'full'),
  );
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
  assertStrictEquals(refundScopeOfCharge({ refunded: true, amount: 5000, amount_refunded: 5000 }), 'full');
});

Deno.test('refundScopeOfCharge — a goodwill part-refund is partial', () => {
  // Stripe emits charge.refunded for a PARTIAL refund too; `refunded` is the
  // discriminator and is false until the whole charge is returned.
  assertStrictEquals(refundScopeOfCharge({ refunded: false, amount: 5000, amount_refunded: 500 }), 'partial');
});

Deno.test('refundScopeOfCharge — refunded:false with nothing refunded is not a partial refund', () => {
  // Must not become a status change on the strength of a zero refund.
  assertStrictEquals(refundScopeOfCharge({ refunded: false, amount: 5000, amount_refunded: 0 }), 'full');
});

Deno.test('refundScopeOfCharge — unknown amounts fall back to full', () => {
  // Historical behaviour, and the safe direction for the buyer.
  assertStrictEquals(refundScopeOfCharge({}), 'full');
  assertStrictEquals(refundScopeOfCharge({ amount: 5000 }), 'full');
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
  const scope = refundScopeOfCharge(charge);
  assertStrictEquals(scope, 'partial');
  assertStrictEquals(
    orderStatusTransition('paid', event!.type, scope),
    'partially_refunded',
  );
});

Deno.test('charge.refunded envelope — the whole charge back releases the seat', () => {
  const event = parseStripeEventEnvelope(chargeRefundedEvent(5000, 5000));
  const charge = event!.data.object;
  assertStrictEquals(refundScopeOfCharge(charge), 'full');
  assertStrictEquals(
    orderStatusTransition('paid', event!.type, refundScopeOfCharge(charge)),
    'refunded',
  );
});

Deno.test('charge.refunded envelope — the balance of a part-refund completes it', () => {
  const first = parseStripeEventEnvelope(chargeRefundedEvent(5000, 500))!;
  const status = orderStatusTransition(
    'paid',
    first.type,
    refundScopeOfCharge(first.data.object),
  );
  const second = parseStripeEventEnvelope(chargeRefundedEvent(5000, 5000))!;
  assertStrictEquals(
    orderStatusTransition(status!, second.type, refundScopeOfCharge(second.data.object)),
    'refunded',
  );
});
