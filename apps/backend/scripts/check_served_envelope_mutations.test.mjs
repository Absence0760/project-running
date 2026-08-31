#!/usr/bin/env node
// Unit tests for the served-tree mutation guard's static half - everything
// that can be checked without a booted `supabase functions serve` host.
//
// The two that matter most are the ones run against the SHIPPED table rather
// than a fixture: an anchor that no longer occurs in the source, and a killed
// case name that no longer occurs in the test file. Both mean the gate the
// entry measures has been renamed or rewritten, and the end-to-end run reports
// them too - but only where a live host exists, which is the one place a
// developer editing the handler is least likely to be looking.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

import {
  BACKEND_DIR,
  escapeForFilter,
  filterFor,
  MUTATIONS,
  phantomKills,
  TEST_FILE,
  unmeasuredCases,
  validateMutations,
} from './check_served_envelope_mutations.mjs';

const FUNCTIONS = join(BACKEND_DIR, 'supabase', 'functions');
/** @param {string} rel */
const readFn = (rel) => readFileSync(join(FUNCTIONS, rel), 'utf8');

/** @type {import('./check_served_envelope_mutations.mjs').Probe} */
const PROBE = { fn: 'refresh-tokens' };

/**
 * @param {Partial<import('./check_served_envelope_mutations.mjs').Mutation>} over
 * @returns {import('./check_served_envelope_mutations.mjs').Mutation}
 */
function mut(over = {}) {
  return {
    id: 'm',
    file: 'a.ts',
    from: 'GATE',
    to: 'false',
    probe: PROBE,
    kills: ['case one'],
    spares: [],
    reason: 'because',
    ...over,
  };
}

test('the shipped mutation table still anchors on the source it names', () => {
  assert.deepEqual(validateMutations(MUTATIONS, readFn), []);
});

test('every killed and spared case name exists in the test file', () => {
  const src = readFileSync(join(BACKEND_DIR, TEST_FILE), 'utf8');
  // A Deno.test name is written as one or more adjacent string literals, so
  // the file never contains the joined name. Match the halves instead: a name
  // this guard invented outright fails on its first fragment.
  for (const m of MUTATIONS) {
    for (const name of [...m.kills, ...m.spares]) {
      const head = name.slice(0, 40);
      assert.ok(
        src.includes(head),
        `${m.id} names a case the test file does not contain: ${JSON.stringify(head)}`,
      );
    }
  }
});

test('every case a mutation names is one of the five self-authenticating functions', () => {
  const fns = new Set([
    'refresh-tokens',
    'strava-webhook',
    'revenuecat-webhook',
    'auth-email',
    'stripe-events-webhook',
  ]);
  for (const m of MUTATIONS) {
    assert.ok(fns.has(m.file.split('/')[0]), `${m.id} mutates ${m.file}, outside the envelope tier`);
    for (const name of m.kills) {
      assert.ok(fns.has(name.split(':')[0]), `${m.id} kills "${name}", which names no such function`);
    }
  }
});

test('validateMutations rejects an anchor that is not unique', () => {
  const errs = validateMutations([mut({ from: 'x' })], () => 'x and x again');
  assert.equal(errs.length, 1);
  assert.match(errs[0], /occurs 2 times/);
});

test('validateMutations rejects an anchor that is absent', () => {
  const errs = validateMutations([mut()], () => 'nothing here');
  assert.match(errs[0], /occurs 0 times/);
});

test('validateMutations rejects a mutation that kills nothing, or argues nothing', () => {
  assert.match(validateMutations([mut({ kills: [] })], () => 'GATE')[0], /no kills/);
  assert.match(validateMutations([mut({ reason: '  ' })], () => 'GATE')[0], /no reason/);
});

test('validateMutations rejects a no-op replacement', () => {
  assert.match(validateMutations([mut({ to: 'GATE' })], () => 'GATE')[0], /with itself/);
});

test('validateMutations rejects a case listed as both a kill and a spare', () => {
  const errs = validateMutations([mut({ spares: ['case one'] })], () => 'GATE');
  assert.match(errs[0], /both a kill and a spare/);
});

test('validateMutations rejects a duplicate id', () => {
  const errs = validateMutations([mut(), mut()], () => 'GATE');
  assert.match(errs[0], /duplicate mutation id/);
});

test('validateMutations checks a beacon in a second file', () => {
  const errs = validateMutations(
    [mut({ beacon: { file: 'b.ts', from: 'BEACON', to: 'x' } })],
    (rel) => (rel === 'a.ts' ? 'GATE' : 'nothing'),
  );
  assert.equal(errs.length, 1);
  assert.match(errs[0], /beacon anchor occurs 0 times in b\.ts/);
});

test('unmeasuredCases names a case no mutation claims', () => {
  assert.deepEqual(unmeasuredCases(['case one', 'case two'], [mut()]), ['case two']);
  assert.deepEqual(unmeasuredCases(['case one'], [mut()]), []);
});

test('phantomKills names a claimed case the baseline never ran', () => {
  assert.deepEqual(phantomKills(['other'], [mut()]), [{ id: 'm', name: 'case one' }]);
});

test('filterFor matches the named cases exactly and nothing else', () => {
  const names = [
    'refresh-tokens: 403 on wrong CRON_SECRET',
    'revenuecat-webhook: 405 on GET (POST-only)',
  ];
  const re = new RegExp(filterFor(names).slice(1, -1));
  for (const n of names) assert.ok(re.test(n), n);
  assert.equal(re.test('refresh-tokens: 403 on wrong CRON_SECRET extra'), false);
  assert.equal(re.test('prefix refresh-tokens: 403 on wrong CRON_SECRET'), false);
});

test('escapeForFilter neutralises every metacharacter a case name carries', () => {
  const raw = 'a.b*c+d?e^f$g{h}i(j)k|l[m]n\\o-p';
  assert.ok(new RegExp(`^${escapeForFilter(raw)}$`).test(raw));
});
