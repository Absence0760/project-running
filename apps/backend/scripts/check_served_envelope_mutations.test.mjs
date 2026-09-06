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
  declaredCases,
  escapeForFilter,
  filterFor,
  GATEWAY_STATUSES,
  MUTATIONS,
  phantomKills,
  satisfies,
  staleExemptions,
  statusOf,
  TEST_FILE,
  unmeasuredCases,
  unnamedDeclaredCases,
  UNMEASURED_CASES,
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

// ── the source-side census ────────────────────────────────────────────
// The runtime half enumerates the cases that RAN. That set is strictly
// smaller than the set the file DECLARES, because `parseJunit` drops deno's
// `<skipped/>` entries: a case whose `ignore:` gate is never false in CI is
// missing from `ran`, so `unmeasuredCases` (which filters `ran`) cannot see
// it, and `phantomKills` sees it only if some mutation happens to name it. A
// declared case that never runs and that nothing names asserts nothing and
// reads as green — the shape § 815 closed one layer out. These pin the third
// edge, `declared ⊆ kills`, which makes the three sets one.

const TEST_SRC = readFileSync(join(BACKEND_DIR, TEST_FILE), 'utf8');

test('declaredCases reads every Deno.test the shipped file carries', () => {
  const declared = declaredCases(TEST_SRC);
  // A positive control on the census itself: a parser that quietly returned
  // nothing, or that stopped at the first name written across two literals,
  // would make every assertion below vacuously true.
  assert.equal(declared.length, TEST_SRC.split('Deno.test(').length - 1);
  assert.ok(declared.length >= 26, `only ${declared.length} cases parsed`);
  const names = declared.map((d) => d.name);
  // A single-literal name, a name written across two adjacent literals, a name
  // carrying a literal ` + ` (which splitting on `+` would cut in half), and
  // one carrying an escaped quote.
  assert.ok(names.includes('refresh-tokens: 403 on wrong CRON_SECRET'));
  assert.ok(names.includes('revenuecat-webhook: 401 missing_signature when no x-revenuecat-hmac header'));
  assert.ok(names.includes('revenuecat-webhook: 200 on valid HMAC + fresh anonymous event'));
  assert.ok(
    names.includes(
      "auth-email: a correctly signed signup hook renders in the recipient's locale and " +
        'delivers over SMTP',
    ),
  );
  // Every name deno will report is exactly what a --filter has to match.
  for (const n of names) assert.equal(n.trim(), n, `name carries edge whitespace: ${n}`);
});

test('declaredCases refuses a form it cannot read rather than skipping it', () => {
  assert.throws(
    () => declaredCases("Deno.test('a name', () => {});"),
    /object form/,
    'the positional form must refuse, not parse to nothing',
  );
  assert.throws(() => declaredCases('Deno.test({ ignore: SKIP, name: "x" });'), /not `name:`/);
  assert.throws(() => declaredCases('Deno.test({ name: `a ${x}`, fn: () => {} });'), /string literal/);
});

test('declaredCases records the gate each case is ignored on', () => {
  const src = [
    "Deno.test({ name: 'always', fn: () => {} });",
    "Deno.test({\n  name: 'gated',\n  ignore: SKIP_DB,\n  fn: () => {},\n});",
    "Deno.test({\n  name: 'never',\n  ignore: true,\n  fn: () => {},\n});",
  ].join('\n');
  assert.deepEqual(declaredCases(src), [
    { name: 'always', ignore: '' },
    { name: 'gated', ignore: 'SKIP_DB' },
    { name: 'never', ignore: 'true' },
  ]);
});

test('every case the shipped file declares is measured or declared unmeasured', () => {
  const unnamed = unnamedDeclaredCases(declaredCases(TEST_SRC), MUTATIONS);
  assert.deepEqual(
    unnamed,
    [],
    'these cases are declared in ' +
      TEST_FILE +
      ' and no mutation kills them. A case that never runs is invisible to the runtime half, so ' +
      'it would read as green while asserting nothing: add a mutation that opens the gate it ' +
      'names, or an UNMEASURED_CASES entry saying why one is not owed.',
  );
});

test('no UNMEASURED_CASES entry has stopped describing the file', () => {
  assert.deepEqual(staleExemptions(declaredCases(TEST_SRC), MUTATIONS), []);
  assert.ok(UNMEASURED_CASES.length > 0, 'the exemption list is the thing being staleness-checked');
});

test('the census fires on a declared case nothing measures', () => {
  const declared = [{ name: 'case one', ignore: 'SKIP' }, { name: 'case two', ignore: 'SKIP_DB' }];
  assert.deepEqual(unnamedDeclaredCases(declared, [mut()], []), ['case two']);
  // …and an exemption is the other way to satisfy it.
  assert.deepEqual(
    unnamedDeclaredCases(declared, [mut()], [{ name: 'case two', reason: 'because' }]),
    [],
  );
});

test('staleExemptions catches a gone case, a spent excuse and an empty reason', () => {
  const declared = [{ name: 'case one', ignore: 'SKIP' }, { name: 'case two', ignore: 'true' }];
  assert.deepEqual(
    staleExemptions(declared, [mut()], [{ name: 'case three', reason: 'r' }]),
    [{ name: 'case three', why: 'the test file no longer declares a case of that name' }],
  );
  assert.deepEqual(
    staleExemptions(declared, [mut()], [{ name: 'case one', reason: 'r' }]),
    [{ name: 'case one', why: 'a mutation now measures it, so the exemption is spent' }],
  );
  assert.deepEqual(
    staleExemptions(declared, [mut()], [{ name: 'case two', reason: '  ' }]),
    [{ name: 'case two', why: 'carries no reason, so nothing says why it is not owed one' }],
  );
  assert.deepEqual(staleExemptions(declared, [mut()], [{ name: 'case two', reason: 'r' }]), []);
});
