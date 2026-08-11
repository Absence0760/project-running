/// Run with `cd apps/backend && deno test supabase/functions/_shared/event_instance.test.ts`.
/// (No flags needed — this module is pure.)
///
/// Pins the instance-timestamp comparison the paid-events functions use to
/// pick a price and a refund policy. Before this helper, events-checkout and
/// events-cancel both did `r.instance_start === instanceStart` — a string
/// compare between PostgREST's `+00:00` rendering and the client's
/// `Date#toISOString` `.000Z` rendering of the same instant, which is never
/// equal. Every per-instance override was therefore skipped in favour of the
/// series default; an event priced ONLY per-instance 404'd `event_not_priced`
/// at checkout and fell back to `no_refund` at cancel, denying a refund the
/// host had granted.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

import { sameInstant, selectEffectivePricing } from './event_instance.ts';

const FROM_DB = '2026-06-01T18:00:00+00:00';
const FROM_CLIENT = '2026-06-01T18:00:00.000Z';

Deno.test('sameInstant matches the PostgREST and toISOString renderings', () => {
  assertEquals(FROM_DB as string === FROM_CLIENT as string, false);
  assertEquals(sameInstant(FROM_DB, FROM_CLIENT), true);
  assertEquals(sameInstant(FROM_CLIENT, FROM_DB), true);
});

Deno.test('sameInstant matches across offsets naming the same moment', () => {
  assertEquals(sameInstant('2026-06-01T20:00:00+02:00', FROM_CLIENT), true);
});

Deno.test('sameInstant separates different instants', () => {
  assertEquals(sameInstant('2026-06-08T18:00:00+00:00', FROM_CLIENT), false);
  assertEquals(sameInstant('2026-06-01T18:00:01+00:00', FROM_CLIENT), false);
});

Deno.test('sameInstant treats an unknown side as not equal, never as a match', () => {
  assertEquals(sameInstant(null, FROM_CLIENT), false);
  assertEquals(sameInstant(FROM_CLIENT, null), false);
  assertEquals(sameInstant(null, null), false);
  assertEquals(sameInstant(undefined, undefined), false);
  assertEquals(sameInstant('not a date', FROM_CLIENT), false);
  assertEquals(sameInstant(FROM_CLIENT, ''), false);
});

Deno.test('selectEffectivePricing prefers the override for that instant', () => {
  const rows = [
    { instance_start: null, price_cents: 2200 },
    { instance_start: FROM_DB, price_cents: 4400 },
  ];
  assertEquals(selectEffectivePricing(rows, FROM_CLIENT)?.price_cents, 4400);
});

Deno.test('selectEffectivePricing falls back to the series default', () => {
  const rows = [
    { instance_start: null, price_cents: 2200 },
    { instance_start: '2026-06-08T18:00:00+00:00', price_cents: 4400 },
  ];
  assertEquals(selectEffectivePricing(rows, FROM_CLIENT)?.price_cents, 2200);
});

Deno.test('selectEffectivePricing returns null when the event is unpriced', () => {
  assertEquals(selectEffectivePricing([], FROM_CLIENT), null);
  assertEquals(
    selectEffectivePricing(
      [{ instance_start: '2026-06-08T18:00:00+00:00' }],
      FROM_CLIENT,
    ),
    null,
  );
});
