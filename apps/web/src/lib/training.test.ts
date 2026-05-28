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
	GOAL_DISTANCES_M,
	formatISO,
	isWorkoutCompleted
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

// Persona-hunt Round 3 finding Woman #3 — gender calibration.
test('pacesFromGoalPace: omitting gender returns the existing (male-curve) values', () => {
	// Back-compat pin — every caller that doesn't pass gender must
	// see the unmodified output. A regression that hard-coded the
	// calibration would silently slow every existing user's prescribed
	// paces by 3%.
	const noGender = pacesFromGoalPace(240);
	const explicitNull = pacesFromGoalPace(240, null);
	const explicitMale = pacesFromGoalPace(240, 'male');
	assert.deepStrictEqual(noGender, explicitNull);
	assert.deepStrictEqual(noGender, explicitMale);
});

test('pacesFromGoalPace: female calibration shifts every band ~3% slower', () => {
	const male = pacesFromGoalPace(240);
	const female = pacesFromGoalPace(240, 'female');
	// Each band must be slower (higher seconds-per-km) for female.
	assert.ok(female.easy > male.easy, `female easy not slower: ${female.easy} vs ${male.easy}`);
	assert.ok(female.marathon > male.marathon);
	assert.ok(female.tempo > male.tempo);
	assert.ok(female.interval > male.interval);
	assert.ok(female.repetition > male.repetition);
	// And the shift must sit in the 2-5% range we documented — looser
	// pin to absorb integer rounding at the tighter bands. Use the
	// `easy` band (widest absolute, most stable under rounding).
	const ratio = female.easy / male.easy;
	assert.ok(
		ratio > 1.02 && ratio < 1.05,
		`female easy / male easy ratio out of 2-5% band: ${ratio}`
	);
});

test('pacesFromGoalPace: nonbinary falls back to the unmodified curve', () => {
	// We do not have a validated calibration for non-binary athletes;
	// applying a wrong adjustment is worse than no adjustment. Pin
	// the conservative default so a future contributor doesn't
	// silently fork this branch.
	const male = pacesFromGoalPace(240);
	const nb = pacesFromGoalPace(240, 'nonbinary');
	assert.deepStrictEqual(nb, male);
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

test('resolveTrainingPaces: marathon-only goal time yields valid pace set', () => {
	const p = resolveTrainingPaces({ goalDistanceM: 42195, goalTimeSec: 4 * 3600 });
	// 4h marathon = 341 s/km goal pace. Easy should be ~416, tempo ~330.
	assert.ok(p.easy > 350 && p.easy < 500, `easy out of range: ${p.easy}`);
	assert.ok(p.tempo < p.marathon, 'tempo must be faster than marathon');
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

// Persona-hunt finding Intermediate #4: 3-day plans used to be all
// long-run + easy with no quality work in any phase — basically just
// a mileage log, not a training plan. Drop the qualityA gate from
// >=4 to >=3 so 3-day plans get one tempo/interval per week (the
// phase picks which).
test('generatePlan: a 3-day plan in base phase still includes a tempo workout', () => {
	const plan = generatePlan({
		goalEvent: 'distance_half',
		startDate: '2026-05-03',
		daysPerWeek: 3,
		goalTimeSec: 105 * 60
	});
	const baseWeek = plan.weeks.find((w) => w.phase === 'base');
	assert.ok(baseWeek, 'plan should have a base-phase week');
	const kinds = new Set(baseWeek!.workouts.map((w) => w.kind));
	const active = baseWeek!.workouts.filter((w) => w.kind !== 'rest');
	assert.equal(active.length, 3, '3-day plan has 3 active days');
	assert.ok(kinds.has('long'), '3-day plan must include the long run');
	assert.ok(
		kinds.has('tempo') || kinds.has('interval'),
		'3-day plan in base phase must include at least one tempo/interval — ' +
			'pre-fix it was all easy + long, not a training plan'
	);
});

test('generatePlan: a 3-day plan in build phase includes intervals', () => {
	const plan = generatePlan({
		goalEvent: 'distance_full',
		startDate: '2026-06-07',
		daysPerWeek: 3,
		goalTimeSec: 4 * 3600
	});
	const buildWeek = plan.weeks.find((w) => w.phase === 'build');
	assert.ok(buildWeek, 'plan should have a build-phase week');
	const kinds = new Set(buildWeek!.workouts.map((w) => w.kind));
	assert.ok(
		kinds.has('interval'),
		'3-day build phase must include the interval workout'
	);
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

// Regression: period-summary prev/next was using `toISOString().slice(0,10)`,
// which rolls the date back a day in any positive-offset zone before
// midnight local. `formatISO` builds yyyy-mm-dd from local components so the
// week-shift always lands on the same wall-clock day.
test('formatISO: returns local-tz components, not UTC', () => {
	// 2025-12-15 at 00:30 local — in any UTC+1..+12 zone, toISOString() would
	// return 2025-12-14. formatISO must stay on the 15th.
	const d = new Date(2025, 11, 15, 0, 30, 0, 0);
	assert.equal(formatISO(d), '2025-12-15');
});

test('formatISO: zero-pads single-digit month and day', () => {
	const d = new Date(2026, 0, 5, 12, 0, 0, 0);
	assert.equal(formatISO(d), '2026-01-05');
});

test('formatISO: shiftPeriod by 7 days lands on the same weekday', () => {
	const start = new Date(2025, 11, 15, 0, 0, 0, 0); // Mon
	const next = new Date(start);
	next.setDate(next.getDate() + 7);
	assert.equal(formatISO(next), '2025-12-22');
});

// ─────────────────────── isWorkoutCompleted ───────────────────────

test("isWorkoutCompleted: false when neither flag set", () => {
	assert.equal(isWorkoutCompleted({}), false);
	assert.equal(
		isWorkoutCompleted({ manually_completed: false, completed_run_id: null }),
		false
	);
});

test("isWorkoutCompleted: true when run is linked", () => {
	assert.equal(isWorkoutCompleted({ completed_run_id: "run-123" }), true);
});

test("isWorkoutCompleted: true when manually marked", () => {
	assert.equal(isWorkoutCompleted({ manually_completed: true }), true);
});

test("isWorkoutCompleted: true when both set", () => {
	assert.equal(
		isWorkoutCompleted({ manually_completed: true, completed_run_id: "run-1" }),
		true
	);
});

