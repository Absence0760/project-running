import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import {
	evaluateGoal,
	periodStart,
	periodEnd,
	formatPaceSecPerKm,
	loadGoals,
	saveGoals,
	newGoalId,
	periodLabel,
	type RunGoal,
} from './goals';
import type { Run } from '../types';

// Build a Run with just enough fields for the goal evaluator. The
// evaluator only touches started_at, distance_m, duration_s, and
// metadata.activity_type — the rest is filler.
function run(partial: {
	started_at: string;
	distance_m: number;
	duration_s: number;
	activity_type?: string;
}): Run {
	return {
		id: 'r' + partial.started_at,
		user_id: 'u1',
		started_at: partial.started_at,
		distance_m: partial.distance_m,
		duration_s: partial.duration_s,
		source: 'app',
		track_url: null,
		track: null,
		route_id: null,
		event_id: null,
		external_id: null,
		is_public: null,
		created_at: null,
		updated_at: null,
		metadata: partial.activity_type ? { activity_type: partial.activity_type } : null,
	} as unknown as Run;
}

// ─────────────── periodStart / periodEnd ───────────────

test('periodStart — week starts on Monday by default', () => {
	// Apr 8 2026 is a Wednesday. Monday before is Apr 6.
	const start = periodStart('week', new Date('2026-04-08T15:00:00'));
	assert.equal(start.getDate(), 6);
	assert.equal(start.getMonth(), 3); // April
	assert.equal(start.getHours(), 0);
	assert.equal(start.getMinutes(), 0);
});

test('periodStart — week with sunday weekStartDay anchors on Sunday', () => {
	const start = periodStart('week', new Date('2026-04-08T15:00:00'), 'sunday');
	assert.equal(start.getDay(), 0); // Sunday
	assert.equal(start.getDate(), 5);
});

test('periodStart — month starts on the 1st', () => {
	const start = periodStart('month', new Date('2026-04-15T12:00:00'));
	assert.equal(start.getDate(), 1);
	assert.equal(start.getMonth(), 3);
});

test('periodEnd — week is start + 7 days', () => {
	const end = periodEnd('week', new Date('2026-04-08T15:00:00'));
	// Start was Apr 6; end is Apr 13.
	assert.equal(end.getDate(), 13);
});

test('periodEnd — month wraps at year boundary', () => {
	const end = periodEnd('month', new Date('2026-12-15T12:00:00'));
	assert.equal(end.getMonth(), 0); // January
	assert.equal(end.getFullYear(), 2027);
});

// ─────────────── formatPaceSecPerKm ───────────────

test('formatPaceSecPerKm — em-dash for non-positive / non-finite', () => {
	assert.equal(formatPaceSecPerKm(0), '—');
	assert.equal(formatPaceSecPerKm(-10), '—');
	assert.equal(formatPaceSecPerKm(Number.POSITIVE_INFINITY), '—');
	assert.equal(formatPaceSecPerKm(Number.NaN), '—');
});

test('formatPaceSecPerKm — formats m:ss/km', () => {
	assert.equal(formatPaceSecPerKm(330), '5:30/km'); // 5:30
	assert.equal(formatPaceSecPerKm(60), '1:00/km');
	assert.equal(formatPaceSecPerKm(125), '2:05/km'); // pads single-digit seconds
});

test('formatPaceSecPerKm — rounds seconds half-up', () => {
	assert.equal(formatPaceSecPerKm(330.4), '5:30/km');
	assert.equal(formatPaceSecPerKm(330.6), '5:31/km');
});

// ─────────────── evaluateGoal ───────────────

const NOW = new Date('2026-04-08T15:00:00');

test('evaluateGoal — empty run list yields 0% targets', () => {
	const goal: RunGoal = { id: 'g1', period: 'week', distanceMetres: 30000 };
	const p = evaluateGoal(goal, [], NOW);
	assert.equal(p.targets.length, 1);
	assert.equal(p.targets[0].percent, 0);
	assert.equal(p.complete, false);
	assert.equal(p.runCount, 0);
	assert.equal(p.overallPercent, 0);
});

test('evaluateGoal — runs outside the period are excluded', () => {
	const goal: RunGoal = { id: 'g1', period: 'week', distanceMetres: 30000 };
	const lastWeek = run({
		started_at: '2026-03-30T07:00:00',
		distance_m: 30000,
		duration_s: 9000,
	});
	const p = evaluateGoal(goal, [lastWeek], NOW);
	assert.equal(p.runCount, 0);
	assert.equal(p.targets[0].percent, 0);
});

test('evaluateGoal — distance target accumulates and reports complete on hit', () => {
	const goal: RunGoal = { id: 'g1', period: 'week', distanceMetres: 30000 };
	const monday = run({
		started_at: '2026-04-06T07:00:00',
		distance_m: 12000,
		duration_s: 3600,
	});
	const wed = run({
		started_at: '2026-04-08T07:00:00',
		distance_m: 18500,
		duration_s: 5400,
	});
	const p = evaluateGoal(goal, [monday, wed], NOW);
	assert.equal(p.runCount, 2);
	assert.equal(p.targets.length, 1);
	assert.equal(p.targets[0].kind, 'distance');
	assert.equal(p.targets[0].percent, 1);
	assert.equal(p.targets[0].complete, true);
	assert.equal(p.complete, true);
});

test('evaluateGoal — pace target excludes cycling rides from the average', () => {
	// 10 km of running at 5:00/km plus a 30 km cycle ride. If cycling
	// were counted the distance-weighted average would tilt fast and
	// hide the runner's slower true pace.
	const running = run({
		started_at: '2026-04-08T07:00:00',
		distance_m: 10000,
		duration_s: 3000, // 5:00/km
	});
	const cycling = run({
		started_at: '2026-04-08T16:00:00',
		distance_m: 30000,
		duration_s: 3600, // 2:00/km equivalent — way faster
		activity_type: 'cycle',
	});
	const goal: RunGoal = { id: 'g1', period: 'week', paceSecPerKm: 320 }; // 5:20/km target
	const p = evaluateGoal(goal, [running, cycling], NOW);
	const pace = p.targets.find((t) => t.kind === 'pace')!;
	// Runner-only pace = 3000 s / 10 km = 300 s/km, which beats 320.
	assert.equal(pace.complete, true);
	assert.equal(pace.percent, 1);
});

test('evaluateGoal — pace target with no qualifying runs reports 0%, not complete', () => {
	const cyclingOnly = run({
		started_at: '2026-04-08T07:00:00',
		distance_m: 30000,
		duration_s: 3600,
		activity_type: 'cycle',
	});
	const goal: RunGoal = { id: 'g1', period: 'week', paceSecPerKm: 300 };
	const p = evaluateGoal(goal, [cyclingOnly], NOW);
	const pace = p.targets.find((t) => t.kind === 'pace')!;
	assert.equal(pace.complete, false);
	assert.equal(pace.percent, 0);
	assert.equal(pace.currentLabel, '—');
	assert.equal(pace.pending, true,
		'pace target with no eligible runs must be pending');
});

// Persona-hunt finding Intermediate #5: an ineligible pace target
// used to drag the overall ring to 0% even when distance + run-count
// targets were on track. Pending targets are now excluded from the
// overall average.
test('evaluateGoal — pending pace target does not drag overall percent', () => {
	// A weekly goal with three targets: 30 km distance, 5:00 pace, 3
	// runs. The runner cross-trained all week (only cycle rides) but
	// they did do 30 km on the bike + 3 sessions. The pace target is
	// ineligible (no run-family activity) and should NOT count
	// against the overall — only distance + run-count should.
	const cycle = (s: string, distance_m: number, duration_s: number) =>
		run({ started_at: s, distance_m, duration_s, activity_type: 'cycle' });
	const goal: RunGoal = {
		id: 'g1',
		period: 'week',
		distanceMetres: 30_000,
		paceSecPerKm: 300,
		runCount: 3,
	};
	const p = evaluateGoal(
		goal,
		[
			cycle('2026-04-06T07:00:00', 10000, 1500),
			cycle('2026-04-07T07:00:00', 10000, 1500),
			cycle('2026-04-08T07:00:00', 10000, 1500),
		],
		NOW,
	);
	const pace = p.targets.find((t) => t.kind === 'pace')!;
	assert.equal(pace.pending, true);
	// Distance is hit (30 km) and runCount is hit (3 sessions). The
	// overall should reflect those two at 100%, not be dragged down
	// by the pending pace target.
	assert.ok(
		p.overallPercent > 0.99,
		`overallPercent should be ~1.0 (distance + runCount both met); ` +
			`got ${p.overallPercent} — pre-fix the pending pace target ` +
			`dragged it to ~0.66`,
	);
	assert.equal(p.complete, true,
		'goal should be complete — pending pace target excluded');
});

test('evaluateGoal — pace target reports lower-is-better partial progress', () => {
	// 10 km at 6:00/km (360 s/km), target 5:00 (300 s/km).
	// Lower-is-better: percent = target / current = 300 / 360 = 0.833…
	const slow = run({
		started_at: '2026-04-08T07:00:00',
		distance_m: 10000,
		duration_s: 3600,
	});
	const goal: RunGoal = { id: 'g1', period: 'week', paceSecPerKm: 300 };
	const p = evaluateGoal(goal, [slow], NOW);
	const pace = p.targets.find((t) => t.kind === 'pace')!;
	assert.equal(pace.complete, false);
	assert.ok(pace.percent > 0.8 && pace.percent < 0.9, `pace percent ${pace.percent}`);
});

test('evaluateGoal — time target sums duration_s across the period', () => {
	const goal: RunGoal = { id: 'g1', period: 'week', timeSeconds: 7200 };
	const r1 = run({ started_at: '2026-04-06T07:00:00', distance_m: 5000, duration_s: 1800 });
	const r2 = run({ started_at: '2026-04-08T07:00:00', distance_m: 10000, duration_s: 3600 });
	const p = evaluateGoal(goal, [r1, r2], NOW);
	const time = p.targets.find((t) => t.kind === 'time')!;
	assert.equal(time.percent, 0.75); // 5400 / 7200
	assert.equal(time.complete, false);
});

test('evaluateGoal — runCount target counts in-period runs', () => {
	const goal: RunGoal = { id: 'g1', period: 'week', runCount: 4 };
	const runs = [
		run({ started_at: '2026-04-06T07:00:00', distance_m: 5000, duration_s: 1800 }),
		run({ started_at: '2026-04-07T07:00:00', distance_m: 5000, duration_s: 1800 }),
		run({ started_at: '2026-04-08T07:00:00', distance_m: 5000, duration_s: 1800 }),
	];
	const p = evaluateGoal(goal, runs, NOW);
	const c = p.targets.find((t) => t.kind === 'runCount')!;
	assert.equal(c.percent, 0.75);
	assert.equal(c.complete, false);
});

test('evaluateGoal — multi-target goal is complete only when every target is hit', () => {
	const goal: RunGoal = {
		id: 'g1',
		period: 'week',
		distanceMetres: 20000,
		runCount: 3,
	};
	const runs = [
		run({ started_at: '2026-04-06T07:00:00', distance_m: 10000, duration_s: 3600 }),
		run({ started_at: '2026-04-08T07:00:00', distance_m: 10000, duration_s: 3600 }),
	];
	const p = evaluateGoal(goal, runs, NOW);
	// Distance hit (20km / 20km), but only 2 of 3 runs.
	assert.equal(p.targets.length, 2);
	assert.equal(p.targets.find((t) => t.kind === 'distance')!.complete, true);
	assert.equal(p.targets.find((t) => t.kind === 'runCount')!.complete, false);
	assert.equal(p.complete, false);
});

test('evaluateGoal — overallPercent is the mean of target percents', () => {
	const goal: RunGoal = {
		id: 'g1',
		period: 'week',
		distanceMetres: 20000,
		runCount: 4,
	};
	const r = run({ started_at: '2026-04-08T07:00:00', distance_m: 10000, duration_s: 3600 });
	const p = evaluateGoal(goal, [r], NOW);
	// distance: 0.5, runCount: 0.25 → mean 0.375.
	assert.equal(p.overallPercent, 0.375);
});

test('evaluateGoal — zero / negative target is ignored (not added to targets list)', () => {
	const goal: RunGoal = { id: 'g1', period: 'week', distanceMetres: 0, runCount: 3 };
	const r = run({ started_at: '2026-04-08T07:00:00', distance_m: 10000, duration_s: 3600 });
	const p = evaluateGoal(goal, [r], NOW);
	assert.equal(p.targets.length, 1);
	assert.equal(p.targets[0].kind, 'runCount');
});

// ─────────────── newGoalId ───────────────

test('newGoalId — produces unique strings', () => {
	const ids = new Set<string>();
	for (let i = 0; i < 100; i++) ids.add(newGoalId());
	assert.equal(ids.size, 100);
});

// ─────────────── periodLabel ───────────────

test('periodLabel — human-friendly strings', () => {
	assert.equal(periodLabel('week'), 'This week');
	assert.equal(periodLabel('month'), 'This month');
});

// ─────────────── loadGoals / saveGoals (with localStorage shim) ───────────────

let storage: Map<string, string>;
const realLocalStorage =
	typeof globalThis !== 'undefined' && 'localStorage' in globalThis
		? (globalThis as { localStorage?: Storage }).localStorage
		: undefined;

beforeEach(() => {
	storage = new Map();
	(globalThis as { localStorage?: Storage }).localStorage = {
		get length() {
			return storage.size;
		},
		clear() {
			storage.clear();
		},
		getItem(k: string) {
			return storage.get(k) ?? null;
		},
		setItem(k: string, v: string) {
			storage.set(k, v);
		},
		removeItem(k: string) {
			storage.delete(k);
		},
		key(i: number) {
			return Array.from(storage.keys())[i] ?? null;
		},
	} as Storage;
});

afterEach(() => {
	if (realLocalStorage === undefined) {
		delete (globalThis as { localStorage?: Storage }).localStorage;
	} else {
		(globalThis as { localStorage?: Storage }).localStorage = realLocalStorage;
	}
});

test('loadGoals — empty when no data', () => {
	assert.deepEqual(loadGoals('user-a'), []);
});

test('saveGoals + loadGoals — round-trip preserves goal fields', () => {
	const goals: RunGoal[] = [
		{ id: 'g1', period: 'week', distanceMetres: 30000 },
		{ id: 'g2', period: 'month', runCount: 12, paceSecPerKm: 300 },
	];
	saveGoals('user-a', goals);
	const back = loadGoals('user-a');
	assert.equal(back.length, 2);
	assert.equal(back[0].id, 'g1');
	assert.equal(back[0].distanceMetres, 30000);
	assert.equal(back[0].period, 'week');
	assert.equal(back[1].id, 'g2');
	assert.equal(back[1].runCount, 12);
	assert.equal(back[1].paceSecPerKm, 300);
	assert.equal(back[1].period, 'month');
});

test('loadGoals — keys per-user; another user sees their own data only', () => {
	saveGoals('user-a', [{ id: 'g1', period: 'week', distanceMetres: 30000 }]);
	saveGoals('user-b', [{ id: 'g2', period: 'month', runCount: 8 }]);
	const a = loadGoals('user-a');
	const b = loadGoals('user-b');
	assert.equal(a.length, 1);
	assert.equal(a[0].id, 'g1');
	assert.equal(b.length, 1);
	assert.equal(b[0].id, 'g2');
});

test('loadGoals — null userId returns empty', () => {
	saveGoals('user-a', [{ id: 'g1', period: 'week', distanceMetres: 30000 }]);
	assert.deepEqual(loadGoals(null), []);
	assert.deepEqual(loadGoals(undefined), []);
});

test('loadGoals — adopts legacy unscoped goals on first load and removes the legacy key', () => {
	storage.set(
		'run_app.goals_v1',
		JSON.stringify([{ id: 'g1', period: 'week', distance_m: 30000 }]),
	);
	const back = loadGoals('user-a');
	assert.equal(back.length, 1);
	assert.equal(back[0].distanceMetres, 30000);
	// Legacy key should be removed after migration.
	assert.equal(storage.has('run_app.goals_v1'), false);
});

test('loadGoals — accepts both legacy camelCase and canonical snake_case wire shapes', () => {
	storage.set(
		'run_app.goals_v1:user-a',
		JSON.stringify([
			{ id: 'g1', period: 'week', distanceMetres: 25000 }, // camelCase
			{ id: 'g2', period: 'month', distance_m: 30000 }, // snake_case
		]),
	);
	const goals = loadGoals('user-a');
	assert.equal(goals[0].distanceMetres, 25000);
	assert.equal(goals[1].distanceMetres, 30000);
});

test('loadGoals — corrupt JSON is swallowed and returns empty', () => {
	storage.set('run_app.goals_v1:user-a', 'not json');
	assert.deepEqual(loadGoals('user-a'), []);
});
