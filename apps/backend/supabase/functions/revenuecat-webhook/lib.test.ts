/// Run with `cd apps/backend && deno test supabase/functions/revenuecat-webhook/lib.test.ts`.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  ACTIVATING_EVENTS,
  DEACTIVATING_EVENTS,
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
