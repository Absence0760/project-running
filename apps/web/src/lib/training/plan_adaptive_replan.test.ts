import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { adaptiveFitnessGateEnabled, adaptiveReplanRemaining } from './plan_adaptive_replan';
import type { ReplanWeek } from './plan_replan';

function wo(
	id: string,
	scheduledDate: string,
	kind: string,
	targetDistanceM: number | null,
	{ completed = false, skipped = false, isPast = false } = {},
) {
	return { id, scheduledDate, kind, targetDistanceM, completed, skipped, isPast };
}

// A completed week with a given planned/actual volume. `under` = actual far
// below planned (flagged under); `over` = far above; `ontrack` = close.
function week(
	weekIndex: number,
	drift: 'under' | 'over' | 'ontrack',
	phase = 'build',
	workouts: ReturnType<typeof wo>[] = [],
): ReplanWeek {
	const plannedMetres = 40_000;
	const actualMetres =
		drift === 'under' ? 26_000 : drift === 'over' ? 54_000 : 39_000;
	return { weekIndex, phase, plannedMetres, actualMetres, isComplete: true, workouts };
}

test('adaptiveReplanRemaining: on track when fewer than two weeks drift', () => {
	const weeks: ReplanWeek[] = [week(0, 'ontrack'), week(1, 'over'), week(2, 'ontrack')];
	const r = adaptiveReplanRemaining({ weeks, today: '2026-07-01' });
	assert.equal(r.reason, 'on_track');
	assert.equal(r.confidence, 'low');
	assert.equal(r.onTrack, true);
	assert.equal(r.changes.length, 0);
});

test('adaptiveReplanRemaining: a single noisy week does not trigger a trend', () => {
	const weeks: ReplanWeek[] = [week(0, 'ontrack'), week(1, 'ontrack'), week(2, 'under')];
	const r = adaptiveReplanRemaining({ weeks, today: '2026-07-01' });
	assert.equal(r.reason, 'on_track');
	assert.equal(r.changes.length, 0);
});

test('adaptiveReplanRemaining: two-of-three under weeks → trend_underfitness, medium confidence', () => {
	// Two under weeks + one on-track in the window; a missed long run gives
	// replanRemaining a safe future make-up to propose.
	const missed = wo('missed', '2026-06-15', 'long', 28_000, { isPast: true });
	const future = wo('next', '2026-07-06', 'long', 22_000);
	const weeks: ReplanWeek[] = [
		week(0, 'under', 'build', [missed]),
		week(1, 'ontrack'),
		week(2, 'under'),
		{ weekIndex: 3, phase: 'build', plannedMetres: 42_000, actualMetres: 0, isComplete: false, workouts: [future] },
	];
	const r = adaptiveReplanRemaining({ weeks, today: '2026-07-01' });
	assert.equal(r.reason, 'trend_underfitness');
	assert.equal(r.confidence, 'medium');
	assert.equal(r.onTrack, false);
	assert.equal(r.changes.some((c) => c.workoutId === 'next' && c.reason === 'make_up_long'), true);
});

test('adaptiveReplanRemaining: three-of-three under weeks → high confidence', () => {
	const missed = wo('missed', '2026-06-15', 'long', 28_000, { isPast: true });
	const future = wo('next', '2026-07-06', 'long', 22_000);
	const weeks: ReplanWeek[] = [
		week(0, 'under', 'build', [missed]),
		week(1, 'under'),
		week(2, 'under'),
		{ weekIndex: 3, phase: 'build', plannedMetres: 42_000, actualMetres: 0, isComplete: false, workouts: [future] },
	];
	const r = adaptiveReplanRemaining({ weeks, today: '2026-07-01' });
	assert.equal(r.reason, 'trend_underfitness');
	assert.equal(r.confidence, 'high');
});

test('adaptiveReplanRemaining: two-of-three over weeks → trend_overtraining with an ease-off change', () => {
	// Last completed week over → replanRemaining eases the next future
	// week's non-long workouts.
	const easy = wo('easy', '2026-07-07', 'easy', 8_000);
	const weeks: ReplanWeek[] = [
		week(0, 'over'),
		week(1, 'ontrack'),
		week(2, 'over'),
		{ weekIndex: 3, phase: 'build', plannedMetres: 42_000, actualMetres: 0, isComplete: false, workouts: [easy] },
	];
	const r = adaptiveReplanRemaining({ weeks, today: '2026-07-01' });
	assert.equal(r.reason, 'trend_overtraining');
	assert.equal(r.changes.some((c) => c.workoutId === 'easy' && c.reason === 'ease_over_running'), true);
});

test('adaptiveReplanRemaining: a flagged under-trend with no safe change stays change-free', () => {
	// Under-running easy volume with NO missed long run: the trend is real
	// but the safe rules cram nothing, so changes is empty / onTrack true.
	const weeks: ReplanWeek[] = [
		week(0, 'under'),
		week(1, 'under'),
		week(2, 'under'),
		{ weekIndex: 3, phase: 'build', plannedMetres: 42_000, actualMetres: 0, isComplete: false, workouts: [wo('f', '2026-07-06', 'easy', 8_000)] },
	];
	const r = adaptiveReplanRemaining({ weeks, today: '2026-07-01' });
	assert.equal(r.reason, 'trend_underfitness');
	assert.equal(r.changes.length, 0);
	assert.equal(r.onTrack, true);
});

test('adaptiveReplanRemaining: in-progress + zero-planned weeks are excluded from the window', () => {
	// Only one completed real week (under); the rest are in-progress or have
	// no planned volume → cannot reach the two-week quorum → on track.
	const weeks: ReplanWeek[] = [
		{ weekIndex: 0, phase: 'base', plannedMetres: 0, actualMetres: 30_000, isComplete: true, workouts: [] },
		week(1, 'under'),
		{ weekIndex: 2, phase: 'build', plannedMetres: 40_000, actualMetres: 12_000, isComplete: false, workouts: [] },
	];
	const r = adaptiveReplanRemaining({ weeks, today: '2026-07-01' });
	assert.equal(r.reason, 'on_track');
	assert.equal(r.trailingDirections.length, 1);
});

// ── P2: fitness direction gate (branch feat/gen-v2-p2-fitness, CISO-gated) ──

function underTrendWeeks(): ReplanWeek[] {
	const missed = wo('missed', '2026-06-15', 'long', 28_000, { isPast: true });
	const future = wo('next', '2026-07-06', 'long', 22_000);
	return [
		week(0, 'under', 'build', [missed]),
		week(1, 'under'),
		week(2, 'under'),
		{ weekIndex: 3, phase: 'build', plannedMetres: 42_000, actualMetres: 0, isComplete: false, workouts: [future] },
	];
}

test('adaptiveReplanRemaining: an under-fitness trend is suppressed for a fatigued runner (tsb<0)', () => {
	const r = adaptiveReplanRemaining({
		weeks: underTrendWeeks(),
		today: '2026-07-01',
		fitness: { tsb: -18, atl: 90, ctl: 72 },
	});
	assert.equal(r.reason, 'on_track');
	assert.equal(r.fitnessGated, true);
	assert.equal(r.changes.length, 0);
});

test('adaptiveReplanRemaining: an under-fitness trend proceeds for a fresh runner (tsb>=0)', () => {
	const r = adaptiveReplanRemaining({
		weeks: underTrendWeeks(),
		today: '2026-07-01',
		fitness: { tsb: 6, atl: 60, ctl: 66 },
	});
	assert.equal(r.reason, 'trend_underfitness');
	assert.equal(r.fitnessGated, false);
	assert.equal(r.changes.some((c) => c.workoutId === 'next'), true);
});

test('adaptiveReplanRemaining: an over-training trend is not fitness-gated even when fatigued', () => {
	const easy = wo('easy', '2026-07-07', 'easy', 8_000);
	const weeks: ReplanWeek[] = [
		week(0, 'over'),
		week(1, 'ontrack'),
		week(2, 'over'),
		{ weekIndex: 3, phase: 'build', plannedMetres: 42_000, actualMetres: 0, isComplete: false, workouts: [easy] },
	];
	const r = adaptiveReplanRemaining({ weeks, today: '2026-07-01', fitness: { tsb: -22, atl: 100, ctl: 78 } });
	assert.equal(r.reason, 'trend_overtraining');
	assert.equal(r.fitnessGated, false);
});

// ── P2 arm 2: the deep-fatigue deload override ──

/// Deeply fatigued: TSB past the -25 floor AND ATL ≥ 1.3 × CTL.
const DEEP = { tsb: -34, atl: 104, ctl: 70 };

/// An under-running trend whose next week holds BOTH a future long (the
/// make-up target) and a future easy run (the deload target), so a test can
/// tell the two directions apart by which workout moved.
function underTrendWeeksWithEasy(): ReplanWeek[] {
	const missed = wo('missed', '2026-06-15', 'long', 28_000, { isPast: true });
	const future = wo('next', '2026-07-06', 'long', 22_000);
	const easy = wo('easy', '2026-07-07', 'easy', 8_000);
	return [
		week(0, 'under', 'build', [missed]),
		week(1, 'under'),
		week(2, 'under'),
		{ weekIndex: 3, phase: 'build', plannedMetres: 42_000, actualMetres: 0, isComplete: false, workouts: [future, easy] },
	];
}

test('adaptiveReplanRemaining: deep fatigue overrides an on-track plan into a deload', () => {
	const easy = wo('easy', '2026-07-07', 'easy', 8_000);
	const weeks: ReplanWeek[] = [
		week(0, 'ontrack'),
		week(1, 'ontrack'),
		week(2, 'ontrack'),
		{ weekIndex: 3, phase: 'build', plannedMetres: 42_000, actualMetres: 0, isComplete: false, workouts: [easy] },
	];
	const r = adaptiveReplanRemaining({ weeks, today: '2026-07-01', fitness: DEEP });
	assert.equal(r.reason, 'deload_fatigue');
	assert.equal(r.confidence, 'high');
	assert.equal(r.onTrack, false);
	assert.deepEqual(
		r.changes.map((c) => [c.workoutId, c.fromMetres, c.toMetres]),
		[['easy', 8_000, 6_800]],
	);
});

test('adaptiveReplanRemaining: deep fatigue overrides an under-trend to a deload, never a make-up', () => {
	const r = adaptiveReplanRemaining({
		weeks: underTrendWeeksWithEasy(),
		today: '2026-07-01',
		fitness: DEEP,
	});
	assert.equal(r.reason, 'deload_fatigue');
	// The volume-adding make-up on the future long is NOT proposed…
	assert.equal(r.changes.some((c) => c.workoutId === 'next'), false);
	// …only the ease-off on the future easy run.
	assert.equal(r.changes.some((c) => c.workoutId === 'easy'), true);
});

test('adaptiveReplanRemaining: high acute load with shallow TSB does not deload', () => {
	// ACWR 100/70 = 1.43 (over the bar) but TSB -5 is a normal hard week.
	const r = adaptiveReplanRemaining({
		weeks: underTrendWeeksWithEasy(),
		today: '2026-07-01',
		fitness: { tsb: -5, atl: 100, ctl: 70 },
	});
	assert.notEqual(r.reason, 'deload_fatigue');
	assert.equal(r.fitnessGated, true);
	assert.equal(r.changes.length, 0);
});

test('adaptiveReplanRemaining: deeply negative TSB without high acute load does not deload', () => {
	// TSB -30 is past the floor, but ACWR 100/95 = 1.05 — a big, well-absorbed
	// block, not an acute spike.
	const r = adaptiveReplanRemaining({
		weeks: underTrendWeeksWithEasy(),
		today: '2026-07-01',
		fitness: { tsb: -30, atl: 100, ctl: 95 },
	});
	assert.notEqual(r.reason, 'deload_fatigue');
	assert.equal(r.fitnessGated, true);
});

test('adaptiveReplanRemaining: no chronic base (ctl 0) never deloads', () => {
	const r = adaptiveReplanRemaining({
		weeks: underTrendWeeksWithEasy(),
		today: '2026-07-01',
		fitness: { tsb: -60, atl: 60, ctl: 0 },
	});
	assert.notEqual(r.reason, 'deload_fatigue');
	assert.equal(r.fitnessGated, true);
});

test('adaptiveReplanRemaining: non-finite load values fail closed', () => {
	const r = adaptiveReplanRemaining({
		weeks: underTrendWeeksWithEasy(),
		today: '2026-07-01',
		fitness: { tsb: Number.NEGATIVE_INFINITY, atl: Number.POSITIVE_INFINITY, ctl: 70 },
	});
	assert.notEqual(r.reason, 'deload_fatigue');
	assert.equal(r.changes.length, 0);
});

test('adaptiveReplanRemaining: deep fatigue with only a taper week ahead proposes nothing', () => {
	const easy = wo('easy', '2026-07-07', 'easy', 8_000);
	const weeks: ReplanWeek[] = [
		week(0, 'ontrack'),
		week(1, 'ontrack'),
		week(2, 'ontrack'),
		{ weekIndex: 3, phase: 'taper', plannedMetres: 20_000, actualMetres: 0, isComplete: false, workouts: [easy] },
	];
	const r = adaptiveReplanRemaining({ weeks, today: '2026-07-01', fitness: DEEP });
	assert.equal(r.reason, 'deload_fatigue');
	assert.equal(r.changes.length, 0);
	assert.equal(r.onTrack, true);
});

test('adaptiveReplanRemaining: the fitness snapshot never leaves the function', () => {
	// Structural, not behavioural: the result carries no load number back to
	// the caller, and the module logs nothing — so a TSB cannot reach a log
	// line, a plan row, or the network. A stated condition of the P2 sign-off.
	const r = adaptiveReplanRemaining({
		weeks: underTrendWeeksWithEasy(),
		today: '2026-07-01',
		fitness: { tsb: -33.7, atl: 101.3, ctl: 71.9 },
	});
	const serialised = JSON.stringify(r);
	for (const leaked of ['33.7', '101.3', '71.9', 'tsb', 'atl', 'ctl']) {
		assert.equal(serialised.includes(leaked), false, `result leaked ${leaked}`);
	}
	const source = readFileSync(resolve('src/lib/training/plan_adaptive_replan.ts'), 'utf-8');
	const resultType = source.slice(
		source.indexOf('export interface AdaptiveReplanResult'),
		source.indexOf('/// Pure parse of the P2 fitness-gate deploy flag'),
	);
	assert.ok(resultType.length > 0, 'could not slice AdaptiveReplanResult — rename?');
	assert.equal(/\b(tsb|atl|ctl)\s*[:?]/.test(resultType), false,
		'AdaptiveReplanResult must not carry a load number back out');
	assert.equal(/\bconsole\s*\./.test(source), false, 'the module must not log');
});

test('adaptiveFitnessGateEnabled: unset / empty / negative values are off', () => {
	for (const raw of [undefined, null, '', '   ', 'false', '0', 'off', 'no', 'enabled', 'truthy']) {
		assert.equal(adaptiveFitnessGateEnabled(raw), false, `${JSON.stringify(raw)} must be off`);
	}
});

test('adaptiveFitnessGateEnabled: only an explicit affirmative turns it on', () => {
	for (const raw of ['1', 'true', 'yes', 'on', 'TRUE', ' On ', 'Yes']) {
		assert.equal(adaptiveFitnessGateEnabled(raw), true, `${JSON.stringify(raw)} must be on`);
	}
});
