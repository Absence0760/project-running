/// Run with `cd apps/backend && deno test --allow-read supabase/functions/stripe-events-webhook/wiring.test.ts`.
///
/// Source-grep guards in the `delete-account/wiring.test.ts` idiom. The
/// refund arm needs a live Supabase plus operator `whsec_` keys to drive
/// end to end, but the properties below are positional and readable off the
/// source — and they are the half `lib.test.ts` cannot see: the lib knows a
/// partial refund maps to `partially_refunded`, it cannot know that the
/// handler asks it, or that the seat release follows the answer.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
const LIB = await Deno.readTextFile(new URL('./lib.ts', import.meta.url));

function donationRefundHandler(): string {
  const start = SRC.indexOf('async function handleDonationRefunded');
  assert(start !== -1, 'handleDonationRefunded is gone — has the donation refund arm moved?');
  const end = SRC.indexOf('async function handleOrderRefunded', start);
  assert(end > start, 'could not find the end of handleDonationRefunded');
  return SRC.slice(start, end);
}

function refundHandler(): string {
  const start = SRC.indexOf('async function handleOrderRefunded');
  assert(start !== -1, 'handleOrderRefunded is gone — has the refund arm moved?');
  const end = SRC.indexOf('async function handleDonationRefundReversed', start);
  assert(end > start, 'could not find the end of handleOrderRefunded');
  return SRC.slice(start, end);
}

function reversalHandlers(): string {
  const start = SRC.indexOf('async function handleDonationRefundReversed');
  assert(start !== -1, 'handleDonationRefundReversed is gone — has the reversal arm moved?');
  const end = SRC.indexOf('async function handleCompleted', start);
  assert(end > start, 'could not find the end of the refund-reversal handlers');
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
    /orderStatusTransition\(\s*order\.status,\s*STRIPE_EVENT\.chargeRefunded,\s*scope,?\s*\)/
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
    src.includes(".eq('status', order.status)"),
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
  const call = SRC.match(
    /donationStatusTransition\(\s*donation\.status,\s*STRIPE_EVENT\.chargeRefunded([^)]*)\)/,
  );
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

Deno.test('the donation refund arm records the AMOUNT, not just the status', () => {
  // A status alone cannot say how much came back, which is the whole reason
  // 20270620_001 exists. An update that moves the status and leaves
  // refunded_cents behind puts the donation in `partially_refunded` with
  // nothing refunded — a state the CHECK refuses, so the delivery would 23514
  // and Stripe would retry it forever.
  const src = donationRefundHandler();
  assert(
    /refundedCentsOfCharge\(\s*charge,\s*donation\.amount_cents,\s*scope,?\s*\)/.test(src),
    'the refunded amount must be derived from the charge and the donation amount',
  );
  assert(
    src.includes('refunded_cents: refundedCents'),
    'the update must write the refunded amount alongside the status',
  );
  assert(
    src.includes('status: nextStatus'),
    'the update must write the status the transition resolved, not a literal',
  );
});

Deno.test('the donation refund CAS cannot walk the refunded total back', () => {
  // charge.amount_refunded is CUMULATIVE, and Stripe does not promise ordered
  // delivery. Two instalments arriving out of order carry 3000 then 1000; a
  // CAS on the status alone lets the second overwrite the first and the
  // thermometer silently gains 2000 the charity does not have.
  const src = donationRefundHandler();
  assert(
    src.includes(".lte('refunded_cents', refundedCents)"),
    'the CAS must refuse a delivery reporting less than the ledger already holds',
  );
  assert(
    src.includes(".eq('status', donation.status)"),
    'the CAS must match the status it read, so a completing refund can move a ' +
      'partially refunded donation on',
  );
  assert(
    !src.includes(".eq('status', 'paid')"),
    'a hardcoded paid CAS cannot complete a partially refunded donation',
  );
});

Deno.test('both donation reads fail loudly instead of reading as "no such donation"', () => {
  // `const { data } = await …` drops the error. On the refund arm that made a
  // transient database failure fall through to the event-order path, which
  // found nothing either and answered 200 — so Stripe recorded the refund as
  // delivered and never retried. On the expiry arm it left the donation
  // `pending` forever; nothing sweeps a lapsed donation reservation.
  for (const [name, src] of [
    ['handleDonationRefunded', donationRefundHandler()],
    ['handleDonationNotPaid', (() => {
      const start = SRC.indexOf('async function handleDonationNotPaid');
      assert(start !== -1, 'handleDonationNotPaid is gone');
      const end = SRC.indexOf('async function handleDonationRefunded', start);
      assert(end > start, 'could not find the end of handleDonationNotPaid');
      return SRC.slice(start, end);
    })()],
  ] as const) {
    assert(
      !/const \{ data: donation \} = await/.test(src),
      `${name} drops the read error — an error is not "no such donation"`,
    );
    assert(
      /const \{ data: donation, error: readErr \} = await/.test(src),
      `${name} must destructure the read error`,
    );
    assert(
      src.includes("{ status: 500 }"),
      `${name} must answer 5xx on a failed read so the dedupe row is released ` +
        'and Stripe retries',
    );
  }
});

Deno.test('the Stripe import stays TYPE-ONLY, because a value import is 4.4x the eszip', () => {
  // Measured with `edge-runtime bundle` on this entrypoint, three ways:
  // 761,148 bytes with no Stripe import at all, 761,378 with the type-only one
  // (the source text of the import itself), 3,373,077 with a value import —
  // esm.sh's `?target=deno` build swaps `node:` specifiers for the
  // deno.land/std polyfill tree (decisions § 699, § 785). Stripe retries this
  // endpoint on timeout, so a 2.6 MB cold-boot cost is not a type-level
  // detail. Dropping the `type` keyword changes nothing the compiler can see.
  const imports = [...LIB.matchAll(/^(import[^\n]*_shared\/stripe\.ts';)$/gm)].map((m) => m[1]);
  assert(
    imports.length > 0,
    'lib.ts no longer imports Stripe at all. If the typed read moved, move this ' +
      'guard with it — without one, the next Stripe import here can be a value ' +
      'import and nothing will say so.',
  );
  const valueImports = imports.filter((line) => !/^import type /.test(line));
  assertEquals(
    valueImports,
    [],
    'these bring the Stripe SDK into the webhook at RUNTIME, adding ~2.6 MB of ' +
      `SDK and node-polyfill tree for a type-level benefit: ${valueImports.join(', ')}`,
  );
  assert(
    !/^import[^\n]*esm\.sh\/stripe@/m.test(LIB) && !/^import[^\n]*esm\.sh\/stripe@/m.test(SRC),
    'the webhook must reach Stripe through _shared/stripe.ts, which carries the ' +
      '@ts-types directive that binds the declarations (decisions § 765)',
  );
});

Deno.test('no handler reads a Stripe object as an untyped bag', () => {
  // Every one of these took `Record<string, unknown>` and dug fields out of it
  // by name. A misspelled key, a renamed field or a shape Stripe widened read
  // as `undefined` — which on this function means "not a full refund", "no
  // payment intent" or "capability off", each a different order status
  // written silently. The typed readers in lib.ts are checked against the
  // SDK's own declarations, so the compiler re-derives the field names on
  // every run of the `deno check` lane.
  const bagged = [...SRC.matchAll(/^\s*(\w+): Record<string, unknown>,$/gm)].map((m) => m[1]);
  assertEquals(
    bagged,
    [],
    `these handler parameters are untyped Stripe payloads again: ${bagged.join(', ')}. ` +
      'Read them through readCheckoutSession / readCharge / readConnectAccount instead.',
  );
  for (
    const reader of [
      'readCheckoutSession(',
      'readCharge(',
      'readConnectAccount(',
      'readRefund(',
    ]
  ) {
    assert(
      SRC.includes(reader),
      `${reader} is not called from index.ts, so some event object is reaching a ` +
        'handler without being narrowed — the guard above only sees the parameter type',
    );
  }
});

Deno.test('every ledger read fails loudly instead of reading as "no such row"', () => {
  // `const { data: x } = await …` drops the error, and a dropped error on a
  // `maybeSingle()` is indistinguishable from "no such row" — which every
  // handler answers 200. Stripe then records the delivery as processed and
  // never retries: the order stays `pending` forever, holding a seat nobody
  // bought, because nothing sweeps a lapsed reservation. Both donation reads
  // were hardened for exactly this; the ORDER expiry read was left.
  //
  // One exemption, which is why this is a list rather than a bare regex: the
  // confirm-time capacity read is best-effort by design. It only shortcuts an
  // already-full event, and the advisory-locked enforce_event_capacity trigger
  // is the authoritative guard — so a failed read degrades to the slow path,
  // not to a wrong answer.
  const EXEMPT = ['event'];
  const dropped = [...SRC.matchAll(/const \{ data: (\w+) \} = await/g)].map((m) => m[1]);
  assertEquals(
    dropped.filter((name) => !EXEMPT.includes(name)),
    [],
    `these reads drop their error: ${dropped.join(', ')}. Destructure ` +
      '`error` and answer 5xx, so the dedupe row is released and Stripe retries.',
  );
  assert(
    dropped.length > 0,
    'no read in index.ts drops its error any more — including the capacity ' +
      'read this guard exempts. If that one was hardened too, delete the ' +
      'exemption rather than leaving a list that matches nothing.',
  );
});

Deno.test('nothing is written until the money has arrived', () => {
  // The settlement gate has to come BEFORE the first write in each confirm
  // handler, not beside it: the CAS is `pending -> paid`, so a write that
  // lands first has already spent the only transition the async outcome could
  // have used, and the seat follows immediately after it.
  for (const [name, end] of [
    ['handleDonationCompleted', 'async function handleDonationNotPaid'],
    ['handleCompleted', 'async function handleNotPaid'],
  ] as const) {
    const start = SRC.indexOf(`async function ${name}`);
    assert(start !== -1, `${name} is gone — has the confirm arm moved?`);
    const stop = SRC.indexOf(end, start);
    assert(stop > start, `could not find the end of ${name}`);
    const src = SRC.slice(start, stop);

    const gate = src.indexOf('isPaymentSettled(session.paymentStatus)');
    const firstWrite = src.indexOf('.update(');
    assert(
      gate !== -1,
      `${name} confirms without checking payment_status. checkout.session.completed ` +
        'fires for a delayed-notification method with the money still in flight',
    );
    assert(firstWrite !== -1, `${name} no longer writes anything — has the CAS moved?`);
    assert(
      gate < firstWrite,
      `${name} writes before it checks whether the payment settled`,
    );
  }
});

Deno.test('the async payment outcomes are dispatched, not 200-ignored', () => {
  // Without these two arms the settlement gate above is a leak, not a fix: a
  // delayed payment that later succeeds would leave the order `pending`
  // forever, holding a seat and never issuing one, because nothing sweeps a
  // lapsed reservation.
  const dispatch = SRC.slice(SRC.indexOf('async function dispatchStripeEvent'));
  for (const [constant, arm] of [
    ['STRIPE_EVENT.checkoutAsyncPaid', 'handleCompleted'],
    ['STRIPE_EVENT.checkoutAsyncFailed', 'handleNotPaid'],
  ] as const) {
    assert(
      dispatch.includes(constant),
      `${constant} is not dispatched, so a delayed payment's real outcome is ignored`,
    );
    assert(
      dispatch.includes(`await ${arm}(`),
      `${constant} has no ${arm} arm to reach`,
    );
  }
});

// ── the refund the bank sent back (decisions § 789) ────────────────────────

Deno.test('a reversed refund never touches a seat', () => {
  // The seat was released when the refund was CREATED and
  // promote_event_waitlist may already have given it to the next person, so
  // re-seating here would either oversell the class or take a seat back off
  // someone who has been told they are in. The buyer cancelled and wants their
  // money; the answer is a payout by another route, which is a human action.
  const src = reversalHandlers();
  assert(
    !src.includes(".from('event_attendees')"),
    'the refund-reversal arm must not write event_attendees — re-seating is a ' +
      'product decision, not a transition-table row (decisions § 789)',
  );
  assert(
    !src.includes('.delete()'),
    'the refund-reversal arm deletes a row — it may only move a status',
  );
});

Deno.test('the reversal is gated on the REFUND status, not on the event type', () => {
  // `refund.updated` fires whenever Stripe attaches an acquirer reference
  // number to a perfectly good refund. Dispatching on the event type alone
  // would walk a correctly refunded order back the moment that happened.
  const dispatch = SRC.indexOf('isRefundLifecycleEvent(event.type)');
  assert(dispatch !== -1, 'the refund-lifecycle arm is not dispatched at all');
  const gate = SRC.indexOf('refundReversed(refund)', dispatch);
  const donationCall = SRC.indexOf('handleDonationRefundReversed(service', dispatch);
  const orderCall = SRC.indexOf('handleOrderRefundReversed(service', dispatch);
  assert(gate !== -1, 'nothing checks the refund status before dispatching');
  assert(donationCall > gate, 'the donation ledger is reached before the status gate');
  assert(orderCall > gate, 'the order ledger is reached before the status gate');
});

Deno.test('both reversal CASs match the status they read', () => {
  // A hardcoded `.eq('status', 'refunded')` would be right today and wrong the
  // moment the table grows another arm into refund_failed; matching the status
  // that was read is what makes an at-least-once redelivery a no-op.
  const src = reversalHandlers();
  assertEquals(
    [...src.matchAll(/\.eq\('status', (\w+(?:\.\w+)*)\)/g)].map((m) => m[1]),
    ['donation.status', 'order.status'],
  );
  assert(
    !/\.eq\('status', '/.test(src),
    'a reversal CAS hardcodes a status literal instead of the one it read',
  );
});

Deno.test('a reversal that is not a transition is logged, never silently dropped', () => {
  // A failed PARTIAL refund transitions on nothing by design (the seat-bearing
  // status must survive). Since § 823 the money discrepancy is also a
  // `payment_refunds` row, so the log line is no longer the ONLY record — but
  // it is still the one an operator tailing the function sees first, and the
  // status it declined to move is not on the row.
  const src = reversalHandlers();
  const noTransition = [...src.matchAll(/skipped: 'no_transition'/g)];
  assertEquals(noTransition.length, 2, 'both ledgers must have a no-transition arm');
  for (const ledger of ['donation:', 'order:']) {
    assert(
      src.includes(`'refund reversal on a`) && src.includes(ledger),
      `the ${ledger} no-transition arm does not log the row it declined to move`,
    );
  }
});


// ── payment_refunds: the row a failed PARTIAL refund gets (§ 823) ────────────

function refundRecorder(): string {
  const start = SRC.indexOf('async function recordPaymentRefund');
  assert(start !== -1, 'recordPaymentRefund is gone — has the refund ledger moved?');
  const end = SRC.indexOf('// ── donation handlers', start);
  assert(end > start, 'could not find the end of recordPaymentRefund');
  return SRC.slice(start, end);
}

function refundLifecycleArm(): string {
  const start = SRC.indexOf('if (isRefundLifecycleEvent(event.type))');
  assert(start !== -1, 'the refund-lifecycle dispatch arm is gone');
  const end = SRC.indexOf('// Unhandled types', start);
  assert(end > start, 'could not find the end of the refund-lifecycle arm');
  return SRC.slice(start, end);
}

Deno.test('the refund is recorded before the reversal gate, and whatever its status', () => {
  // `refundReversed` is false for `succeeded` and for every benign
  // `refund.updated`. Recording behind that gate would keep only the failures,
  // and the ledger would then hold a reversal with no sibling instalment to
  // read it against.
  const src = refundLifecycleArm();
  const record = src.indexOf('recordPaymentRefund(service, refund)');
  const gate = src.indexOf('refundReversed(refund)');
  assert(record !== -1, 'the lifecycle arm never records the refund');
  assert(gate !== -1, 'the reversal gate is gone');
  assert(record < gate, 'the refund must be recorded before the reversal gate, not after it');
});

Deno.test('the refund row is keyed on the Stripe Refund id, so a replay is one row', () => {
  // This is the whole idempotency argument. `refunded_cents -= amount` moves
  // once per delivery; an upsert on a unique key does not move at all on the
  // second (§ 789's refusal, § 823's answer).
  const src = refundRecorder();
  assert(
    /\.upsert\(/.test(src),
    'the refund record must be an upsert — a bare insert 23505s on every replay',
  );
  assert(
    src.includes("onConflict: 'stripe_refund_id'"),
    'the upsert must conflict on the Stripe Refund id, not on the surrogate key',
  );
});

Deno.test('recording a refund never touches a running total or a seat', () => {
  const src = refundRecorder();
  assert(
    !src.includes('refunded_cents'),
    'the refund recorder writes refunded_cents — the arithmetic § 789 refused',
  );
  assert(
    !src.includes(".from('event_attendees')") && !src.includes('.delete()'),
    'the refund recorder touches seats; it may only write payment_refunds',
  );
  assert(
    !src.includes("update("),
    'the refund recorder must go through the upsert, not a second write path',
  );
});

Deno.test('an unresolvable parent writes nothing, and a failed read retries', () => {
  const src = refundRecorder();
  // payment_refunds_one_ledger_check requires exactly one parent, so a refund
  // on a charge neither ledger knows has no row to write.
  assert(
    /if \(!order\) return null;/.test(src),
    'a refund on an unknown charge must write no row',
  );
  // A read that ERRORED is not "not a donation". Falling through on it would
  // attribute a donation refund to the order ledger, find nothing, and answer
  // 200 — closing the delivery on the one event that says the money came back.
  assertEquals(
    [...src.matchAll(/status: 500/g)].length,
    3,
    'both parent reads and the upsert must 500 so Stripe retries',
  );
});
