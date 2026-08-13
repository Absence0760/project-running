import { test } from 'node:test';
import assert from 'node:assert/strict';
import { freshnessFor, liveElapsedS, LIVE_STALE_AFTER_MS } from './live_freshness';

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

test('an age that cannot be established fails closed as stale, never fresh', () => {
	// `new Date(malformed).getTime()` is NaN, and every comparison against NaN
	// is false — so the old code reported `stale: false` (a green LIVE dot) plus
	// "Updated NaN days ago" for a runner whose position age is unknowable.
	for (const bad of [NaN, Infinity, -Infinity]) {
		const f = freshnessFor(bad, NOW);
		assert.equal(f.stale, true, `sentAtMs ${bad} must fail closed`);
		assert.equal(f.bucket, 'unknown');
		assert.equal(f.ageMs, null);
		assert.equal(f.value, null);
	}
});

test('a non-finite clock also fails closed rather than inverting the age', () => {
	for (const bad of [NaN, Infinity]) {
		const f = freshnessFor(NOW, bad);
		assert.equal(f.stale, true, `nowMs ${bad} must fail closed`);
		assert.equal(f.bucket, 'unknown');
	}
});

test('a finite ping is never routed into the unknown bucket', () => {
	// Guards the shape of the finite-check: a legitimately old but readable
	// ping must still bucket + report a number, not collapse into `unknown`.
	const old = freshnessFor(NOW - 400 * 24 * 3600_000, NOW);
	assert.equal(old.bucket, 'days');
	assert.equal(old.value, 400);
	assert.equal(old.stale, true);
	assert.equal(freshnessFor(0, NOW).bucket, 'days');
	assert.equal(freshnessFor(NOW, NOW).bucket, 'now');
});

function pick(f: { bucket: string; value: number | null }): [string, number | null] {
	return [f.bucket, f.value];
}

test('liveElapsedS advances the race clock by the ping age', () => {
	// A cut-off deadline runs on wall time. 40 min after the last ping the
	// runner has burned 40 min of their budget whether or not it reached us.
	assert.equal(liveElapsedS(3_600, 0), 3_600);
	assert.equal(liveElapsedS(3_600, 40 * 60_000), 3_600 + 2_400);
	// Sub-second remainders floor, matching the seconds-granularity readout.
	assert.equal(liveElapsedS(3_600, 1_999), 3_601);
});

test('liveElapsedS composes with a freshness age', () => {
	const NOW = 1_700_000_000_000;
	const f = freshnessFor(NOW - 5 * 60_000, NOW);
	assert.equal(f.stale, true);
	assert.equal(liveElapsedS(7_200, f.ageMs), 7_200 + 300);
});

test('liveElapsedS never rewinds the clock or invents time it cannot date', () => {
	// An age we cannot establish advances nothing — better the last known
	// figure than a guess. Same for a future-dated (clock-skewed) ping.
	assert.equal(liveElapsedS(3_600, null), 3_600);
	assert.equal(liveElapsedS(3_600, NaN), 3_600);
	assert.equal(liveElapsedS(3_600, -60_000), 3_600);
	// A nonsense anchor degrades to the ping age alone rather than propagating
	// NaN into the cut-off maths, where every comparison against it reads false.
	assert.equal(liveElapsedS(NaN, 60_000), 60);
	assert.equal(liveElapsedS(NaN, null), 0);
	assert.equal(liveElapsedS(-10, 60_000), 60);
});
