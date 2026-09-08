// Unit tests for scripts/check_retention_cron_register.mjs.
//
// The guard's claim is that each of the four drifts decisions § 1507 records
// fails it, so each is a case below: a job unscheduled under a row that still
// advertises it, a live job in neither the table nor the exclusion list, an
// exclusion that outlived its job, and a stated schedule that is not the
// scheduled one.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	EXCLUDED_JOBS,
	REGISTER,
	ROOT,
	backtickedJobNames,
	check,
	cronFields,
	describeCron,
	firstJobName,
	liveCronState,
	migrationVersion,
	parseRegister,
	readCronOps,
	scheduleDisagreement,
	statesCount,
} from './check_retention_cron_register.mjs';

test('migrationVersion orders a short version before the long one sharing its prefix', () => {
	assert.equal(migrationVersion('20270708_001_x.sql'), '20270708');
	assert.equal(migrationVersion('20270708000010_y.sql'), '20270708000010');
	assert.ok(migrationVersion('20270708_001_x.sql') < migrationVersion('20270708000010_y.sql'));
});

test('liveCronState takes the last operation per name, in either direction', () => {
	const state = liveCronState([
		{ file: 'a.sql', op: 'schedule', name: 'j', expr: '0 * * * *' },
		{ file: 'b.sql', op: 'unschedule', name: 'j' },
		{ file: 'c.sql', op: 'unschedule', name: 'k' },
		{ file: 'd.sql', op: 'schedule', name: 'k', expr: '5 * * * *' },
	]);
	assert.equal(state.get('j')?.live, false);
	assert.equal(state.get('k')?.live, true);
	assert.equal(state.get('k')?.expr, '5 * * * *');
});

test('cronFields accepts five fields and refuses anything else', () => {
	assert.deepEqual(cronFields('17 3 * * *'), ['17', '3', '*', '*', '*']);
	assert.equal(cronFields('17 3 * *'), null);
});

test('describeCron puts the three shapes it knows into words and refuses the rest', () => {
	assert.deepEqual(describeCron(['*/15', '*', '*', '*', '*']), { kind: 'minutes', marker: '15' });
	assert.deepEqual(describeCron(['17', '*', '*', '*', '*']), { kind: 'hourly', marker: 'hourly' });
	assert.deepEqual(describeCron(['13', '4', '*', '*', '*']), { kind: 'daily', marker: '04:13' });
	assert.equal(describeCron(['0', '8', '*', '*', '1']), null);
});

test('scheduleDisagreement accepts the register wordings the document actually uses', () => {
	assert.equal(scheduleDisagreement('every 15 min (`*/15`)', '*/15 * * * *'), null);
	assert.equal(scheduleDisagreement('hourly (`17 * * * *`)', '17 * * * *'), null);
	assert.equal(scheduleDisagreement('hourly', '0 * * * *'), null);
	assert.equal(scheduleDisagreement('04:13 UTC daily', '13 4 * * *'), null);
});

test('scheduleDisagreement rejects a clock time that is not the scheduled one', () => {
	const why = scheduleDisagreement('03:19 UTC daily', '17 3 * * *');
	assert.ok(why !== null && why.includes('03:17'));
});

test('scheduleDisagreement rejects an abbreviation that drops a non-wildcard field', () => {
	const why = scheduleDisagreement('every 15 min (`*/15`)', '*/15 4 * * *');
	assert.ok(why !== null && why.includes('may only drop fields'));
});

test('scheduleDisagreement rejects a backticked expression that is simply different', () => {
	const why = scheduleDisagreement('hourly (`17 * * * *`)', '19 * * * *');
	assert.ok(why !== null && why.includes('19 * * * *'));
});

test('a shape the guard cannot describe must state its own expression', () => {
	assert.ok(scheduleDisagreement('weekly on Mondays', '0 8 * * 1') !== null);
	assert.equal(scheduleDisagreement('weekly on Mondays (`0 8 * * 1`)', '0 8 * * 1'), null);
});

test('statesCount reads a count written as digits or as an English word', () => {
	assert.ok(statesCount('Fourteen jobs are live', 14));
	assert.ok(statesCount('14 jobs are live', 14));
	assert.ok(!statesCount('Thirteen jobs are live', 14));
});

test('job names are read out of backticks and non-job tokens are ignored', () => {
	assert.equal(firstJobName('| `purge-stale-jobs` (`purge_stale_jobs()`) '), 'purge-stale-jobs');
	assert.equal(firstJobName('| `20270530_001` '), null);
	assert.deepEqual(backtickedJobNames('`a-b` and `c_d` and `a-b` and `20270530_001`'), ['a-b']);
});

const ROWS = [
	'| `purge-stale-widgets` | 03:17 UTC daily | widgets | `a.sql` |',
	'| `purge-stale-doohickeys` | hourly | doohickeys | `b.sql` |',
	'| `cleanup-stale-gadgets` | **NOT SCHEDULED** — kept as break-glass | gadgets | `c.sql` |',
].join('\n');

const PROSE =
	'Two `cron.schedule`d retention jobs are live. The other one live schedule is not a ' +
	'retention job and is excluded: `enqueue-doodads`. (`cleanup-stale-gadgets` is deliberately ' +
	'unscheduled and is listed so nobody re-derives it as missing.)';

const EXCLUDED = [{ name: 'enqueue-doodads', reason: 'Enqueues; deletes nothing.' }];

/** @param {{ rows?: string, prose?: string }} parts */
function registerDoc(parts) {
	return [
		'# Data retention policy',
		'',
		'## Auto-deletion / purge jobs',
		'',
		'| Job | Schedule | What it deletes | Migration that defines it |',
		'|---|---|---|---|',
		parts.rows ?? ROWS,
		'',
		parts.prose ?? PROSE,
		'',
		'## Backups',
		'',
	].join('\n');
}

/** @param {Array<[string, boolean, string]>} entries */
function stateOf(entries) {
	return new Map(entries.map(([name, live, expr]) => [name, { live, expr, file: 'x.sql' }]));
}

const CLEAN = /** @type {Array<[string, boolean, string]>} */ ([
	['purge-stale-widgets', true, '17 3 * * *'],
	['purge-stale-doohickeys', true, '0 * * * *'],
	['cleanup-stale-gadgets', false, ''],
	['enqueue-doodads', true, '0 * * * *'],
]);

test('a register that agrees with the migrations reports no error', () => {
	const { errors } = check({
		state: stateOf(CLEAN),
		register: parseRegister(registerDoc({})),
		excluded: EXCLUDED,
	});
	assert.deepEqual(errors, []);
});

test('a live job in neither the table nor the exclusion list fails', () => {
	const { errors } = check({
		state: stateOf([...CLEAN, ['purge-stale-sprockets', true, '5 2 * * *']]),
		register: parseRegister(registerDoc({})),
		excluded: EXCLUDED,
	});
	assert.ok(errors.some((e) => e.includes('purge-stale-sprockets') && e.includes('EXCLUDED_JOBS')));
});

test('a row still advertising a job the migrations unscheduled fails', () => {
	const { errors } = check({
		state: stateOf([['purge-stale-widgets', false, ''], ...CLEAN.slice(1)]),
		register: parseRegister(registerDoc({})),
		excluded: EXCLUDED,
	});
	assert.ok(errors.some((e) => e.includes('purge-stale-widgets') && /NOT SCHEDULED/.test(e)));
});

test('a row marked NOT SCHEDULED whose job is live fails too', () => {
	const { errors } = check({
		state: stateOf([...CLEAN.slice(0, 2), ['cleanup-stale-gadgets', true, '0 4 * * *'], CLEAN[3]]),
		register: parseRegister(registerDoc({})),
		excluded: EXCLUDED,
	});
	assert.ok(errors.some((e) => e.includes('cleanup-stale-gadgets') && e.includes('leaves it live')));
});

test('an exclusion that outlived its job fails', () => {
	const { errors } = check({
		state: stateOf([...CLEAN.slice(0, 3), ['enqueue-doodads', false, '']]),
		register: parseRegister(registerDoc({})),
		excluded: EXCLUDED,
	});
	assert.ok(errors.some((e) => e.includes('enqueue-doodads') && e.includes('drop the exclusion')));
});

test('a job claimed as both a retention row and an exclusion fails', () => {
	const { errors } = check({
		state: stateOf(CLEAN),
		register: parseRegister(registerDoc({})),
		excluded: [...EXCLUDED, { name: 'purge-stale-widgets', reason: 'claimed twice' }],
	});
	assert.ok(errors.some((e) => e.includes('either a retention job or it is not')));
});

test('a stated schedule that is not the scheduled one fails through check', () => {
	const { errors } = check({
		state: stateOf([['purge-stale-widgets', true, '19 3 * * *'], ...CLEAN.slice(1)]),
		register: parseRegister(registerDoc({})),
		excluded: EXCLUDED,
	});
	assert.ok(errors.some((e) => e.includes('purge-stale-widgets') && e.includes('03:19')));
});

test('the closing paragraph must name every excluded schedule', () => {
	const { errors } = check({
		state: stateOf(CLEAN),
		register: parseRegister(
			registerDoc({ prose: 'Two retention jobs are live; the other one is excluded.' }),
		),
		excluded: EXCLUDED,
	});
	assert.ok(errors.some((e) => e.includes('does not name the excluded schedule')));
});

test('the closing paragraph may not name a job the migrations never heard of', () => {
	const { errors } = check({
		state: stateOf(CLEAN),
		register: parseRegister(registerDoc({ prose: `${PROSE} (\`refresh-mv-nothing\` is gone.)` })),
		excluded: EXCLUDED,
	});
	assert.ok(errors.some((e) => e.includes('refresh-mv-nothing')));
});

test('a stated live count that is not the derived one fails', () => {
	const { errors } = check({
		state: stateOf(CLEAN),
		register: parseRegister(registerDoc({ prose: PROSE.replace('Two', 'Seven') })),
		excluded: EXCLUDED,
	});
	assert.ok(errors.some((e) => e.includes('2 retention jobs are live')));
});

test('the shipped register agrees with the shipped migrations', () => {
	const state = liveCronState(readCronOps(ROOT));
	const register = parseRegister(readFileSync(join(ROOT, REGISTER), 'utf-8'));
	const { errors } = check({ state, register, excluded: EXCLUDED_JOBS });
	assert.deepEqual(errors, []);
});
