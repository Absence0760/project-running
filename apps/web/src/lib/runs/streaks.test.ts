import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { computeRunStreaks } from './streaks';

// Helper: build a local-noon Date for a given local Y/M/D. We use
// noon (not midnight) to keep the test stable against fractional-hour
// TZ offsets — noon never falls on the wrong side of a day boundary.
function localNoon(y: number, m: number, d: number): Date {
	return new Date(y, m - 1, d, 12, 0, 0, 0);
}

test('computeRunStreaks: empty input → zero', () => {
	const out = computeRunStreaks([], localNoon(2026, 5, 13));
	assert.deepEqual(out, { current: 0, best: 0 });
});

test('computeRunStreaks: single run today → current=1, best=1', () => {
	const out = computeRunStreaks([localNoon(2026, 5, 13)], localNoon(2026, 5, 13));
	assert.deepEqual(out, { current: 1, best: 1 });
});

test('computeRunStreaks: multiple runs same day count once', () => {
	const out = computeRunStreaks(
		[
			localNoon(2026, 5, 13),
			new Date(2026, 4, 13, 7, 0, 0, 0),
			new Date(2026, 4, 13, 18, 0, 0, 0),
		],
		localNoon(2026, 5, 13),
	);
	assert.deepEqual(out, { current: 1, best: 1 });
});

test('computeRunStreaks: three-day streak ending today', () => {
	const out = computeRunStreaks(
		[
			localNoon(2026, 5, 11),
			localNoon(2026, 5, 12),
			localNoon(2026, 5, 13),
		],
		localNoon(2026, 5, 13),
	);
	assert.deepEqual(out, { current: 3, best: 3 });
});

test('computeRunStreaks: Strava grace — missing today but yesterday present', () => {
	// User ran yesterday, hasn't gone out yet today. Streak is still
	// alive — Strava's "you have until end of today to keep it going"
	// rule. Current reflects the streak ending at yesterday.
	const out = computeRunStreaks(
		[
			localNoon(2026, 5, 11),
			localNoon(2026, 5, 12),
		],
		localNoon(2026, 5, 13),
	);
	assert.deepEqual(out, { current: 2, best: 2 });
});

test('computeRunStreaks: two consecutive days missing breaks the streak', () => {
	// Ran 3 days ago and earlier — both today AND yesterday missing.
	// Current is 0; best preserves the historical 2-day run.
	const out = computeRunStreaks(
		[
			localNoon(2026, 5, 9),
			localNoon(2026, 5, 10),
		],
		localNoon(2026, 5, 13),
	);
	assert.deepEqual(out, { current: 0, best: 2 });
});

test('computeRunStreaks: best preserves a historical longer run', () => {
	// 5-day historical run, then a 2-day current run with a gap.
	const out = computeRunStreaks(
		[
			localNoon(2026, 4, 1),
			localNoon(2026, 4, 2),
			localNoon(2026, 4, 3),
			localNoon(2026, 4, 4),
			localNoon(2026, 4, 5),
			localNoon(2026, 5, 12),
			localNoon(2026, 5, 13),
		],
		localNoon(2026, 5, 13),
	);
	assert.deepEqual(out, { current: 2, best: 5 });
});

test('computeRunStreaks: future-dated runs are clamped to <= today', () => {
	// Phone clock skew sometimes stamps a run tomorrow. The helper
	// must ignore it — we don't want "current = 2" because of a
	// phantom day in the future.
	const out = computeRunStreaks(
		[
			localNoon(2026, 5, 13),
			localNoon(2026, 5, 14), // future
			localNoon(2026, 5, 15), // future
		],
		localNoon(2026, 5, 13),
	);
	assert.deepEqual(out, { current: 1, best: 1 });
});

test('computeRunStreaks: long single streak — current === best', () => {
	const days = 30;
	const runs: Date[] = [];
	for (let i = 0; i < days; i++) {
		runs.push(localNoon(2026, 4, 14 + i));
	}
	const out = computeRunStreaks(runs, localNoon(2026, 5, 13));
	// 30 days April 14 - May 13.
	assert.equal(out.current, days);
	assert.equal(out.best, days);
});

test('computeRunStreaks: input order does not matter', () => {
	const ordered = computeRunStreaks(
		[
			localNoon(2026, 5, 11),
			localNoon(2026, 5, 12),
			localNoon(2026, 5, 13),
		],
		localNoon(2026, 5, 13),
	);
	const shuffled = computeRunStreaks(
		[
			localNoon(2026, 5, 13),
			localNoon(2026, 5, 11),
			localNoon(2026, 5, 12),
		],
		localNoon(2026, 5, 13),
	);
	assert.deepEqual(ordered, shuffled);
});

test('computeRunStreaks: month boundary is consecutive', () => {
	// Apr 30 → May 1 must register as consecutive even though m+1.
	const out = computeRunStreaks(
		[localNoon(2026, 4, 30), localNoon(2026, 5, 1), localNoon(2026, 5, 13)],
		localNoon(2026, 5, 13),
	);
	assert.deepEqual(out, { current: 1, best: 2 });
});

test('computeRunStreaks: year boundary is consecutive', () => {
	const out = computeRunStreaks(
		[localNoon(2025, 12, 31), localNoon(2026, 1, 1)],
		localNoon(2026, 1, 1),
	);
	assert.deepEqual(out, { current: 2, best: 2 });
});

test('computeRunStreaks: gap of exactly one day breaks the streak', () => {
	// Ran today AND two days ago, but skipped yesterday entirely.
	// Strava grace covers exactly one *trailing* day (today missing).
	// A gap *inside* the streak breaks it.
	const out = computeRunStreaks(
		[localNoon(2026, 5, 11), localNoon(2026, 5, 13)],
		localNoon(2026, 5, 13),
	);
	assert.deepEqual(out, { current: 1, best: 1 });
});

// ─────────── DST safety ───────────

test('computeRunStreaks: spring-forward day + next day still register as consecutive', () => {
	// Mar 8 2026 is the US DST spring-forward (clocks 02:00 → 03:00,
	// so the day is 23 hours long). A naive `t - 86_400_000` would
	// land on the SAME day in DST-aware zones and silently miss the
	// consecutive-day match. The helper uses Y/M/D arithmetic, so
	// this test passes regardless of system TZ.
	const out = computeRunStreaks(
		[
			new Date(2026, 2, 8, 12, 0, 0, 0),
			new Date(2026, 2, 9, 12, 0, 0, 0),
		],
		new Date(2026, 2, 9, 12, 0, 0, 0),
	);
	assert.deepEqual(out, { current: 2, best: 2 });
});

test('computeRunStreaks: fall-back day + next day still register as consecutive', () => {
	// Nov 1 2026 is the US DST fall-back (25-hour day).
	const out = computeRunStreaks(
		[
			new Date(2026, 10, 1, 12, 0, 0, 0),
			new Date(2026, 10, 2, 12, 0, 0, 0),
		],
		new Date(2026, 10, 2, 12, 0, 0, 0),
	);
	assert.deepEqual(out, { current: 2, best: 2 });
});

test('streaks.ts is DST-safe: previousLocalDay uses Y/M/D arithmetic', () => {
	// Reason: subtracting milliseconds from a Date crosses a DST
	// boundary as a 23/25-hour day and silently misaligns the local-day
	// keys. The helper documents the gotcha; this guard pins it.
	const source = readFileSync(resolve('src/lib/runs/streaks.ts'), 'utf-8');
	assert.doesNotMatch(
		source,
		/\.getTime\(\)\s*-\s*(?:24\s*\*\s*60\s*\*\s*60\s*\*\s*1000|86_?400_?000)/,
		'previousLocalDay must not subtract 86_400_000 ms from a Date',
	);
	assert.match(
		source,
		/new Date\([^,]+\.getFullYear\(\),\s*[^,]+\.getMonth\(\),\s*[^,]+\.getDate\(\)\s*-\s*1\)/,
		'expected Y/M/D arithmetic in previousLocalDay',
	);
});
