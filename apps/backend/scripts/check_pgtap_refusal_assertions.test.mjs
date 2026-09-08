import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFINER_NEUTRALISERS,
  TRANSACTION_LOCAL,
  TRANSACTION_LOCAL_SQL,
  UNREGISTERED_DEFINER_RELATIONS,
  mine,
} from './pgtap_definer_neutralisers.mjs';
import {
  CONDITIONALLY_STAMPED_ASSERTIONS,
  EXPECTED_SURVIVORS,
  FILTERED_RPC_ARGUMENTS,
  STAMPED_VALUE_ASSERTIONS,
  assertionDescriptions,
  assignedColumns,
  conditionallyStampedColumns,
  descriptionOf,
  parameterLandings,
  readMigrations,
  rpcArgumentLandings,
  signatureParameters,
  stampedThroughRpc,
  writerFunctions,
  stampedColumns,
  stampedPairCount,
  stampedValueWrites,
  tgOpCondition,
  PREAMBLE,
  REFUSAL_VOCABULARY,
  TESTS_DIR,
  WIDEN_GUC,
  buildMutant,
  definerSpan,
  findCalls,
  literalOf,
  parseRelationSecurity,
  parseTap,
  refusalAssertions,
  relationsIn,
  splitArgs,
  statementEnd,
  statementStart,
  throwsPinsItsError,
  verdictFor,
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
  /** @type {import('./check_pgtap_refusal_assertions.mjs').RelationMap} */
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
  assert.equal(mutant.match(/^savepoint pgtap_guard_definer;$/gm)?.length, 1);
  assert.equal(mutant.match(/create or replace view public\.public_routes/g)?.length, 1);
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
    /** @type {import('./check_pgtap_refusal_assertions.mjs').RelationMap} */
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

test('buildMutant arms the widening only around the named assertion', () => {
  const sql = [
    'begin;',
    'select plan(2);',
    "select is_empty($$ select id from t $$, 'a stranger cannot read t');",
    "select ok(true, 'unrelated');",
    'rollback;',
  ].join('\n');
  const call = findCalls(sql, 'is_empty')[0];
  const mutant = buildMutant(sql, [{ ...call }]);
  assert.match(mutant, /create extension if not exists pgtap/);
  const armAt = mutant.indexOf(`set_config('${WIDEN_GUC}','on',true)`);
  const assertAt = mutant.indexOf('is_empty');
  const disarmAt = mutant.indexOf(`set_config('${WIDEN_GUC}','off',true)`);
  const unrelatedAt = mutant.indexOf("ok(true, 'unrelated')");
  assert.ok(armAt < assertAt && assertAt < disarmAt && disarmAt < unrelatedAt);
});

// The counterpart of "every permissive replacement is scoped to the rows the
// transaction wrote", for the operator that has no relation to replace. A role
// change to the BYPASSRLS owner is what this used to be, and it revealed the
// whole table (decisions.md 753) — so the base-table span must carry no role
// change at all, and the policy it arms must carry the transaction-local test.
test('the base-table operator widens row-level security rather than bypassing it', () => {
  const sql = [
    'begin;',
    "select is_empty($$ select id from t $$, 'a stranger cannot read t');",
    'rollback;',
  ].join('\n');
  const call = findCalls(sql, 'is_empty')[0];
  const mutant = buildMutant(sql, [{ ...call }]);
  const span = mutant.slice(
    mutant.indexOf(`set_config('${WIDEN_GUC}','on',true)`),
    mutant.indexOf(`set_config('${WIDEN_GUC}','off',true)`),
  );
  assert.equal(
    /set_config\(\s*'role'/.test(span),
    false,
    'the base-table span changes role, which bypasses RLS outright and leaves the widening policy unconsulted — every row in the table is then revealed, so a kill says a subject exists in the database rather than that the test built one',
  );
  assert.match(PREAMBLE, /create policy pgtap_guard_widen on %s as permissive for select/);
  assert.ok(
    PREAMBLE.includes(`${TRANSACTION_LOCAL}(xmin)`),
    'the widening policy is not scoped to the rows this transaction wrote',
  );
  assert.ok(
    PREAMBLE.includes(TRANSACTION_LOCAL_SQL),
    'the mutant declares the transaction-local test but never defines it',
  );
});

// pgtap's own `lives_ok` / `throws_ok` run their payload in a subtransaction, so
// a fixture filed the idiomatic way carries a subtransaction's xid rather than
// the top-level one. § 751's `xmin = pg_current_xact_id()::xid` reads those as
// foreign, which turns every such assertion into a reported survivor; the
// end-to-end control files its own subject that way so the scope can never
// quietly narrow back to top-level writes only.
test('the transaction-local test is the one that reaches a subtransaction write', () => {
  assert.match(TRANSACTION_LOCAL_SQL, /pg_xact_status\(w\) = 'in progress'/);
  assert.match(TRANSACTION_LOCAL_SQL, /security definer/);
  const guard = readFileSync(
    join(TESTS_DIR, '..', '..', 'scripts', 'check_pgtap_refusal_assertions.mjs'),
    'utf8',
  );
  assert.match(guard, /select lives_ok\(\$\$ update routes set name = 'guard control/);
});

test('parseTap keys results by description so a shifted ordinal cannot mislabel one', () => {
  const tap = parseTap(['1..2', 'ok 1 - alpha', 'not ok 2 - beta', '# Failed test 2'].join('\n'));
  assert.deepEqual(tap.get('alpha'), [true]);
  assert.deepEqual(tap.get('beta'), [false]);
  assert.deepEqual(verdictFor(tap, 'alpha'), { status: 'survived', count: 1 });
  assert.deepEqual(verdictFor(tap, 'beta'), { status: 'killed', count: 1 });
  assert.deepEqual(verdictFor(tap, 'gamma'), { status: 'unreached', count: 0 });
});

// The description is the only handle the TAP stream offers on a call site, so
// a repeated one is a verdict that cannot be attributed. It used to be
// resolved last-writer-wins, wrongly in BOTH directions: `ok` then `not ok`
// scored the surviving — vacuous — assertion as killed, which is the § 741
// inversion pointed at the instrument, and the reverse scored a genuinely
// killed one as a survivor. decisions § 774.
test('two assertions sharing a description are ambiguous, not silently collapsed', () => {
  const desc = 'other user cannot read the row';
  for (const order of [
    [`ok 1 - ${desc}`, `not ok 2 - ${desc}`],
    [`not ok 1 - ${desc}`, `ok 2 - ${desc}`],
  ]) {
    const tap = parseTap(order.join('\n'));
    assert.equal(tap.get(desc)?.length, 2);
    assert.deepEqual(verdictFor(tap, desc), { status: 'ambiguous', count: 2 });
  }
});

test('agreeing duplicates are ambiguous too, because EXPECTED_SURVIVORS keys on the same string', () => {
  const desc = 'nobody else sees it';
  const tap = parseTap([`ok 1 - ${desc}`, `ok 2 - ${desc}`].join('\n'));
  assert.deepEqual(verdictFor(tap, desc), { status: 'ambiguous', count: 2 });
});

// The population the guard actually runs over. A duplicate is a real failure
// once one exists, so the guard is only free of that noise while this holds.
test('no committed pgtap file reuses an assertion description', () => {
  const KINDS = [
    'is_empty', 'is', 'isnt', 'results_eq', 'results_ne', 'ok', 'throws_ok', 'lives_ok',
    'set_eq', 'set_has', 'bag_eq', 'row_eq', 'matches', 'cmp_ok', 'isa_ok',
    'has_table', 'has_column', 'col_is_pk', 'policies_are',
  ];
  let descriptions = 0;
  /** @type {string[]} */
  const duplicates = [];
  const files = readdirSync(TESTS_DIR).filter((f) => f.endsWith('.sql'));
  for (const file of files) {
    const text = readFileSync(join(TESTS_DIR, file), 'utf8');
    /** @type {Map<string, number>} */
    const counts = new Map();
    for (const kind of KINDS) {
      for (const call of findCalls(text, kind)) {
        const description = literalOf(call.argv.at(-1) ?? '');
        if (description === null) continue;
        descriptions += 1;
        counts.set(description, (counts.get(description) ?? 0) + 1);
      }
    }
    for (const [description, n] of counts) {
      if (n > 1) duplicates.push(`${file}: "${description}" × ${n}`);
    }
  }
  assert.ok(descriptions > 1000, `only ${descriptions} descriptions scanned across ${files.length} files`);
  assert.deepEqual(duplicates, []);
});

// The population is admitted by `relations.has(...)`, so the catalogue read is
// the one input whose failure would take the population to zero while the
// guard went on reporting a count — 741's inversion pointed at the instrument.
test('parseRelationSecurity refuses a catalogue read it cannot use rather than measuring nothing', () => {
  const good = parseRelationSecurity(
    ['routes|base', 'public_routes|definer', 'search_user_profiles|invoker', ''].join('\n'),
  );
  assert.equal(good.failure, null);
  assert.equal(good.relations.get('public_routes'), 'definer');

  assert.match(parseRelationSecurity('').failure ?? '', /no relations at all/);
  assert.match(parseRelationSecurity('\n\n').failure ?? '', /no relations at all/);
  assert.match(parseRelationSecurity('routes|table').failure ?? '', /not one of/);
  assert.match(parseRelationSecurity('routes').failure ?? '', /not one of/);
});

test('parseRelationSecurity lets a table outrank a function of the same name', () => {
  const { relations } = parseRelationSecurity(['routes|base', 'routes|definer'].join('\n'));
  assert.equal(relations.get('routes'), 'base');
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

// ── Positives emptied by a correcting BEFORE trigger (decisions 1324) ────────

/** The unconditional / conditional pair for one operation, as arrays. */
/** @param {string} body @param {'insert' | 'update'} op */
const assignedUnder = (body, op) => assignedColumns(body)[op];

test('assignedColumns separates a stamp that always fires from one that may not', () => {
	assert.deepEqual(assignedUnder('begin\n  new.name_key := f(new.name);\n  return new;\nend;', 'insert'), {
		unconditional: ['name_key'],
		conditional: [],
	});
	// The whole distinction: inside an `if`, whether the supplied value survives
	// depends on the fixture, and a caller may be asserting the branch does NOT
	// fire. `enforce_event_capacity` and the privacy-zone clippers are this shape.
	assert.deepEqual(
		assignedUnder('begin\n  if full then\n    new.status := 1;\n  end if;\n  return new;\nend;', 'insert'),
		{ unconditional: [], conditional: ['status'] },
	);
	// A comment naming the shape is not the shape.
	assert.deepEqual(
		assignedUnder('begin\n  -- new.name_key := f(new.name);\n  return new;\nend;', 'insert'),
		{ unconditional: [], conditional: [] },
	);
	// An assignment after the `if` closes is back on every path.
	assert.deepEqual(
		assignedUnder(
			'begin\n  if x then\n    new.a := 1;\n  end if;\n  new.b := 2;\n  return new;\nend;',
			'insert',
		),
		{ unconditional: ['b'], conditional: ['a'] },
	);
});

test('tgOpCondition reads only a condition that decides the operation by itself', () => {
	assert.deepEqual(tgOpCondition("tg_op = 'insert'"), {
		taken: new Set(['insert']),
		skipped: new Set(['update']),
	});
	assert.deepEqual(tgOpCondition("(tg_op <> 'insert')"), {
		taken: new Set(['update']),
		skipped: new Set(['insert']),
	});
	assert.deepEqual(tgOpCondition("tg_op in ('insert', 'update')"), {
		taken: new Set(['insert', 'update']),
		skipped: new Set(),
	});
	// A condition that only MENTIONS tg_op still depends on the row, so it must
	// not be read as deciding the operation — the branch stays fixture-dependent
	// and keeps whatever operations its parent admitted.
	assert.equal(tgOpCondition("tg_op = 'update' and old.status = 'pending'"), null);
	assert.equal(tgOpCondition('new.status is not null'), null);
});

test('a tg_op branch stamps only the operation it names, and its else takes the other', () => {
	// `lock_payment_refund_writes` in miniature: the assignment is unreachable on
	// INSERT, which is what let payment_refund_ledger_test's INSERT be judged
	// against an arm that only runs on UPDATE (decisions 1485).
	const oneArm =
		"begin\n  if tg_op = 'UPDATE' then\n    new.status := old.status;\n  end if;\n  return new;\nend;";
	assert.deepEqual(assignedUnder(oneArm, 'insert'), { unconditional: [], conditional: [] });
	assert.deepEqual(assignedUnder(oneArm, 'update'), { unconditional: ['status'], conditional: [] });

	// `fitness_snapshots_set_day` in miniature: both arms assign, so the column
	// is unconditional under both operations rather than conditional under one.
	const split =
		"begin\n  if tg_op = 'INSERT' then\n    new.day := now();\n  else\n    new.day := old.day;\n  end if;\n  return new;\nend;";
	assert.deepEqual(assignedUnder(split, 'insert'), { unconditional: ['day'], conditional: [] });
	assert.deepEqual(assignedUnder(split, 'update'), { unconditional: ['day'], conditional: [] });
});

test('an earlier return inside a branch makes what follows it skippable', () => {
	// `freeze_user_profile_managed_columns`: the row reaches the table unfrozen
	// whenever the guard returns, so the assignment below cannot be read as one
	// the supplied value never survives.
	const guarded =
		"begin\n  if current_user not in ('anon') then\n    return new;\n  end if;\n  new.shadow_hidden := false;\n  return new;\nend;";
	assert.deepEqual(assignedUnder(guarded, 'insert'), {
		unconditional: [],
		conditional: ['shadow_hidden'],
	});

	// But a branch that assigns the column BEFORE returning leaves every exiting
	// path carrying it, which is `route_markers_set_position`'s null guard. Depth
	// counting called this conditional.
	const bothExits =
		'begin\n  if v is null then\n    new.position_m := null;\n    return new;\n  end if;\n  new.position_m := 1;\n  return new;\nend;';
	assert.deepEqual(assignedUnder(bothExits, 'insert'), {
		unconditional: ['position_m'],
		conditional: [],
	});
});

test('a block form that closes with a bare end closes the frame it opened', () => {
	// An EXPRESSION `case` closes with a bare `end`, not `end case`, so the frame
	// it opened used to stay on the stack and the enclosing `end if` popped IT
	// instead — leaving the `if` open, and everything after it reading as
	// unconditional when it is not (decisions 1538).
	const exprCase =
		'begin\n  if new.a is null then\n    new.b := case when new.x > 0 then 1 else 2 end;\n  end if;\n  new.c := 3;\n  return new;\nend;';
	assert.deepEqual(assignedUnder(exprCase, 'insert'), {
		unconditional: ['c'],
		conditional: ['b'],
	});

	// The unsafe direction the same mis-nesting takes under a `tg_op` split: the
	// else arm's assignment is attributed to the operation the THEN arm names,
	// and the other operation is left reporting nothing at all.
	const split =
		"begin\n  if tg_op = 'INSERT' then\n    new.a := case when new.x is null then 0 else new.x end;\n  else\n    new.b := 1;\n  end if;\n  return new;\nend;";
	assert.deepEqual(assignedUnder(split, 'insert'), { unconditional: ['a'], conditional: [] });
	assert.deepEqual(assignedUnder(split, 'update'), { unconditional: ['b'], conditional: [] });

	// A plpgsql BLOCK closes with a bare `end` too, and unlike a `case` it is not
	// a branch: what it assigns carries out of it, so the sibling assignment
	// after it is inside the `if` and the one after the `if` is not.
	const nested =
		'begin\n  if new.a is null then\n    begin\n      new.b := 1;\n    end;\n    new.c := 2;\n  end if;\n  new.d := 3;\n  return new;\nend;';
	assert.deepEqual(assignedUnder(nested, 'insert'), {
		unconditional: ['d'],
		conditional: ['b', 'c'],
	});

	// An exception handler is a second way out of the block, and the guard cannot
	// read what it leaves assigned, so the block stops carrying its must-set.
	const handled =
		'begin\n  begin\n    new.b := 1;\n  exception when others then null;\n  end;\n  return new;\nend;';
	assert.deepEqual(assignedUnder(handled, 'insert'), {
		unconditional: [],
		conditional: ['b'],
	});
});

test('a case arm that assigns nothing is a path through the case', () => {
	// `when` separates a `case`'s arms the way `elsif` separates an `if`'s. Read
	// as one region, the empty arm inherits the previous arm's assignment and the
	// closing `else` then makes the whole thing look exhaustive.
	const gap =
		"begin\n  case new.kind\n    when 'a' then new.x := 1;\n    when 'b' then null;\n    else new.x := 2;\n  end case;\n  return new;\nend;";
	assert.deepEqual(assignedUnder(gap, 'insert'), { unconditional: [], conditional: ['x'] });

	// Every arm assigning it, with an `else` to make the arms exhaustive, is the
	// case that IS unconditional — so the fix above is not a blanket downgrade.
	const covered =
		"begin\n  case new.kind\n    when 'a' then new.x := 1;\n    else new.x := 2;\n  end case;\n  new.y := 3;\n  return new;\nend;";
	assert.deepEqual(assignedUnder(covered, 'insert'), {
		unconditional: ['x', 'y'],
		conditional: [],
	});

	// The region before the first `when` is the selector expression, not an arm.
	// Counting it as a path makes every `case` unconditional in nothing.
	const noElse =
		"begin\n  case new.kind\n    when 'a' then new.x := 1;\n  end case;\n  return new;\nend;";
	assert.deepEqual(assignedUnder(noElse, 'insert'), { unconditional: [], conditional: ['x'] });
});

test('a block keyword inside a string is payload, not structure', () => {
	// `raise exception 'no end if here'` used to close the enclosing `if`, which
	// promoted every assignment after the message to unconditional. A bare `end`
	// closing a frame makes this far likelier than it was: an error string
	// containing the word "end" is ordinary.
	const message =
		"begin\n  if new.a is null then\n    raise exception 'no end if here';\n    new.b := 1;\n  end if;\n  return new;\nend;";
	assert.deepEqual(assignedUnder(message, 'insert'), { unconditional: [], conditional: ['b'] });

	// But the `tg_op` comparison is read out of the same text, so a string is
	// masked for the token walk and kept verbatim for the condition.
	const tgOp =
		"begin\n  if tg_op = 'INSERT' then\n    new.a := 1;\n  end if;\n  return new;\nend;";
	assert.deepEqual(assignedUnder(tgOp, 'insert'), { unconditional: ['a'], conditional: [] });
	assert.deepEqual(assignedUnder(tgOp, 'update'), { unconditional: [], conditional: [] });
});

test('stampedColumns replays the migrations rather than reading the last one', () => {
	/** @param {string} name @param {string} col */
	const stamp = (name, col) =>
		`create or replace function public.${name}() returns trigger language plpgsql as $x$\n` +
		`begin\n  new.${col} := 1;\n  return new;\nend;\n$x$;`;

	/** @param {{name: string, text: string}[]} migrations */
	const pairs = (migrations) => {
		const out = stampedColumns(migrations);
		return { insert: [...out.insert], update: [...out.update] };
	};

	// The drop-then-create pair every stamping migration opens with is a replace,
	// not a removal.
	assert.deepEqual(
		pairs([
			{
				name: '001.sql',
				text:
					`${stamp('f', 'k')}\ndrop trigger if exists t on public.tbl;\n` +
					'create trigger t before insert or update on public.tbl for each row execute function public.f();',
			},
		]),
		{ insert: [['tbl.k', 't']], update: [['tbl.k', 't']] },
	);

	// The trigger's own event clause binds: a `before insert` trigger cannot
	// stamp an UPDATE however plainly its body assigns (decisions 1485).
	assert.deepEqual(
		pairs([
			{
				name: '001.sql',
				text: `${stamp('f', 'k')}\ncreate trigger t before insert on public.tbl for each row execute function public.f();`,
			},
		]),
		{ insert: [['tbl.k', 't']], update: [] },
	);

	// A trigger dropped in a later migration stops stamping.
	assert.deepEqual(
		pairs([
			{
				name: '001.sql',
				text: `${stamp('f', 'k')}\ncreate trigger t before insert on public.tbl for each row execute function public.f();`,
			},
			{ name: '002.sql', text: 'drop trigger t on public.tbl;' },
		]),
		{ insert: [], update: [] },
	);

	// The body is re-read, so replacing the function moves the column with it.
	assert.deepEqual(
		pairs([
			{
				name: '001.sql',
				text: `${stamp('f', 'k')}\ncreate trigger t before insert on public.tbl for each row execute function public.f();`,
			},
			{ name: '002.sql', text: stamp('f', 'other') },
		]),
		{ insert: [['tbl.other', 't']], update: [] },
	);

	// AFTER triggers cannot correct the row being written — NEW is already
	// stored — so they are not this defect and must not be reported as it.
	assert.deepEqual(
		pairs([
			{
				name: '001.sql',
				text: `${stamp('f', 'k')}\ncreate trigger t after insert on public.tbl for each row execute function public.f();`,
			},
		]),
		{ insert: [], update: [] },
	);
});

test('stampedValueWrites judges each statement against its own operation', () => {
	const both = {
		insert: new Map([['exercises.name_key', 'exercises_stamp_name_key_trigger']]),
		update: new Map([['exercises.name_key', 'exercises_stamp_name_key_trigger']]),
	};
	assert.deepEqual(
		stampedValueWrites('insert into exercises (author_id, name, name_key) values (a, b, c)', both),
		[
			{
				op: 'insert',
				table: 'exercises',
				column: 'name_key',
				trigger: 'exercises_stamp_name_key_trigger',
			},
		],
	);
	assert.deepEqual(stampedValueWrites('update public.exercises set name_key = x where id = 1', both), [
		{
			op: 'update',
			table: 'exercises',
			column: 'name_key',
			trigger: 'exercises_stamp_name_key_trigger',
		},
	]);
	// A write that supplies only columns nothing stamps is not this defect.
	assert.deepEqual(stampedValueWrites('insert into exercises (author_id, name) values (a, b)', both), []);
	// The column belongs to a table, not to the suite: the same name on another
	// table is untouched.
	assert.deepEqual(stampedValueWrites('insert into other (name_key) values (a)', both), []);

	// And the operation binds. `payment_refund_ledger_test`'s INSERT was judged
	// against an arm reachable only from an UPDATE, which is a guard agreeing
	// with a defect rather than measuring one (decisions 1485).
	const updateOnly = {
		insert: new Map(),
		update: new Map([['payment_refunds.status', 'payment_refunds_write_lock']]),
	};
	assert.deepEqual(
		stampedValueWrites("insert into payment_refunds (id, status) values (a, 'failed')", updateOnly),
		[],
	);
	assert.deepEqual(
		stampedValueWrites("update payment_refunds set status = 'failed' where id = a", updateOnly),
		[
			{
				op: 'update',
				table: 'payment_refunds',
				column: 'status',
				trigger: 'payment_refunds_write_lock',
			},
		],
	);
});

test('the stamped-column scan finds a population, so a broken parse cannot read as clean', () => {
	// 510: a scan whose input has moved reports nothing at all. The registry
	// below is what anchors this one — an empty `stamped` makes every entry go
	// stale — but the population is asserted outright too.
	const stamped = stampedColumns(readMigrations());
	assert.ok(
		stampedPairCount(stamped) >= 10,
		`only ${stampedPairCount(stamped)} unconditionally stamped columns found`,
	);
	assert.equal(
		stamped.insert.get('gym_routine_exercises.exercise_key'),
		'gym_routine_exercises_stamp_exercise_key_trigger',
	);
	assert.equal(stamped.insert.get('exercises.name_key'), 'exercises_stamp_name_key_trigger');
	assert.equal(stamped.update.get('gym_sets.exercise_key'), 'gym_sets_stamp_exercise_key_trigger');
	// The operation is read off the trigger, not assumed: `safety_contacts_
	// unconfirmed_on_insert` is armed for INSERT only, so an UPDATE supplying
	// `confirmed_at` reaches nothing that would rewrite it.
	assert.equal(
		stamped.insert.get('safety_contacts.confirmed_at'),
		'safety_contacts_unconfirmed_on_insert',
	);
	assert.equal(stamped.update.get('safety_contacts.confirmed_at'), undefined);
});

test('no pgtap positive supplies a value a BEFORE trigger overwrites, unless registered', () => {
	const stamped = stampedColumns(readMigrations());
	const registered = new Set(STAMPED_VALUE_ASSERTIONS.map((e) => `${e.file} ${e.description}`));
	const matched = new Set();
	const offenders = [];
	for (const file of readdirSync(TESTS_DIR).filter((f) => f.endsWith('.sql'))) {
		const text = readFileSync(join(TESTS_DIR, file), 'utf8');
		for (const call of findCalls(text, 'lives_ok')) {
			const sql = literalOf(call.argv[0]);
			if (sql === null) continue;
			if (stampedValueWrites(sql, stamped).length === 0) continue;
			const key = `${file} ${literalOf(call.argv[1]) ?? ''}`;
			if (registered.has(key)) matched.add(key);
			else offenders.push(`${file}:${call.line}`);
		}
	}
	assert.deepEqual(offenders, []);
	for (const entry of STAMPED_VALUE_ASSERTIONS) {
		assert.ok(
			matched.has(`${entry.file} ${entry.description}`),
			`STAMPED_VALUE_ASSERTIONS entry ${entry.file} / "${entry.description}" is stale`,
		);
		assert.ok(entry.reason.length > 40, `${entry.file} entry needs a real reason`);
	}
});


test('assignedColumns separates a branch assignment from one that always fires', () => {
	const body = `
begin
  new.always := 1;
  if new.status = 'going' then
    new.status := 'waitlisted';
  end if;
  return new;
end;`;
	assert.deepEqual(assignedUnder(body, 'insert'), {
		unconditional: ['always'],
		conditional: ['status'],
	});

	// A column assigned BOTH ways belongs to the stronger population: the
	// top-level assignment always fires, so the branch adds nothing to what the
	// supplied value is worth.
	assert.deepEqual(
		assignedUnder('begin\n  new.k := 1;\n  if x then\n    new.k := 2;\n  end if;\nend;', 'insert'),
		{ unconditional: ['k'], conditional: [] },
	);
});

test('conditionallyStampedColumns subtracts the columns some live trigger always stamps', () => {
	/** @param {string} name @param {string} body */
	const fn = (name, body) =>
		`create or replace function public.${name}() returns trigger language plpgsql as $x$\nbegin\n${body}\n  return new;\nend;\n$x$;`;
	const migrations = [
		{
			name: '001.sql',
			text:
				`${fn('branchy', '  if x then\n    new.k := 1;\n    new.j := 2;\n  end if;')}\n` +
				'create trigger a before insert on public.tbl for each row execute function public.branchy();\n' +
				`${fn('always', '  new.k := 3;')}\n` +
				'create trigger b before insert on public.tbl for each row execute function public.always();',
		},
	];
	// `k` is stamped unconditionally by the second trigger, so whether the
	// supplied value survives is not a fixture question at all; only `j` is.
	const conditional = conditionallyStampedColumns(migrations);
	assert.deepEqual([...conditional.insert], [['tbl.j', 'a']]);
	// Both triggers are armed for INSERT only, so neither reaches an UPDATE.
	assert.deepEqual([...conditional.update], []);
});

test('descriptionOf folds the implicit concatenation SQL applies to adjacent literals', () => {
	assert.equal(descriptionOf("'one'"), 'one');
	assert.equal(descriptionOf("'one '\n  'two'"), 'one two');
	assert.equal(descriptionOf("'it''s '\n  'folded'"), "it's folded");
	assert.equal(descriptionOf('coalesce(a, b)'), null);
	assert.equal(descriptionOf("'a' || 'b'"), null);
});

test('assertionDescriptions reads the last argument of every pgtap assertion form', () => {
	const sql = [
		"select lives_ok($$ insert into t values (1) $$, 'the write lives');",
		"select is((select k from t), 1, 'and stores what it supplied');",
		"select results_eq($$ select k from t $$, $$ values (1) $$, 'read back '\n  'in two literals');",
		"select ok(true, 'plain');",
	].join('\n');
	const found = assertionDescriptions(sql);
	assert.ok(found.has('the write lives'));
	assert.ok(found.has('and stores what it supplied'));
	assert.ok(found.has('read back in two literals'));
	assert.ok(found.has('plain'));
});

test('the conditionally-stamped population is non-empty, so a broken parse cannot read as clean', () => {
	// The same 510 floor the unconditional scan carries. The registry below
	// anchors it - an empty set makes all twelve entries go stale - but the
	// population is asserted outright too, named at the triggers the filing was
	// about.
	const conditional = conditionallyStampedColumns(readMigrations());
	assert.ok(
		stampedPairCount(conditional) >= 10,
		`only ${stampedPairCount(conditional)} conditionally stamped columns found`,
	);
	assert.equal(conditional.insert.get('event_attendees.status'), 'trg_enforce_event_capacity');
	assert.equal(conditional.update.get('event_attendees.status'), 'trg_enforce_event_capacity');
	assert.equal(
		conditional.insert.get('live_run_pings.ele'),
		'live_run_pings_drop_in_zone_before_insert',
	);
	assert.equal(conditional.insert.get('race_pings.coarse'), 'race_pings_drop_in_zone_before_insert');
	// Both clippers are BEFORE INSERT triggers, so neither can rewrite an UPDATE.
	assert.equal(conditional.update.get('live_run_pings.ele'), undefined);
	assert.equal(conditional.update.get('race_pings.coarse'), undefined);
	// The two arms of the refund lock sit inside `if tg_op = 'UPDATE'`, so an
	// INSERT of a `payment_refunds` row supplies nothing the trigger can rewrite.
	assert.equal(conditional.update.get('payment_refunds.status'), 'payment_refunds_write_lock');
	assert.equal(conditional.insert.get('payment_refunds.status'), undefined);
	assert.equal(conditional.insert.get('payment_refunds.failure_reason'), undefined);
});

test('every pgtap positive supplying a conditionally stamped column is registered and read', () => {
	const conditional = conditionallyStampedColumns(readMigrations());
	const registry = new Map(
		CONDITIONALLY_STAMPED_ASSERTIONS.map((e) => [`${e.file} ${e.description}`, e]),
	);
	/** @type {Set<string>} */
	const matched = new Set();
	/** @type {string[]} */
	const offenders = [];
	for (const file of readdirSync(TESTS_DIR).filter((f) => f.endsWith('.sql'))) {
		const text = readFileSync(join(TESTS_DIR, file), 'utf8');
		/** @type {Set<string> | null} */
		let descriptions = null;
		for (const call of findCalls(text, 'lives_ok')) {
			const sql = literalOf(call.argv[0]);
			if (sql === null) continue;
			const writes = stampedValueWrites(sql, conditional);
			if (writes.length === 0) continue;
			const key = `${file} ${call.argv[1] === undefined ? '' : (descriptionOf(call.argv[1]) ?? '')}`;
			const entry = registry.get(key);
			if (entry === undefined) {
				offenders.push(`${file}:${call.line}`);
				continue;
			}
			matched.add(key);
			assert.deepEqual(
				entry.columns,
				[...new Set(writes.map((w) => `${w.table}.${w.column}`))].sort(),
				`${entry.file} / "${entry.description}" names a stale column set`,
			);
			assert.ok(entry.reason.length > 40, `${entry.file} entry needs a real reason`);
			if (entry.readBack === undefined) continue;
			descriptions ??= assertionDescriptions(text);
			assert.ok(
				descriptions.has(entry.readBack),
				`${entry.file} / "${entry.description}" names a read-back no assertion carries: "${entry.readBack}"`,
			);
		}
	}
	assert.deepEqual(offenders, []);
	for (const entry of CONDITIONALLY_STAMPED_ASSERTIONS) {
		assert.ok(
			matched.has(`${entry.file} ${entry.description}`),
			`CONDITIONALLY_STAMPED_ASSERTIONS entry ${entry.file} / "${entry.description}" is stale`,
		);
	}
});

test('signatureParameters names the parameters a call site is resolved against', () => {
	assert.deepEqual(
		signatureParameters("p_event_id uuid,\n  p_bib text default null,\n  p_note text default 'x, y'"),
		['p_event_id', 'p_bib', 'p_note'],
	);
	// A default carrying a comma must not split into two parameters, or every
	// argument after it binds to the wrong name.
	assert.deepEqual(signatureParameters('in a int, out b int, variadic c text[]'), ['a', 'b', 'c']);
	assert.deepEqual(signatureParameters(''), []);
});

test('parameterLandings separates a parameter planted verbatim from one an expression decides', () => {
	const body =
		'begin\n' +
		'  insert into t (a, b, c) values (p_a, case when g then p_b end, 1);\n' +
		'  update t x set d = coalesce(x.d, p_d), e = p_e where x.id = 1;\n' +
		'  return null;\nend;';
	assert.deepEqual(parameterLandings(body, ['p_a', 'p_b', 'p_d', 'p_e']), [
		{ table: 't', column: 'a', param: 'p_a', op: 'insert', verbatim: true },
		{ table: 't', column: 'b', param: 'p_b', op: 'insert', verbatim: false },
		{ table: 't', column: 'd', param: 'p_d', op: 'update', verbatim: false },
		{ table: 't', column: 'e', param: 'p_e', op: 'update', verbatim: true },
	]);

	// A column list and a values list of different lengths is a failed parse,
	// and lining them up anyway would attribute a landing to the wrong column.
	assert.deepEqual(parameterLandings('begin\n  insert into t (a, b) values (p_a);\nend;', ['p_a']), []);
});

test('rpcArgumentLandings resolves an argument to its parameter, positionally and by name', () => {
	const writers = new Map([
		[
			'f',
			{
				params: ['p_one', 'p_two', 'p_three'],
				lands: /** @type {import('./check_pgtap_refusal_assertions.mjs').ParameterLanding[]} */ ([
					{ table: 't', column: 'one', param: 'p_one', op: 'insert', verbatim: true },
					{ table: 't', column: 'three', param: 'p_three', op: 'insert', verbatim: false },
				]),
			},
		],
	]);
	// A parameter left on its default was supplied by nobody, so the column it
	// would have reached is not this assertion's claim.
	assert.deepEqual(rpcArgumentLandings('select f(1, 2)', writers), [
		{ fn: 'f', table: 't', column: 'one', param: 'p_one', op: 'insert', verbatim: true },
	]);
	assert.deepEqual(
		rpcArgumentLandings('select f(1, 2, 3)', writers).map((l) => l.column),
		['one', 'three'],
	);
	assert.deepEqual(
		rpcArgumentLandings('select f(p_three => 3, p_one => 1)', writers).map((l) => l.column),
		['one', 'three'],
	);
	// A comma inside an argument must not shift every later argument onto the
	// wrong parameter.
	assert.deepEqual(
		rpcArgumentLandings("select f('a, b', 2, 3)", writers).map((l) => l.column),
		['one', 'three'],
	);
	// Another function whose name merely ends the same way is not this one.
	assert.deepEqual(rpcArgumentLandings('select gf(1, 2, 3)', writers), []);
});

test('a verbatim landing carries the trigger scan through the RPC', () => {
	/** @type {import('./check_pgtap_refusal_assertions.mjs').ParameterLanding[]} */
	const landings = [
		{ table: 'exercises', column: 'name_key', param: 'p_key', op: 'insert', verbatim: true },
		{ table: 'exercises', column: 'name_key', param: 'p_key', op: 'update', verbatim: false },
	];
	const stamped = {
		insert: new Map([['exercises.name_key', 'exercises_stamp_name_key_trigger']]),
		update: new Map([['exercises.name_key', 'exercises_stamp_name_key_trigger']]),
	};
	// Only the verbatim one: where an expression already decides the value, the
	// trigger is not what emptied the assertion and the filtered registry is.
	assert.deepEqual(
		stampedThroughRpc(
			landings.map((l) => ({ fn: 'f', ...l })),
			stamped,
		),
		[
			{
				op: 'insert',
				table: 'exercises',
				column: 'name_key',
				trigger: 'exercises_stamp_name_key_trigger',
			},
		],
	);
});

test('the writer-function population is non-empty and names the RPC-only write surfaces', () => {
	// 510 again: a scan whose input has moved reports nothing at all. The two
	// tables whose ONLY write surface is an RPC are asserted by name, because
	// those are the ones the direct INSERT/UPDATE scan can never see.
	const writers = writerFunctions(readMigrations());
	assert.ok(writers.size >= 20, `only ${writers.size} parameter-planting functions found`);
	const crossing = writers.get('upsert_checkpoint_crossing');
	assert.ok(crossing !== undefined, 'upsert_checkpoint_crossing is not read as a writer');
	assert.ok(crossing.params.includes('p_body_weight_kg'));
	const health = crossing.lands.filter((l) => l.column === 'body_weight_kg');
	assert.equal(health.length, 2, 'both arms of the upsert should land body_weight_kg');
	assert.ok(
		health.every((l) => !l.verbatim),
		'the Art 9 gate means no arm plants body_weight_kg verbatim',
	);
	// And the bib does arrive unchanged on the insert arm, so the two answers
	// are distinguished rather than everything reading as filtered.
	assert.ok(
		crossing.lands.some((l) => l.column === 'bib' && l.op === 'insert' && l.verbatim),
		'p_bib should be read as landing verbatim on the insert arm',
	);
});

test('every pgtap positive handing a value to a filtering RPC is registered', () => {
	const writers = writerFunctions(readMigrations());
	const registry = new Map(FILTERED_RPC_ARGUMENTS.map((e) => [`${e.file} ${e.description}`, e]));
	/** @type {Set<string>} */
	const matched = new Set();
	/** @type {string[]} */
	const offenders = [];
	for (const file of readdirSync(TESTS_DIR).filter((f) => f.endsWith('.sql'))) {
		const text = readFileSync(join(TESTS_DIR, file), 'utf8');
		/** @type {Set<string> | null} */
		let descriptions = null;
		for (const call of findCalls(text, 'lives_ok')) {
			const sql = literalOf(call.argv[0]);
			if (sql === null) continue;
			const filtered = [
				...new Set(
					rpcArgumentLandings(sql, writers)
						.filter((l) => !l.verbatim)
						.map((l) => `${l.table}.${l.column}`),
				),
			].sort();
			if (filtered.length === 0) continue;
			const key = `${file} ${call.argv[1] === undefined ? '' : (descriptionOf(call.argv[1]) ?? '')}`;
			const entry = registry.get(key);
			if (entry === undefined) {
				offenders.push(`${file}:${call.line}`);
				continue;
			}
			matched.add(key);
			assert.deepEqual(entry.columns, filtered, `${entry.file} names a stale column set`);
			assert.ok(entry.reason.length > 40, `${entry.file} entry needs a real reason`);
			if (entry.readBack === undefined) continue;
			descriptions ??= assertionDescriptions(text);
			assert.ok(
				descriptions.has(entry.readBack),
				`${entry.file} names a read-back no assertion carries: "${entry.readBack}"`,
			);
		}
	}
	assert.deepEqual(offenders, []);
	for (const entry of FILTERED_RPC_ARGUMENTS) {
		assert.ok(
			matched.has(`${entry.file} ${entry.description}`),
			`FILTERED_RPC_ARGUMENTS entry ${entry.file} / "${entry.description}" is stale`,
		);
	}
});

test('the money path and the two ping positives are read back, not excused by prose', () => {
	// The three sites decisions 1324 named as unsupportable, plus the terminal
	// -status control and the re-asserted seat found beside them. Named
	// individually rather than left to the count, because dropping a read-back
	// and its registry entry in one change would otherwise be silent.
	const byKey = new Map(
		CONDITIONALLY_STAMPED_ASSERTIONS.map((e) => [`${e.file} ${e.description}`, e]),
	);
	for (const [file, description] of [
		['paid_events_test.sql', 'going on a priced event with a matching paid order succeeds'],
		['paid_events_test.sql', 'a partially refunded order still backs a re-asserted going seat'],
		[
			'refund_failed_ledger_test.sql',
			'a partially_refunded order still seats its attendee (20270522_001 stands)',
		],
		[
			'payment_refund_ledger_test.sql',
			'a terminal status can still be replaced by another terminal one',
		],
		['unbounded_numeric_column_bounds_test.sql', 'an ordinary live ping still stores'],
		['unbounded_numeric_column_bounds_test.sql', 'an ordinary race ping still stores'],
	]) {
		const entry = byKey.get(`${file} ${description}`);
		assert.ok(entry !== undefined, `${file} / "${description}" is not registered`);
		assert.ok(
			entry.readBack !== undefined,
			`${file} / "${description}" is excused by prose where a read-back is owed`,
		);
	}
});
