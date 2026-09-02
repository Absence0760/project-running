/// Run with `cd apps/backend && deno test supabase/functions/_shared/webhook_security.test.ts`.
/// (No allow-net flag needed — this module is pure.)

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  hmacHex,
  isAnonymousAppUserId,
  shouldReleaseDedupe,
  timingSafeEqual,
  validateFreshness,
} from './webhook_security.ts';

// Reference vector pinned by RFC 4868 §2.7.2 (SHA-256 case 4): a key
// of 0x0102…0x19 (25 bytes) over body 'cdcdcdcd' × 50 produces
// 82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b.
// Generating new vectors at home is straightforward (`openssl dgst
// -sha256 -hmac …`); RFC vectors mean the test catches a digest
// regression even if the new HMAC ever needed re-validating.
Deno.test(
  'hmacHex — RFC 4868 §2.7.2 case 4 SHA-256 reference vector',
  async () => {
    // Pass Uint8Array on both sides so the non-ASCII body bytes
    // (0xcd × 50) reach HMAC as bytes — not UTF-8-expanded. The
    // previous version of this test stringified everything via
    // `String.fromCharCode`, which made TextEncoder emit `c3 8d` for
    // each 0xcd byte and broke the reference-vector check.
    const keyBytes = new Uint8Array(25);
    for (let i = 0; i < 25; i++) keyBytes[i] = 0x01 + i;
    const bodyBytes = new Uint8Array(50).fill(0xcd);
    const result = await hmacHex(keyBytes, bodyBytes);
    assertEquals(
      result,
      '82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b',
    );
  },
);

Deno.test('hmacHex — empty body produces a stable digest', async () => {
  const result = await hmacHex('shared-secret', '');
  // Cross-checked once with `printf '' | openssl dgst -sha256 -hmac
  // shared-secret -hex`; the value will never change unless this
  // function changes its input encoding.
  assertEquals(
    result,
    '7b044c3dd799953a630dbe15e3ff5b35c73270a81761044546851aa97a54bd17',
  );
});

Deno.test('hmacHex — known-different keys produce different digests', async () => {
  const a = await hmacHex('key-a', 'payload');
  const b = await hmacHex('key-b', 'payload');
  assertEquals(a.length, 64);
  assertEquals(b.length, 64);
  // Just guard against the trivial accidental degenerate case
  // where the function ignores the key.
  if (a === b) {
    throw new Error('hmacHex must vary by key — got identical digests');
  }
});

Deno.test('timingSafeEqual — equal strings return true', () => {
  assertStrictEquals(timingSafeEqual('abc123', 'abc123'), true);
  assertStrictEquals(timingSafeEqual('', ''), true);
  assertStrictEquals(
    timingSafeEqual(
      'a'.repeat(64),
      'a'.repeat(64),
    ),
    true,
  );
});

Deno.test('timingSafeEqual — different strings of equal length return false', () => {
  assertStrictEquals(timingSafeEqual('abc', 'abd'), false);
  // Single-bit difference.
  assertStrictEquals(timingSafeEqual('a', 'b'), false);
});

Deno.test('timingSafeEqual — length mismatch returns false', () => {
  assertStrictEquals(timingSafeEqual('abc', 'abcd'), false);
  assertStrictEquals(timingSafeEqual('', 'a'), false);
});

Deno.test('timingSafeEqual — does NOT short-circuit on first mismatch', () => {
  // We can't directly observe non-short-circuit behaviour from a unit
  // test (we'd need a clock-cycle harness), but we can pin the
  // behavioural surface: any mismatched character anywhere in the
  // string returns false, including the last one. Combined with the
  // implementation being a simple bitwise OR loop (read the source),
  // this gives us coverage that the "constant-time" property holds.
  const a = 'a'.repeat(63) + 'x';
  const b = 'a'.repeat(63) + 'y';
  assertStrictEquals(timingSafeEqual(a, b), false);
});

Deno.test('validateFreshness — recent event is ok', () => {
  const now = 1_700_000_000_000;
  // 5 seconds ago.
  assertEquals(validateFreshness(now - 5_000, now), 'ok');
  // Same ms.
  assertEquals(validateFreshness(now, now), 'ok');
});

Deno.test('validateFreshness — event older than 7 days is too_old', () => {
  const now = 1_700_000_000_000;
  const eightDaysMs = 8 * 24 * 60 * 60 * 1000;
  assertEquals(validateFreshness(now - eightDaysMs, now), 'too_old');
});

Deno.test('validateFreshness — event right at the 7-day boundary is ok', () => {
  const now = 1_700_000_000_000;
  const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
  // ageMs == windowMs → not strictly greater → 'ok'.
  assertEquals(validateFreshness(now - sevenDaysMs, now), 'ok');
  // Just past the boundary.
  assertEquals(validateFreshness(now - sevenDaysMs - 1, now), 'too_old');
});

Deno.test('validateFreshness — event slightly in the future is ok (clock skew)', () => {
  const now = 1_700_000_000_000;
  // Up to 60 s in the future is allowed by default.
  assertEquals(validateFreshness(now + 30_000, now), 'ok');
  assertEquals(validateFreshness(now + 60_000, now), 'ok');
});

Deno.test('validateFreshness — event too far in the future is too_future', () => {
  const now = 1_700_000_000_000;
  // 2 minutes ahead — past the default 60 s clock-skew tolerance.
  assertEquals(validateFreshness(now + 120_000, now), 'too_future');
});

Deno.test('validateFreshness — custom windowMs / clockSkewMs are honoured', () => {
  const now = 1_700_000_000_000;
  // Tighter window: 1 hour.
  assertEquals(validateFreshness(now - 30 * 60 * 1000, now, 60 * 60 * 1000), 'ok');
  assertEquals(validateFreshness(now - 90 * 60 * 1000, now, 60 * 60 * 1000), 'too_old');
  // Tighter clock skew: 1 ms.
  assertEquals(validateFreshness(now + 100, now, 7 * 24 * 60 * 60 * 1000, 1), 'too_future');
});

Deno.test('isAnonymousAppUserId — RC anonymous prefix detected', () => {
  assertStrictEquals(isAnonymousAppUserId('$RCAnonymousID:abc123'), true);
  assertStrictEquals(isAnonymousAppUserId('$RCAnonymousID'), true);
});

Deno.test('isAnonymousAppUserId — non-anonymous ids return false', () => {
  assertStrictEquals(
    isAnonymousAppUserId('12345678-1234-1234-1234-123456789abc'),
    false,
  );
  assertStrictEquals(isAnonymousAppUserId(''), false);
  assertStrictEquals(isAnonymousAppUserId('rcanonymousid:abc'), false);
});

Deno.test('validateFreshness — an unusable stamp is refused, not waved through', () => {
  // Every comparison against NaN is false, so both gates fell through and the
  // replay window opened for anything a caller could make unparseable —
  // `Date.parse` of a bad string, a field read off a body with no schema, an
  // arithmetic overflow. The two live callers type-check their field first,
  // which is why nothing had noticed; the gate must not depend on that.
  const now = Date.now();
  for (const bad of [NaN, Infinity, -Infinity]) {
    assertEquals(validateFreshness(bad, now), 'too_old', String(bad));
  }
  // A broken clock on our side is the same problem from the other direction.
  assertEquals(validateFreshness(now, NaN), 'too_old');
  // The positive control beside it: a good stamp against a good clock is
  // still ok, so the guard is not a blanket refusal.
  assertEquals(validateFreshness(now - 1000, now), 'ok');
});

Deno.test('validateFreshness — the future edge is exclusive, like the past one', () => {
  // The past side has both its edges pinned above. The future side had only
  // an inside and an outside point, so a `<` / `<=` slip was invisible.
  const now = Date.now();
  const skew = 60 * 1000;
  assertEquals(validateFreshness(now + skew, now), 'ok');
  assertEquals(validateFreshness(now + skew + 1, now), 'too_future');
});

// ── insert-first dedupe: the row has to come back ────────────────────────────
//
// Every webhook here reserves `webhook_events` BEFORE the side effect, so two
// concurrent deliveries of one event cannot both act. The price is that a
// handler which fails owes the row back — the provider retries on a non-2xx
// and the retry hits the 23505 path, answers 200 `duplicate_event`, and closes
// the delivery for good. Stripe and Strava released it; RevenueCat did not,
// and RevenueCat is the one that grants a paid tier.

Deno.test('shouldReleaseDedupe — every 5xx, and the boundary is 500 exactly', () => {
  for (const status of [500, 502, 503, 504, 599]) {
    assertEquals(shouldReleaseDedupe(status), true, `status ${status} must release`);
  }
  for (const status of [200, 201, 204, 400, 401, 404, 409, 429, 499]) {
    assertEquals(shouldReleaseDedupe(status), false, `status ${status} must keep the row`);
  }
});

Deno.test('every insert-first deduper gives the row back on a 5xx', async () => {
  // Derived from the tree rather than listed, so a fourth webhook that
  // reserves a dedupe row is covered the day it lands. The pairing is the
  // whole check: reserving without releasing is not a stricter posture, it is
  // a delivery that can never be retried.
  const dir = new URL('../', import.meta.url);
  const reserving: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (!entry.isDirectory || entry.name.startsWith('_')) continue;
    let src: string;
    try {
      src = await Deno.readTextFile(new URL(`${entry.name}/index.ts`, dir));
    } catch {
      continue;
    }
    if (!/\.from\('webhook_events'\)\s*\n?\s*\.insert\(/.test(src)) continue;
    reserving.push(entry.name);
    assert(
      /\.from\('webhook_events'\)\s*\n?\s*\.delete\(\)/.test(src),
      `${entry.name} reserves a webhook_events row and never deletes one, so a failed ` +
        'delivery is answered 200 duplicate_event on every retry and is lost',
    );
  }
  // A positive control: an empty tree, or a rename of the table, would satisfy
  // the loop above by iterating zero times.
  assertEquals(
    reserving.sort(),
    ['revenuecat-webhook', 'strava-webhook', 'stripe-events-webhook'],
    'the set of insert-first dedupers changed — check the new one releases too',
  );
});

Deno.test('the two webhooks that dispatch behind a release use this rule, not a local one', async () => {
  // Stripe's copy lived in its own lib for as long as RevenueCat went without
  // any. Both now read the same function, so the boundary cannot drift to two
  // different numbers on two providers whose retry envelopes are the same.
  for (const fn of ['stripe-events-webhook', 'revenuecat-webhook']) {
    const src = await Deno.readTextFile(new URL(`../${fn}/index.ts`, import.meta.url));
    assert(
      /if \(shouldReleaseDedupe\(res\.status\)\) \{/.test(src),
      `${fn} must gate its release on shouldReleaseDedupe(res.status)`,
    );
    assert(
      !/res\.status >= 500/.test(src),
      `${fn} must not re-spell the 5xx boundary inline`,
    );
  }
});

Deno.test('a throw past the dispatcher releases the row too', async () => {
  // withSentry answers 500 for an uncaught throw, and that 500 never passes
  // through the status check above it — so the catch arm is the only thing
  // between a thrown handler and a permanently-swallowed delivery.
  for (const fn of ['stripe-events-webhook', 'revenuecat-webhook']) {
    const src = await Deno.readTextFile(new URL(`../${fn}/index.ts`, import.meta.url));
    assert(
      /\} catch \(err\) \{\s*\n\s*await releaseDedupe\([^)]*\);\s*\n\s*throw err;/.test(src),
      `${fn} must release the dedupe row before rethrowing`,
    );
  }
});
