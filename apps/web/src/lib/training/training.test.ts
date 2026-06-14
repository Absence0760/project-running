// Unit tests for the training engine. Run with `node --test` — no external
// test runner needed. The engine is pure TS with no browser or SvelteKit
// deps so Node 20+ can execute it directly via tsx / ts-node, or via the
// compiled output if we add vitest later.
//
// Invocation example (from apps/web):
//   npx tsx --test src/lib/training/training.test.ts
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
	predictionConfidence,
	pacesFromGoalPace,
	resolveTrainingPaces,
	phaseFor,
	generatePlan,
	isMastersAge,
	defaultPlanWeeks,
	walkRunDefaultWeeks,
	GOAL_DISTANCES_M,
	formatISO,
	fmtHms,
	isWorkoutCompleted,
	isWorkoutSkipped,
	type WorkoutStructure
} from './training';

// ─────────────────────── walk-run kind + structure (#22) ───────────────────────

test('generatePlan: a no-anchor 5k plan ramps gentler than an anchored one (#23)', () => {
	const base = {
		goalEvent: 'distance_5k' as const,
		startDate: '2026-06-01',
		daysPerWeek: 4
	};
	const anchored = generatePlan({ ...base, recent5kSec: 22 * 60 });
	const noAnchor = generatePlan(base);
	const weekVol = (p: typeof anchored, i: number) =>
		p.weeks[i].workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0);
	const activeDays = (p: typeof anchored, i: number) =>
		p.weeks[i].workouts.filter((w) => w.kind !== 'rest').length;
	// Week 1 must honour daysPerWeek — the old limitToDays missed 'recovery'
	// fillers, so a 4-day plan ran 6 days and stacked floored recoveries.
	assert.equal(activeDays(noAnchor, 0), 4);
	// No-anchor peak scaling makes its week-1 lower than the anchored plan's,
	// and beginner-sane for a no-info 5k (< 15 km vs the old ~20 km).
	assert.ok(weekVol(noAnchor, 0) < weekVol(anchored, 0));
	assert.ok(weekVol(noAnchor, 0) < 15_000, `week1=${weekVol(noAnchor, 0)}`);
});

test('generatePlan(beginnerWalkRun): every session is a walk_run workout', () => {
	const plan = generatePlan({
		goalEvent: 'distance_5k',
		startDate: '2026-06-01',
		daysPerWeek: 3,
		beginnerWalkRun: true
	});
	// Default 9-week C25K progression.
	assert.equal(plan.weeks.length, 9);
	const allWorkouts = plan.weeks.flatMap((w) => w.workouts);
	const sessions = allWorkouts.filter((w) => w.kind !== 'rest');
	assert.ok(sessions.length > 0);
	assert.ok(sessions.every((w) => w.kind === 'walk_run'));
	// 3 run days per week.
	assert.equal(sessions.length, 9 * 3);
	// Week 1 session: timed run/walk repeats with a 'walk' recovery.
	const wk1 = plan.weeks[0].workouts.find((w) => w.kind === 'walk_run')!;
	assert.equal(wk1.structure?.repeats?.recovery_pace, 'walk');
	assert.equal(wk1.structure?.repeats?.duration_s, 60);
	assert.equal(wk1.structure?.repeats?.recovery_duration_s, 90);
	assert.equal(wk1.structure?.repeats?.count, 8);
	// Graduation week: a single continuous run, no recovery interval.
	const wk9 = plan.weeks[8].workouts.find((w) => w.kind === 'walk_run')!;
	assert.equal(wk9.structure?.repeats?.count, 1);
	assert.equal(wk9.structure?.repeats?.recovery_duration_s, undefined);
});

// Persona round-5 runner-new: a default 5k beginner plan arrives with
// weeks=8 (defaultPlanWeeks('distance_5k')) against a 9-stage progression.
// Without the engine floor, week index 8 — the single continuous-run
// graduation week — was silently dropped.
test('walkRunDefaultWeeks: matches the full progression length', () => {
	// 9-stage C25K table → 9-week default for a beginner plan.
	assert.equal(walkRunDefaultWeeks(), 9);
});

test('generatePlan(beginnerWalkRun, weeks=8): keeps the graduation week (off-by-one fix)', () => {
	// Simulate the old PlanEditor path that forced weeks=defaultPlanWeeks('distance_5k')=8.
	const plan = generatePlan({
		goalEvent: 'distance_5k',
		startDate: '2026-06-01',
		daysPerWeek: 3,
		weeks: 8,
		beginnerWalkRun: true
	});
	// Floored up to the full progression so graduation isn't truncated.
	assert.equal(plan.weeks.length, 9);
	const wkLast = plan.weeks[plan.weeks.length - 1].workouts.find((w) => w.kind === 'walk_run')!;
	assert.equal(wkLast.structure?.repeats?.count, 1);
	assert.equal(wkLast.structure?.repeats?.recovery_duration_s, undefined);
	assert.match(wkLast.notes ?? '', /Graduation week/);
});

// Persona round-5 runner-comeback: when the engine can't derive paces from a
// recent race or a goal time it falls back to a conservative 10:00/km. The
// plan must flag that so the wizard can disclose it rather than presenting a
// placeholder as a real prescription.
test('generatePlan: pacesAreFallback is true with no anchor, false with an anchor', () => {
	const noAnchor = generatePlan({
		goalEvent: 'distance_10k',
		startDate: '2026-06-01',
		daysPerWeek: 3
	});
	assert.equal(noAnchor.pacesAreFallback, true);

	const withGoal = generatePlan({
		goalEvent: 'distance_10k',
		startDate: '2026-06-01',
		daysPerWeek: 3,
		goalTimeSec: 45 * 60
	});
	assert.equal(withGoal.pacesAreFallback, false);

	const withRecent = generatePlan({
		goalEvent: 'distance_10k',
		startDate: '2026-06-01',
		daysPerWeek: 3,
		recent5kSec: 24 * 60
	});
	assert.equal(withRecent.pacesAreFallback, false);
	// The fallback paces are still usable — the plan generates either way.
	assert.ok(noAnchor.paces.easy > 0 && noAnchor.weeks.length > 0);
});

test('WorkoutStructure: a time-based walk-run rep block is well-typed', () => {
	// Compile-time check that duration_s / recovery_duration_s / recovery_pace
	// 'walk' are accepted; the assertion just confirms the shape round-trips.
	const s: WorkoutStructure = {
		repeats: {
			count: 8,
			duration_s: 60,
			pace_sec_per_km: 420,
			recovery_duration_s: 90,
			recovery_pace: 'walk'
		}
	};
	assert.equal(s.repeats?.recovery_pace, 'walk');
	assert.equal(s.repeats?.duration_s, 60);
});

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

test('generatePlan: stated weekly volume equals the sum of emitted workout distances', () => {
	// The headline `target_volume_m` must match what the week actually
	// prescribes. Pre-fix it was `weeklyKm * 1000`, which overshot the
	// rounded/floored per-day distances by ~25-70% on small-volume plans.
	for (const goalEvent of ['distance_5k', 'distance_half'] as const) {
		for (const daysPerWeek of [3, 4, 5]) {
			const plan = generatePlan({
				goalEvent,
				startDate: '2026-05-03',
				daysPerWeek,
				goalTimeSec: goalEvent === 'distance_5k' ? 25 * 60 : 105 * 60
			});
			for (const week of plan.weeks) {
				const emitted = week.workouts.reduce(
					(s, w) => s + (w.target_distance_m ?? 0),
					0
				);
				assert.equal(
					week.target_volume_m,
					emitted,
					`${goalEvent} ${daysPerWeek}d week ${week.week_index}: stated ` +
						`${week.target_volume_m} should equal emitted ${emitted}`
				);
			}
		}
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

// ─────────────────────── isWorkoutSkipped ───────────────────────

test("isWorkoutSkipped: false when skipped_at absent or null", () => {
	assert.equal(isWorkoutSkipped({}), false);
	assert.equal(isWorkoutSkipped({ skipped_at: null }), false);
});

test("isWorkoutSkipped: true when skipped_at stamped", () => {
	assert.equal(isWorkoutSkipped({ skipped_at: "2026-06-13T10:00:00.000Z" }), true);
});

test("isWorkoutSkipped is independent of completion flags", () => {
	// The write layer keeps skip and done mutually exclusive, but the read
	// helper only inspects skipped_at — a row that somehow carried both
	// still reads as skipped here (defensive: the predicate is single-axis).
	assert.equal(
		isWorkoutSkipped({ skipped_at: "2026-06-13T10:00:00.000Z", completed_run_id: "run-1" }),
		true
	);
});

// ─────────────────────── masters age-band calibration (#30) ───────────────────────

test('isMastersAge: boundary is 50 inclusive; null/undefined are not masters', () => {
	assert.equal(isMastersAge(49), false);
	assert.equal(isMastersAge(50), true);
	assert.equal(isMastersAge(72), true);
	assert.equal(isMastersAge(null), false);
	assert.equal(isMastersAge(undefined), false);
});

// Offset (in days) of a workout from its week's first slot (the long
// run / race on dow 0). workouts are pushed in dow order, so [0] is the
// week start.
function dayOffsetInWeek(week: { workouts: { scheduled_date: string; kind: string }[] }, kinds: string[]): number | null {
	const start = Date.parse(week.workouts[0].scheduled_date + 'T00:00:00Z');
	const q = week.workouts.find((w) => kinds.includes(w.kind));
	if (!q) return null;
	const at = Date.parse(q.scheduled_date + 'T00:00:00Z');
	return Math.round((at - start) / 86_400_000);
}

const QUALITY_KINDS = ['tempo', 'interval', 'marathon_pace'];

test('generatePlan: masters push the first quality day to 72h after the long run (Wed vs Tue)', () => {
	const base = {
		goalEvent: 'distance_half' as const,
		startDate: '2026-06-07', // a Sunday — long run lands on dow 0
		daysPerWeek: 5,
		goalTimeSec: 100 * 60
	};
	const standard = generatePlan(base);
	const masters = generatePlan({ ...base, age: 58 });

	// Find a build-phase week that actually allocated quality in both plans.
	const stdWeek = standard.weeks.find((w) => dayOffsetInWeek(w, QUALITY_KINDS) != null)!;
	const mstWeek = masters.weeks.find((w) => dayOffsetInWeek(w, QUALITY_KINDS) != null)!;
	assert.equal(dayOffsetInWeek(stdWeek, QUALITY_KINDS), 2, 'standard plan: first quality on Tue (48h)');
	assert.equal(dayOffsetInWeek(mstWeek, QUALITY_KINDS), 3, 'masters plan: first quality on Wed (72h)');
});

test('generatePlan: masters never schedule a quality day on the slot right after the long run', () => {
	const masters = generatePlan({
		goalEvent: 'distance_full',
		startDate: '2026-06-07',
		daysPerWeek: 5,
		recent5kSec: 24 * 60,
		age: 55
	});
	for (const week of masters.weeks) {
		const off = dayOffsetInWeek(week, QUALITY_KINDS);
		if (off != null) {
			assert.ok(off >= 3, `masters quality must be >=72h after long run, got ${off}d (week ${week.week_index})`);
		}
	}
});

test('generatePlan: masters step back volume every 3rd week, not every 4th', () => {
	const masters = generatePlan({
		goalEvent: 'distance_full',
		startDate: '2026-06-07',
		daysPerWeek: 5,
		recent5kSec: 22 * 60,
		age: 60
	});
	// Week index 2 (3rd week) is the masters step-back. Guard against it
	// being pushed into taper on a short plan.
	if (masters.weeks.length >= 4 && masters.weeks[2].phase !== 'taper') {
		assert.ok(
			masters.weeks[2].target_volume_m <= masters.weeks[1].target_volume_m,
			'masters 3rd-week step-back should not exceed the 2nd week'
		);
		assert.match(masters.weeks[2].notes ?? '', /Step-back/);
	}
});

test('generatePlan: a sub-masters age leaves the standard Tue/Thu schedule intact', () => {
	const plan = generatePlan({
		goalEvent: 'distance_half',
		startDate: '2026-06-07',
		daysPerWeek: 5,
		goalTimeSec: 100 * 60,
		age: 34
	});
	const week = plan.weeks.find((w) => dayOffsetInWeek(w, QUALITY_KINDS) != null)!;
	assert.equal(dayOffsetInWeek(week, QUALITY_KINDS), 2);
});


// ─────────────────────── predictionConfidence ───────────────────────

const FIVE_K = 5000;
const TEN_K = 10000;
const MARATHON = 42195;

test('predictionConfidence: high when distance is close, effort recent, well-sampled', () => {
	const q = predictionConfidence({
		knownDistanceM: TEN_K,
		targetDistanceM: FIVE_K,
		daysSinceBest: 10,
		qualifyingRunCount: 5,
	});
	assert.equal(q.confidence, 'high');
	assert.equal(q.reason, 'similar');
});

test('predictionConfidence: low + extrapolated when projecting a marathon off a 5k', () => {
	const q = predictionConfidence({
		knownDistanceM: FIVE_K,
		targetDistanceM: MARATHON,
		daysSinceBest: 5,
		qualifyingRunCount: 8,
	});
	assert.equal(q.confidence, 'low');
	assert.equal(q.reason, 'extrapolated');
});

test('predictionConfidence: moderate + stale when the only recent effort is weeks old', () => {
	const q = predictionConfidence({
		knownDistanceM: FIVE_K,
		targetDistanceM: FIVE_K,
		daysSinceBest: 45,
		qualifyingRunCount: 4,
	});
	assert.equal(q.confidence, 'moderate');
	assert.equal(q.reason, 'stale');
});

test('predictionConfidence: moderate + limited when close + recent but thinly sampled', () => {
	const q = predictionConfidence({
		knownDistanceM: FIVE_K,
		targetDistanceM: FIVE_K,
		daysSinceBest: 7,
		qualifyingRunCount: 1,
	});
	assert.equal(q.confidence, 'moderate');
	assert.equal(q.reason, 'limited');
});

test('predictionConfidence: moderate + extrapolated for a meaningful but not extreme gap', () => {
	// 5k → half marathon is ~4.2x — past the close band but within the
	// moderate factor<=3? No: 21097/5000 = 4.2 > 4 → far → low.
	// Use 10k → half (2.1x) to land in the moderate-extrapolated band.
	const q = predictionConfidence({
		knownDistanceM: TEN_K,
		targetDistanceM: 21097,
		daysSinceBest: 10,
		qualifyingRunCount: 5,
	});
	assert.equal(q.confidence, 'moderate');
	assert.equal(q.reason, 'extrapolated');
});

test('predictionConfidence: low + stale when the anchoring effort is over two months old', () => {
	const q = predictionConfidence({
		knownDistanceM: FIVE_K,
		targetDistanceM: FIVE_K,
		daysSinceBest: 75,
		qualifyingRunCount: 4,
	});
	assert.equal(q.confidence, 'low');
	assert.equal(q.reason, 'stale');
});

test('predictionConfidence: low + limited with no qualifying runs', () => {
	const q = predictionConfidence({
		knownDistanceM: FIVE_K,
		targetDistanceM: FIVE_K,
		daysSinceBest: 5,
		qualifyingRunCount: 0,
	});
	assert.equal(q.confidence, 'low');
	assert.equal(q.reason, 'limited');
});

test('fmtHms — zero/null/negative render the em-dash placeholder', () => {
	assert.equal(fmtHms(0), '—');
	assert.equal(fmtHms(null), '—');
	assert.equal(fmtHms(undefined), '—');
	// A negative is truthy in JS; the <= 0 guard must still placeholder it.
	assert.equal(fmtHms(-90), '—');
});

test('fmtHms — formats a positive duration', () => {
	assert.equal(fmtHms(90), '1:30');
	assert.equal(fmtHms(3661), '1:01:01');
});

test('generatePlan: a zero anchor is treated as no anchor (no Infinity vdot)', () => {
	const base = {
		goalEvent: 'distance_5k' as const,
		startDate: '2026-06-01',
		daysPerWeek: 4
	};
	const zero = generatePlan({ ...base, recent5kSec: 0 });
	const noAnchor = generatePlan(base);
	assert.equal(zero.vdot, null);
	const weekVol = (p: typeof zero, i: number) =>
		p.weeks[i].workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0);
	// A zero anchor scales volume identically to no anchor (0.6× peak).
	assert.equal(weekVol(zero, 0), weekVol(noAnchor, 0));
});
