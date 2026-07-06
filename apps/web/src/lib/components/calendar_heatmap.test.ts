import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { localDateKey, bucketRunsByLocalDay, heatScaleMax } from './calendar_heatmap';
import { formatISO } from '../training/training';
import type { Run } from '../types';

// These assertions only hold in a positive-offset timezone, which is where
// the UTC-vs-local bug bites. Guard so a CI runner left on UTC reports a
// clear skip instead of a confusing pass.
const offsetMin = -new Date('2026-01-15T23:30:00+05:00').getTimezoneOffset();

function makeRun(startedAt: string): Run {
	return { started_at: startedAt, distance_m: 1000 } as unknown as Run;
}

test('localDateKey buckets an early-morning UTC+ run under the LOCAL day, matching the cell key', { skip: offsetMin <= 0 }, () => {
	// Early-morning local time in a positive-offset zone is still the
	// previous calendar day in UTC: e.g. 02:00 local on the 16th in +05:30
	// is 20:30 UTC on the 15th. The runner's calendar (and the grid cell)
	// says the 16th; the naive UTC `.slice(0,10)` says the 15th — the bug.
	const localMorning = new Date('2026-01-16T02:00:00');
	const iso = localMorning.toISOString();
	const key = localDateKey(iso);
	const cellKey = formatISO(localMorning);
	assert.equal(key, cellKey, 'bucket key must equal the local cell key');
	// And the naive UTC slice would disagree (that's the bug).
	assert.notEqual(key, iso.slice(0, 10));
});

test('localDateKey equals formatISO(new Date(iso)) for any timestamp', () => {
	const iso = '2026-03-09T07:15:00.000Z';
	assert.equal(localDateKey(iso), formatISO(new Date(iso)));
});

test('bucketRunsByLocalDay sums distances under one local-day key', () => {
	const iso = '2026-03-09T07:15:00.000Z';
	const day = formatISO(new Date(iso));
	const map = bucketRunsByLocalDay([makeRun(iso), makeRun(iso)]);
	assert.equal(map.get(day), 2000);
	assert.equal(map.size, 1);
});

test('bucketRunsByLocalDay defaults to bucketing the full history (no cutoff)', () => {
	const map = bucketRunsByLocalDay([
		makeRun('2020-01-01T12:00:00.000Z'),
		makeRun('2026-06-08T12:00:00.000Z'),
	]);
	assert.equal(map.size, 2, 'with no cutoff every run is bucketed');
});

test('bucketRunsByLocalDay skips runs older than the window cutoff', () => {
	// perf-hunt 2026-06-10: the heatmap renders a fixed window, so the helper
	// must drop pre-window runs instead of bucketing (and spreading) the whole
	// history. Bounds both the loop's productive work and the returned map.
	const cutoffMs = new Date('2026-01-01T00:00:00.000Z').getTime();
	const map = bucketRunsByLocalDay(
		[makeRun('2020-01-01T12:00:00.000Z'), makeRun('2026-06-08T12:00:00.000Z')],
		cutoffMs,
	);
	assert.equal(map.size, 1, 'the pre-cutoff run must not be bucketed');
	assert.equal(
		map.has(formatISO(new Date('2020-01-01T12:00:00.000Z'))),
		false,
		'the out-of-window day key must be absent from the bounded map',
	);
});

test('bucketRunsByLocalDay keys match formatISO so cells light up', { skip: offsetMin <= 0 }, () => {
	const iso = new Date('2026-01-16T02:00:00').toISOString();
	const map = bucketRunsByLocalDay([makeRun(iso)]);
	// The grid cell for that local day is keyed by formatISO(date); it must
	// find the bucket. The UTC-slice key would miss it.
	const cellKey = formatISO(new Date('2026-01-16T02:00:00'));
	assert.ok(map.has(cellKey), 'local cell key must hit the bucket');
});

test('heatScaleMax returns 1 for empty or all-zero inputs', () => {
	assert.equal(heatScaleMax([]), 1);
	assert.equal(heatScaleMax([0, 0]), 1);
});

test('heatScaleMax equals the max for small samples', () => {
	assert.equal(heatScaleMax([5000]), 5000);
	assert.equal(heatScaleMax([3000, 8000]), 8000);
});

test('heatScaleMax ignores a single outlier long run in a full window', () => {
	// Nine ordinary 5 km days + one half-marathon: the scale should sit at
	// the ordinary volume so those days do not all collapse into the
	// lightest bucket.
	const days = [...Array.from({ length: 9 }, () => 5000), 21100];
	assert.equal(heatScaleMax(days), 5000);
});

test('heatScaleMax skips zero days when picking the percentile', () => {
	assert.equal(heatScaleMax([0, 0, 0, 4000, 6000]), 6000);
});
