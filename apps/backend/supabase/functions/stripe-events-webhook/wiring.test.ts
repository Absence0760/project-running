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
    ['handleDonationExpired', (() => {
      const start = SRC.indexOf('async function handleDonationExpired');
      assert(start !== -1, 'handleDonationExpired is gone');
      const end = SRC.indexOf('async function handleDonationRefunded', start);
      assert(end > start, 'could not find the end of handleDonationExpired');
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
    'these bring the Stripe SDK into the webhook at RUNTIME, taking the eszip ' +
      `from 761 KB to 3.4 MB for a type-level benefit: ${valueImports.join(', ')}`,
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
  for (const reader of ['readCheckoutSession(', 'readCharge(', 'readConnectAccount(']) {
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
