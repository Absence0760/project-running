import { test } from 'node:test';
import assert from 'node:assert/strict';
import { freshnessFor, LIVE_STALE_AFTER_MS } from './live_freshness';

const NOW = 1_700_000_000_000;

test('a future-dated ping (clock skew) clamps to age 0, never negative', () => {
	const f = freshnessFor(NOW + 5_000, NOW);
	assert.equal(f.ageMs, 0);
	assert.equal(f.stale, false);
	assert.equal(f.bucket, 'now');
});

test('stale threshold is inclusive at the boundary', () => {
	const justFresh = freshnessFor(NOW - (LIVE_STALE_AFTER_MS - 1), NOW);
	assert.equal(justFresh.stale, false, 'one ms under the threshold is still fresh');
	const justStale = freshnessFor(NOW - LIVE_STALE_AFTER_MS, NOW);
	assert.equal(justStale.stale, true, 'exactly at the threshold is stale');
});

test('a long no-signal stretch is honestly stale, not a fresh LIVE dot', () => {
	const eighteenHours = freshnessFor(NOW - 18 * 3600_000, NOW);
	assert.equal(eighteenHours.stale, true);
	assert.equal(eighteenHours.bucket, 'hours');
	assert.equal(eighteenHours.value, 18);
});

test('bucket boundaries', () => {
	assert.deepEqual(pick(freshnessFor(NOW - 9_000, NOW)), ['now', 0]);
	assert.deepEqual(pick(freshnessFor(NOW - 10_000, NOW)), ['seconds', 10]);
	assert.deepEqual(pick(freshnessFor(NOW - 59_000, NOW)), ['seconds', 59]);
	assert.deepEqual(pick(freshnessFor(NOW - 60_000, NOW)), ['minutes', 1]);
	assert.deepEqual(pick(freshnessFor(NOW - 59 * 60_000, NOW)), ['minutes', 59]);
	assert.deepEqual(pick(freshnessFor(NOW - 3600_000, NOW)), ['hours', 1]);
	assert.deepEqual(pick(freshnessFor(NOW - 23 * 3600_000, NOW)), ['hours', 23]);
	assert.deepEqual(pick(freshnessFor(NOW - 24 * 3600_000, NOW)), ['days', 1]);
	assert.deepEqual(pick(freshnessFor(NOW - 50 * 3600_000, NOW)), ['days', 2]);
});

test('an exactly-now ping reads as fresh "now"', () => {
	const f = freshnessFor(NOW, NOW);
	assert.equal(f.ageMs, 0);
	assert.equal(f.bucket, 'now');
	assert.equal(f.stale, false);
});

function pick(f: { bucket: string; value: number }): [string, number] {
	return [f.bucket, f.value];
}
