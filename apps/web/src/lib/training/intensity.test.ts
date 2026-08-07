// Unit tests for the easy/hard intensity distribution. Run with:
//   npx tsx --test src/lib/training/intensity.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	computeIntensity,
	effortSegments,
	kHardVelocityFraction,
	kMinClassifiedRuns,
	kMinSegmentMetres,
	kMinSegmentSeconds,
	kOnGuidelineMinEasyShare,
} from './intensity';
import { currentVdot, thresholdPaceSecPerKmFromVdot } from './fitness';
import type { Run } from '../types';

const NOW = new Date('2026-06-17T10:00:00');

function r(partial: {
	started_at: string;
	distance_m: number;
	duration_s: number;
	source?: string;
	metadata?: Record<string, unknown> | null;
}): Run {
	return {
		id: 'r' + partial.started_at + partial.duration_s,
		user_id: 'u1',
		started_at: partial.started_at,
		distance_m: partial.distance_m,
		duration_s: partial.duration_s,
		source: partial.source ?? 'app',
		track_url: null,
		track: null,
		route_id: null,
		event_id: null,
		external_id: null,
		is_public: null,
		created_at: null,
		updated_at: null,
		metadata: partial.metadata ?? null,
	} as unknown as Run;
}

function daysAgoIso(n: number): string {
	return new Date(NOW.getTime() - n * 86_400_000).toISOString();
}

// 20:00 5K (4:00/km) — anchors VDOT ≈ 49.8, threshold ≈ 4:16/km, so the
// hard boundary (88% of threshold velocity) sits near 4:51/km.
function hardRun(daysAgo: number): Run {
	return r({ started_at: daysAgoIso(daysAgo), distance_m: 5000, duration_s: 1200 });
}

// 8 km at 6:40/km — comfortably below the boundary for that anchor.
function easyRun(daysAgo: number): Run {
	return r({ started_at: daysAgoIso(daysAgo), distance_m: 8000, duration_s: 3200 });
}

test('empty history returns null', () => {
	assert.equal(computeIntensity([], 56, NOW), null);
});

test('no derivable threshold (no qualifying run) returns null', () => {
	// Sub-1.5km runs never qualify, so no VDOT and no threshold.
	const runs = Array.from({ length: 6 }, (_, i) =>
		r({ started_at: daysAgoIso(i * 3), distance_m: 1000, duration_s: 600 }),
	);
	assert.equal(computeIntensity(runs, 56, NOW), null);
});

test('fewer classified runs than the floor returns null (self-hide)', () => {
	const runs = [hardRun(1), easyRun(5), easyRun(9)];
	assert.ok(runs.length < kMinClassifiedRuns);
	assert.equal(computeIntensity(runs, 56, NOW), null);
});

test('classifies easy vs hard by pace against the VDOT threshold', () => {
	const runs = [hardRun(1), easyRun(3), easyRun(8), easyRun(15), easyRun(22), easyRun(29)];
	const s = computeIntensity(runs, 56, NOW);
	assert.ok(s);
	assert.equal(s.totalRuns, 6);
	assert.equal(s.hardRuns, 1);
	assert.equal(s.easyRuns, 5);
	assert.equal(s.easySeconds, 5 * 3200);
	assert.equal(s.hardSeconds, 1200);
	// 16000 / 17200 = 93%.
	assert.equal(s.easyTimePct, 93);
	assert.equal(s.hardTimePct, 7);
	assert.equal(s.verdict, 'onGuideline');
});

test('the split is weighted by time, not by run count', () => {
	// One 3-hour easy run vs three 20-minute hard runs: only 25% of RUNS are
	// easy, but 75% of TIME is — the time share is what the card reports.
	const long = r({ started_at: daysAgoIso(2), distance_m: 16_000, duration_s: 10_800 });
	const s = computeIntensity([long, hardRun(4), hardRun(9), hardRun(14)], 56, NOW);
	assert.ok(s);
	assert.equal(s.easyRuns, 1);
	assert.equal(s.hardRuns, 3);
	assert.equal(s.easyTimePct, 75);
	// Exactly at the on-guideline floor pins the >= comparison.
	assert.equal(s.easySeconds / (s.easySeconds + s.hardSeconds), kOnGuidelineMinEasyShare);
	assert.equal(s.verdict, 'onGuideline');
});

test('mostly-hard time reads tooHard', () => {
	const s = computeIntensity(
		[easyRun(2), hardRun(4), hardRun(9), hardRun(14), hardRun(20)],
		56,
		NOW,
	);
	assert.ok(s);
	// 3200 easy / 8000 total = 40%.
	assert.equal(s.easyTimePct, 40);
	assert.equal(s.verdict, 'tooHard');
});

test('all-easy window reads allEasy (threshold may anchor outside the window)', () => {
	// The hard anchor is 70 days old: outside the 56-day classification
	// window but inside the 90-day VDOT window, so the threshold still
	// derives from it while only easy runs get classified.
	const runs = [hardRun(70), easyRun(3), easyRun(10), easyRun(17), easyRun(24)];
	const s = computeIntensity(runs, 56, NOW);
	assert.ok(s);
	assert.equal(s.totalRuns, 4);
	assert.equal(s.hardRuns, 0);
	assert.equal(s.easyTimePct, 100);
	assert.equal(s.verdict, 'allEasy');
});

test('runs outside the window are not classified', () => {
	const runs = [easyRun(1), easyRun(8), easyRun(15), easyRun(22), hardRun(60), hardRun(65)];
	const s = computeIntensity(runs, 56, NOW);
	assert.ok(s);
	assert.equal(s.totalRuns, 4);
	assert.equal(s.hardRuns, 0);
});

test('a run exactly at the boundary pace classifies hard (>=)', () => {
	const anchor = hardRun(1);
	const threshold = thresholdPaceSecPerKmFromVdot(currentVdot([anchor], NOW.getTime()));
	assert.ok(threshold != null);
	const boundaryPace = threshold / kHardVelocityFraction;
	const atBoundary = r({
		started_at: daysAgoIso(5),
		distance_m: 5000,
		duration_s: boundaryPace * 5,
	});
	const justSlower = r({
		started_at: daysAgoIso(9),
		distance_m: 5000,
		duration_s: boundaryPace * 5 + 60,
	});
	const s = computeIntensity([anchor, atBoundary, justSlower, easyRun(14)], 56, NOW);
	assert.ok(s);
	assert.equal(s.hardRuns, 2); // anchor + the exact-boundary run
	assert.equal(s.easyRuns, 2);
});

test('non-qualifying runs are excluded from both threshold and classification', () => {
	// A manual entry with a superhuman pace must not poison the threshold or
	// count toward the split.
	const manual = r({
		started_at: daysAgoIso(2),
		distance_m: 10_000,
		duration_s: 1200,
		source: 'manual',
	});
	const runs = [manual, hardRun(4), easyRun(8), easyRun(15), easyRun(22), easyRun(29)];
	const s = computeIntensity(runs, 56, NOW);
	assert.ok(s);
	assert.equal(s.totalRuns, 5);
	assert.equal(s.hardRuns, 1);
});

test('percentages are complementary and the threshold is reported', () => {
	const s = computeIntensity(
		[hardRun(1), easyRun(3), easyRun(8), easyRun(15), easyRun(22)],
		56,
		NOW,
	);
	assert.ok(s);
	assert.equal(s.easyTimePct + s.hardTimePct, 100);
	assert.ok(s.thresholdPaceSecPerKm > 0);
	assert.equal(s.windowWeeks, 8);
});

test('a non-positive window is rejected', () => {
	assert.equal(computeIntensity([hardRun(1)], 0, NOW), null);
});

// --- Per-segment classification (issue #676) ---------------------------------
//
// Against the `hardRun` anchor the threshold is ~256 s/km, so the hard boundary
// (threshold / 0.88) sits at ~291 s/km. Every fixture below is built from paces
// either side of that and the expected seconds are the fixture's own arithmetic.

/// A plan-executed VO2max session: 2 km warmup @6:00/km, 6x800m @3:45/km with
/// 400 m @7:30/km jog recoveries, 1.5 km cooldown @6:00/km. The reps run at
/// 225 s/km (well past the 291 s/km boundary); the whole-run average is
/// 319.6 s/km, which reads EASY — that dilution IS the bug.
const REP_SECONDS = 6 * 180;
const SESSION_SECONDS = 720 + REP_SECONDS + 6 * 180 + 540;
const SESSION_METRES = 2000 + 6 * 800 + 6 * 400 + 1500;

function step(kind: string, duration_s: number, actual_distance_m: number) {
	return {
		step_index: 0,
		kind,
		target_distance_m: actual_distance_m,
		actual_distance_m,
		target_pace_sec_per_km: Math.round(duration_s / (actual_distance_m / 1000)),
		actual_pace_sec_per_km: Math.round(duration_s / (actual_distance_m / 1000)),
		duration_s,
		status: 'completed' as const,
	};
}

function intervalSession(daysAgo: number): Run {
	const steps = [step('warmup', 720, 2000)];
	for (let i = 0; i < 6; i++) {
		steps.push(step('interval', 180, 800));
		steps.push(step('recovery', 180, 400));
	}
	steps.push(step('cooldown', 540, 1500));
	return r({
		started_at: daysAgoIso(daysAgo),
		distance_m: SESSION_METRES,
		duration_s: SESSION_SECONDS,
		metadata: { workout_step_results: steps },
	});
}

test('the whole-run average of an interval session really does read easy', () => {
	// Guards the fixture: without this, the test below could pass for the wrong
	// reason (a session whose mean was already hard).
	const session = intervalSession(3);
	const flat = r({
		started_at: session.started_at,
		distance_m: session.distance_m,
		duration_s: session.duration_s,
	});
	const s = computeIntensity([hardRun(1), flat, easyRun(8), easyRun(15)], 56, NOW);
	assert.ok(s);
	assert.equal(s.hardRuns, 1); // the anchor alone
	assert.equal(s.hardSeconds, 1200);
});

test('an interval session contributes its rep time to hard, not all of it to easy', () => {
	const s = computeIntensity([hardRun(1), intervalSession(3), easyRun(8), easyRun(15)], 56, NOW);
	assert.ok(s);
	assert.equal(s.totalRuns, 4);
	// The session joins the anchor as a hard session instead of an easy one.
	assert.equal(s.hardRuns, 2);
	assert.equal(s.easyRuns, 2);
	// Its 18 minutes of reps land in hard; its warmup, recoveries and cooldown
	// stay easy. Both halves of the same run are counted.
	assert.equal(s.hardSeconds, 1200 + REP_SECONDS);
	assert.equal(s.easySeconds, 2 * 3200 + (SESSION_SECONDS - REP_SECONDS));
});

test('run tallies still partition the classified runs', () => {
	const s = computeIntensity(
		[hardRun(1), intervalSession(3), intervalSession(6), easyRun(10), easyRun(17)],
		56,
		NOW,
	);
	assert.ok(s);
	assert.equal(s.easyRuns + s.hardRuns, s.totalRuns);
	assert.equal(s.totalRuns, 5);
});

test('marked laps segment a session that carries no workout steps', () => {
	// A fartlek the runner lapped by hand: 4 x (1 km @4:00/km hard, 1 km
	// @7:30/km easy). No plan link, so `laps` is the only breakdown there is.
	const laps = [];
	for (let i = 0; i < 4; i++) {
		laps.push({ index: laps.length + 1, start_offset_s: 0, distance_m: 1000, duration_s: 240 });
		laps.push({ index: laps.length + 1, start_offset_s: 0, distance_m: 1000, duration_s: 450 });
	}
	const fartlek = r({
		started_at: daysAgoIso(4),
		distance_m: 8000,
		duration_s: 4 * (240 + 450),
		metadata: { laps },
	});
	const s = computeIntensity([hardRun(1), fartlek, easyRun(9), easyRun(16)], 56, NOW);
	assert.ok(s);
	assert.equal(s.hardRuns, 2);
	assert.equal(s.hardSeconds, 1200 + 4 * 240);
	assert.equal(s.easySeconds, 2 * 3200 + 4 * 450);
});

test('workout steps win over laps when a run carries both', () => {
	// Same session, plus a single whole-run lap that would read easy on its own.
	const session = intervalSession(3);
	const both = r({
		started_at: session.started_at,
		distance_m: SESSION_METRES,
		duration_s: SESSION_SECONDS,
		metadata: {
			...(session.metadata as Record<string, unknown>),
			laps: [
				{ index: 1, start_offset_s: 0, distance_m: SESSION_METRES, duration_s: SESSION_SECONDS },
			],
		},
	});
	const s = computeIntensity([hardRun(1), both, easyRun(8), easyRun(15)], 56, NOW);
	assert.ok(s);
	assert.equal(s.hardSeconds, 1200 + REP_SECONDS);
});

test('time the breakdown leaves uncovered is classified at its own pace', () => {
	// 6 km of easy laps @7:30/km, then a 2 km finish @4:10/km the runner never
	// lapped. The residual is 500 s over 2000 m = 250 s/km — hard.
	const laps = Array.from({ length: 6 }, (_, i) => ({
		index: i + 1,
		start_offset_s: i * 450,
		distance_m: 1000,
		duration_s: 450,
	}));
	const fastFinish = r({
		started_at: daysAgoIso(4),
		distance_m: 8000,
		duration_s: 6 * 450 + 500,
		metadata: { laps },
	});
	const s = computeIntensity([hardRun(1), fastFinish, easyRun(9), easyRun(16)], 56, NOW);
	assert.ok(s);
	assert.equal(s.hardSeconds, 1200 + 500);
	assert.equal(s.easySeconds, 2 * 3200 + 6 * 450);
});

test('a sub-floor lap sliver cannot flip an easy run to hard', () => {
	// A double-tapped lap key leaves a 2 s / 5 m lap. Read on its own that is
	// 400 s/km... but the tap could equally land the other way, so the floor
	// keeps such slivers out of the per-slice classification entirely: they fall
	// into the residual, which here is the rest of a genuinely easy run.
	const easy = r({
		started_at: daysAgoIso(4),
		distance_m: 8000,
		duration_s: 3200,
		metadata: {
			laps: [
				{ index: 1, start_offset_s: 0, distance_m: 4000, duration_s: 1600 },
				{ index: 2, start_offset_s: 1600, distance_m: 5, duration_s: 2 },
				{ index: 3, start_offset_s: 1602, distance_m: 3995, duration_s: 1598 },
			],
		},
	});
	const s = computeIntensity([hardRun(1), easy, easyRun(9), easyRun(16)], 56, NOW);
	assert.ok(s);
	assert.equal(s.hardRuns, 1); // the anchor alone
	assert.equal(s.easyRuns, 3);
	// The sliver's 2 s is unattributable and is not invented into either bucket.
	assert.equal(s.easySeconds, 2 * 3200 + 1600 + 1598);
});

test('a steady run with laps stays one easy run', () => {
	// The regression that matters most: segmenting must not manufacture hard
	// time out of an ordinary lapped easy run.
	const lapped = r({
		started_at: daysAgoIso(4),
		distance_m: 8000,
		duration_s: 3200,
		metadata: {
			laps: Array.from({ length: 8 }, (_, i) => ({
				index: i + 1,
				start_offset_s: i * 400,
				distance_m: 1000,
				duration_s: 400,
			})),
		},
	});
	const s = computeIntensity([hardRun(1), lapped, easyRun(9), easyRun(16)], 56, NOW);
	assert.ok(s);
	assert.equal(s.hardRuns, 1);
	assert.equal(s.hardSeconds, 1200);
	assert.equal(s.easySeconds, 3 * 3200);
});

test('effortSegments falls back to the whole run without a usable breakdown', () => {
	const plain = easyRun(2);
	assert.deepEqual(effortSegments(plain), [{ seconds: 3200, metres: 8000 }]);

	// A schemaless bag can hold anything; none of these is a breakdown.
	for (const metadata of [
		{},
		{ laps: null },
		{ laps: [] },
		{ laps: 'nope' },
		{ laps: [null, 7, 'x'] },
		{ laps: [{ index: 1 }] },
		{ laps: [{ distance_m: 1000, duration_s: '450' }] },
		{ laps: [{ distance_m: Number.NaN, duration_s: 450 }] },
		{ workout_step_results: [{ duration_s: 180 }] },
	]) {
		const run = r({ started_at: daysAgoIso(2), distance_m: 8000, duration_s: 3200, metadata });
		assert.deepEqual(
			effortSegments(run),
			[{ seconds: 3200, metres: 8000 }],
			`unusable breakdown ${JSON.stringify(metadata)} should fall back to the whole run`,
		);
	}
});

test('effortSegments accepts a slice exactly at the floor', () => {
	const run = r({
		started_at: daysAgoIso(2),
		distance_m: 8000,
		duration_s: 3200,
		metadata: {
			laps: [{ index: 1, distance_m: kMinSegmentMetres, duration_s: kMinSegmentSeconds }],
		},
	});
	const segs = effortSegments(run);
	assert.equal(segs.length, 2); // the at-floor lap + the residual
	assert.deepEqual(segs[0], { seconds: kMinSegmentSeconds, metres: kMinSegmentMetres });
	assert.deepEqual(segs[1], {
		seconds: 3200 - kMinSegmentSeconds,
		metres: 8000 - kMinSegmentMetres,
	});
});

test('effortSegments drops a residual that would be negative', () => {
	// Laps summing past the run row's own totals (a re-imported/edited run)
	// must not produce a negative-duration segment.
	const run = r({
		started_at: daysAgoIso(2),
		distance_m: 4000,
		duration_s: 1600,
		metadata: {
			laps: [
				{ index: 1, distance_m: 3000, duration_s: 1200 },
				{ index: 2, distance_m: 3000, duration_s: 1200 },
			],
		},
	});
	const segs = effortSegments(run);
	assert.equal(segs.length, 2);
	assert.ok(segs.every((s) => s.seconds > 0 && s.metres > 0));
});
