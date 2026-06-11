/// Run with `cd apps/backend && deno test supabase/functions/stripe-events-webhook/lib.test.ts`.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { hmacHex } from '../_shared/webhook_security.ts';
import {
  attendeeRowFromSession,
  capacityDecision,
  orderStatusTransition,
  parseStripeEventEnvelope,
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

Deno.test('orderStatusTransition — terminal source states never transition', () => {
  for (const s of ['paid', 'refunded', 'partially_refunded', 'failed', 'canceled']) {
    assertStrictEquals(orderStatusTransition(s, 'checkout.session.completed'), null);
    assertStrictEquals(orderStatusTransition(s, 'checkout.session.expired'), null);
  }
});

Deno.test('orderStatusTransition — unknown event type -> null', () => {
  assertStrictEquals(orderStatusTransition('pending', 'charge.refunded'), null);
  assertStrictEquals(orderStatusTransition('pending', 'account.updated'), null);
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
