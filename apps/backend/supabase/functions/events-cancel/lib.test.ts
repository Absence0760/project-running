/// Run with `cd apps/backend && deno test supabase/functions/events-cancel/lib.test.ts`.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { cancelAction, resolveRefundEligibility } from './lib.ts';

const HOUR = 60 * 60 * 1000;
const START = Date.parse('2026-07-01T18:00:00Z');
const START_ISO = '2026-07-01T18:00:00Z';

Deno.test('resolveRefundEligibility — no_refund is never eligible', () => {
  // Even well before the start.
  assertEquals(resolveRefundEligibility('no_refund', START - 10 * HOUR, START_ISO), {
    eligible: false,
    fullRefund: false,
  });
});

Deno.test('resolveRefundEligibility — full_until_start eligible before start, not after', () => {
  assertEquals(resolveRefundEligibility('full_until_start', START - 1, START_ISO), {
    eligible: true,
    fullRefund: true,
  });
  // Exactly at start -> not eligible (now < cutoff is strict).
  assertEquals(resolveRefundEligibility('full_until_start', START, START_ISO), {
    eligible: false,
    fullRefund: false,
  });
  assertEquals(resolveRefundEligibility('full_until_start', START + 1, START_ISO), {
    eligible: false,
    fullRefund: false,
  });
});

Deno.test('resolveRefundEligibility — full_until_24h cutoff is 24h before start', () => {
  const cutoff = START - 24 * HOUR;
  assertStrictEquals(
    resolveRefundEligibility('full_until_24h', cutoff - 1, START_ISO).eligible,
    true,
  );
  // Exactly at the 24h boundary -> not eligible.
  assertStrictEquals(
    resolveRefundEligibility('full_until_24h', cutoff, START_ISO).eligible,
    false,
  );
  // 12h before start (inside the no-refund window) -> not eligible.
  assertStrictEquals(
    resolveRefundEligibility('full_until_24h', START - 12 * HOUR, START_ISO).eligible,
    false,
  );
});

Deno.test('resolveRefundEligibility — unparseable instance start fails closed', () => {
  assertEquals(resolveRefundEligibility('full_until_start', START, 'not-a-date'), {
    eligible: false,
    fullRefund: false,
  });
});

Deno.test('resolveRefundEligibility — unknown policy fails closed', () => {
  assertEquals(
    resolveRefundEligibility('weird' as never, START - 10 * HOUR, START_ISO),
    { eligible: false, fullRefund: false },
  );
});

Deno.test('cancelAction — pending always releases the reservation (no charge)', () => {
  assertStrictEquals(cancelAction('pending', false), 'release_reservation');
  assertStrictEquals(cancelAction('pending', true), 'release_reservation');
});

Deno.test('cancelAction — paid + eligible refunds, paid + not eligible is policy_no_refund', () => {
  assertStrictEquals(cancelAction('paid', true), 'refund');
  assertStrictEquals(cancelAction('paid', false), 'policy_no_refund');
});

Deno.test('cancelAction — terminal statuses no-op', () => {
  for (const s of ['refunded', 'canceled', 'failed', 'partially_refunded']) {
    assertStrictEquals(cancelAction(s, true), 'noop');
    assertStrictEquals(cancelAction(s, false), 'noop');
  }
});
