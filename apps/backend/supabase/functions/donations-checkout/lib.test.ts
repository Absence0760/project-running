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
