import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
	planHeadCopyFields,
	planWeekCopyRows,
	planWorkoutCopyRows,
} from './plan_copy';

/// Every column name in one generated table's `Row`. Read from
/// `database.types.ts` rather than restated here, so a migration that adds a
/// column makes the census below fail until the new column is either copied
/// on publish or explicitly excused.
function rowColumns(table: string): string[] {
	const src = readFileSync(
		resolve('src/lib/database.types.ts'),
		'utf-8',
	);
	const start = src.indexOf(`      ${table}: {`);
	assert.ok(start > 0, `${table} is not in database.types.ts`);
	const rowStart = src.indexOf('Row: {', start);
	const rowEnd = src.indexOf('        }', rowStart);
	assert.ok(rowStart > 0 && rowEnd > rowStart, `${table}.Row not parseable`);
	return [...src.slice(rowStart, rowEnd).matchAll(/^\s{10}(\w+)\??:/gm)].map(
		(m) => m[1],
	);
}

const sourcePlan = {
	id: 'plan-1',
	user_id: 'author',
	name: 'Autumn marathon',
	goal_event: 'marathon',
	goal_distance_m: 42195,
	goal_time_seconds: 12600,
	start_date: '2026-01-04',
	end_date: '2026-04-19',
	days_per_week: 5,
	vdot: 52.4,
	current_5k_seconds: 1140,
	status: 'active',
	source: 'generated',
	notes: 'left knee ITB flare — keep Tuesdays easy',
	rules: [{ kind: 'cap_weekly_increase', pct: 10 }],
	is_template: false,
	is_public_template: false,
	club_id: null,
	parent_template_id: null,
	assigned_by_coach_id: null,
	created_at: '2025-12-01T00:00:00Z',
	updated_at: '2025-12-02T00:00:00Z',
} as unknown as Parameters<typeof planHeadCopyFields>[0];

const sourceWeek = {
	id: 'week-1',
	plan_id: 'plan-1',
	week_index: 0,
	phase: 'base',
	target_volume_m: 48000,
	notes: 'ease in',
} as unknown as Parameters<typeof planWeekCopyRows>[0][number];

const sourceWorkout = {
	id: 'wo-1',
	week_id: 'week-1',
	scheduled_date: '2026-01-06',
	kind: 'tempo',
	target_distance_m: 12000,
	target_duration_seconds: 3300,
	target_pace_sec_per_km: 265,
	target_pace_end_sec_per_km: 250,
	target_pace_tolerance_sec: 5,
	pace_zone: 'threshold',
	structure: { reps: 4, on_m: 1600 },
	notes: '4x1600m at threshold',
	completed_at: '2026-01-06T09:12:00Z',
	completed_run_id: 'run-9',
	manually_completed: true,
	skipped_at: null,
	updated_at: '2026-01-06T09:13:00Z',
	updated_by: 'author',
} as unknown as Parameters<typeof planWorkoutCopyRows>[0][number];

test('a published workout keeps every plan-design field the source carried', () => {
	// Reason: the two publishers each held their own copy of this list and the
	// public-library half had fallen behind by two — a published plan lost
	// `target_pace_end_sec_per_km` (the progression target the workout detail
	// page renders) and `pace_zone` (the zone chip), on every workout, with no
	// error anywhere. Assert the VALUES round-trip, not that a source line
	// mentions them.
	const [row] = planWorkoutCopyRows(
		[sourceWorkout],
		new Map([['week-1', 'new-week-1']]),
	);
	assert.equal(row.week_id, 'new-week-1');
	assert.equal(row.target_pace_end_sec_per_km, 250);
	assert.equal(row.pace_zone, 'threshold');
	assert.equal(row.target_pace_sec_per_km, 265);
	assert.equal(row.target_pace_tolerance_sec, 5);
	assert.deepEqual(row.structure, { reps: 4, on_m: 1600 });
	assert.equal(row.notes, '4x1600m at threshold');
	assert.equal(row.kind, 'tempo');
	assert.equal(row.scheduled_date, '2026-01-06');
	assert.equal(row.target_distance_m, 12000);
	assert.equal(row.target_duration_seconds, 3300);
});

test('a published workout starts fresh — no completion state rides along', () => {
	// Reason: a template is a plan somebody else is about to run. Copying
	// `completed_at` / `completed_run_id` / `manually_completed` would hand a
	// cloner a plan that believes their first six weeks are already done, and
	// `completed_run_id` additionally points at the publisher's own run row.
	const [row] = planWorkoutCopyRows(
		[sourceWorkout],
		new Map([['week-1', 'new-week-1']]),
	);
	for (const col of [
		'completed_at',
		'completed_run_id',
		'manually_completed',
		'skipped_at',
		'id',
		'updated_by',
	]) {
		assert.ok(
			!(col in row),
			`${col} must not ride along onto a published template workout`,
		);
	}
});

test('a workout whose week did not make the copy is dropped, not orphaned', () => {
	// Reason: `plan_workouts.week_id` is a NOT NULL FK. A workout whose week is
	// missing from the mapping has nothing honest to write, and inventing a
	// week id would attach it to somebody else's plan.
	const rows = planWorkoutCopyRows(
		[sourceWorkout, { ...sourceWorkout, week_id: 'week-absent' }],
		new Map([['week-1', 'new-week-1']]),
	);
	assert.equal(rows.length, 1);
	assert.equal(rows[0].week_id, 'new-week-1');
});

test('the published plan head keeps source and rules, and never the private fields', () => {
	// Reason: `rules` is what the adaptive re-plan reads; without it a cloned
	// plan cannot be re-planned at all. `vdot` / `current_5k_seconds` / `notes`
	// are the publisher's own — stripped by each caller and by the trigger in
	// 20270508_001 — so this shared helper must not carry them in the first
	// place, or a caller that forgets its explicit null would leak them.
	const head = planHeadCopyFields(sourcePlan);
	assert.deepEqual(head.rules, [{ kind: 'cap_weekly_increase', pct: 10 }]);
	assert.equal(head.source, 'generated');
	assert.equal(head.name, 'Autumn marathon');
	for (const col of ['vdot', 'current_5k_seconds', 'notes']) {
		assert.ok(!(col in head), `planHeadCopyFields must not carry ${col}`);
	}
});

test('a published week keeps its phase, volume and notes under the new plan id', () => {
	const [row] = planWeekCopyRows([sourceWeek], 'new-plan');
	assert.deepEqual(row, {
		plan_id: 'new-plan',
		week_index: 0,
		phase: 'base',
		target_volume_m: 48000,
		notes: 'ease in',
	});
});

// ── Census: a new column must be copied or excused, never silently dropped ──
//
// The requirement is derived from `database.types.ts`, which only changes when
// a migration does — so this cannot be satisfied by editing the thing it
// checks. Each exclusion states why that column has no business on a copy.

test('every plan_workouts column is either copied on publish or excused', () => {
	const excused = new Map([
		['id', 'server-generated on the new row'],
		['week_id', 'remapped to the new week, not copied'],
		['completed_at', 'completion state — a template starts fresh'],
		['completed_run_id', "points at the publisher's own run"],
		['manually_completed', 'completion state — a template starts fresh'],
		['skipped_at', 'completion state — a template starts fresh'],
		['updated_at', 'server-maintained'],
		['updated_by', 'server-maintained'],
	]);
	const [copied] = planWorkoutCopyRows(
		[sourceWorkout],
		new Map([['week-1', 'new-week-1']]),
	);
	const missing = rowColumns('plan_workouts').filter(
		(c) => !(c in copied) && !excused.has(c),
	);
	assert.deepEqual(
		missing,
		[],
		`plan_workouts columns neither copied on publish nor excused: ${missing.join(', ')}`,
	);
});

test('every plan_weeks column is either copied on publish or excused', () => {
	const excused = new Set(['id', 'plan_id']);
	const [copied] = planWeekCopyRows([sourceWeek], 'new-plan');
	const missing = rowColumns('plan_weeks').filter(
		(c) => !(c in copied) && !excused.has(c),
	);
	assert.deepEqual(missing, [], `plan_weeks columns dropped on publish: ${missing.join(', ')}`);
});

test('every training_plans column is either copied on publish or excused', () => {
	const excused = new Map([
		['id', 'server-generated on the new row'],
		['user_id', 'the publisher, stated by each caller'],
		['vdot', "publisher-private fitness proxy — stripped on publish"],
		['current_5k_seconds', "publisher-private fitness proxy — stripped on publish"],
		['notes', "publisher's own free text — stripped on publish"],
		['status', 'a template is always inserted completed'],
		['is_template', 'what makes the row a template'],
		['is_public_template', 'the library-vs-club distinction each caller states'],
		['club_id', 'the library-vs-club distinction each caller states'],
		['parent_template_id', 'a publish has no parent — cloning sets it'],
		['assigned_by_coach_id', 'a coach assignment is not a property of the design'],
		['created_at', 'server-maintained'],
		['updated_at', 'server-maintained'],
	]);
	const copied = planHeadCopyFields(sourcePlan);
	const missing = rowColumns('training_plans').filter(
		(c) => !(c in copied) && !excused.has(c),
	);
	assert.deepEqual(
		missing,
		[],
		`training_plans columns neither copied on publish nor excused: ${missing.join(', ')}`,
	);
});

test('both plan publishers shape their rows through this module', () => {
	// Reason: the defect was two lists, not a wrong list. A publisher that
	// re-inlines its own `plan_workouts` row literal is back where it started,
	// and the census above would not see it — it checks this module, which
	// would still be correct and simply unused.
	const source = readFileSync(resolve('src/lib/core/data.ts'), 'utf-8');
	for (const fn of ['publishPlanToLibrary', 'publishPlanAsTemplate']) {
		const start = source.indexOf(`export async function ${fn}(`);
		assert.ok(start > 0, `${fn} not found — rename it here too.`);
		const body = source.slice(start, source.indexOf('\nexport ', start + 1));
		for (const helper of ['planHeadCopyFields', 'planWeekCopyRows', 'planWorkoutCopyRows']) {
			assert.ok(
				body.includes(`${helper}(`),
				`${fn} must build its rows with ${helper} rather than its own list.`,
			);
		}
		assert.doesNotMatch(
			body,
			/target_pace_sec_per_km:/,
			`${fn} must not restate the workout column list inline.`,
		);
	}
});
