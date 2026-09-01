/// What the handler HANDS the tier mapper, and what it does with a body it
/// cannot read.
///
/// `lib.test.ts` proves `mapEventToTier` protects a lifetime holder — but it
/// supplies `currentTier` itself, so it cannot see that the handler used to
/// supply `null` for four of the five activating event types. The guard was
/// therefore unreachable exactly where a lifetime owner is billed monthly for
/// a parallel entitlement: every RENEWAL wrote `pro` over `lifetime`, and the
/// monthly's eventual EXPIRATION then read `pro` and wrote `free`.
///
/// Source greps in the `delete-account/wiring.test.ts` idiom: the handler is
/// a bare `Deno.serve` with no exports, so its wiring is only readable off
/// the source. Every negative below is paired with the positive it depends
/// on, so an emptied file satisfies neither.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/revenuecat-webhook/wiring.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { ACTIVATING_EVENTS, DEACTIVATING_EVENTS, mapEventToTier } from './lib.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

Deno.test('the current tier is resolved for every event that can move the tier', () => {
  // The two lists together are exactly the set `mapEventToTier` answers
  // non-null for; anything narrower leaves the lifetime guard unreachable
  // for the difference.
  const gate = SRC.match(/let currentTier: string \| null = null;\s*\n\s*if \(([\s\S]*?)\n\s*\) \{/);
  assert(gate, 'the currentTier gate is gone — has the read moved?');
  const cond = gate[1];
  assert(
    cond.includes('DEACTIVATING_EVENTS'),
    'the deactivating types must resolve the current tier',
  );
  assert(
    cond.includes('ACTIVATING_EVENTS'),
    'the activating types must resolve the current tier too — lifetime outranks pro',
  );
  // The narrower form the bug shipped as. Named so a revert to it fails here
  // rather than only in production.
  assert(
    !/event\.type === 'PRODUCT_CHANGE'/.test(cond),
    'PRODUCT_CHANGE must not be singled out — it is one of ACTIVATING_EVENTS',
  );
});

Deno.test('the resolved tier is what reaches the mapper, and it is read first', () => {
  const read = SRC.indexOf("currentTier = data?.subscription_tier ?? null;");
  const map = SRC.indexOf('mapEventToTier(');
  assert(read !== -1, 'nothing assigns currentTier from the profile row');
  assert(map !== -1, 'the tier mapper is never called');
  assert(read < map, 'the profile read must precede the tier decision');
  assert(
    /mapEventToTier\(event\.type, event\.product_id \?\? null, currentTier\)/.test(SRC),
    'the mapper must be handed the resolved tier, not a literal',
  );
});

Deno.test('a lifetime holder survives every activating event, not only PRODUCT_CHANGE', () => {
  // The behavioural half of the guard above: with the tier actually resolved,
  // each activating type must decline to write. Asserted over the exported
  // list rather than a hand-copied one, with a membership pin beside it so an
  // emptied list runs zero iterations and still fails.
  assertEquals(
    [...ACTIVATING_EVENTS].sort(),
    ['INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE', 'PRODUCT_CHANGE', 'RENEWAL', 'UNCANCELLATION'],
  );
  for (const type of ACTIVATING_EVENTS) {
    assertEquals(
      mapEventToTier(type, 'pro_monthly', 'lifetime'),
      null,
      `${type} must not downgrade a lifetime holder`,
    );
    // The same event on a non-lifetime holder still grants pro, so the guard
    // is a lifetime rule and not a blanket refusal.
    assertEquals(mapEventToTier(type, 'pro_monthly', 'pro'), 'pro');
  }
  assertEquals([...DEACTIVATING_EVENTS].sort(), ['CANCELLATION', 'EXPIRATION']);
});

Deno.test('a signed body carrying no event object is a 400, not a 500', () => {
  // `JSON.parse('{}')` succeeds and yields `undefined` for `.event`; the first
  // field read then threw past the handler. RevenueCat retries a 5xx for three
  // days, so the cost of getting this wrong is a delivery that can never
  // succeed being redelivered until the window closes.
  const guard = SRC.indexOf("typeof event !== 'object' || event === null");
  assert(guard !== -1, 'nothing checks that the parsed body carried an event object');
  assert(
    SRC.indexOf('event.event_timestamp_ms') > guard,
    'the shape check must precede the first field read',
  );
  const status = SRC.slice(guard, guard + 260);
  assert(
    /status: 400/.test(status),
    'an unreadable event body must answer 400, or RevenueCat retries it for days',
  );
});
