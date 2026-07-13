// Unit tests for the easy/hard intensity distribution. Run with:
//   npx tsx --test src/lib/training/intensity.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	computeIntensity,
	kHardVelocityFraction,
	kMinClassifiedRuns,
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
