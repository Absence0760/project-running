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
  TIER_EVENT_TS_COLUMN,
  tierEventGuardFilter,
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

// ── monotonic tier-write guard (out-of-order delivery) ────────────
//
// The webhook stamps `tier_updated_event_ts` on every tier change and
// gates the UPDATE with `tierEventGuardFilter` so a stale, out-of-order
// deactivation cannot downgrade a re-subscribed user. The gate runs in
// Postgres (an atomic conditional UPDATE), so these tests emulate the
// exact WHERE the filter compiles to — `tier_updated_event_ts IS NULL OR
// tier_updated_event_ts <= eventTsMs` — against a modelled stored value.

/// Emulate the PostgREST `.or()` filter `tierEventGuardFilter` produces:
/// does the conditional UPDATE match a row whose stored tier-event
/// timestamp is `storedTsMs` (null = never set)?
function guardMatches(storedTsMs: number | null, eventTsMs: number): boolean {
  const filter = tierEventGuardFilter(eventTsMs);
  // filter === "tier_updated_event_ts.is.null,tier_updated_event_ts.lte.<ts>"
  const [isNull, lte] = filter.split(',');
  if (isNull !== `${TIER_EVENT_TS_COLUMN}.is.null` || !lte.startsWith(`${TIER_EVENT_TS_COLUMN}.lte.`)) {
    throw new Error(`unexpected filter shape: ${filter}`);
  }
  const threshold = Number(lte.slice(`${TIER_EVENT_TS_COLUMN}.lte.`.length));
  return storedTsMs === null || storedTsMs <= threshold;
}

Deno.test('tierEventGuardFilter — exact PostgREST or() shape', () => {
  assertStrictEquals(
    tierEventGuardFilter(1_700_000_000_000),
    'tier_updated_event_ts.is.null,tier_updated_event_ts.lte.1700000000000',
  );
});

Deno.test('monotonic guard — out-of-order EXPIRATION after a newer RENEWAL is dropped', () => {
  const T1 = 1_700_000_000_000; // EXPIRATION event time
  const T2 = 1_700_000_060_000; // RENEWAL event time, one minute later

  // RENEWAL (T2) processed first → stored tier-event ts is now T2, tier 'pro'.
  const storedAfterRenewal = T2;

  // The out-of-order EXPIRATION (T1 < T2) arrives second. Its guard filter
  // is `<= T1`, which does NOT match the row (stored T2 > T1) → zero rows
  // updated → tier stays 'pro'. This is the bug the fix closes.
  assertStrictEquals(guardMatches(storedAfterRenewal, T1), false);
});

Deno.test('monotonic guard — an in-order EXPIRATION still downgrades', () => {
  const T2 = 1_700_000_060_000; // last tier-moving event (a purchase)
  const T3 = 1_700_000_120_000; // later, genuine EXPIRATION

  // The normal case: the EXPIRATION is the newest event (T3 > T2) → its
  // guard `<= T3` matches the row (stored T2) → the downgrade to 'free'
  // lands. The fix must not break the ordinary lapse path.
  assertStrictEquals(guardMatches(T2, T3), true);
});

Deno.test('monotonic guard — first-ever tier write (null stored) always applies', () => {
  // A never-subscribed user has tier_updated_event_ts = null; the
  // `is.null` disjunct matches so the initial purchase always lands.
  assertStrictEquals(guardMatches(null, 1_700_000_000_000), true);
});

Deno.test('monotonic guard — a same-timestamp distinct event still applies (inclusive lte)', () => {
  // Two distinct events sharing an event_timestamp_ms is rare but legal;
  // an exact replay is already caught by the event-id dedupe, so the
  // guard is inclusive (`<=`) rather than strict.
  const T = 1_700_000_000_000;
  assertStrictEquals(guardMatches(T, T), true);
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
