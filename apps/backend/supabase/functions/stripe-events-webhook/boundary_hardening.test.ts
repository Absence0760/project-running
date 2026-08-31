/// The wire boundary: what a body has to be before any ledger arm is reached.
///
/// Everything downstream of here is HMAC-verified and therefore trusted to be
/// FROM Stripe. That makes this the only place where an attacker chooses the
/// bytes, so the properties worth stating are the ones a valid-signature test
/// cannot reach: what the verifier does with a header shape Stripe never sends,
/// what the parser does with a body that is JSON but not an event, and what the
/// narrowing readers do with a field of the wrong type.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/stripe-events-webhook/boundary_hardening.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { hmacHex } from '../_shared/webhook_security.ts';
import {
  attendeeRowFromSession,
  donationIdFromSession,
  isDonationSession,
  isPaymentSettled,
  parseStripeEventEnvelope,
  readCharge,
  readCheckoutSession,
  readConnectAccount,
  readRefund,
  verifyStripeSignature,
} from './lib.ts';

const SECRET = 'whsec_testsecret';
const T = 1_700_000_000;
const NOW_MS = T * 1000;

const sign = (body: string, t = T, secret = SECRET) => hmacHex(secret, `${t}.${body}`);

Deno.test('verifyStripeSignature — the signed payload is the RAW bytes, byte for byte', async () => {
  // Re-serialising a parsed body does not round-trip whitespace or key order,
  // so a verifier that signed anything but the bytes it was handed would reject
  // every real delivery. Two bodies that JSON.parse identically must produce
  // different verdicts under one signature.
  const raw = '{"id":"evt_1", "type":"charge.refunded"}';
  const reserialised = JSON.stringify(JSON.parse(raw));
  assert(raw !== reserialised);
  const v1 = await sign(raw);
  assertEquals(await verifyStripeSignature(raw, `t=${T},v1=${v1}`, SECRET, NOW_MS), true);
  assertEquals(await verifyStripeSignature(reserialised, `t=${T},v1=${v1}`, SECRET, NOW_MS), false);
});

Deno.test('verifyStripeSignature — a unicode body verifies over its UTF-8 bytes', async () => {
  // The donor message field is free text, so an event body really does carry
  // astral-plane characters. A verifier that hashed anything but UTF-8 would
  // reject those deliveries only.
  const raw = JSON.stringify({ id: 'evt_1', message: 'Bonne chance \u{1F3C3}‍♀️ 日本' });
  const v1 = await sign(raw);
  assertEquals(await verifyStripeSignature(raw, `t=${T},v1=${v1}`, SECRET, NOW_MS), true);
  const tweaked = raw.replace('日', '本');
  assertEquals(await verifyStripeSignature(tweaked, `t=${T},v1=${v1}`, SECRET, NOW_MS), false);
});

Deno.test('verifyStripeSignature — a large body still verifies, and one flipped byte does not', async () => {
  const raw = `{"id":"evt_1","pad":"${'x'.repeat(512 * 1024)}"}`;
  const v1 = await sign(raw);
  assertEquals(await verifyStripeSignature(raw, `t=${T},v1=${v1}`, SECRET, NOW_MS), true);
  const flipped = `${raw.slice(0, 300_000)}y${raw.slice(300_001)}`;
  assertEquals(flipped.length, raw.length);
  assertEquals(await verifyStripeSignature(flipped, `t=${T},v1=${v1}`, SECRET, NOW_MS), false);
});

Deno.test('verifyStripeSignature — an empty body is signable and its signature is body-specific', async () => {
  const v1 = await sign('');
  assertEquals(await verifyStripeSignature('', `t=${T},v1=${v1}`, SECRET, NOW_MS), true);
  assertEquals(await verifyStripeSignature('{}', `t=${T},v1=${v1}`, SECRET, NOW_MS), false);
});

Deno.test('verifyStripeSignature — every unusable timestamp is refused', async () => {
  const raw = '{"id":"evt_1"}';
  const v1 = await sign(raw);
  // A `t` that parses to something other than the seconds Stripe signed cannot
  // reproduce the digest, so each of these fails for the right reason rather
  // than by accident: the header is rejected outright or the HMAC input is
  // wrong. Both are refusals, and a refusal is the only safe answer.
  const headers = [
    `v1=${v1}`,
    `t=,v1=${v1}`,
    `t=abc,v1=${v1}`,
    `t=1.7e9,v1=${v1}`,
    `t= ,v1=${v1}`,
    `t=NaN,v1=${v1}`,
    `t=Infinity,v1=${v1}`,
    `t=0x${T.toString(16)},v1=${v1}`,
  ];
  for (const header of headers) {
    assertEquals(await verifyStripeSignature(raw, header, SECRET, NOW_MS), false, header);
  }
});

Deno.test('verifyStripeSignature — a v0 scheme alone never establishes a signature', async () => {
  // Stripe's older `v0` scheme is deliberately ignored. A verifier that
  // accepted it would take a digest computed under different rules, and an
  // endpoint carrying only v0 must fail rather than pass on a v1 match it
  // never made.
  const raw = '{"id":"evt_1"}';
  const v1 = await sign(raw);
  assertEquals(await verifyStripeSignature(raw, `t=${T},v0=${v1}`, SECRET, NOW_MS), false);
  assertEquals(
    await verifyStripeSignature(raw, `t=${T},v0=${v1},v1=${v1}`, SECRET, NOW_MS),
    true,
    'a v1 beside a v0 is still the v1 that decides',
  );
});

Deno.test('verifyStripeSignature — an unknown scheme cannot smuggle a match', async () => {
  const raw = '{"id":"evt_1"}';
  const v1 = await sign(raw);
  assertEquals(await verifyStripeSignature(raw, `t=${T},v2=${v1}`, SECRET, NOW_MS), false);
  assertEquals(await verifyStripeSignature(raw, `t=${T},V1=${v1}`, SECRET, NOW_MS), false);
  assertEquals(await verifyStripeSignature(raw, `t=${T},${v1}`, SECRET, NOW_MS), false);
});

Deno.test('verifyStripeSignature — the hex comparison does not fold case', async () => {
  // `hmacHex` emits lower-case and so does Stripe. Accepting the upper-case
  // form would mean the comparison is doing something other than comparing the
  // digest, which is the property the constant-time compare exists to have.
  const raw = '{"id":"evt_1"}';
  const v1 = await sign(raw);
  assertEquals(await verifyStripeSignature(raw, `t=${T},v1=${v1}`, SECRET, NOW_MS), true);
  assertEquals(await verifyStripeSignature(raw, `t=${T},v1=${v1.toUpperCase()}`, SECRET, NOW_MS), false);
});

Deno.test('verifyStripeSignature — a truncated or padded digest is refused', async () => {
  const raw = '{"id":"evt_1"}';
  const v1 = await sign(raw);
  for (const bad of [v1.slice(0, -1), v1.slice(1), `${v1}0`, `0${v1}`, '', v1.replace(/./g, '0')]) {
    assertEquals(await verifyStripeSignature(raw, `t=${T},v1=${bad}`, SECRET, NOW_MS), false, bad.slice(0, 8));
  }
});

Deno.test('verifyStripeSignature — the freshness window is symmetric and its edge is inclusive', async () => {
  const raw = '{"id":"evt_1"}';
  const v1 = await sign(raw);
  const header = `t=${T},v1=${v1}`;
  const at = (offsetSec: number) => verifyStripeSignature(raw, header, SECRET, NOW_MS + offsetSec * 1000, 300);
  assertEquals(await at(0), true);
  assertEquals(await at(300), true, 'exactly at the tolerance still passes');
  assertEquals(await at(-300), true, 'and symmetrically in the past');
  assertEquals(await at(301), false);
  assertEquals(await at(-301), false);
});

Deno.test('verifyStripeSignature — a zero tolerance admits only the signing second', async () => {
  const raw = '{"id":"evt_1"}';
  const v1 = await sign(raw);
  const header = `t=${T},v1=${v1}`;
  assertEquals(await verifyStripeSignature(raw, header, SECRET, NOW_MS, 0), true);
  assertEquals(await verifyStripeSignature(raw, header, SECRET, NOW_MS + 1001, 0), false);
});

Deno.test('verifyStripeSignature — a rotation window accepts either live secret, and no third', async () => {
  const raw = '{"id":"evt_1"}';
  const oldSig = await sign(raw, T, 'whsec_old');
  const newSig = await sign(raw, T, 'whsec_new');
  const header = `t=${T},v1=${oldSig},v1=${newSig}`;
  assertEquals(await verifyStripeSignature(raw, header, 'whsec_old', NOW_MS), true);
  assertEquals(await verifyStripeSignature(raw, header, 'whsec_new', NOW_MS), true);
  assertEquals(await verifyStripeSignature(raw, header, 'whsec_other', NOW_MS), false);
});

Deno.test('verifyStripeSignature — an unset secret refuses without reaching the primitive', async () => {
  // A deployment that forgot STRIPE_WEBHOOK_SECRET must reject every delivery.
  // The guard has to sit AHEAD of the digest, not merely fail the comparison:
  // Web Crypto refuses a zero-length HMAC key with a DataError, so a verifier
  // that got as far as `hmacHex` would turn a misconfiguration into an
  // unhandled throw — a 500 and a retried delivery, not a refusal. Proved by
  // observation, since the same call from this test's own helper throws.
  const raw = '{"id":"evt_1"}';
  const v1 = await sign(raw);
  assertEquals(await verifyStripeSignature(raw, `t=${T},v1=${v1}`, '', NOW_MS), false);
  let threw = false;
  try {
    await hmacHex('', `${T}.${raw}`);
  } catch {
    threw = true;
  }
  assert(threw, 'an empty HMAC key throws, which is what the early guard avoids');
});

Deno.test('parseStripeEventEnvelope — every shape that is JSON but not an event is refused', () => {
  const refused = [
    '',
    'null',
    'true',
    '42',
    '"evt_1"',
    '[]',
    '[{"id":"evt_1","type":"x","data":{"object":{}}}]',
    '{',
    '{"type":"x","data":{"object":{}}}',
    '{"id":"evt_1","data":{"object":{}}}',
    '{"id":"evt_1","type":"x"}',
    '{"id":"evt_1","type":"x","data":null}',
    '{"id":"evt_1","type":"x","data":"o"}',
    '{"id":"evt_1","type":"x","data":{}}',
    '{"id":"evt_1","type":"x","data":{"object":null}}',
    '{"id":"evt_1","type":"x","data":{"object":"s"}}',
    '{"id":1,"type":"x","data":{"object":{}}}',
    '{"id":"evt_1","type":2,"data":{"object":{}}}',
  ];
  for (const body of refused) {
    assertEquals(parseStripeEventEnvelope(body), null, JSON.stringify(body).slice(0, 40));
  }
});

Deno.test('parseStripeEventEnvelope — the accepted shape keeps the object verbatim', () => {
  const parsed = parseStripeEventEnvelope(
    '{"id":"evt_1","type":"charge.refunded","data":{"object":{"id":"ch_1","amount":5000}},"livemode":true}',
  );
  assert(parsed !== null);
  assertEquals(parsed.id, 'evt_1');
  assertEquals(parsed.type, 'charge.refunded');
  assertEquals(parsed.data.object, { id: 'ch_1', amount: 5000 });
});

Deno.test('parseStripeEventEnvelope — an empty id or type parses but reaches no arm', () => {
  // The parser's job is shape, not vocabulary: an empty type is a string. What
  // has to hold is that nothing downstream treats it as a known event, which
  // the ledger sweep asserts separately.
  const parsed = parseStripeEventEnvelope('{"id":"","type":"","data":{"object":{}}}');
  assert(parsed !== null);
  assertEquals(parsed.type, '');
});

Deno.test('readCheckoutSession — a settlement claim survives only an exact match', () => {
  const settled = ['paid', 'no_payment_required'];
  const notSettled = ['unpaid', 'Paid', 'PAID', ' paid', 'complete', 'succeeded', ''];
  for (const status of settled) {
    const s = readCheckoutSession({ payment_status: status });
    assertEquals(s.paymentStatus, status);
    assertEquals(isPaymentSettled(s.paymentStatus), true, status);
  }
  for (const status of notSettled) {
    const s = readCheckoutSession({ payment_status: status });
    assertEquals(s.paymentStatus, status === 'unpaid' ? 'unpaid' : null, status);
    assertEquals(isPaymentSettled(s.paymentStatus), false, status);
  }
  for (const bogus of [null, undefined, 1, true, {}, []]) {
    const s = readCheckoutSession({ payment_status: bogus });
    assertEquals(s.paymentStatus, null);
    assertEquals(isPaymentSettled(s.paymentStatus), false);
  }
});

Deno.test('readCheckoutSession — a payment_intent that is neither a string nor an object is absent', () => {
  for (const bogus of [null, undefined, 42, true, [], {}, { id: 7 }, { id: null }]) {
    assertEquals(readCheckoutSession({ payment_intent: bogus }).paymentIntentId, null, String(bogus));
  }
  assertEquals(readCheckoutSession({ payment_intent: 'pi_1' }).paymentIntentId, 'pi_1');
  assertEquals(readCheckoutSession({ payment_intent: { id: 'pi_1' } }).paymentIntentId, 'pi_1');
});

Deno.test('readCheckoutSession — metadata is a flat map of strings and nothing else', () => {
  const s = readCheckoutSession({
    metadata: {
      kind: 'donation',
      n: 1,
      b: true,
      nul: null,
      nested: { a: 'b' },
      arr: ['a'],
      empty: '',
    },
  });
  assertEquals(s.metadata, { kind: 'donation', empty: '' });
  for (const bogus of [null, undefined, 'x', 42, true]) {
    assertEquals(readCheckoutSession({ metadata: bogus }).metadata, {}, String(bogus));
  }
});

Deno.test('readCheckoutSession — a metadata key inherited from a prototype is not a claim', () => {
  // A donation is decided on `metadata.kind` and a seat on four metadata keys.
  // Reading them off anything but the body's own properties would let a crafted
  // JSON body claim a seat it does not carry.
  const body = JSON.parse('{"metadata":{"__proto__":{"kind":"donation"}}}');
  const s = readCheckoutSession(body);
  assertEquals(isDonationSession(s), false);
  assertEquals(donationIdFromSession(s), null);
  assertEquals(attendeeRowFromSession(s), null);
});

Deno.test('attendeeRowFromSession — all four keys are required and none may be empty', () => {
  const full = {
    event_id: 'e1',
    buyer_user_id: 'u1',
    instance_start: '2026-01-01T10:00:00Z',
    order_id: 'o1',
  };
  assertEquals(attendeeRowFromSession(readCheckoutSession({ metadata: full })), {
    event_id: 'e1',
    user_id: 'u1',
    instance_start: '2026-01-01T10:00:00Z',
    order_id: 'o1',
  });
  for (const key of Object.keys(full)) {
    const missing = { ...full } as Record<string, string>;
    delete missing[key];
    assertEquals(
      attendeeRowFromSession(readCheckoutSession({ metadata: missing })),
      null,
      `missing ${key}`,
    );
    const blank = { ...full, [key]: '' };
    assertEquals(
      attendeeRowFromSession(readCheckoutSession({ metadata: blank })),
      null,
      `blank ${key}`,
    );
  }
});

Deno.test('isDonationSession — only the exact stamp the donation checkout writes', () => {
  for (const kind of ['donation', 'Donation', 'DONATION', 'donations', ' donation', '']) {
    assertEquals(
      isDonationSession(readCheckoutSession({ metadata: { kind } })),
      kind === 'donation',
      kind,
    );
  }
  assertEquals(isDonationSession(readCheckoutSession({})), false, 'an event seat carries no kind');
});

Deno.test('readCharge — every field is checked, and an unreadable one is absent', () => {
  assertEquals(
    readCharge({ payment_intent: 'pi_1', refunded: true, amount: 5000, amount_refunded: 5000 }),
    { paymentIntentId: 'pi_1', refunded: true, amountCents: 5000, amountRefundedCents: 5000 },
  );
  assertEquals(readCharge({ refunded: 'true', amount: '5000', amount_refunded: null }), {
    paymentIntentId: null,
    refunded: null,
    amountCents: null,
    amountRefundedCents: null,
  });
  assertEquals(readCharge({}), {
    paymentIntentId: null,
    refunded: null,
    amountCents: null,
    amountRefundedCents: null,
  });
});

Deno.test('readRefund — an expanded payment_intent resolves and a wrong-typed field is absent', () => {
  assertEquals(
    readRefund({
      id: 're_1',
      payment_intent: { id: 'pi_1', object: 'payment_intent' },
      status: 'failed',
      failure_reason: 'expired_or_canceled_card',
    }),
    {
      id: 're_1',
      paymentIntentId: 'pi_1',
      status: 'failed',
      failureReason: 'expired_or_canceled_card',
    },
  );
  assertEquals(readRefund({ id: 1, payment_intent: 7, status: false, failure_reason: {} }), {
    id: null,
    paymentIntentId: null,
    status: null,
    failureReason: null,
  });
});

Deno.test('readConnectAccount — every capability is off unless it is literally true', () => {
  for (const bogus of [undefined, null, 'true', 1, 0, false, {}, []]) {
    const acct = readConnectAccount({
      id: 'acct_1',
      charges_enabled: bogus,
      payouts_enabled: bogus,
      details_submitted: bogus,
    });
    assertEquals(acct.chargesEnabled, false, String(bogus));
    assertEquals(acct.payoutsEnabled, false, String(bogus));
    assertEquals(acct.detailsSubmitted, false, String(bogus));
  }
  assertEquals(
    readConnectAccount({
      id: 'acct_1',
      charges_enabled: true,
      payouts_enabled: true,
      details_submitted: true,
    }),
    { id: 'acct_1', chargesEnabled: true, payoutsEnabled: true, detailsSubmitted: true },
  );
});
