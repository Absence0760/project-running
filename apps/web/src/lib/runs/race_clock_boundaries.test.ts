// The spectator's two clocks, at every boundary the surface can reach.
//
// `/live/[id]` renders a race clock and a runner timer side by side, and
// before decisions.md § 712 it rendered one number under both meanings. The
// two quantities answer different questions and fail in different directions:
// the race clock is wall time from `started_at` and keeps running through a
// dead zone; the timer is the recorder's own stopwatch, frozen at the last
// fix and stopped for any stretch the runner explicitly paused.
//
// `live_freshness.test.ts` pins the happy path of each. This file pins the
// SEAMS between them — the ordering invariant that makes `liveElapsedS` a
// safe fallback, the withheld clock on a run with no conclusion instant, the
// clamps, and the flooring — because a cut-off verdict is computed off
// whichever of the two the page could resolve.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { freshnessFor, liveElapsedS, raceClockS, LIVE_STALE_AFTER_MS } from './live_freshness';

const NOW = Date.UTC(2026, 7, 31, 12, 0, 0);
const H = 3_600_000;

test('raceClockS floors to whole seconds and never rounds a clock up', () => {
	// A clock that rounds up states a second the runner has not yet spent,
	// which on a cut-off comparison is the wrong direction to be wrong in.
	assert.equal(raceClockS(NOW - 999, NOW), 0);
	assert.equal(raceClockS(NOW - 1_000, NOW), 1);
	assert.equal(raceClockS(NOW - 1_001, NOW), 1);
	assert.equal(raceClockS(NOW - 1_999, NOW), 1);
	assert.equal(raceClockS(NOW - 2_000, NOW), 2);
});

test('raceClockS clamps every future-stamped start to zero, not just the near ones', () => {
	// Clock skew is unbounded in principle: a phone with the year wrong stamps
	// a start decades ahead. Every one of these must read 0, and none may
	// return a negative clock that a downstream `secondsRemaining` would then
	// read as a cut-off already made.
	for (const skewMs of [1, 999, 1_000, 60_000, LIVE_STALE_AFTER_MS, 25 * H, 365 * 24 * H]) {
		assert.equal(raceClockS(NOW + skewMs, NOW), 0, `skew ${skewMs}`);
	}
});

test('raceClockS is exact over an ultra-length race, with no drift from the flooring', () => {
	// A 240-mile race runs past 100 hours. Seconds must still be seconds.
	const cutoffS = 112 * 3_600;
	assert.equal(raceClockS(NOW - cutoffS * 1_000, NOW), cutoffS);
	// And one second under the limit is one second under, not a rounded 112 h.
	assert.equal(raceClockS(NOW - (cutoffS - 1) * 1_000, NOW), cutoffS - 1);
});

test('a run that concluded before the conclusion marker existed withholds its race clock', () => {
	// § 712: a finished run measures to its conclusion instant. A row from
	// before `concluded_at` was written has no end to measure to — the page
	// passes null and the tile is WITHHELD. Measuring to `now` instead would
	// state a race clock that grows every second for a run that stopped
	// months ago.
	const startedAtMs = NOW - 3 * H;
	assert.equal(raceClockS(startedAtMs, null), null);
	// The distinction is load-bearing: the same start measured to a real
	// conclusion is a real figure, so `null` cannot be read as "no clock
	// exists for this run".
	assert.equal(raceClockS(startedAtMs, NOW - H), 2 * 3_600);
});

test('a concluded race clock is frozen — a later render of the same page reads the same', () => {
	const startedAtMs = NOW - 5 * H;
	const concludedAtMs = NOW - 2 * H;
	const first = raceClockS(startedAtMs, concludedAtMs);
	// The page's own second-tick advances `now`; the conclusion instant does
	// not move, so the tile must not either.
	const later = raceClockS(startedAtMs, concludedAtMs);
	assert.equal(first, 3 * 3_600);
	assert.equal(later, first);
	// ... whereas measuring to `now` would have ticked on.
	assert.notEqual(raceClockS(startedAtMs, NOW), first);
});

test('liveElapsedS is a LOWER BOUND on the race clock for a runner who paused', () => {
	// The recorder's stopwatch stops on an explicit manual pause, so the
	// timer under-reports wall time by exactly the paused stretch. The
	// fallback must therefore never overtake the clock it substitutes for —
	// a cut-off computed off it errs toward "you have less time than you
	// think", which is the safe direction.
	const startedAtMs = NOW - 6 * H;
	const raceClock = raceClockS(startedAtMs, NOW);
	assert.equal(raceClock, 6 * 3_600);
	for (const pausedS of [0, 1, 60, 900, 3 * 3_600, 6 * 3_600]) {
		for (const ageMs of [0, 5_000, 90_000, 18 * H]) {
			const anchorElapsedS = 6 * 3_600 - pausedS - Math.floor(ageMs / 1000);
			if (anchorElapsedS < 0) continue;
			const fallback = liveElapsedS(anchorElapsedS, ageMs);
			assert.ok(
				fallback <= (raceClock as number),
				`paused ${pausedS}s, age ${ageMs}ms: fallback ${fallback} > race clock ${raceClock}`,
			);
		}
	}
});

test('liveElapsedS credits only elapsed time, never distance, across an 18-hour dead zone', () => {
	// The Moab case § 712 was written for. The position is the last fix; only
	// the clock moves.
	const ageMs = 18 * H;
	const anchorElapsedS = 22 * 3_600;
	assert.equal(liveElapsedS(anchorElapsedS, ageMs), 22 * 3_600 + 18 * 3_600);
	// And the freshness of that fix says outright that the position is stale,
	// so nothing renders the advanced clock as a live position.
	const f = freshnessFor(NOW - ageMs, NOW);
	assert.equal(f.stale, true);
	assert.equal(f.bucket, 'hours');
});

test('liveElapsedS refuses to invent time from a broken anchor or a broken age', () => {
	// An anchor we cannot read contributes nothing, and the age is still
	// credited: 60 s is a lower bound on any clock, which is what this
	// fallback is allowed to claim. It must not become NaN, which every
	// downstream comparison would silently answer `false` to.
	assert.equal(liveElapsedS(Number.NaN, 60_000), 60);
	assert.equal(liveElapsedS(Number.POSITIVE_INFINITY, 60_000), 60);
	assert.equal(liveElapsedS(-500, 60_000), 60);
	assert.equal(liveElapsedS(Number.NaN, null), 0);
	assert.equal(liveElapsedS(120, null), 120);
	assert.equal(liveElapsedS(120, Number.NaN), 120);
	assert.equal(liveElapsedS(120, 0), 120);
	assert.equal(liveElapsedS(120, -1), 120);
	// A sub-second age adds nothing rather than rounding a second into being.
	assert.equal(liveElapsedS(120, 999), 120);
	assert.equal(liveElapsedS(120, 1_000), 121);
});

test('the two clocks disagree by exactly the paused stretch when the fix is current', () => {
	// With a fresh fix (age ~0) the only thing separating the timer from the
	// race clock is the pause. Stating that here is what makes the separate
	// tiles meaningful: they are not two renderings of one number.
	const pausedS = 47 * 60;
	const startedAtMs = NOW - 4 * H;
	const anchorElapsedS = 4 * 3_600 - pausedS;
	const raceClock = raceClockS(startedAtMs, NOW) as number;
	assert.equal(raceClock - liveElapsedS(anchorElapsedS, 0), pausedS);
});

test('raceClockS rejects every non-finite input rather than propagating NaN into a cut-off', () => {
	const bad = [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY];
	for (const b of bad) {
		assert.equal(raceClockS(b, NOW), null, `start ${b}`);
		assert.equal(raceClockS(NOW, b), null, `at ${b}`);
		assert.equal(raceClockS(b, b), null, `both ${b}`);
	}
	assert.equal(raceClockS(null, null), null);
	assert.equal(raceClockS(null, NOW), null);
	assert.equal(raceClockS(NOW, null), null);
});

test('a start equal to the measured instant is a zero clock, not a withheld one', () => {
	// The instant the recorder pre-creates the row. 0 is a real race clock and
	// must render as "0:00", not vanish.
	assert.equal(raceClockS(NOW, NOW), 0);
	assert.notEqual(raceClockS(NOW, NOW), null);
});

test('freshnessFor buckets on the exact second boundaries the labels claim', () => {
	const at = (ms: number) => freshnessFor(NOW - ms, NOW);
	assert.equal(at(9_999).bucket, 'now');
	assert.equal(at(10_000).bucket, 'seconds');
	assert.equal(at(10_000).value, 10);
	assert.equal(at(59_999).bucket, 'seconds');
	assert.equal(at(60_000).bucket, 'minutes');
	assert.equal(at(60_000).value, 1);
	assert.equal(at(59 * 60_000 + 59_999).bucket, 'minutes');
	assert.equal(at(60 * 60_000).bucket, 'hours');
	assert.equal(at(23 * H + 3_599_999).bucket, 'hours');
	assert.equal(at(24 * H).bucket, 'days');
	assert.equal(at(24 * H).value, 1);
});

test('freshnessFor goes stale AT the threshold, not one millisecond after it', () => {
	assert.equal(freshnessFor(NOW - (LIVE_STALE_AFTER_MS - 1), NOW).stale, false);
	assert.equal(freshnessFor(NOW - LIVE_STALE_AFTER_MS, NOW).stale, true);
	// A caller-supplied threshold behaves the same way at its own edge.
	assert.equal(freshnessFor(NOW - 4_999, NOW, 5_000).stale, false);
	assert.equal(freshnessFor(NOW - 5_000, NOW, 5_000).stale, true);
});

test('a stale fix still reports its measured age — the timer is qualified, not withheld', () => {
	// § 712: the page withholds PROJECTIONS off a stale fix and qualifies
	// MEASUREMENTS taken at it. So a stale freshness must still carry a
	// usable age for the "Timer, last fix" relabel.
	const f = freshnessFor(NOW - 6 * H, NOW);
	assert.equal(f.stale, true);
	assert.notEqual(f.ageMs, null);
	assert.equal(f.ageMs, 6 * H);
});
