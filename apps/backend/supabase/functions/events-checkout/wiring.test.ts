/// Run with `cd apps/backend && deno test --allow-read supabase/functions/events-checkout/wiring.test.ts`.
///
/// Source-grep guards in the `delete-account/wiring.test.ts` idiom. The
/// handler itself needs a live Supabase plus operator `sk_test_` keys to
/// exercise, but the idempotency contract is positional and readable off
/// the source — and it is the half `lib.test.ts` cannot see.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

Deno.test('the Checkout Session expiry is derived from the order, not the clock', () => {
  // Stripe rejects a reused idempotency key whose request body has moved
  // (`idempotency_error`) instead of replaying it, and holds the key ~24 h.
  // A `Date.now()`-derived `expires_at` moved the body every second, so
  // every retry 502'd for a day. The anchor has to come off the order row.
  const arg = SRC.match(/expiresAtUnix:\s*([^\n,]+)/);
  assert(arg, 'no expiresAtUnix argument found — has the create call moved?');
  assert(
    arg[1].trim() === 'checkoutExpiresAtUnix(anchorMs)',
    `expires_at must be anchored on the order via checkoutExpiresAtUnix(anchorMs), got: ${arg[1]}`,
  );
  assert(
    /const anchorMs = hold\.anchorMs \?\? nowMs;/.test(SRC),
    'anchorMs must come from the resolved hold, falling back to now only for a brand-new order',
  );
});

Deno.test('the idempotency key is scoped to the order, not to (buyer, event, instance)', () => {
  // (buyer, event, instance) spans every hold that pair will ever open, and
  // each hold carries its own order_id and expiry — so the key was certain
  // to be reused against a changed body. The order is the widest scope over
  // which the whole body is constant.
  const arg = SRC.match(/idempotencyKey:\s*([^\n}]+)/);
  assert(arg, 'no idempotencyKey found on the Stripe create call');
  assert(
    arg[1].trim().startsWith('checkoutIdempotencyKey(orderId)'),
    `the key must be checkoutIdempotencyKey(orderId), got: ${arg[1]}`,
  );
});

Deno.test('reusing a live hold does not extend its reservation', () => {
  // The hold is 15 min and the Stripe session 30, both anchored on the same
  // creation instant. Extending `reserved_until` on every re-click would let
  // the hold outlive the session backing it — the buyer would be handed a
  // dead checkout URL while still occupying a seat — and would let a buyer
  // hold a seat indefinitely by re-clicking.
  const reuse = SRC.slice(SRC.indexOf('if (hold.orderId) {'), SRC.indexOf('} else {'));
  assert(reuse.length > 0, 'the hold-reuse branch is gone — has the flow changed?');
  assert(
    !/reserved_until\s*:/.test(reuse),
    'the reuse branch must not write reserved_until',
  );
});

Deno.test('a superseded hold is expired at Stripe before its replacement opens', () => {
  // A lapsed hold released its seat but its session stays payable for another
  // ~15 min. Two open sessions for one registration is a double-charge.
  const idx = SRC.indexOf('checkout.sessions.expire(hold.supersedeSessionId)');
  assert(idx !== -1, 'the superseded session is never expired at Stripe');
  assert(
    idx < SRC.indexOf('checkout.sessions.create('),
    'the supersede must run before the replacement session is created',
  );
});
