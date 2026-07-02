import { test } from 'node:test';
import assert from 'node:assert/strict';
import { adaptiveReplanRemaining } from './plan_adaptive_replan';
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
