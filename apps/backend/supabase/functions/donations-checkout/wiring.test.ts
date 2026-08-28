/// Run with `cd apps/backend && deno test --allow-read supabase/functions/donations-checkout/wiring.test.ts`.
///
/// Source-grep guards in the `stripe-events-webhook/wiring.test.ts` idiom.
/// `lib.test.ts` can prove `resolveDonationIntent` decides correctly; it cannot
/// see whether index.ts asks it anything, whether it asks BEFORE the Stripe
/// call (the whole point — a decision taken afterwards cannot stop a second
/// session being opened), or whether the row it writes carries the key a later
/// call has to find it by. Each of those is positional and readable off the
/// source, and each restores the § 769 double-charge on its own.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

Deno.test('the client idempotency key is required and validated', () => {
  // An optional dedupe key is one an omitted field silently disables, and a
  // free-form one is a table-wide unique column an attacker picks values in.
  assert(
    /const idempotencyKey = typeof body\.idempotency_key === 'string'/.test(SRC),
    'the key must be read off the request body',
  );
  assert(
    /if \(!idempotencyKey \|\| !isValidUuid\(idempotencyKey\)\)/.test(SRC),
    'a missing or malformed key must be rejected, not defaulted',
  );
});

Deno.test('the intent is resolved BEFORE the Stripe session is created', () => {
  const resolve = SRC.indexOf('resolveDonationIntent(');
  const create = SRC.indexOf('stripe.checkout.sessions.create');
  assert(resolve !== -1, 'the intent resolution is gone — has the dedupe moved?');
  assert(create !== -1, 'the Stripe create is gone');
  assert(
    resolve < create,
    'resolving a retry after the session exists cannot stop the second session',
  );
  assert(
    /\.eq\('client_request_id', idempotencyKey\)/.test(SRC),
    'the pending donation must be looked up by the caller\'s key',
  );
});

Deno.test('the donation row is persisted before the Stripe call, carrying the key', () => {
  // Writing the row afterwards left the only record of the attempt at Stripe,
  // where the next call could not find it: a crash between the create and the
  // insert made the retry open a second session against a second row.
  const insert = SRC.indexOf(".from('donations')\n      .insert({");
  const create = SRC.indexOf('stripe.checkout.sessions.create');
  assert(insert !== -1, 'the donation insert is gone — has it moved?');
  assert(insert < create, 'the donation must exist before the Checkout Session does');
  const insertBlock = SRC.slice(insert, create);
  assert(
    insertBlock.includes('client_request_id: idempotencyKey'),
    'the row must carry the key, or no later call can resolve to it',
  );
  assert(
    !insertBlock.includes('stripe_checkout_session_id'),
    'the session id cannot be known before the session exists',
  );
});

Deno.test('the Stripe key is derived from the resolved donation id', () => {
  // The id is what makes the params byte-identical across a retry, which is
  // what makes Stripe replay rather than answer `idempotency_error`.
  assert(
    /\{ idempotencyKey: donationIdempotencyKey\(donationId\) \}/.test(SRC),
    'the Stripe idempotency key must be built from the resolved donation id',
  );
  assert(
    /donationId = intent\.donationId/.test(SRC),
    'a resumed attempt must reuse the donation id it already opened',
  );
});
