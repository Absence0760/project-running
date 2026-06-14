/// Run with `cd apps/backend && deno test supabase/functions/revenuecat-webhook/lib.test.ts`.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  ACTIVATING_EVENTS,
  DEACTIVATING_EVENTS,
  mapEventToBillingIssue,
  mapEventToTier,
} from './lib.ts';

Deno.test('mapEventToTier — INITIAL_PURCHASE → pro', () => {
  assertEquals(mapEventToTier('INITIAL_PURCHASE', 'pro_monthly', null), 'pro');
});

Deno.test('mapEventToTier — RENEWAL → pro', () => {
  assertEquals(mapEventToTier('RENEWAL', 'pro_yearly', null), 'pro');
});

Deno.test('mapEventToTier — UNCANCELLATION → pro', () => {
  assertEquals(mapEventToTier('UNCANCELLATION', 'pro_monthly', null), 'pro');
});

Deno.test('mapEventToTier — PRODUCT_CHANGE → pro', () => {
  assertEquals(mapEventToTier('PRODUCT_CHANGE', 'pro_yearly', null), 'pro');
});

Deno.test('mapEventToTier — NON_RENEWING_PURCHASE with non-lifetime sku → pro', () => {
  assertEquals(mapEventToTier('NON_RENEWING_PURCHASE', 'one_time_addon', null), 'pro');
});

Deno.test('mapEventToTier — product id with "lifetime" substring → lifetime', () => {
  assertEquals(mapEventToTier('NON_RENEWING_PURCHASE', 'pro_lifetime', null), 'lifetime');
  assertEquals(mapEventToTier('INITIAL_PURCHASE', 'pro_lifetime_v2', null), 'lifetime');
  // Substring match — anywhere in the id, not just suffix.
  assertEquals(mapEventToTier('PRODUCT_CHANGE', 'lifetime_special', null), 'lifetime');
});

Deno.test('mapEventToTier — PRODUCT_CHANGE to a non-lifetime product does NOT downgrade a lifetime holder', () => {
  // A lifetime owner with a parallel monthly sub for another entitlement does
  // a plan change on that sub: RC fires PRODUCT_CHANGE with a non-lifetime
  // product id. Knocking them to `pro` would lose "never expires" and then
  // drop them to free when the sub later expires. Must keep lifetime (null =
  // no tier write).
  assertStrictEquals(mapEventToTier('PRODUCT_CHANGE', 'pro_yearly', 'lifetime'), null);
  assertStrictEquals(mapEventToTier('PRODUCT_CHANGE', null, 'lifetime'), null);
  // A genuine upgrade TO a lifetime product still asserts lifetime.
  assertEquals(mapEventToTier('PRODUCT_CHANGE', 'pro_lifetime', 'lifetime'), 'lifetime');
  // A non-lifetime holder is unaffected — PRODUCT_CHANGE still grants pro.
  assertEquals(mapEventToTier('PRODUCT_CHANGE', 'pro_yearly', 'pro'), 'pro');
  assertEquals(mapEventToTier('PRODUCT_CHANGE', 'pro_yearly', 'free'), 'pro');
});

Deno.test('mapEventToTier — null product id with activating event → pro (default)', () => {
  // RC's payloads always include product_id but the helper is
  // permissive: missing → empty string → no "lifetime" substring → pro.
  assertEquals(mapEventToTier('INITIAL_PURCHASE', null, null), 'pro');
  assertEquals(mapEventToTier('INITIAL_PURCHASE', undefined, null), 'pro');
});

Deno.test('mapEventToTier — EXPIRATION on a non-lifetime user → free', () => {
  assertEquals(mapEventToTier('EXPIRATION', null, 'pro'), 'free');
  assertEquals(mapEventToTier('EXPIRATION', null, 'free'), 'free');
});

Deno.test('mapEventToTier — CANCELLATION on a non-lifetime user → free', () => {
  assertEquals(mapEventToTier('CANCELLATION', null, 'pro'), 'free');
});

Deno.test('mapEventToTier — EXPIRATION/CANCELLATION on a lifetime holder → null (no change)', () => {
  // The point of this branch: a lifetime holder might have a parallel
  // monthly sub for another entitlement. Cancelling that monthly must
  // NOT downgrade them. mapEventToTier returns null → caller skips the
  // tier write entirely.
  assertStrictEquals(mapEventToTier('EXPIRATION', null, 'lifetime'), null);
  assertStrictEquals(mapEventToTier('CANCELLATION', null, 'lifetime'), null);
});

Deno.test('mapEventToTier — null currentTier on a deactivation → free (conservative default)', () => {
  // If the profile lookup returns nothing (deleted user or query
  // error), treat as not-lifetime and apply the deactivation. The
  // alternative — skipping the write — would leave a cancelled user
  // sitting on `pro` indefinitely.
  assertEquals(mapEventToTier('EXPIRATION', null, null), 'free');
  assertEquals(mapEventToTier('CANCELLATION', null, undefined), 'free');
});

Deno.test('mapEventToTier — unknown event type → null', () => {
  assertStrictEquals(mapEventToTier('TRANSFER', null, null), null);
  assertStrictEquals(mapEventToTier('SUBSCRIBER_ALIAS', null, 'pro'), null);
  assertStrictEquals(mapEventToTier('', null, null), null);
});

Deno.test('mapEventToTier — BILLING_ISSUE → null (NO tier change during grace period)', () => {
  // The contract: a failed renewal must NOT downgrade the user
  // mid-grace-period. RC keeps trying the card for ~16-30 days; only
  // when the grace exhausts does EXPIRATION fire. A regression that
  // collapsed BILLING_ISSUE into the deactivating set would pull
  // access from users with a temporarily declined card. Pin the
  // null-return at the lib level so any future refactor that
  // unifies the "money trouble" events into one branch will fail
  // here.
  assertStrictEquals(mapEventToTier('BILLING_ISSUE', null, 'pro'), null);
  assertStrictEquals(mapEventToTier('BILLING_ISSUE', 'pro_monthly', 'pro'), null);
  assertStrictEquals(mapEventToTier('BILLING_ISSUE', null, 'lifetime'), null);
});

Deno.test('mapEventToTier — SUBSCRIPTION_PAUSED / TRANSFER → null (no tier change)', () => {
  // SUBSCRIPTION_PAUSED is Play Store's "I want to pause my sub for
  // a few months" flow — RC keeps the entitlement active per Play's
  // policy, so the tier stays. TRANSFER is RC's user-merge — the
  // tier carries over with the entitlement and our handler shouldn't
  // touch it. Both are no-ops by design.
  assertStrictEquals(mapEventToTier('SUBSCRIPTION_PAUSED', null, 'pro'), null);
  assertStrictEquals(mapEventToTier('TRANSFER', null, 'pro'), null);
});

Deno.test('mapEventToBillingIssue — BILLING_ISSUE → ISO timestamp string', () => {
  const fixed = new Date('2026-04-30T12:00:00Z');
  assertStrictEquals(
    mapEventToBillingIssue('BILLING_ISSUE', fixed),
    '2026-04-30T12:00:00.000Z',
  );
});

Deno.test('mapEventToBillingIssue — recovery + ended events clear the flag', () => {
  // RENEWAL = the retried payment went through; UNCANCELLATION = user
  // came back. Either way the billing issue is resolved.
  // EXPIRATION / CANCELLATION = the access has ended; the flag is
  // moot at that point (the user is now free).
  assertStrictEquals(mapEventToBillingIssue('RENEWAL'), null);
  assertStrictEquals(mapEventToBillingIssue('UNCANCELLATION'), null);
  assertStrictEquals(mapEventToBillingIssue('EXPIRATION'), null);
  assertStrictEquals(mapEventToBillingIssue('CANCELLATION'), null);
});

Deno.test('mapEventToBillingIssue — events that don\'t move the dimension → undefined', () => {
  // INITIAL_PURCHASE / PRODUCT_CHANGE / NON_RENEWING_PURCHASE all
  // create-or-keep-active a sub but don't say anything about a
  // payment failure. SUBSCRIPTION_PAUSED is Play-side state that
  // doesn't imply a card problem. TRANSFER / SUBSCRIBER_ALIAS are
  // RC-side metadata. None of these should write the flag (clearing
  // a pending billing-issue on INITIAL_PURCHASE would be wrong if
  // the original sub still has a billing problem, etc.).
  assertStrictEquals(mapEventToBillingIssue('INITIAL_PURCHASE'), undefined);
  assertStrictEquals(mapEventToBillingIssue('PRODUCT_CHANGE'), undefined);
  assertStrictEquals(mapEventToBillingIssue('NON_RENEWING_PURCHASE'), undefined);
  assertStrictEquals(mapEventToBillingIssue('SUBSCRIPTION_PAUSED'), undefined);
  assertStrictEquals(mapEventToBillingIssue('TRANSFER'), undefined);
  assertStrictEquals(mapEventToBillingIssue('SUBSCRIBER_ALIAS'), undefined);
  assertStrictEquals(mapEventToBillingIssue(''), undefined);
});

Deno.test('billing-issue + tier branches are independent for BILLING_ISSUE', () => {
  // The whole point of the split: BILLING_ISSUE moves the flag but
  // NOT the tier. A future refactor that re-couples them would slip
  // through if we didn't have a test that asserts both at once.
  const tier = mapEventToTier('BILLING_ISSUE', 'pro_monthly', 'pro');
  const flag = mapEventToBillingIssue('BILLING_ISSUE');
  assertStrictEquals(tier, null);
  assertStrictEquals(typeof flag, 'string');
});

Deno.test('event taxonomy lists are disjoint', () => {
  // Sanity: an event type in BOTH lists would make routing
  // dependent on iteration order. This test catches a future
  // edit that drops a string into both arrays.
  for (const e of ACTIVATING_EVENTS) {
    assertStrictEquals(
      (DEACTIVATING_EVENTS as readonly string[]).includes(e),
      false,
      `${e} appears in both ACTIVATING_EVENTS and DEACTIVATING_EVENTS`,
    );
  }
});
