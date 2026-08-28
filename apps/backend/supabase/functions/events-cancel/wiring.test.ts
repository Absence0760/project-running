/// Run with `cd apps/backend && deno test --allow-read supabase/functions/events-cancel/wiring.test.ts`.
///
/// Source-grep guards in the `events-checkout/wiring.test.ts` idiom. This is
/// the one call in the tier that moves money OUT, and the half `lib.test.ts`
/// cannot see is which shape actually reaches Stripe: a hand-rolled literal at
/// the call site satisfies neither the params guard nor the lib test, and that
/// is precisely how the transfer went un-reversed for as long as it did
/// (decisions § 769). Exercising the handler itself needs a live Supabase plus
/// operator `sk_test_` keys.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

Deno.test('the refund params come from buildRefundParams, not an inline literal', () => {
  const call = SRC.match(/stripe\.refunds\.create\(\s*([^\n,]+)/);
  assert(call, 'no stripe.refunds.create call found — has the refund moved?');
  assert(
    call[1].trim() === 'buildRefundParams(paymentIntent)',
    'the refund body must be built by buildRefundParams, whose keys the ' +
      '`RefundParamsAreStripeParams` alias checks against the SDK and whose ' +
      `flags lib.test.ts pins. Got: ${call[1]}`,
  );
});

Deno.test('the params guard alias is still declared against the SDK', () => {
  // Assignability alone does not check a function return's keys — no
  // excess-property check runs on one. Declaring the alias IS the check, so
  // nothing references it and a tidy-up is free to delete it.
  assert(
    /UnknownParamKeys<\s*ReturnType<typeof buildRefundParams>,\s*Stripe\.RefundCreateParams\s*>/
      .test(SRC),
    'the RefundCreateParams excess-property guard is gone. Without it a ' +
      'misspelled `reverse_transfers` compiles and Stripe answers `Received ' +
      'unknown parameter` — leaving the transfer un-reversed at request time.',
  );
});

Deno.test('the refund stamp is guarded on the status read, not a hardcoded paid', () => {
  // A refundable order may be `partially_refunded`. Matching only 'paid'
  // updates zero rows and reports no error, so the stamp silently never lands
  // and the "refund in progress" badge never shows.
  const stamps = SRC.match(/refund_initiated_at:[^}]*\}\)[\s\S]{0,200}?\.eq\('status', ([^)]+)\)/g);
  assert(stamps && stamps.length === 2, `expected the stamp + its rollback, got ${stamps?.length}`);
  for (const stamp of stamps) {
    assert(
      /\.eq\('status', orderStatus\)/.test(stamp),
      `a refund_initiated_at write is still keyed on a literal status: ${stamp.slice(-60)}`,
    );
  }
});
