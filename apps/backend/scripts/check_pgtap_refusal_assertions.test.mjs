import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  EXPECTED_SURVIVORS,
  REFUSAL_VOCABULARY,
  TESTS_DIR,
  buildMutant,
  findCalls,
  literalOf,
  parseTap,
  refusalAssertions,
  relationsIn,
  splitArgs,
  statementEnd,
  statementStart,
  throwsPinsItsError,
} from './check_pgtap_refusal_assertions.mjs';

test('findCalls ignores a call name that only appears inside a dollar-quoted body', () => {
  const sql = `select is_empty($$ select 1 from t where note = 'is_empty(x)' $$, 'd');`;
  assert.equal(findCalls(sql, 'is_empty').length, 1);
});

test('splitArgs keeps commas inside dollar quotes, strings and nested parens', () => {
  const args = `$$ select a, b from t $$, 'x, y', coalesce(p, q), 'desc'`;
  assert.deepEqual(splitArgs(args), [
    '$$ select a, b from t $$',
    "'x, y'",
    'coalesce(p, q)',
    "'desc'",
  ]);
});

test('literalOf unwraps both quote forms and refuses an expression', () => {
  assert.equal(literalOf("'a''b'"), "a'b");
  assert.equal(literalOf('$$ body $$'), ' body ');
  assert.equal(literalOf('current_setting($1)'), null);
});

test('throwsPinsItsError accepts a SQLSTATE, a message, or a computed expectation', () => {
  assert.ok(throwsPinsItsError(['q', "'42501'", 'null', "'d'"]));
  assert.ok(throwsPinsItsError(['q', 'null', "'poisoned row'", "'d'"]));
  assert.ok(throwsPinsItsError(['q', "'not authorised to edit plan'", "'d'"]));
  assert.ok(throwsPinsItsError(['q', "'a: ' || current_setting('t.plan')", "'d'"]));
});

test('throwsPinsItsError rejects the shape that passes on any error', () => {
  assert.equal(throwsPinsItsError(['q']), false);
  assert.equal(throwsPinsItsError(['q', 'null', 'null', "'d'"]), false);
  assert.equal(throwsPinsItsError(['q', 'NULL', 'NULL', "'d'"]), false);
});

test('REFUSAL_VOCABULARY separates an access claim from a trigger claim', () => {
  assert.ok(REFUSAL_VOCABULARY.test('anon cannot read coach_messages'));
  assert.ok(REFUSAL_VOCABULARY.test('a stranger cannot SELECT reports on a private route'));
  assert.ok(REFUSAL_VOCABULARY.test('RLS hides another reporter reports'));
  assert.equal(REFUSAL_VOCABULARY.test('a plain member is NOT notified'), false);
  assert.equal(REFUSAL_VOCABULARY.test('deleting the auth user cascade-removes their gear'), false);
});

test('relationsIn finds the base tables a query reads, schema-qualified or not', () => {
  assert.deepEqual(
    [...relationsIn('select 1 from public.jobs j join notifications n on n.id = j.id')].sort(),
    ['jobs', 'notifications'],
  );
});

test('refusalAssertions selects only zero-or-empty claims over a base table', () => {
  const sql = [
    'begin;',
    "select is_empty($$ select id from route_markers where id = 'x' $$, 'a stranger cannot read the marker');",
    "select is((select count(*)::int from notifications where user_id = 'y'), 0, 'a plain member is NOT notified');",
    "select is((select count(*)::int from route_markers where id = 'x'), 1, 'the marker survives');",
    "select is_empty($$ select id from public_runs where id = 'x' $$, 'a stranger cannot read the run');",
    'rollback;',
  ].join('\n');
  const found = refusalAssertions(sql, new Set(['route_markers', 'notifications']));
  assert.deepEqual(
    found.map((f) => f.description),
    ['a stranger cannot read the marker'],
  );
});

test('statementStart and statementEnd bracket the whole assertion statement', () => {
  const sql = "select 1;\n\nselect is_empty($$ select 1; $$, 'd');\nselect 2;";
  const call = findCalls(sql, 'is_empty')[0];
  const span = sql.slice(statementStart(sql, call.offset), statementEnd(sql, call.offset));
  assert.equal(span.trim(), "select is_empty($$ select 1; $$, 'd');");
});

test('buildMutant wraps only the named assertion and restores the role after it', () => {
  const sql = [
    'begin;',
    'select plan(2);',
    "select is_empty($$ select id from t $$, 'a stranger cannot read t');",
    "select ok(true, 'unrelated');",
    'rollback;',
  ].join('\n');
  const call = findCalls(sql, 'is_empty')[0];
  const mutant = buildMutant(sql, [{ ...call, description: 'a stranger cannot read t' }]);
  assert.match(mutant, /create extension if not exists pgtap/);
  const bypassAt = mutant.indexOf("set_config('role','none',true)");
  const assertAt = mutant.indexOf('is_empty');
  const restoreAt = mutant.indexOf("set_config('role', current_setting('pgtap_guard.role')");
  const unrelatedAt = mutant.indexOf("ok(true, 'unrelated')");
  assert.ok(bypassAt < assertAt && assertAt < restoreAt && restoreAt < unrelatedAt);
});

test('parseTap keys results by description so a shifted ordinal cannot mislabel one', () => {
  const tap = parseTap(['1..2', 'ok 1 - alpha', 'not ok 2 - beta', '# Failed test 2'].join('\n'));
  assert.equal(tap.get('alpha'), true);
  assert.equal(tap.get('beta'), false);
});

// The allowlist is only trustworthy while every entry still points at a real
// assertion. The guard itself re-checks that the entry still SURVIVES the
// mutation, which needs a database; this half needs none and catches the
// cheaper rot of a renamed or deleted description.
test('every EXPECTED_SURVIVORS entry still names an assertion that exists', () => {
  for (const entry of EXPECTED_SURVIVORS) {
    const text = readFileSync(join(TESTS_DIR, entry.file), 'utf8');
    assert.ok(
      text.includes(entry.description),
      `${entry.file} no longer contains the assertion "${entry.description}"`,
    );
    assert.ok(entry.reason.length > 40, `${entry.file} entry needs a real reason`);
  }
});

test('no pgtap negative pins neither a SQLSTATE nor a message', () => {
  const offenders = [];
  for (const file of readdirSync(TESTS_DIR).filter((f) => f.endsWith('.sql'))) {
    const text = readFileSync(join(TESTS_DIR, file), 'utf8');
    for (const call of findCalls(text, 'throws_ok')) {
      if (!throwsPinsItsError(call.argv)) offenders.push(`${file}:${call.line}`);
    }
  }
  assert.deepEqual(offenders, []);
});
