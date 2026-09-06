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
  EXPECTED_SURVIVORS,
  STAMPED_VALUE_ASSERTIONS,
  readMigrations,
  stampedColumns,
  stampedValueWrites,
  unconditionalAssignments,
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

test('unconditionalAssignments separates a stamp that always fires from one that may not', () => {
	assert.deepEqual(
		unconditionalAssignments('begin\n  new.name_key := f(new.name);\n  return new;\nend;'),
		['name_key'],
	);
	// The whole distinction: inside an `if`, whether the supplied value survives
	// depends on the fixture, and a caller may be asserting the branch does NOT
	// fire. `enforce_event_capacity` and the privacy-zone clippers are this shape.
	assert.deepEqual(
		unconditionalAssignments(
			'begin\n  if full then\n    new.status := 1;\n  end if;\n  return new;\nend;',
		),
		[],
	);
	// A comment naming the shape is not the shape.
	assert.deepEqual(
		unconditionalAssignments('begin\n  -- new.name_key := f(new.name);\n  return new;\nend;'),
		[],
	);
	// An assignment after the `if` closes is back at the top level.
	assert.deepEqual(
		unconditionalAssignments(
			'begin\n  if x then\n    new.a := 1;\n  end if;\n  new.b := 2;\n  return new;\nend;',
		),
		['b'],
	);
});

test('stampedColumns replays the migrations rather than reading the last one', () => {
	/** @param {string} name @param {string} col */
	const stamp = (name, col) =>
		`create or replace function public.${name}() returns trigger language plpgsql as $x$\n` +
		`begin\n  new.${col} := 1;\n  return new;\nend;\n$x$;`;

	// The drop-then-create pair every stamping migration opens with is a replace,
	// not a removal.
	assert.deepEqual(
		[
			...stampedColumns([
				{
					name: '001.sql',
					text:
						`${stamp('f', 'k')}\ndrop trigger if exists t on public.tbl;\n` +
						'create trigger t before insert or update on public.tbl for each row execute function public.f();',
				},
			]),
		],
		[['tbl.k', 't']],
	);

	// A trigger dropped in a later migration stops stamping.
	assert.deepEqual(
		[
			...stampedColumns([
				{
					name: '001.sql',
					text: `${stamp('f', 'k')}\ncreate trigger t before insert on public.tbl for each row execute function public.f();`,
				},
				{ name: '002.sql', text: 'drop trigger t on public.tbl;' },
			]),
		],
		[],
	);

	// The body is re-read, so replacing the function moves the column with it.
	assert.deepEqual(
		[
			...stampedColumns([
				{
					name: '001.sql',
					text: `${stamp('f', 'k')}\ncreate trigger t before insert on public.tbl for each row execute function public.f();`,
				},
				{ name: '002.sql', text: stamp('f', 'other') },
			]),
		],
		[['tbl.other', 't']],
	);

	// AFTER triggers cannot correct the row being written — NEW is already
	// stored — so they are not this defect and must not be reported as it.
	assert.deepEqual(
		[
			...stampedColumns([
				{
					name: '001.sql',
					text: `${stamp('f', 'k')}\ncreate trigger t after insert on public.tbl for each row execute function public.f();`,
				},
			]),
		],
		[],
	);
});

test('stampedValueWrites reads the supplied columns off an INSERT and an UPDATE', () => {
	const stamped = new Map([['exercises.name_key', 'exercises_stamp_name_key_trigger']]);
	assert.deepEqual(
		stampedValueWrites('insert into exercises (author_id, name, name_key) values (a, b, c)', stamped),
		[{ table: 'exercises', column: 'name_key', trigger: 'exercises_stamp_name_key_trigger' }],
	);
	assert.deepEqual(stampedValueWrites('update public.exercises set name_key = x where id = 1', stamped), [
		{ table: 'exercises', column: 'name_key', trigger: 'exercises_stamp_name_key_trigger' },
	]);
	// A write that supplies only columns nothing stamps is not this defect.
	assert.deepEqual(stampedValueWrites('insert into exercises (author_id, name) values (a, b)', stamped), []);
	// The column belongs to a table, not to the suite: the same name on another
	// table is untouched.
	assert.deepEqual(stampedValueWrites('insert into other (name_key) values (a)', stamped), []);
});

test('the stamped-column scan finds a population, so a broken parse cannot read as clean', () => {
	// 510: a scan whose input has moved reports nothing at all. The registry
	// below is what anchors this one — an empty `stamped` makes every entry go
	// stale — but the population is asserted outright too.
	const stamped = stampedColumns(readMigrations());
	assert.ok(stamped.size >= 10, `only ${stamped.size} unconditionally stamped columns found`);
	assert.equal(
		stamped.get('gym_routine_exercises.exercise_key'),
		'gym_routine_exercises_stamp_exercise_key_trigger',
	);
	assert.equal(stamped.get('exercises.name_key'), 'exercises_stamp_name_key_trigger');
	assert.equal(stamped.get('gym_sets.exercise_key'), 'gym_sets_stamp_exercise_key_trigger');
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
