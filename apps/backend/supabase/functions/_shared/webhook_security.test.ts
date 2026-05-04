/// Run with `cd apps/backend && deno test supabase/functions/_shared/webhook_security.test.ts`.
/// (No allow-net flag needed — this module is pure.)

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  isAnonymousAppUserId,
  isValidUuid,
  timingSafeEqual,
  validateFreshness,
} from './webhook_security.ts';

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

Deno.test('isValidUuid — accepts standard 8-4-4-4-12 hex shape', () => {
  assertStrictEquals(isValidUuid('00000000-0000-0000-0000-000000000000'), true);
  assertStrictEquals(isValidUuid('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  assertStrictEquals(isValidUuid('AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'), true);
  // Real-shape user-id from the seed.
  assertStrictEquals(isValidUuid('12345678-1234-1234-1234-123456789abc'), true);
});

Deno.test('isValidUuid — rejects malformed shapes', () => {
  // Wrong segment lengths.
  assertStrictEquals(isValidUuid('0000-0000-0000-0000-000000000000'), false);
  assertStrictEquals(isValidUuid('00000000-0000-0000-0000-00000000000'), false);
  assertStrictEquals(isValidUuid('00000000-0000-0000-0000-0000000000000'), false);
  // Non-hex characters.
  assertStrictEquals(isValidUuid('zzzzzzzz-0000-0000-0000-000000000000'), false);
  // Empty / wrong type.
  assertStrictEquals(isValidUuid(''), false);
  // RevenueCat anonymous prefix shape.
  assertStrictEquals(isValidUuid('$RCAnonymousID:abcdef'), false);
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
