/// The two shape gates that keep a raw postgres error off a caller, and the
/// instant comparison that decides what a buyer is charged.
///
/// `isValidTimestamptz` exists because `Date.parse` is wrong in both
/// directions, so the calendar arithmetic it replaces it with is the thing to
/// test: leap years, the century rule, the end-of-day literal, the leap second
/// and the offset ceiling are each a branch nothing else exercises. And
/// `selectEffectivePricing` picks the `event_pricing` row that governs a
/// checkout's amount and a cancellation's refund policy, which makes "falls
/// through to the series default" a money answer rather than a lookup detail.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/_shared/validation_hardening.test.ts`.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { isValidTimestamptz, isValidUuid } from './input_validation.ts';
import { sameInstant, selectEffectivePricing } from './event_instance.ts';

Deno.test('isValidUuid — the accepted shape, and the near-misses that reach 22P02', () => {
  const accepted = [
    '00000000-0000-0000-0000-000000000000',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
    'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF',
    '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
  ];
  for (const s of accepted) assertEquals(isValidUuid(s), true, s);
  const refused: unknown[] = [
    '',
    ' 3f2504e0-4f89-11d3-9a0c-0305e82c3301',
    '3f2504e0-4f89-11d3-9a0c-0305e82c3301 ',
    '3f2504e0-4f89-11d3-9a0c-0305e82c330',
    '3f2504e0-4f89-11d3-9a0c-0305e82c33011',
    '3f2504e04f8911d39a0c0305e82c3301',
    '{3f2504e0-4f89-11d3-9a0c-0305e82c3301}',
    '3f2504e0-4f89-11d3-9a0c-0305e82c330g',
    '3f2504e0_4f89_11d3_9a0c_0305e82c3301',
    "3f2504e0-4f89-11d3-9a0c-0305e82c3301' or '1'='1",
    null,
    undefined,
    42,
    true,
    {},
    [],
  ];
  for (const s of refused) assertEquals(isValidUuid(s), false, JSON.stringify(s) ?? String(s));
});

Deno.test('isValidTimestamptz — the leap-year rule is the calendar\'s, not a mod-four guess', () => {
  assertEquals(isValidTimestamptz('2024-02-29T00:00:00Z'), true, 'a leap year');
  assertEquals(isValidTimestamptz('2023-02-29T00:00:00Z'), false, 'not a leap year');
  assertEquals(isValidTimestamptz('2100-02-29T00:00:00Z'), false, 'the century exception');
  assertEquals(isValidTimestamptz('2000-02-29T00:00:00Z'), true, 'the 400-year exception');
  assertEquals(isValidTimestamptz('2026-02-28T00:00:00Z'), true);
  // V8 rolls a day-of-month overflow forward rather than failing, so
  // `Date.parse` accepts every one of these and Postgres 22007s on the wire.
  for (const s of ['2026-02-30T00:00:00Z', '2026-04-31T00:00:00Z', '2026-06-31T00:00:00Z']) {
    assertEquals(isValidTimestamptz(s), false, s);
  }
});

Deno.test('isValidTimestamptz — every month\'s last day is admitted and its overflow is not', () => {
  const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  lengths.forEach((last, i) => {
    const mm = String(i + 1).padStart(2, '0');
    assertEquals(isValidTimestamptz(`2026-${mm}-${String(last).padStart(2, '0')}T00:00:00Z`), true, mm);
    assertEquals(
      isValidTimestamptz(`2026-${mm}-${String(last + 1).padStart(2, '0')}T00:00:00Z`),
      false,
      `${mm} overflow`,
    );
  });
  assertEquals(isValidTimestamptz('2026-00-01T00:00:00Z'), false, 'month zero');
  assertEquals(isValidTimestamptz('2026-13-01T00:00:00Z'), false, 'month thirteen');
  assertEquals(isValidTimestamptz('2026-01-00T00:00:00Z'), false, 'day zero');
});

Deno.test('isValidTimestamptz — the end-of-day literal and the leap second, at their edges', () => {
  assertEquals(isValidTimestamptz('2026-01-01T24:00:00Z'), true, '24:00:00 is a legal literal');
  assertEquals(isValidTimestamptz('2026-01-01T24:00:01Z'), false);
  assertEquals(isValidTimestamptz('2026-01-01T24:01:00Z'), false);
  assertEquals(isValidTimestamptz('2026-01-01T25:00:00Z'), false);
  assertEquals(isValidTimestamptz('2026-01-01T23:59:60Z'), true, 'the leap second');
  assertEquals(isValidTimestamptz('2026-01-01T23:59:61Z'), false);
  assertEquals(isValidTimestamptz('2026-01-01T23:60:00Z'), false);
});

Deno.test('isValidTimestamptz — the offset tops out where Postgres does', () => {
  assertEquals(isValidTimestamptz('2026-01-01T00:00:00+15:59'), true);
  assertEquals(isValidTimestamptz('2026-01-01T00:00:00-15:59'), true);
  assertEquals(isValidTimestamptz('2026-01-01T00:00:00+16:00'), false);
  assertEquals(isValidTimestamptz('2026-01-01T00:00:00+15:60'), false);
  assertEquals(isValidTimestamptz('2026-01-01T00:00:00+02'), true, 'hour-only offset');
  assertEquals(isValidTimestamptz('2026-01-01T00:00:00+0200'), true, 'compact offset');
});

Deno.test('isValidTimestamptz — the renderings every client here actually emits', () => {
  const emitted = [
    new Date('2026-06-01T18:00:00Z').toISOString(),
    '2026-06-01T18:00:00+00:00',
    '2026-06-01 18:00:00+00',
    '2026-06-01T18:00Z',
    '2026-06-01T18:00:00',
    '2026-06-01T18:00:00.1Z',
    '2026-06-01T18:00:00.123456789Z',
  ];
  for (const s of emitted) assertEquals(isValidTimestamptz(s), true, s);
});

Deno.test('isValidTimestamptz — the forms that only look like timestamps', () => {
  const refused: unknown[] = [
    '',
    '2026-06-01',
    '18:00:00Z',
    'Sat Jan 01 2026 00:00:00 GMT+0000 (Coordinated Universal Time)',
    'now()',
    '2026-06-01T18:00:00.1234567890Z',
    '2026-6-1T18:00:00Z',
    '26-06-01T18:00:00Z',
    `2026-06-01T18:00:00Z${' '.repeat(20)}`,
    null,
    undefined,
    1780000000000,
    true,
    {},
    [],
  ];
  for (const s of refused) assertEquals(isValidTimestamptz(s), false, JSON.stringify(s) ?? String(s));
});

Deno.test('sameInstant — two renderings of one instant match, and an unknown one never does', () => {
  assertEquals(sameInstant('2026-06-01T18:00:00+00:00', '2026-06-01T18:00:00.000Z'), true);
  assertEquals(sameInstant('2026-06-01T20:00:00+02:00', '2026-06-01T18:00:00.000Z'), true);
  assertEquals(sameInstant('2026-06-01T18:00:00Z', '2026-06-01T18:00:01Z'), false);
  for (const bad of [null, undefined, '', 'soon', 'now()']) {
    assertEquals(sameInstant(bad, '2026-06-01T18:00:00Z'), false, String(bad));
    assertEquals(sameInstant('2026-06-01T18:00:00Z', bad), false, String(bad));
  }
  assertEquals(sameInstant(null, null), false, 'two unknowns are not equal, they are unknown');
});

interface Pricing {
  id: string;
  instance_start: string | null;
  price_cents: number;
}

Deno.test('selectEffectivePricing — an override for that exact instant wins, in either rendering', () => {
  const rows: Pricing[] = [
    { id: 'default', instance_start: null, price_cents: 5000 },
    { id: 'override', instance_start: '2026-06-01T18:00:00+00:00', price_cents: 2500 },
  ];
  for (const asked of ['2026-06-01T18:00:00.000Z', '2026-06-01T18:00:00+00:00', '2026-06-01T20:00:00+02:00']) {
    assertEquals(selectEffectivePricing(rows, asked)?.id, 'override', asked);
    assertEquals(selectEffectivePricing(rows, asked)?.price_cents, 2500, asked);
  }
});

Deno.test('selectEffectivePricing — a different occurrence pays the series default', () => {
  const rows: Pricing[] = [
    { id: 'default', instance_start: null, price_cents: 5000 },
    { id: 'override', instance_start: '2026-06-01T18:00:00Z', price_cents: 2500 },
  ];
  assertEquals(selectEffectivePricing(rows, '2026-06-08T18:00:00Z')?.id, 'default');
  assertEquals(selectEffectivePricing(rows, '2026-06-08T18:00:00Z')?.price_cents, 5000);
});

Deno.test('selectEffectivePricing — an unusable instant charges the default, never an override', () => {
  // Charging an override's price off a bad parse is the failure that would show
  // up as a buyer paying the wrong amount, so an instant nobody can read has to
  // fall through rather than match whatever is first in the list.
  const rows: Pricing[] = [
    { id: 'override', instance_start: '2026-06-01T18:00:00Z', price_cents: 2500 },
    { id: 'default', instance_start: null, price_cents: 5000 },
  ];
  for (const asked of [null, undefined, '', 'not a date', 'now()']) {
    assertEquals(selectEffectivePricing(rows, asked)?.id, 'default', String(asked));
  }
  // And an override row whose own instant is unreadable cannot be selected by
  // anything either.
  const brokenOverride: Pricing[] = [
    { id: 'override', instance_start: 'not a date', price_cents: 2500 },
    { id: 'default', instance_start: null, price_cents: 5000 },
  ];
  assertEquals(selectEffectivePricing(brokenOverride, 'not a date')?.id, 'default');
});

Deno.test('selectEffectivePricing — an unpriced event selects nothing rather than a free seat', () => {
  assertEquals(selectEffectivePricing([] as Pricing[], '2026-06-01T18:00:00Z'), null);
  const overrideOnly: Pricing[] = [
    { id: 'override', instance_start: '2026-06-01T18:00:00Z', price_cents: 2500 },
  ];
  assertEquals(selectEffectivePricing(overrideOnly, '2026-06-08T18:00:00Z'), null);
  assertEquals(selectEffectivePricing(overrideOnly, '2026-06-01T18:00:00Z')?.id, 'override');
});

Deno.test('selectEffectivePricing — the first matching row decides, deterministically', () => {
  // Duplicate rows for one instant are a data problem, not a licence to charge
  // an arbitrary one of them: two reads of the same list must name the same
  // price.
  const rows: Pricing[] = [
    { id: 'first', instance_start: '2026-06-01T18:00:00Z', price_cents: 2500 },
    { id: 'second', instance_start: '2026-06-01T18:00:00.000Z', price_cents: 9900 },
    { id: 'default-a', instance_start: null, price_cents: 5000 },
    { id: 'default-b', instance_start: null, price_cents: 7700 },
  ];
  assertEquals(selectEffectivePricing(rows, '2026-06-01T18:00:00Z')?.id, 'first');
  assertEquals(selectEffectivePricing(rows, '2026-06-08T18:00:00Z')?.id, 'default-a');
});

Deno.test('isValidTimestamptz — the calendar starts at year 1, because Postgres does', () => {
  // ISO 8601 writes 1 BC as 0000; Postgres has no year zero and raises 22008
  // on it. The gate exists to turn exactly that class of cast failure into a
  // 400, and it used to admit the value and let it 500 on the wire.
  assertEquals(isValidTimestamptz('0000-01-01T00:00:00Z'), false);
  assertEquals(isValidTimestamptz('0000-12-31T23:59:59+00:00'), false);
  // The first year Postgres will take, and the four-digit years around it,
  // are still admitted — the guard is a floor, not a narrowing.
  assertEquals(isValidTimestamptz('0001-01-01T00:00:00Z'), true);
  assertEquals(isValidTimestamptz('1999-12-31T23:59:59Z'), true);
  assertEquals(isValidTimestamptz('9999-12-31T23:59:59Z'), true);
});
