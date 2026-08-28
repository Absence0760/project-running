/// Run with `cd apps/backend && deno test supabase/functions/donations-checkout/lib.test.ts`.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildDonationSessionParams,
  clampText,
  computeApplicationFeeCents,
  donationIdempotencyKey,
  MAX_DONATION_CENTS,
  MAX_DISPLAY_NAME_LEN,
  MIN_DONATION_CENTS,
  resolveDonationIntent,
  validateDonationAmount,
} from './lib.ts';

Deno.test('validateDonationAmount — in-bounds integer is ok', () => {
  assertStrictEquals(validateDonationAmount(2500), 'ok');
  assertStrictEquals(validateDonationAmount(MIN_DONATION_CENTS), 'ok');
  assertStrictEquals(validateDonationAmount(MAX_DONATION_CENTS), 'ok');
});

Deno.test('validateDonationAmount — below floor / above ceiling', () => {
  assertStrictEquals(validateDonationAmount(MIN_DONATION_CENTS - 1), 'too_small');
  assertStrictEquals(validateDonationAmount(MAX_DONATION_CENTS + 1), 'too_large');
});

Deno.test('validateDonationAmount — non-integer / non-finite / wrong type is invalid', () => {
  assertStrictEquals(validateDonationAmount(25.5), 'invalid');
  assertStrictEquals(validateDonationAmount(Number.NaN), 'invalid');
  assertStrictEquals(validateDonationAmount('2500' as unknown), 'invalid');
  assertStrictEquals(validateDonationAmount(undefined as unknown), 'invalid');
});

Deno.test('computeApplicationFeeCents — 0 bps (charity default) yields 0', () => {
  assertStrictEquals(computeApplicationFeeCents(2500, 0), 0);
});

Deno.test('computeApplicationFeeCents — floors the cut', () => {
  // 2.5% of 2500 = 62.5 -> floor 62
  assertStrictEquals(computeApplicationFeeCents(2500, 250), 62);
});

Deno.test('clampText — trims, nulls blank, caps length', () => {
  assertStrictEquals(clampText('  Jane D.  ', MAX_DISPLAY_NAME_LEN), 'Jane D.');
  assertStrictEquals(clampText('   ', MAX_DISPLAY_NAME_LEN), null);
  assertStrictEquals(clampText(undefined, MAX_DISPLAY_NAME_LEN), null);
  assertStrictEquals(clampText('x'.repeat(200), MAX_DISPLAY_NAME_LEN)!.length, MAX_DISPLAY_NAME_LEN);
});

Deno.test('donationIdempotencyKey — stable function of the donation id', () => {
  assertStrictEquals(donationIdempotencyKey('abc'), 'donations-checkout:abc');
  // different rows -> different keys
  assertStrictEquals(donationIdempotencyKey('abc') === donationIdempotencyKey('def'), false);
});

const REQ = { fundraiserId: 'f1', amountCents: 2500, donorUserId: 'u1' };
const ROW = {
  id: 'd1',
  status: 'pending',
  fundraiser_id: 'f1',
  amount_cents: 2500,
  donor_user_id: 'u1' as string | null,
};

Deno.test('resolveDonationIntent — no row for the key opens a new donation', () => {
  assertEquals(resolveDonationIntent(null, REQ), { action: 'open' });
});

Deno.test('resolveDonationIntent — a pending row for the same request is resumed', () => {
  // The whole point: the retry rebuilds the same Stripe params against the same
  // donation id, so Stripe replays the session already open instead of opening
  // a second one the donor could also pay. decisions § 776.
  assertEquals(resolveDonationIntent({ ...ROW }, REQ), { action: 'resume', donationId: 'd1' });
});

Deno.test('resolveDonationIntent — an anonymous donor resumes on a null donor id', () => {
  // A donation needs no JWT (fundraising.md), which is exactly why the key has
  // to come from the client — there is no identity for the server to key on.
  const anon = { ...ROW, donor_user_id: null };
  assertEquals(
    resolveDonationIntent(anon, { ...REQ, donorUserId: null }),
    { action: 'resume', donationId: 'd1' },
  );
  // …and an anonymous key does not resolve for a signed-in caller, or the
  // reverse: those are different donors presenting the same key.
  assertEquals(
    resolveDonationIntent(anon, REQ),
    { action: 'conflict', reason: 'params_changed' },
  );
  assertEquals(
    resolveDonationIntent({ ...ROW }, { ...REQ, donorUserId: null }),
    { action: 'conflict', reason: 'params_changed' },
  );
});

Deno.test('resolveDonationIntent — a key presented against a different request conflicts', () => {
  // A guessed or replayed key must not hand its bearer someone else's open
  // Checkout Session. Guessing a v4 UUID is already infeasible; this makes the
  // consequence of guessing one nil rather than small.
  assertEquals(
    resolveDonationIntent({ ...ROW, fundraiser_id: 'other' }, REQ),
    { action: 'conflict', reason: 'params_changed' },
  );
  assertEquals(
    resolveDonationIntent({ ...ROW, amount_cents: 9900 }, REQ),
    { action: 'conflict', reason: 'params_changed' },
  );
  assertEquals(
    resolveDonationIntent({ ...ROW, donor_user_id: 'someone_else' }, REQ),
    { action: 'conflict', reason: 'params_changed' },
  );
});

Deno.test('resolveDonationIntent — a spent key is refused, never reopened', () => {
  // A key whose row is already `paid` means the client is retrying an attempt
  // that in fact completed. Opening a new donation there charges the donor a
  // second time — the exact failure the key exists to prevent. A new donation
  // carries a new key.
  for (const status of ['paid', 'partially_refunded', 'refunded', 'canceled', 'failed']) {
    assertEquals(
      resolveDonationIntent({ ...ROW, status }, REQ),
      { action: 'conflict', reason: 'already_used' },
      `status=${status} must not resume`,
    );
  }
});

Deno.test('resolveDonationIntent — a wrong-request check outranks a spent key', () => {
  // Both are 409s, but they are different sentences: the caller who changed
  // the amount is told the key does not match this request, not that their
  // donation already went through.
  assertEquals(
    resolveDonationIntent({ ...ROW, status: 'paid', amount_cents: 100 }, REQ),
    { action: 'conflict', reason: 'params_changed' },
  );
});

Deno.test('buildDonationSessionParams — destination charge with owner account + metadata', () => {
  const params = buildDonationSessionParams({
    amountCents: 2500,
    currency: 'usd',
    productName: 'Donation: Red Cross',
    applicationFeeCents: 0,
    ownerAccountId: 'acct_owner_123',
    successUrl: 'https://app.example/fundraisers/f1?donated=1',
    cancelUrl: 'https://app.example/fundraisers/f1?donated=0',
    metadata: { kind: 'donation', donation_id: 'd1', fundraiser_id: 'f1' },
  });
  assertStrictEquals(params.mode, 'payment');
  assertStrictEquals(params.line_items[0].price_data.unit_amount, 2500);
  assertStrictEquals(params.payment_intent_data.transfer_data.destination, 'acct_owner_123');
  assertStrictEquals(params.payment_intent_data.application_fee_amount, 0);
  assertEquals(params.metadata, { kind: 'donation', donation_id: 'd1', fundraiser_id: 'f1' });
  // No reservation TTL on a donation (unlike a seat).
  assertStrictEquals('expires_at' in params, false);
});
