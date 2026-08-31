/// The donation intent, the amount gate and the two donor-supplied text fields.
///
/// `resolveDonationIntent` is a client-presented idempotency key, which means
/// the interesting inputs are the ones a client would not send: a key against a
/// changed request, a key whose donation is already paid, and the precedence
/// between the two. `clampText` is the other half of the same boundary — the
/// only place donor free text is shaped before it is persisted.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/donations-checkout/intent_invariants.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildDonationSessionParams,
  clampText,
  computeApplicationFeeCents,
  type DonationIntentRequest,
  type DonationIntentRow,
  donationIdempotencyKey,
  MAX_DISPLAY_NAME_LEN,
  MAX_DONATION_CENTS,
  MAX_MESSAGE_LEN,
  MIN_DONATION_CENTS,
  resolveDonationIntent,
  validateDonationAmount,
} from './lib.ts';
import { checkoutIdempotencyKey } from '../events-checkout/lib.ts';

const REQUEST: DonationIntentRequest = {
  fundraiserId: 'fr_1',
  amountCents: 5000,
  donorUserId: 'u_1',
};

const row = (over: Partial<DonationIntentRow> = {}): DonationIntentRow => ({
  id: 'don_1',
  status: 'pending',
  fundraiser_id: 'fr_1',
  amount_cents: 5000,
  donor_user_id: 'u_1',
  ...over,
});

Deno.test('resolveDonationIntent — every field of the request is part of the match', () => {
  // A key that resolved on the id alone would hand a guesser somebody else's
  // open Checkout Session. Each field is varied on its own so a comparison
  // dropped from the conjunction is named.
  assertEquals(resolveDonationIntent(row(), REQUEST), { action: 'resume', donationId: 'don_1' });
  const changed: Array<[string, Partial<DonationIntentRow>]> = [
    ['fundraiser', { fundraiser_id: 'fr_2' }],
    ['amount', { amount_cents: 5001 }],
    ['donor', { donor_user_id: 'u_2' }],
    ['donor becoming anonymous', { donor_user_id: null }],
  ];
  for (const [what, over] of changed) {
    assertEquals(
      resolveDonationIntent(row(over), REQUEST),
      { action: 'conflict', reason: 'params_changed' },
      what,
    );
  }
});

Deno.test('resolveDonationIntent — an anonymous donor resumes only against a null donor', () => {
  const anon: DonationIntentRequest = { ...REQUEST, donorUserId: null };
  assertEquals(resolveDonationIntent(row({ donor_user_id: null }), anon), {
    action: 'resume',
    donationId: 'don_1',
  });
  assertEquals(resolveDonationIntent(row({ donor_user_id: 'u_1' }), anon), {
    action: 'conflict',
    reason: 'params_changed',
  });
});

Deno.test('resolveDonationIntent — a key whose donation is no longer pending is never reopened', () => {
  // Opening a fresh donation for a key whose row already settled charges the
  // donor a second time, which is the failure the whole mechanism exists to
  // prevent.
  for (const status of ['paid', 'partially_refunded', 'refunded', 'refund_failed', 'failed', 'canceled', 'Pending', '']) {
    assertEquals(
      resolveDonationIntent(row({ status }), REQUEST),
      { action: 'conflict', reason: 'already_used' },
      status,
    );
  }
});

Deno.test('resolveDonationIntent — a wrong-request check outranks a spent key at every status', () => {
  // Both refusals are conflicts, but they say different things to the client,
  // and the params check has to be first: a guessed key against a settled
  // donation must not be told that key exists and belongs to this request.
  for (const status of ['paid', 'refunded', 'canceled']) {
    assertEquals(
      resolveDonationIntent(row({ status, fundraiser_id: 'fr_2' }), REQUEST),
      { action: 'conflict', reason: 'params_changed' },
      status,
    );
  }
});

Deno.test('resolveDonationIntent — no row is the only path that opens a new donation', () => {
  assertEquals(resolveDonationIntent(null, REQUEST), { action: 'open' });
});

Deno.test('donationIdempotencyKey — namespaced, stable, and never the checkout rail\'s key', () => {
  assertEquals(donationIdempotencyKey('don_1'), 'donations-checkout:don_1');
  assertEquals(donationIdempotencyKey('don_1'), donationIdempotencyKey('don_1'));
  assert(donationIdempotencyKey('a') !== donationIdempotencyKey('b'));
  // The two rails share one Stripe account and therefore one idempotency key
  // space. An unnamespaced key would collide the day a donation id equalled an
  // order id, and Stripe answers a collision with `idempotency_error`.
  assert(donationIdempotencyKey('x') !== checkoutIdempotencyKey('x'));
});

Deno.test('validateDonationAmount — the band is closed at both ends, to the cent', () => {
  assertEquals(validateDonationAmount(MIN_DONATION_CENTS - 1), 'too_small');
  assertEquals(validateDonationAmount(MIN_DONATION_CENTS), 'ok');
  assertEquals(validateDonationAmount(MAX_DONATION_CENTS), 'ok');
  assertEquals(validateDonationAmount(MAX_DONATION_CENTS + 1), 'too_large');
  assertEquals(MIN_DONATION_CENTS, 100);
  assertEquals(MAX_DONATION_CENTS, 1_000_000);
});

Deno.test('validateDonationAmount — anything that is not an integer number of cents is invalid', () => {
  const invalid: unknown[] = [
    '5000',
    null,
    undefined,
    true,
    {},
    [],
    [5000],
    5000.5,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.NEGATIVE_INFINITY,
  ];
  for (const bad of invalid) {
    assertEquals(validateDonationAmount(bad), 'invalid', JSON.stringify(bad) ?? String(bad));
  }
  // A negative is a NUMBER, so it is graded rather than refused as malformed —
  // and it lands below the floor, which is the answer the donor can act on.
  assertEquals(validateDonationAmount(-5000), 'too_small');
  assertEquals(validateDonationAmount(0), 'too_small');
});

Deno.test('clampText — trims, nulls the blank, and caps at exactly the limit', () => {
  assertEquals(clampText('  hello  ', 80), 'hello');
  assertEquals(clampText('   ', 80), null);
  assertEquals(clampText('\t\n', 80), null);
  assertEquals(clampText('', 80), null);
  assertEquals(clampText('x'.repeat(80), 80), 'x'.repeat(80));
  assertEquals(clampText('x'.repeat(81), 80), 'x'.repeat(80));
  // The trim runs BEFORE the cap, so padding cannot eat the allowance.
  assertEquals(clampText(`${' '.repeat(50)}${'x'.repeat(80)}`, 80), 'x'.repeat(80));
});

Deno.test('clampText — a non-string is null, never coerced', () => {
  for (const bad of [null, undefined, 42, true, {}, [], ['a']]) {
    assertEquals(clampText(bad, 80), null, String(bad));
  }
});

Deno.test('clampText — truncation never leaves a lone surrogate in a value we persist', () => {
  // `slice` counts UTF-16 units, so a cap landing inside a surrogate pair used
  // to hand back an ill-formed string: `isWellFormed()` false, and
  // `JSON.stringify` emits it as a bare `\ud83d` escape, which is exactly the
  // form a Postgres JSON parse refuses ("Unicode low surrogate must follow a
  // high surrogate"). The donation insert then fails on a message the donor can
  // only ever retype identically.
  const wellFormed = (s: string) => [...s].every((c) => {
    const code = c.codePointAt(0)!;
    return code < 0xd800 || code > 0xdfff;
  });
  for (const cap of [4, 40, MAX_DISPLAY_NAME_LEN, MAX_MESSAGE_LEN]) {
    for (let lead = 0; lead < 4; lead++) {
      const text = `${'a'.repeat(cap - 1 + lead)}\u{1F600}${'b'.repeat(10)}`;
      const out = clampText(text, cap);
      assert(out !== null);
      assert(wellFormed(out), `cap ${cap} lead ${lead} produced ${JSON.stringify(out)}`);
      assert(out.length <= cap, `cap ${cap} lead ${lead} overran`);
    }
  }
  // The pair survives whole when it fits, so the guard trims the split pair and
  // not the emoji.
  assertEquals(clampText(`${'a'.repeat(8)}\u{1F600}`, 10), `${'a'.repeat(8)}\u{1F600}`);
  assertEquals(clampText(`${'a'.repeat(9)}\u{1F600}`, 10), 'a'.repeat(9));
});

Deno.test('clampText — an input that was already ill-formed does not become a stored value', () => {
  // A client can put a bare `\ud83d` in its JSON body, so the repair cannot be
  // conditional on this function having done the cutting.
  assertEquals(clampText('\ud83d', 80), null);
  assertEquals(clampText('ok\ud83d', 80), 'ok');
});

Deno.test('computeApplicationFeeCents — a charity donation defaults to no platform cut', () => {
  assertEquals(computeApplicationFeeCents(5000, 0), 0);
  assertEquals(computeApplicationFeeCents(MAX_DONATION_CENTS, 0), 0);
  // The same function the event rail uses, so a fee the donation path did want
  // is floored and clamped identically.
  assertEquals(computeApplicationFeeCents(5000, 250), 125);
  assertEquals(computeApplicationFeeCents(5000, 20000), 5000);
});

Deno.test('buildDonationSessionParams — the exact key set, and no expiry', () => {
  const params = buildDonationSessionParams({
    amountCents: 5000,
    currency: 'usd',
    productName: 'Trail fund',
    applicationFeeCents: 0,
    ownerAccountId: 'acct_1',
    successUrl: 'https://threkir.com/ok',
    cancelUrl: 'https://threkir.com/no',
    metadata: { kind: 'donation', donation_id: 'don_1', fundraiser_id: 'fr_1' },
  });
  assertEquals(Object.keys(params).sort(), [
    'cancel_url',
    'line_items',
    'metadata',
    'mode',
    'payment_intent_data',
    'success_url',
  ]);
  // A donation holds no seat, so it holds no reservation that must lapse — and
  // an `expires_at` would move the body under a resumed idempotency key.
  assert(!('expires_at' in params));
  assertEquals(params.mode, 'payment');
  assertEquals(params.payment_intent_data.application_fee_amount, 0);
  assertEquals(params.payment_intent_data.transfer_data.destination, 'acct_1');
  assertEquals(params.metadata.kind, 'donation');
});

Deno.test('buildDonationSessionParams — a resumed donation rebuilds byte-identical params', () => {
  // The whole point of `resume`: Stripe replays the session already open only
  // if the body it is presented with is the one the key was minted against.
  const args = {
    amountCents: 5000,
    currency: 'usd',
    productName: 'Trail fund',
    applicationFeeCents: 0,
    ownerAccountId: 'acct_1',
    successUrl: 'https://threkir.com/ok',
    cancelUrl: 'https://threkir.com/no',
    metadata: { kind: 'donation' as const, donation_id: 'don_1', fundraiser_id: 'fr_1' },
  };
  assertEquals(
    JSON.stringify(buildDonationSessionParams(args)),
    JSON.stringify(buildDonationSessionParams(args)),
  );
});
