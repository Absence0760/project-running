// Unit tests for the training engine. Run with `node --test` — no external
// test runner needed. The engine is pure TS with no browser or SvelteKit
// deps so Node 20+ can execute it directly via tsx / ts-node, or via the
// compiled output if we add vitest later.
//
// Invocation example (from apps/web):
//   npx tsx --test src/lib/training.test.ts
//
// Or if you prefer raw Node once this is transpiled:
//   node --test src/lib/training.test.js
//
// Adding a test runner is a tooling question the user hasn't decided — these
// are written to the stdlib `node:test` API so any runner will pick them up.

import { test } from 'node:test';
import assert from 'node:assert/strict';

// Relative import without extension so SvelteKit's svelte-check (which runs
// under `noUncheckedSideEffectImports` / no-extension TS config) is happy.
// `tsx --test` resolves this to training.ts at runtime.
import {
	vdotFromRace,
	riegelPredict,
	pacesFromGoalPace,
	resolveTrainingPaces,
	phaseFor,
	generatePlan,
	defaultPlanWeeks,
	GOAL_DISTANCES_M
} from './training';

// ─────────────────────── VDOT ───────────────────────

test('vdotFromRace: a 20-minute 5k is close to VDOT 50', () => {
	const v = vdotFromRace(5000, 20 * 60);
	assert.ok(Math.abs(v - 49.8) < 1.5, `expected ~50, got ${v}`);
});

test('vdotFromRace: a 3:00 marathon is close to VDOT 54', () => {
	const v = vdotFromRace(42_195, 3 * 3600);
	assert.ok(Math.abs(v - 54.3) < 2, `expected ~54, got ${v}`);
});

test('vdotFromRace: slower runners get lower VDOT', () => {
	const fast = vdotFromRace(5000, 20 * 60);
	const slow = vdotFromRace(5000, 30 * 60);
	assert.ok(fast > slow, 'faster 5k must produce higher VDOT');
});

// ─────────────────────── Riegel ───────────────────────

test('riegelPredict: 20-min 5k projects to a ~41-42 min 10k', () => {
	const t10k = riegelPredict(5000, 20 * 60, 10_000);
	assert.ok(Math.abs(t10k - 41.7 * 60) < 60, `expected ~41:40, got ${t10k / 60} min`);
});

test('riegelPredict: identity for same distance', () => {
	assert.equal(riegelPredict(5000, 1234, 5000), 1234);
});

test('riegelPredict: longer target means longer predicted time', () => {
	const short = riegelPredict(5000, 1200, 5000);
	const long = riegelPredict(5000, 1200, 10_000);
	assert.ok(long > short);
});

// ─────────────────────── Pace multipliers ───────────────────────

test('pacesFromGoalPace: zones are ordered slow → fast', () => {
	const p = pacesFromGoalPace(240); // 4:00/km goal
	assert.ok(p.easy > p.marathon, 'easy slower than marathon');
	assert.ok(p.marathon > p.tempo, 'marathon slower than tempo');
	assert.ok(p.tempo > p.interval, 'tempo slower than interval');
	assert.ok(p.interval > p.repetition, 'interval slower than repetition');
});

test('pacesFromGoalPace: 4:00/km goal yields easy in 4:30-5:15 band', () => {
	const p = pacesFromGoalPace(240);
	assert.ok(p.easy >= 270 && p.easy <= 315, `easy out of band: ${p.easy}`);
});

test('resolveTrainingPaces: a recent 5k beats a goal time as the anchor', () => {
	// Runner wants a sub-20 5k but their recent 5k is 25:00. Plan paces
	// should reflect current fitness, not the goal.
	const withRecent = resolveTrainingPaces({
		goalDistanceM: 5000,
		goalTimeSec: 19 * 60 + 59,
		recent5kSec: 25 * 60
	});
	const withGoalOnly = resolveTrainingPaces({
		goalDistanceM: 5000,
		goalTimeSec: 19 * 60 + 59
	});
	assert.ok(
		withRecent.easy > withGoalOnly.easy,
		'recent-5k anchor should yield slower (safer) easy pace'
	);
});

test('resolveTrainingPaces: fall-back produces a valid pace set', () => {
	const p = resolveTrainingPaces({ goalDistanceM: 10_000 });
	assert.ok(p.easy > 0 && p.interval > 0);
});

// ─────────────────────── Phases ───────────────────────

test('phaseFor: a 16-week plan is ~30/40/20/10 base/build/peak/taper', () => {
	const counts = { base: 0, build: 0, peak: 0, taper: 0, race: 0 };
	for (let i = 0; i < 16; i++) counts[phaseFor(i, 16)]++;
	assert.equal(counts.race, 1, 'race week is last');
	assert.ok(counts.base >= 4 && counts.base <= 5);
	assert.ok(counts.build >= 6 && counts.build <= 7);
	assert.ok(counts.peak >= 2 && counts.peak <= 4);
	assert.ok(counts.taper >= 1 && counts.taper <= 2);
});

test('phaseFor: final week is always race', () => {
	for (const total of [4, 8, 12, 16, 20]) {
		assert.equal(phaseFor(total - 1, total), 'race');
	}
});

// ─────────────────────── Plan generation ───────────────────────

test('generatePlan: produces the requested number of weeks', () => {
	const plan = generatePlan({
		goalEvent: 'distance_half',
		startDate: '2026-05-03',
		daysPerWeek: 4,
		goalTimeSec: 90 * 60
	});
	assert.equal(plan.weeks.length, defaultPlanWeeks('distance_half'));
});

test('generatePlan: a 4-day plan has exactly 3 runs + 1 long per week in base', () => {
	const plan = generatePlan({
		goalEvent: 'distance_10k',
		startDate: '2026-05-03',
		daysPerWeek: 4,
		goalTimeSec: 45 * 60
	});
	const w0 = plan.weeks[0];
	const active = w0.workouts.filter((w) => w.kind !== 'rest');
	assert.equal(active.length, 4);
	assert.ok(active.some((w) => w.kind === 'long'));
});

test('generatePlan: taper weeks have lower volume than peak', () => {
	const plan = generatePlan({
		goalEvent: 'distance_full',
		startDate: '2026-06-07',
		daysPerWeek: 5,
		goalTimeSec: 4 * 3600
	});
	const peakWeek = plan.weeks.find((w) => w.phase === 'peak')!;
	const taperWeek = plan.weeks.find((w) => w.phase === 'taper')!;
	assert.ok(
		peakWeek.target_volume_m > taperWeek.target_volume_m,
		`taper (${taperWeek.target_volume_m}) should be below peak (${peakWeek.target_volume_m})`
	);
});

test('generatePlan: race week ends with a race-kind workout', () => {
	const plan = generatePlan({
		goalEvent: 'distance_5k',
		startDate: '2026-05-03',
		daysPerWeek: 4,
		goalTimeSec: 25 * 60
	});
	const raceWeek = plan.weeks[plan.weeks.length - 1];
	assert.equal(raceWeek.phase, 'race');
	assert.ok(raceWeek.workouts.some((w) => w.kind === 'race'));
});

test('generatePlan: builds interval structure for build-phase intervals', () => {
	const plan = generatePlan({
		goalEvent: 'distance_half',
		startDate: '2026-05-03',
		daysPerWeek: 5,
		goalTimeSec: 95 * 60
	});
	const interval = plan.weeks
		.flatMap((w) => w.workouts)
		.find((w) => w.kind === 'interval');
	assert.ok(interval, 'expected at least one interval session');
	assert.ok(interval!.structure, 'interval must carry a structure');
	assert.ok(interval!.structure!.repeats, 'interval must have repeats');
	assert.ok((interval!.structure!.repeats!.count ?? 0) > 0);
});

test('generatePlan: no recent5k + no goal still produces a plan', () => {
	const plan = generatePlan({
		goalEvent: 'distance_10k',
		startDate: '2026-05-03',
		daysPerWeek: 3
	});
	assert.ok(plan.weeks.length > 0);
	assert.ok(plan.paces.easy > 0);
	assert.equal(plan.vdot, null);
});

test('generatePlan: weekly volume steps back every 4th week', () => {
	const plan = generatePlan({
		goalEvent: 'distance_full',
		startDate: '2026-06-07',
		daysPerWeek: 5,
		recent5kSec: 22 * 60
	});
	// In base phase the 4th week (index 3) should be lower than the 3rd.
	// Guard against the edge where index 3 is already in taper for short plans.
	if (plan.weeks.length >= 5 && plan.weeks[3].phase !== 'taper') {
		assert.ok(
			plan.weeks[3].target_volume_m <= plan.weeks[2].target_volume_m,
			'step-back week should not exceed the week before it'
		);
	}
});

test('GOAL_DISTANCES_M: half marathon is within 1m of 21.0975km', () => {
	assert.equal(GOAL_DISTANCES_M.distance_half, 21097.5);
});

test('generatePlan: every generated workout has a kind (regression for the null-kind race-week bug)', () => {
	// Exercise every phase boundary the generator can hit — varying weeks
	// and days/week — so a race week or sparse-allocation phase can't
	// silently emit a kindless workout the way the old quality-slot code did.
	for (const [goal, weeks] of [
		['distance_5k', 8],
		['distance_10k', 12],
		['distance_half', 16],
		['distance_full', 32]
	] as const) {
		for (const dpw of [3, 4, 5, 6, 7]) {
			const plan = generatePlan({
				goalEvent: goal,
				startDate: '2026-03-30',
				daysPerWeek: dpw,
				goalTimeSec: 3 * 3600,
				recent5kSec: 22 * 60,
				weeks
			});
			for (const w of plan.weeks) {
				for (const wo of w.workouts) {
					assert.ok(
						wo.kind,
						`null kind in ${goal} ${weeks}w × ${dpw}/wk at week ${w.week_index} ${wo.scheduled_date}`
					);
					assert.ok(wo.scheduled_date, 'scheduled_date missing');
				}
			}
		}
	}
});
