/// Run with `cd apps/backend && deno test --allow-read supabase/functions/_shared/param_validation_wiring.test.ts`.
///
/// Source-grep guards, in the `delete-account/wiring.test.ts` idiom: the
/// handlers themselves need a live Supabase to exercise, but the
/// property that matters is positional and readable off the source —
/// every caller-supplied `uuid` / `timestamptz` is shape-checked BEFORE
/// it reaches the query that would cast it.
///
/// Without the check, PostgREST hands Postgres a value it cannot cast:
/// `22P02 invalid_input_syntax` on a uuid column, `22007
/// invalid_datetime_format` on a timestamptz one. Both surface as a 500
/// (or, where the handler collapses `error || !row`, as a misleading
/// 404), page Sentry, and — on `donations-checkout`, which anon callers
/// can reach — burn a rate-limit slot first.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

async function read(fn: string): Promise<string> {
  return await Deno.readTextFile(new URL(`../${fn}/index.ts`, import.meta.url));
}

/// Assert `guard` appears in `src` and appears before `consumer`.
function assertGuardedBefore(
  src: string,
  fn: string,
  guard: string,
  consumer: string,
): void {
  const g = src.indexOf(guard);
  const c = src.indexOf(consumer);
  assert(g !== -1, `${fn} must validate with \`${guard}\` — has the gate been dropped?`);
  assert(c !== -1, `${fn} no longer contains \`${consumer}\` — has the query moved or been renamed?`);
  assert(
    g < c,
    `${fn}: \`${guard}\` must run BEFORE \`${consumer}\`, otherwise the malformed ` +
      'value reaches Postgres and the caller gets a 500 instead of a 400',
  );
}

Deno.test('events-cancel validates event_id + instance_start before querying', async () => {
  const src = await read('events-cancel');
  assert(
    src.includes("from '../_shared/input_validation.ts'"),
    'events-cancel must import the shared validators',
  );
  assertGuardedBefore(src, 'events-cancel', 'isValidUuid(eventId)', ".eq('event_id', eventId)");
  assertGuardedBefore(
    src,
    'events-cancel',
    'isValidTimestamptz(instanceStart)',
    ".eq('instance_start', instanceStart)",
  );
});

Deno.test('events-checkout validates event_id + instance_start before querying', async () => {
  const src = await read('events-checkout');
  assert(
    src.includes("from '../_shared/input_validation.ts'"),
    'events-checkout must import the shared validators',
  );
  assertGuardedBefore(src, 'events-checkout', 'isValidUuid(eventId)', ".eq('id', eventId)");
  // The `Date.parse` + `Number.isFinite` pair this replaced accepted
  // shapes Postgres rejects, so the value passed validation and 22007'd
  // on the wire anyway.
  assertGuardedBefore(
    src,
    'events-checkout',
    'isValidTimestamptz(instanceStart)',
    ".eq('instance_start', instanceStart)",
  );
});

Deno.test('donations-checkout validates fundraiser_id before the rate limit', async () => {
  const src = await read('donations-checkout');
  assert(
    src.includes("from '../_shared/input_validation.ts'"),
    'donations-checkout must import the shared validators',
  );
  assertGuardedBefore(
    src,
    'donations-checkout',
    'isValidUuid(fundraiserId)',
    ".eq('id', fundraiserId)",
  );
  // This function is anon-reachable by design (donors need no account),
  // so the shape check has to come before the IP bucket is spent —
  // otherwise a malformed id costs the caller a slot on the way to a
  // 500. Same ordering `clip-public-track` already takes.
  assertGuardedBefore(src, 'donations-checkout', 'isValidUuid(fundraiserId)', 'ipBucketKey(req)');
});

Deno.test('race-results-import validates listingId + matchRunId before querying', async () => {
  const src = await read('race-results-import');
  assert(
    src.includes("from '../_shared/input_validation.ts'"),
    'race-results-import must import the shared validators',
  );
  assertGuardedBefore(
    src,
    'race-results-import',
    'isValidUuid(listingId)',
    ".eq('id', listingId)",
  );
  assertGuardedBefore(
    src,
    'race-results-import',
    'isValidUuid(matchRunId)',
    ".eq('id', matchRunId)",
  );
});

Deno.test('clip-public-track keeps its uuid gate ahead of the rate-limit spend', async () => {
  // The original of this pattern (audit/edge-functions 2026-05-25) and
  // the reason the ordering rule exists at all.
  const src = await read('clip-public-track');
  assertGuardedBefore(src, 'clip-public-track', 'isValidUuid(runId)', 'ipBucketKey(req)');
});
