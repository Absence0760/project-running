/// Run with `cd apps/backend && deno test supabase/functions/_shared/input_validation.test.ts`.
/// (No allow-net flag needed — this module is pure.)
///
/// Both validators exist to convert a Postgres cast failure into a 400.
/// The cases below are the ones that actually reached PostgREST from a
/// request body: a non-uuid where a `uuid` column was expected (22P02)
/// and a non-ISO string where a `timestamptz` column was expected
/// (22007). A regression that loosened either would restore the 500s.

import { assertStrictEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { isValidTimestamptz, isValidUuid } from './input_validation.ts';

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
  assertStrictEquals(isValidUuid(null), false);
  assertStrictEquals(isValidUuid(undefined), false);
  assertStrictEquals(isValidUuid(42), false);
  // RevenueCat anonymous prefix shape.
  assertStrictEquals(isValidUuid('$RCAnonymousID:abcdef'), false);
});

Deno.test('isValidTimestamptz — accepts every shape the clients emit', () => {
  // JS `toISOString()`.
  assertStrictEquals(isValidTimestamptz('2026-06-01T09:00:00.000Z'), true);
  // Dart `toUtc().toIso8601String()`.
  assertStrictEquals(isValidTimestamptz('2026-06-01T09:00:00.000000Z'), true);
  // Read back from PostgREST.
  assertStrictEquals(isValidTimestamptz('2026-06-01T09:00:00+00:00'), true);
  assertStrictEquals(isValidTimestamptz('2026-06-01T09:00:00+0200'), true);
  // Seconds and offset are both optional; a naive literal resolves
  // against the server TimeZone, which Postgres accepts.
  assertStrictEquals(isValidTimestamptz('2026-06-01T09:00'), true);
  assertStrictEquals(isValidTimestamptz('2026-06-01 09:00:00'), true);
});

Deno.test('isValidTimestamptz — rejects what Postgres would 22007 on', () => {
  assertStrictEquals(isValidTimestamptz('not a date'), false);
  assertStrictEquals(isValidTimestamptz(''), false);
  assertStrictEquals(isValidTimestamptz('2026-06-01'), false, 'a bare date is not a timestamp');
  assertStrictEquals(isValidTimestamptz("2026-06-01T09:00:00Z'; select 1--"), false);
  assertStrictEquals(isValidTimestamptz(null), false);
  assertStrictEquals(isValidTimestamptz(undefined), false);
  assertStrictEquals(isValidTimestamptz(1780000000000), false);
});

Deno.test('isValidTimestamptz — rejects the JS toString() form Date.parse accepts', () => {
  // The whole reason `Date.parse` alone is not the gate: V8 parses this
  // happily, Postgres does not, so the value would sail past validation
  // and 22007 on the wire.
  const jsToString = 'Sat Jan 01 2026 00:00:00 GMT+0000 (Coordinated Universal Time)';
  assertStrictEquals(Number.isFinite(Date.parse(jsToString)), true);
  assertStrictEquals(isValidTimestamptz(jsToString), false);
});

Deno.test('isValidTimestamptz — rejects an in-shape but out-of-range date', () => {
  // The regex cannot know February has no 30th; the parse does.
  assertStrictEquals(isValidTimestamptz('2026-02-30T00:00:00Z'), false);
  assertStrictEquals(isValidTimestamptz('2026-13-01T00:00:00Z'), false);
  assertStrictEquals(isValidTimestamptz('2026-06-01T25:00:00Z'), false);
});
