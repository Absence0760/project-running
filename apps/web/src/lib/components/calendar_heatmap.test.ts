import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { localDateKey, bucketRunsByLocalDay } from './calendar_heatmap';
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

test('bucketRunsByLocalDay keys match formatISO so cells light up', { skip: offsetMin <= 0 }, () => {
	const iso = new Date('2026-01-16T02:00:00').toISOString();
	const map = bucketRunsByLocalDay([makeRun(iso)]);
	// The grid cell for that local day is keyed by formatISO(date); it must
	// find the bucket. The UTC-slice key would miss it.
	const cellKey = formatISO(new Date('2026-01-16T02:00:00'));
	assert.ok(map.has(cellKey), 'local cell key must hit the bucket');
});
