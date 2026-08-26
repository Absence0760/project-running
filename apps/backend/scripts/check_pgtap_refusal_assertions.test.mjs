import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFINER_NEUTRALISERS,
  UNREGISTERED_DEFINER_RELATIONS,
  mine,
} from './pgtap_definer_neutralisers.mjs';
import {
  EXPECTED_SURVIVORS,
  REFUSAL_VOCABULARY,
  TESTS_DIR,
  buildMutant,
  definerSpan,
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

test('refusalAssertions selects zero-or-empty claims over any relation, base table or not', () => {
  const sql = [
    'begin;',
    "select is_empty($$ select id from route_markers where id = 'x' $$, 'a stranger cannot read the marker');",
    "select is((select count(*)::int from notifications where user_id = 'y'), 0, 'a plain member is NOT notified');",
    "select is((select count(*)::int from route_markers where id = 'x'), 1, 'the marker survives');",
    "select is_empty($$ select id from public_runs where id = 'x' $$, 'a stranger cannot read the run');",
    "select is_empty($$ select id from public_routes where id = 'x' $$, 'a stranger cannot read the route');",
    'rollback;',
  ].join('\n');
  const relations = new Map([
    ['route_markers', 'base'],
    ['notifications', 'base'],
    ['public_runs', 'definer'],
    ['public_routes', 'definer'],
  ]);
  const found = refusalAssertions(sql, relations);
  assert.deepEqual(
    found.map((f) => f.description),
    [
      'a stranger cannot read the marker',
      'a stranger cannot read the run',
      'a stranger cannot read the route',
    ],
  );
  // public_routes has a registered replacement and public_runs does not, so
  // one is measured under the second operator and the other is not measured at
  // all — never quietly scored under an operator that cannot reach it.
  assert.deepEqual(found[0].neutralise, []);
  assert.deepEqual(found[0].unmeasurable, []);
  assert.deepEqual(found[1].neutralise, []);
  assert.deepEqual(found[1].unmeasurable, ['public_runs']);
  assert.deepEqual(found[2].neutralise, ['public_routes']);
  assert.deepEqual(found[2].unmeasurable, []);
});

test('buildMutant reaches for the permissive replacement only where one is registered', () => {
  const sql = [
    'begin;',
    'select plan(2);',
    "select is_empty($$ select id from t $$, 'a stranger cannot read t');",
    "select is_empty($$ select id from public_routes $$, 'a stranger cannot read the route');",
    'rollback;',
  ].join('\n');
  const calls = findCalls(sql, 'is_empty');
  const mutant = buildMutant(sql, [
    { ...calls[0], neutralise: [] },
    { ...calls[1], neutralise: ['public_routes'] },
  ]);
  assert.equal(mutant.match(/^savepoint pgtap_guard_definer;$/gm).length, 1);
  assert.equal(mutant.match(/create or replace view public\.public_routes/g).length, 1);
  const savepointAt = mutant.search(/^savepoint pgtap_guard_definer;$/m);
  const replaceAt = mutant.indexOf('create or replace view public.public_routes');
  const assertAt = mutant.indexOf('from public_routes $$');
  const rollbackAt = mutant.indexOf('rollback to savepoint pgtap_guard_definer;');
  assert.ok(savepointAt < replaceAt && replaceAt < assertAt && assertAt < rollbackAt);
});

test('definerSpan refuses a relation it has no replacement for rather than emitting an inert span', () => {
  assert.throws(
    () => definerSpan("select is_empty($$ select 1 $$, 'd');", ['not_a_registered_relation']),
    /no permissive replacement registered/,
  );
});

test('every permissive replacement redefines the relation it is registered under', () => {
  for (const [name, entry] of DEFINER_NEUTRALISERS) {
    assert.match(
      entry.sql,
      new RegExp(`create or replace (view|function) public\\.${name}\\b`),
      `${name}'s replacement does not redefine ${name}`,
    );
    assert.ok(entry.why.length > 0, `${name} does not say which access control it drops`);
    assert.ok(
      entry.witness?.setup?.length > 0 && entry.witness?.probe?.length > 0,
      `${name} has no witness, so nothing proves its replacement is not inert`,
    );
  }
});

test('every permissive replacement is scoped to the rows the transaction wrote', () => {
  for (const [name, entry] of DEFINER_NEUTRALISERS) {
    assert.ok(
      typeof entry.subject === 'string' && entry.subject.length > 0,
      `${name} does not name the relation its revealed rows come from, so nothing says which alias the transaction-local scope belongs on`,
    );
    const alias = entry.subject.split(/\s+/)[1];
    assert.ok(
      alias && /^[a-z_][a-z0-9_]*$/.test(alias),
      `${name}'s subject "${entry.subject}" does not read as "<table> <alias>"`,
    );
    assert.ok(
      entry.sql.includes(mine(alias)),
      `${name} declares its subject as ${entry.subject} but its replacement does not carry ${mine(alias)}. ` +
        'An unscoped replacement reveals every row in the table, so it kills a refusal whose fixture was never filed.',
    );
  }
});

test('every unreplaced definer relation still names an assertion in the suite', () => {
  const descriptions = new Set();
  for (const file of readdirSync(TESTS_DIR).filter((f) => f.endsWith('.sql'))) {
    const text = readFileSync(join(TESTS_DIR, file), 'utf8');
    for (const kind of ['is_empty', 'is', 'results_eq']) {
      for (const call of findCalls(text, kind)) {
        const description = literalOf(call.argv.at(-1) ?? '');
        if (description !== null) descriptions.add(description);
      }
    }
  }
  for (const entry of UNREGISTERED_DEFINER_RELATIONS) {
    assert.ok(entry.reason.length > 0, `${entry.relation} is left unreplaced with no reason`);
    assert.ok(
      descriptions.has(entry.assertion),
      `UNREGISTERED_DEFINER_RELATIONS names "${entry.assertion}" for ${entry.relation}, and no assertion in the suite carries that description any more`,
    );
    assert.ok(
      !DEFINER_NEUTRALISERS.has(entry.relation),
      `${entry.relation} is declared unreplaced AND has a permissive replacement — one of the two is wrong`,
    );
  }
});

test('no permissive replacement outlives the assertions it exists for', () => {
  const read = new Set();
  for (const file of readdirSync(TESTS_DIR).filter((f) => f.endsWith('.sql'))) {
    const text = readFileSync(join(TESTS_DIR, file), 'utf8');
    for (const kind of ['is_empty', 'is', 'results_eq']) {
      for (const call of findCalls(text, kind)) {
        const sql = literalOf(call.argv[0] ?? '') ?? call.argv[0] ?? '';
        for (const relation of relationsIn(sql)) read.add(relation);
      }
    }
  }
  const stale = [...DEFINER_NEUTRALISERS.keys()].filter((name) => !read.has(name));
  assert.deepEqual(
    stale,
    [],
    'these relations have a permissive replacement but no assertion reads them any more: delete the entry rather than carrying a copy of a definition nothing checks',
  );
});

test('an explicit refusal marker selects an assertion whose own wording cannot', () => {
  const sql = [
    'begin;',
    "select is((select count(*)::int from t where kind = 'walk'), 0, 'the run filter excludes a walk');",
    '-- refusal: the under-18 floor is access control, not a search filter',
    "select is((select count(*)::int from t where id = 'x'), 0, 'the minor is excluded from search');",
    'rollback;',
  ].join('\n');
  const found = refusalAssertions(sql, new Map([['t', 'base']]));
  assert.deepEqual(
    found.map((f) => f.description),
    ['the minor is excluded from search'],
  );
});

test('a refusal marker reaches only the assertion it sits above', () => {
  const sql = [
    'begin;',
    '-- refusal: this one',
    "select is_empty($$ select id from t $$, 'the first claim');",
    "select is_empty($$ select id from t $$, 'the second claim');",
    'rollback;',
  ].join('\n');
  const found = refusalAssertions(sql, new Map([['t', 'base']]));
  assert.deepEqual(
    found.map((f) => f.description),
    ['the first claim'],
  );
});

test('every refusal marker in the suite sits above an assertion the guard then selects', () => {
  for (const file of readdirSync(TESTS_DIR).filter((f) => f.endsWith('.sql'))) {
    const text = readFileSync(join(TESTS_DIR, file), 'utf8');
    const markers = [...text.matchAll(/--[ \t]*refusal:[^\n]*/g)];
    if (markers.length === 0) continue;
    // Every relation is claimed to be a base table so the selection under test
    // is the marker's, not the catalogue's.
    const relations = new Map(
      [...text.matchAll(/\b(?:from|join)\s+(?:only\s+)?([a-z_][a-z0-9_]*)/gi)].map((m) => [
        m[1].toLowerCase(),
        'base',
      ]),
    );
    const selected = refusalAssertions(text, relations).length;
    const vocabularyOnly = refusalAssertions(
      text.replaceAll(/--[ \t]*refusal:/g, '-- (was refusal)'),
      relations,
    ).length;
    assert.equal(
      selected - vocabularyOnly,
      markers.length,
      `${file}: ${markers.length} refusal marker(s) but only ${selected - vocabularyOnly} added assertion(s) to the population. A marker that sits above a non-assertion, or above one the vocabulary already selects, says nothing and should be removed.`,
    );
  }
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
