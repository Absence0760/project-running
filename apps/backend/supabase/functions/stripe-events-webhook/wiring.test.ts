/// Run with `cd apps/backend && deno test --allow-read supabase/functions/stripe-events-webhook/wiring.test.ts`.
///
/// Source-grep guards in the `delete-account/wiring.test.ts` idiom. The
/// refund arm needs a live Supabase plus operator `whsec_` keys to drive
/// end to end, but the properties below are positional and readable off the
/// source — and they are the half `lib.test.ts` cannot see: the lib knows a
/// partial refund maps to `partially_refunded`, it cannot know that the
/// handler asks it, or that the seat release follows the answer.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

function refundHandler(): string {
  const start = SRC.indexOf('async function handleOrderRefunded');
  assert(start !== -1, 'handleOrderRefunded is gone — has the refund arm moved?');
  const end = SRC.indexOf('async function handleCompleted', start);
  assert(end > start, 'could not find the end of handleOrderRefunded');
  return SRC.slice(start, end);
}

Deno.test('the refund arm reads how much of the charge came back', () => {
  // Stripe emits `charge.refunded` for a PARTIAL refund too. Deciding off the
  // event type alone made a small goodwill refund on a large registration
  // read as a full one.
  const src = refundHandler();
  assert(
    src.includes('refundScopeOfCharge(charge)'),
    'the handler must classify the refund from the charge amounts',
  );
  assert(
    /orderStatusTransition\(\s*order\.status as string,\s*'charge\.refunded',\s*scope,?\s*\)/
      .test(src),
    'the resolved scope must be passed to orderStatusTransition',
  );
});

Deno.test('the seat release follows the resulting STATE, not the event name', () => {
  const src = refundHandler();
  const partialGuard = src.indexOf("nextStatus === 'partially_refunded'");
  const seatDelete = src.indexOf(".from('event_attendees')");
  assert(partialGuard !== -1, 'nothing short-circuits on partially_refunded');
  assert(seatDelete !== -1, 'the seat release is gone');
  assert(
    partialGuard < seatDelete,
    'a partially refunded order still holds its seat — the release must be ' +
      'gated on the transition result before event_attendees is touched',
  );
});

Deno.test('the refund CAS matches the status it read, not a hardcoded paid', () => {
  // A completing refund transitions from `partially_refunded`. Matching only
  // 'paid' would leave the seat unreleasable once any partial had landed.
  const src = refundHandler();
  assert(
    src.includes(".eq('status', order.status as string)"),
    'the CAS must match the status that was read',
  );
  assert(
    !src.includes(".eq('status', 'paid')"),
    'a hardcoded paid CAS cannot complete a partially refunded order',
  );
});

Deno.test('the donation refund arm reads the scope too, not just the event name', () => {
  // `donationStatusTransition`'s scope parameter DEFAULTS to 'full', so a call
  // site that forgets to pass it silently restores the bug the default exists
  // to describe: a partial refund erasing a whole donation from the charity's
  // thermometer. The lib test cannot see which arguments index.ts passes.
  const call = SRC.match(/donationStatusTransition\(\s*donation\.status as string,\s*'charge\.refunded'([^)]*)\)/);
  assert(call, "the donation charge.refunded transition call is gone — has the arm moved?");
  assert(
    /,\s*scope\b/.test(call[1]),
    `the donation refund transition must be given the charge's refund scope, got: ${call[1]}`,
  );
  assert(
    /const scope = refundScopeOfCharge\(charge\);/.test(SRC),
    'the scope must be derived from the charge via refundScopeOfCharge',
  );
});
