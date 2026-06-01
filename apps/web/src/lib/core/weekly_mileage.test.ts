import { test } from 'node:test';
import assert from 'node:assert/strict';
import { bucketWeeklyMileage } from './weekly_mileage';

test('bucketWeeklyMileage — sums runs in the same Monday-week', () => {
	// 2026-01-05 is a Monday; the 7th is the same week.
	const out = bucketWeeklyMileage([
		{ started_at: '2026-01-05T08:00:00Z', distance_m: 5000 },
		{ started_at: '2026-01-07T08:00:00Z', distance_m: 3000 },
	]);
	assert.equal(out.length, 1);
	assert.equal(out[0].distance_m, 8000);
});

test('bucketWeeklyMileage — does NOT merge the same calendar week across years', () => {
	// The year-merge regression: a day/month-only key fused these two
	// distinct weeks (early-Jan 2025 and early-Jan 2026) into one bar.
	const out = bucketWeeklyMileage([
		{ started_at: '2025-01-06T08:00:00Z', distance_m: 4000 },
		{ started_at: '2026-01-06T08:00:00Z', distance_m: 6000 },
	]);
	assert.equal(out.length, 2, 'two different years must be two separate weeks');
	assert.deepEqual(
		out.map((w) => w.distance_m),
		[4000, 6000],
		'chronological order, not merged',
	);
});

test('bucketWeeklyMileage — caps to the most recent N weeks, chronological', () => {
	const runs = Array.from({ length: 20 }, (_, i) => ({
		// One run per week, Mondays stepping forward.
		started_at: new Date(Date.UTC(2026, 0, 5 + i * 7, 8)).toISOString(),
		distance_m: (i + 1) * 1000,
	}));
	const out = bucketWeeklyMileage(runs, 12);
	assert.equal(out.length, 12);
	// Last 12 of 20 → distances 9000..20000, ascending.
	assert.equal(out[0].distance_m, 9000);
	assert.equal(out[out.length - 1].distance_m, 20000);
});

test('bucketWeeklyMileage — sorts unsorted input chronologically', () => {
	const out = bucketWeeklyMileage([
		{ started_at: '2026-03-02T08:00:00Z', distance_m: 2000 },
		{ started_at: '2026-01-05T08:00:00Z', distance_m: 1000 },
	]);
	assert.deepEqual(
		out.map((w) => w.distance_m),
		[1000, 2000],
	);
});

test('bucketWeeklyMileage — empty input → empty output', () => {
	assert.deepEqual(bucketWeeklyMileage([]), []);
});

test('bucketWeeklyMileage — the week label honours the locale (W-10 label)', () => {
	// 2026-01-05 is a Monday → the week label is that date.
	const runs = [{ started_at: '2026-01-05T08:00:00Z', distance_m: 1000 }];
	const en = bucketWeeklyMileage(runs, 12, 'en-GB')[0].week;
	const ja = bucketWeeklyMileage(runs, 12, 'ja')[0].week;
	const de = bucketWeeklyMileage(runs, 12, 'de')[0].week;
	assert.match(en, /Jan/, 'en short month');
	assert.match(ja, /月/, 'ja uses CJK month marker');
	assert.doesNotMatch(ja, /Jan/);
	assert.notEqual(en, de, 'de differs from en-GB (5. Jan. vs 5 Jan)');
});

test('bucketWeeklyMileage — the bucket KEY stays locale-independent (no cross-locale split)', () => {
	const runs = [
		{ started_at: '2026-01-05T08:00:00Z', distance_m: 1000 },
		{ started_at: '2026-01-07T08:00:00Z', distance_m: 2000 },
	];
	// Same Monday-week regardless of label locale → one merged bar.
	const out = bucketWeeklyMileage(runs, 12, 'ja');
	assert.equal(out.length, 1);
	assert.equal(out[0].distance_m, 3000);
});
