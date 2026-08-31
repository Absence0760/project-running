/// Buyer self-cancel, stated as the whole decision rather than as its three
/// happy arms — and as the SET of Stripe parameters rather than as the two
/// flags that were wrong.
///
/// The defect § 769 records is not that a flag was missing; it is that nothing
/// asserted what the params object CONTAINED, so `refund_application_fee: true`
/// on its own read as a claw-back and paid the host our cut on top of the
/// ticket they had already kept. An assertion on the exact key set is the shape
/// that would have caught it, and the same shape catches the next stray key.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/events-cancel/refund_invariants.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildRefundParams,
  type CancelAction,
  cancelAction,
  type RefundPolicy,
  resolveRefundEligibility,
} from './lib.ts';

/// Every status `event_orders_status_check` can hold, plus two the column
/// cannot. `cancelAction` takes a bare string, so what it does with a value
/// outside the vocabulary is part of its contract.
const ALL_STATUSES = [
  'pending',
  'paid',
  'partially_refunded',
  'refunded',
  'refund_failed',
  'failed',
  'canceled',
  '',
  'Paid',
];

/// The statuses `index.ts` will actually hand over: its `.in('status', ...)`
/// filter. Written out so widening the filter without teaching this decision
/// about the new value fails here rather than silently no-opping a cancel.
const SELECTED_BY_THE_HANDLER = ['pending', 'paid', 'partially_refunded'];

Deno.test('cancelAction — the whole table, so a widened selector cannot silently no-op', () => {
  const table: Record<string, [CancelAction, CancelAction]> = {
    // status: [eligible, not eligible]
    pending: ['release_reservation', 'release_reservation'],
    paid: ['refund', 'policy_no_refund'],
    partially_refunded: ['refund', 'policy_no_refund'],
    refunded: ['noop', 'noop'],
    refund_failed: ['noop', 'noop'],
    failed: ['noop', 'noop'],
    canceled: ['noop', 'noop'],
    '': ['noop', 'noop'],
    Paid: ['noop', 'noop'],
  };
  for (const status of ALL_STATUSES) {
    const [whenEligible, whenNot] = table[status];
    assertEquals(cancelAction(status, true), whenEligible, `${status} + eligible`);
    assertEquals(cancelAction(status, false), whenNot, `${status} + not eligible`);
  }
});

Deno.test('cancelAction — every status the handler selects reaches a real action', () => {
  // A `noop` for a status the query deliberately fetched is the § 769 defect:
  // the caller reports success, no refund is created, and the seat stays held.
  // Asserted as membership of the acting set rather than as `!== 'noop'`: a
  // function with no answer at all satisfies the inequality, which is the shape
  // § 788 found on four security assertions.
  const acting: readonly CancelAction[] = ['release_reservation', 'refund', 'policy_no_refund'];
  for (const status of SELECTED_BY_THE_HANDLER) {
    assert(acting.includes(cancelAction(status, true)), `${status} + eligible`);
    assert(acting.includes(cancelAction(status, false)), `${status} + not eligible`);
  }
});

Deno.test('cancelAction — a refund that failed is not a second chance to cancel', () => {
  // `refund_failed` (§ 789) means the seat was already released and the money
  // came back to us. Reading it as cancelable would fire another automated
  // refund at a rail Stripe has just said cannot deliver.
  assertEquals(cancelAction('refund_failed', true), 'noop');
  assertEquals(cancelAction('refund_failed', false), 'noop');
});

const POLICIES: readonly RefundPolicy[] = ['no_refund', 'full_until_start', 'full_until_24h'];
const START = '2026-06-01T10:00:00Z';
const START_MS = Date.parse(START);
const DAY_MS = 24 * 60 * 60 * 1000;

Deno.test('resolveRefundEligibility — each policy\'s cutoff, to the millisecond, on both sides', () => {
  const cutoffs: Record<string, number | null> = {
    no_refund: null,
    full_until_start: START_MS,
    full_until_24h: START_MS - DAY_MS,
  };
  for (const policy of POLICIES) {
    const cutoff = cutoffs[policy];
    if (cutoff === null) {
      for (const now of [0, START_MS - DAY_MS, START_MS, START_MS + DAY_MS]) {
        assertEquals(resolveRefundEligibility(policy, now, START).eligible, false, `${policy}`);
      }
      continue;
    }
    assertEquals(resolveRefundEligibility(policy, cutoff - 1, START).eligible, true, `${policy} -1ms`);
    assertEquals(
      resolveRefundEligibility(policy, cutoff, START).eligible,
      false,
      `${policy} exactly at the cutoff is CLOSED`,
    );
    assertEquals(resolveRefundEligibility(policy, cutoff + 1, START).eligible, false, `${policy} +1ms`);
  }
});

Deno.test('resolveRefundEligibility — fullRefund tracks eligible exactly, on every input', () => {
  // The field exists so a future proration policy can diverge; until one lands,
  // a divergence is a bug. Asserting the identity means the day it moves, this
  // fails and the caller is looked at.
  const clocks = [0, START_MS - 2 * DAY_MS, START_MS - DAY_MS, START_MS, START_MS + DAY_MS];
  for (const policy of POLICIES) {
    for (const now of clocks) {
      const r = resolveRefundEligibility(policy, now, START);
      assertEquals(r.fullRefund, r.eligible, `${policy} at ${now}`);
    }
  }
});

Deno.test('resolveRefundEligibility — an instance start we cannot time-bound refunds nothing', () => {
  const unparseable = ['', 'tomorrow', '2026-13-45T99:99:99Z', 'null', 'NaN', '   '];
  for (const policy of POLICIES) {
    for (const start of unparseable) {
      const r = resolveRefundEligibility(policy, 0, start);
      assertEquals(r.eligible, false, `${policy} ${JSON.stringify(start)}`);
      assertEquals(r.fullRefund, false);
    }
  }
});

Deno.test('resolveRefundEligibility — an offset form names the same instant as its UTC twin', () => {
  // `instance_start` arrives from PostgREST, whose rendering carries an offset
  // rather than a Z. A cutoff computed off the literal text instead of the
  // instant would move the refund window by the offset.
  const utc = '2026-06-01T10:00:00Z';
  const offset = '2026-06-01T12:00:00+02:00';
  assertEquals(Date.parse(utc), Date.parse(offset));
  // Each comparison names the answer as well as the agreement: two calls of the
  // same function agreeing is satisfied by a function with no answers (§ 788),
  // and the point here is that BOTH forms produce the same REAL verdict.
  const expected: Record<string, boolean[]> = {
    // clocks: 24h+1ms before start, 1ms before start, 1ms after start
    no_refund: [false, false, false],
    full_until_start: [true, true, false],
    full_until_24h: [true, false, false],
  };
  const clocks = [START_MS - DAY_MS - 1, START_MS - 1, START_MS + 1];
  for (const policy of POLICIES) {
    clocks.forEach((now, i) => {
      const viaOffset = resolveRefundEligibility(policy, now, offset);
      const viaUtc = resolveRefundEligibility(policy, now, utc);
      assertEquals(viaOffset, viaUtc, `${policy} at ${now}`);
      assertEquals(viaUtc.eligible, expected[policy][i], `${policy} verdict at clock ${i}`);
    });
  }
});

Deno.test('resolveRefundEligibility — a policy string outside the vocabulary refunds nothing', () => {
  for (const bogus of ['', 'full', 'FULL_UNTIL_START', 'full_until_48h', 'refundable']) {
    const r = resolveRefundEligibility(bogus as RefundPolicy, START_MS - 10 * DAY_MS, START);
    assertEquals(r.eligible, false, bogus);
    assertEquals(r.fullRefund, false, bogus);
  }
});

Deno.test('buildRefundParams — the params are exactly three keys, and both flags are set', () => {
  // A key set assertion rather than a per-flag one. § 769's defect was a params
  // object that was RIGHT about every key it carried and wrong about the one it
  // did not, so the property that catches it is the set.
  const params = buildRefundParams('pi_123');
  assertEquals(Object.keys(params).sort(), [
    'payment_intent',
    'refund_application_fee',
    'reverse_transfer',
  ]);
  assertEquals(params.refund_application_fee, true);
  assertEquals(params.reverse_transfer, true);
});

Deno.test('buildRefundParams — refund_application_fee is never sent without reverse_transfer', () => {
  // Stripe couples them: "If you refund the application fee for a destination
  // charge, you must also reverse the transfer." Alone, the first pays the host
  // our cut on top of a ticket they keep, so the platform funds a cancelled
  // class twice. Stated as an implication so the pair cannot come apart in
  // either direction.
  const params = buildRefundParams('pi_123') as Record<string, unknown>;
  if (params.refund_application_fee === true) {
    assertEquals(params.reverse_transfer, true, 'the fee refund without the transfer reversal');
  }
  if (params.reverse_transfer === true) {
    assertEquals(params.refund_application_fee, true, 'the transfer reversal without the fee');
  }
});

Deno.test('buildRefundParams — the payment intent is passed through, never rewritten', () => {
  for (const pi of ['pi_1', 'pi_3KtT9aLkdIwHu7ix0snn0B6q', '']) {
    assertEquals(buildRefundParams(pi).payment_intent, pi);
  }
});

Deno.test('buildRefundParams — a fresh object per call, so one caller cannot poison the next', () => {
  const a = buildRefundParams('pi_1') as Record<string, unknown>;
  a.reverse_transfer = false;
  assertEquals(buildRefundParams('pi_2').reverse_transfer, true);
});
