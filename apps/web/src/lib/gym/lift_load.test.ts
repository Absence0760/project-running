import { test } from 'node:test';
import assert from 'node:assert/strict';
import { liftsFromSetHistory } from './lift_load';
import { computeTrainingLoadSeries } from '../training/training_load';

test('groups flat set rows by workout into LiftForLoad sessions', () => {
	const out = liftsFromSetHistory([
		{ workout_id: 'w1', started_at: '2026-06-03T08:00:00Z', reps: 5, weight_kg: 60, rpe: 8 },
		{ workout_id: 'w1', started_at: '2026-06-03T08:00:00Z', reps: 5, weight_kg: 60, rpe: null },
		{ workout_id: 'w2', started_at: '2026-06-01T18:00:00Z', reps: 8, weight_kg: 40, rpe: null },
	]);
	assert.equal(out.length, 2);
	const w1 = out.find((l) => l.started_at === '2026-06-03T08:00:00Z');
	assert.ok(w1);
	assert.equal(w1.sets.length, 2);
	assert.deepEqual(w1.sets[0], { reps: 5, weight_kg: 60, rpe: 8 });
});

test('drops rows with no workout date (cannot land on a calendar day)', () => {
	const out = liftsFromSetHistory([
		{ workout_id: 'w1', started_at: '', reps: 5, weight_kg: 60, rpe: 8 },
		{ workout_id: '', started_at: '2026-06-03T08:00:00Z', reps: 5, weight_kg: 60, rpe: 8 },
	]);
	assert.equal(out.length, 0);
});

test('grouped lifts raise the load series vs runs-only (separability holds)', () => {
	// End the window on a fixed day; put a heavy lift session yesterday.
	const end = new Date('2026-06-10T12:00:00Z');
	const lifts = liftsFromSetHistory([
		{ workout_id: 'w1', started_at: '2026-06-09T08:00:00Z', reps: 8, weight_kg: 100, rpe: 8 },
		{ workout_id: 'w1', started_at: '2026-06-09T08:00:00Z', reps: 8, weight_kg: 100, rpe: 8 },
		{ workout_id: 'w1', started_at: '2026-06-09T08:00:00Z', reps: 8, weight_kg: 100, rpe: 8 },
	]);
	const runsOnly = computeTrainingLoadSeries([], {}, 30, end, []);
	const withLifts = computeTrainingLoadSeries([], {}, 30, end, lifts);
	const liftDay = withLifts.find((p) => p.date === '2026-06-09');
	assert.ok(liftDay, 'window includes the lift day');
	assert.ok(liftDay.liftStress > 0, 'lift stress lands on its calendar day');
	assert.equal(liftDay.runStress, 0, 'no runs → run stress stays 0');
	// Run-only curve is recoverable unchanged (no lift bleed into it).
	assert.equal(runsOnly[runsOnly.length - 1].atl, 0);
	assert.ok(withLifts[withLifts.length - 1].atl > 0, 'lifts raise fatigue');
});
