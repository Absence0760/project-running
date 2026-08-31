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
  GATEWAY_STATUSES,
  MUTATIONS,
  phantomKills,
  satisfies,
  statusOf,
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
    expect: { status: 200 },
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

test('every mutation declares the answer its mutant settles on', () => {
  for (const m of MUTATIONS) {
    assert.ok(Number.isInteger(m.expect.status), `${m.id} declares no expected status`);
    // A bare gateway status is what the runtime answers WHILE RESTARTING, so a
    // round waiting for one cannot tell the mutant from the reload window.
    if (GATEWAY_STATUSES.has(m.expect.status)) {
      assert.ok(m.expect.contains, `${m.id} expects ${m.expect.status} with no discriminating body`);
    }
  }
});

test('no mutation can be satisfied by a restarting runtime', () => {
  // The CI failure this pins: the wait used to accept any answer that merely
  // DIFFERED from the pre-mutation one, so two consecutive gateway 503s during
  // the `functions serve` restart let the round run against a host that was
  // serving nothing. Every case then failed on the wrong answer - scoring the
  // kills as killed and the SPARES as moved, which is exactly what came back
  // from run 33421025889.
  const restarting = [
    '503 upstream connect error',
    '502 Bad Gateway',
    '504 Gateway Timeout',
    'ERR error sending request for url (http://127.0.0.1:54321/functions/v1/x)',
    'ERR connection closed before message completed',
  ];
  for (const m of MUTATIONS) {
    for (const fp of restarting) {
      assert.equal(
        satisfies(fp, m.expect),
        false,
        `${m.id} would accept a restarting runtime's ${JSON.stringify(fp)} as its mutant`,
      );
    }
  }
});

test('validateMutations rejects a mutation with no expected answer, or an unusable one', () => {
  const noExpect = mut();
  // @ts-expect-error - deliberately malformed, which is what the guard is for
  delete noExpect.expect;
  assert.match(validateMutations([noExpect], () => 'GATE')[0], /no HTTP status/);
  assert.match(
    validateMutations([mut({ expect: { status: 503 } })], () => 'GATE')[0],
    /gateway status/,
  );
  assert.deepEqual(
    validateMutations([mut({ expect: { status: 503, contains: 'smtp_not_configured' } })], () => 'GATE'),
    [],
  );
  assert.match(validateMutations([mut({ expect: { status: 200, contains: '' } })], () => 'GATE')[0], /empty/);
});

test('statusOf reads the code, and a transport failure is not a status', () => {
  assert.equal(statusOf('418 {"a":1}'), 418);
  assert.equal(statusOf('ERR connection reset'), -1);
  assert.equal(statusOf(''), -1);
});

test('satisfies needs the status, and the body when one is declared', () => {
  assert.equal(satisfies('418 body', { status: 418 }), true);
  assert.equal(satisfies('503 body', { status: 418 }), false);
  assert.equal(satisfies('ERR reset', { status: 418 }), false);
  assert.equal(satisfies('503 {"error":"smtp_not_configured"}', { status: 503, contains: 'smtp_not_configured' }), true);
  // A kong gateway 503 during the reload carries no such body, which is the
  // whole reason the discriminator is required at that status.
  assert.equal(satisfies('503 upstream unavailable', { status: 503, contains: 'smtp_not_configured' }), false);
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
