#!/usr/bin/env node
// Unit tests for the Edge Function vacuity guard's two halves: the neuterer
// that builds the mutant, and the JUnit reader that scores it.
//
// The neuterer is the half worth pinning hardest. If it silently stops finding
// an exported name, the stub loses the binding, the importing test file dies
// at load, and every one of its test cases is scored a KILL it never earned -
// which is exactly the inversion this whole guard exists to detect, turned on
// the guard itself. The end-to-end run has its own check for that (a baseline
// case absent from the mutant report), and these are the cheap half.

import assert from 'node:assert/strict';
import { readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

import { neuterModule, topLevelExports } from './edge_function_neuter.mjs';
import {
  EXPECTED_SURVIVORS,
  MATERIALISED,
  NEUTERED_ARTIFACTS,
  parseJunit,
  REPO_ROOT,
  sourceModules,
} from './check_edge_function_test_vacuity.mjs';

/// Every declaration form the functions tree actually uses, plus the three
/// constructs whose braces would shift the depth if they were read as code.
const FIXTURE = `
/// A doc comment with a brace { and the word export in it.
import type { Database } from './database.ts';

const RE = /^\\{[a-z]{2}\\}$/;
const TPL = \`a \${'b'} { c\`;
const S = 'a } b';

export function plain(a: number): string { return String(a); }
export async function later(): Promise<void> { const inner = { export: 1 }; }
export class Boom extends Error {}
export const LIMIT = 10;
export let mutable = 1;
export type Alias = string;
export interface Shape { a: number }
export type { Database };
export { plain as renamed };
export default Boom;

function notExported() {
  const nested = { a: 1 };
  return nested;
}
`;

test('topLevelExports reads every declaration form the tree uses', () => {
  const found = topLevelExports(FIXTURE);
  assert.deepEqual(
    found.map((e) => `${e.kind}:${e.name}`).sort(),
    [
      'async function:later',
      'class:Boom',
      'default:default',
      'function:plain',
      'type:Alias',
      'type:Database',
      'type:Shape',
      'value:LIMIT',
      'value:mutable',
      'value:renamed',
    ],
  );
});

test('a brace inside a regex, a template or a string does not shift the depth', () => {
  // Each of these precedes every export in the fixture, so an unbalanced read
  // of any one of them would swallow the whole list.
  for (const construct of ['const RE = /^\\{[a-z]{2}\\}$/;', 'const TPL', "const S = 'a } b';"]) {
    assert.ok(FIXTURE.includes(construct), `fixture no longer carries ${construct}`);
  }
  assert.equal(topLevelExports(FIXTURE).length, 10);
});

test('an export nested inside a function body is not a top-level export', () => {
  const found = topLevelExports(FIXTURE).map((e) => e.name);
  assert.ok(!found.includes('1'), 'the object key `export: 1` was read as a declaration');
  assert.ok(!found.includes('notExported'));
});

test('the same name exported as a type and as a value is stubbed as the value', () => {
  const found = topLevelExports('export interface Thing { a: number }\nexport const Thing = 1;\n');
  assert.deepEqual(found, [{ kind: 'value', name: 'Thing' }]);
});

test('neuterModule preserves each export shape', () => {
  const stub = neuterModule(FIXTURE, 'fixture.ts');
  assert.match(stub, /export function plain\(\) \{ return undefined; \}/);
  assert.match(stub, /export async function later\(\) \{ return undefined; \}/);
  assert.match(stub, /export class Boom extends Error \{\}/);
  assert.match(stub, /export const LIMIT = undefined;/);
  assert.match(stub, /export default undefined;/);
  // Shape preservation is not cosmetic: an async function stubbed as a sync
  // one breaks `await`-shaped tests for a reason they did not earn, and a
  // vacuous test hidden behind such a kill is one this guard never reports.
  assert.ok(!/export function later/.test(stub));
});

test('the neutered twin of every real module exports exactly the names the original did', () => {
  // The operator's validity condition. A stub short of one name makes its
  // importers die at load, and a dead import scores every test in the file as
  // a kill nobody proved.
  for (const rel of sourceModules()) {
    const src = readFileSync(join(REPO_ROOT, rel), 'utf8');
    const before = topLevelExports(src).map((e) => e.name).sort();
    const after = topLevelExports(neuterModule(src, rel)).map((e) => e.name).sort();
    assert.deepEqual(after, before, `${rel}: the stub lost or invented an export`);
  }
});

test('parseJunit separates a pass, a failure and a skip', () => {
  const xml = `<?xml version="1.0"?>
<testsuites>
  <testsuite name="./a.test.ts">
    <testcase name="green &amp; fine" classname="./a.test.ts" line="3" col="6">
    </testcase>
    <testcase name="red" classname="./a.test.ts" line="9" col="6">
      <failure message="boom">stack</failure>
    </testcase>
    <testcase name="ignored" classname="./a.test.ts" line="14" col="6">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>`;
  const out = parseJunit(xml);
  assert.equal(out.size, 2, 'a skipped case is neither a pass nor a failure and must not be scored');
  assert.equal(out.get('./a.test.ts::green & fine')?.passed, true);
  assert.equal(out.get('./a.test.ts::green & fine')?.line, '3');
  assert.equal(out.get('./a.test.ts::red')?.passed, false);
});

test('every path the mirror materialises exists', () => {
  for (const rel of MATERIALISED) statSync(join(REPO_ROOT, rel));
});

test('every neutered artifact is named with a reason and still exists', () => {
  for (const a of NEUTERED_ARTIFACTS) {
    assert.ok(a.reason.trim(), `${a.path} carries no reason`);
    statSync(join(REPO_ROOT, a.path));
  }
});

test('every expected survivor names a reason and a file that exists', () => {
  for (const e of EXPECTED_SURVIVORS) {
    assert.ok(e.reason.trim(), `${e.file} :: ${e.name} carries no reason`);
    statSync(join(REPO_ROOT, 'apps', 'backend', e.file.replace(/^\.\//, '')));
  }
});
