import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
	computeEffortFromTrack,
	assignCompetitionRanks,
	crownLabel,
	SEGMENT_AGE_BANDS,
} from './segments';
import type { TrackPoint } from '../types';

/**
 * Synthesises a straight-line track at constant pace. Each step adds
 * roughly `stepM` of distance and `stepS` seconds. Lat advances along
 * a meridian (~111_320 m per degree) so haversine-cumulated distance
 * matches `(i * stepM)` to about half a metre.
 */
function straightTrack(opts: { points: number; stepM: number; stepS: number }): TrackPoint[] {
	const startLat = 37.0;
	const lng = -122.0;
	const out: TrackPoint[] = [];
	const t0 = Date.parse('2026-01-01T00:00:00Z');
	const degPerM = 1 / 111_320;
	for (let i = 0; i < opts.points; i++) {
		out.push({
			lat: startLat + i * opts.stepM * degPerM,
			lng,
			ts: new Date(t0 + i * opts.stepS * 1000).toISOString(),
		});
	}
	return out;
}

test('computes elapsed time over a clean segment', () => {
	const track = straightTrack({ points: 200, stepM: 5, stepS: 1 }); // 5 m/s = 200 s/km
	const eff = computeEffortFromTrack(track, { start_distance_m: 100, end_distance_m: 600 });
	assert.notEqual(eff, null);
	// 500 m at 5 m/s = 100 s, with sub-second interpolation slop.
	assert.ok(Math.abs(eff!.time_seconds - 100) < 1);
	assert.equal(typeof eff!.started_at, 'string');
});

test('returns null when the run is shorter than the segment end', () => {
	const track = straightTrack({ points: 50, stepM: 5, stepS: 1 }); // ~245 m
	const eff = computeEffortFromTrack(track, { start_distance_m: 0, end_distance_m: 1000 });
	assert.equal(eff, null);
});

test('returns null on tracks shorter than two points', () => {
	assert.equal(computeEffortFromTrack([], { start_distance_m: 0, end_distance_m: 100 }), null);
	assert.equal(
		computeEffortFromTrack([{ lat: 0, lng: 0, ts: '2026-01-01T00:00:00Z' }], {
			start_distance_m: 0,
			end_distance_m: 100,
		}),
		null,
	);
});

test('returns null when the segment window has zero or negative length', () => {
	const track = straightTrack({ points: 50, stepM: 5, stepS: 1 });
	assert.equal(computeEffortFromTrack(track, { start_distance_m: 100, end_distance_m: 100 }), null);
	assert.equal(computeEffortFromTrack(track, { start_distance_m: 200, end_distance_m: 100 }), null);
});

test('rejects sparse sampling (median step > segment / 5)', () => {
	// 10s sampling at 5 m/s = 50 m steps; segment of 100 m → ratio 50/100 = 0.5,
	// well above 0.2, so this should be rejected.
	const track = straightTrack({ points: 30, stepM: 50, stepS: 10 });
	const eff = computeEffortFromTrack(track, { start_distance_m: 100, end_distance_m: 200 });
	assert.equal(eff, null);
});

test('returns null when adjacent track points lack timestamps', () => {
	// Window 50–55m falls in the bracket [10, 11]. Stripping ts on
	// either end of that bracket should kill the interpolation.
	const track = straightTrack({ points: 50, stepM: 5, stepS: 1 });
	delete (track[10] as any).ts;
	delete (track[11] as any).ts;
	const eff = computeEffortFromTrack(track, { start_distance_m: 50, end_distance_m: 55 });
	assert.equal(eff, null);
});

test('interpolates start and end timestamps mid-segment', () => {
	// Segment endpoints fall between samples — interpolation should
	// land within the same fractional bracket.
	const track = straightTrack({ points: 200, stepM: 10, stepS: 2 }); // 5 m/s
	const eff = computeEffortFromTrack(track, { start_distance_m: 105, end_distance_m: 605 });
	assert.notEqual(eff, null);
	assert.ok(Math.abs(eff!.time_seconds - 100) < 1);
});

test('handles a track that passes the segment endpoints exactly at sample crossings', () => {
	const track = straightTrack({ points: 100, stepM: 10, stepS: 2 });
	const eff = computeEffortFromTrack(track, { start_distance_m: 100, end_distance_m: 500 });
	assert.notEqual(eff, null);
	assert.ok(Math.abs(eff!.time_seconds - 80) < 1);
});

// ─────────── assignCompetitionRanks ───────────

test('assignCompetitionRanks: empty input returns empty array', () => {
	assert.deepEqual(assignCompetitionRanks([]), []);
});

test('assignCompetitionRanks: distinct times yield 1..n', () => {
	const ranks = assignCompetitionRanks([
		{ time_seconds: 10 },
		{ time_seconds: 20 },
		{ time_seconds: 30 },
	]).map((r) => r.rank);
	assert.deepEqual(ranks, [1, 2, 3]);
});

test('assignCompetitionRanks: ties share a rank, next jumps to ordinal slot', () => {
	const ranks = assignCompetitionRanks([
		{ time_seconds: 10 },
		{ time_seconds: 10 },
		{ time_seconds: 15 },
		{ time_seconds: 15 },
		{ time_seconds: 20 },
	]).map((r) => r.rank);
	assert.deepEqual(ranks, [1, 1, 3, 3, 5]);
});

test('assignCompetitionRanks: leading tie of three rows shares rank 1', () => {
	const ranks = assignCompetitionRanks([
		{ time_seconds: 60 },
		{ time_seconds: 60 },
		{ time_seconds: 60 },
		{ time_seconds: 65 },
	]).map((r) => r.rank);
	assert.deepEqual(ranks, [1, 1, 1, 4]);
});

test('assignCompetitionRanks: rank=0 time does not collide with NaN seed', () => {
	// Regression: an initial lastTime sentinel of -1 would have made a
	// 0-second effort match the seed and inherit rank 0 from lastRank.
	// We seed with NaN, which never === any number, so the first row
	// always gets rank 1.
	const ranks = assignCompetitionRanks([
		{ time_seconds: 0 },
		{ time_seconds: 0 },
		{ time_seconds: 5 },
	]).map((r) => r.rank);
	assert.deepEqual(ranks, [1, 1, 3]);
});

test('assignCompetitionRanks: preserves the original row payload', () => {
	const rows = [
		{ time_seconds: 10, id: 'a', extra: 'x' },
		{ time_seconds: 10, id: 'b', extra: 'y' },
	];
	const out = assignCompetitionRanks(rows);
	assert.equal(out[0].row.id, 'a');
	assert.equal(out[1].row.id, 'b');
	assert.equal(out[0].row.extra, 'x');
});

// ─────────── SEGMENT_AGE_BANDS shape ───────────

test('SEGMENT_AGE_BANDS: 13 entries (Strava 5-year bins from 18 to 75+)', () => {
	assert.equal(SEGMENT_AGE_BANDS.length, 13);
});

test('SEGMENT_AGE_BANDS: starts at 18-19 and ends at 75+', () => {
	assert.equal(SEGMENT_AGE_BANDS[0], '18-19');
	assert.equal(SEGMENT_AGE_BANDS[SEGMENT_AGE_BANDS.length - 1], '75+');
});

test('SEGMENT_AGE_BANDS: every entry matches the RPC parser', () => {
	// `segment_leaderboard_tiered` only accepts '75+' or '\d+-\d+'; any
	// other shape raises 22023. The unit-test pins the client-side list
	// against that contract so a typo can't get past PR review.
	for (const band of SEGMENT_AGE_BANDS) {
		assert.ok(band === '75+' || /^\d+-\d+$/.test(band), `band ${band} would crash the RPC`);
	}
});

test('SEGMENT_AGE_BANDS: contiguous 5-year bins between the bookends', () => {
	for (let i = 0; i < SEGMENT_AGE_BANDS.length - 1; i++) {
		const band = SEGMENT_AGE_BANDS[i];
		if (band === '75+') continue;
		const [lo, hi] = band.split('-').map((s) => parseInt(s, 10));
		// First bin is 18-19 (a 2-year bin); the rest must be 5-year
		// bins where (hi - lo) === 4 and lo % 5 === 0.
		if (band === '18-19') {
			assert.equal(lo, 18);
			assert.equal(hi, 19);
			continue;
		}
		assert.equal(hi - lo, 4, `band ${band} not a 5-year bin`);
		assert.equal(lo % 5, 0, `band ${band} not anchored on a multiple of 5`);
	}
});

// ─────────── assignCompetitionRanks — additional edge cases ───────────

test('assignCompetitionRanks: single element gets rank 1', () => {
	const ranks = assignCompetitionRanks([{ time_seconds: 42 }]).map((r) => r.rank);
	assert.deepEqual(ranks, [1]);
});

test('assignCompetitionRanks: every row tied still produces all rank 1', () => {
	const ranks = assignCompetitionRanks([
		{ time_seconds: 100 },
		{ time_seconds: 100 },
		{ time_seconds: 100 },
		{ time_seconds: 100 },
	]).map((r) => r.rank);
	assert.deepEqual(ranks, [1, 1, 1, 1]);
});

test('assignCompetitionRanks: tie cluster in the middle', () => {
	const ranks = assignCompetitionRanks([
		{ time_seconds: 50 },
		{ time_seconds: 60 },
		{ time_seconds: 60 },
		{ time_seconds: 60 },
		{ time_seconds: 75 },
	]).map((r) => r.rank);
	assert.deepEqual(ranks, [1, 2, 2, 2, 5]);
});

test('assignCompetitionRanks: alternating ties', () => {
	const ranks = assignCompetitionRanks([
		{ time_seconds: 10 },
		{ time_seconds: 10 },
		{ time_seconds: 20 },
		{ time_seconds: 30 },
		{ time_seconds: 30 },
	]).map((r) => r.rank);
	assert.deepEqual(ranks, [1, 1, 3, 4, 4]);
});

test('assignCompetitionRanks: floating-point times compared by strict equality', () => {
	const ranks = assignCompetitionRanks([
		{ time_seconds: 10.5 },
		{ time_seconds: 10.5 },
		{ time_seconds: 10.5000001 },
	]).map((r) => r.rank);
	assert.deepEqual(ranks, [1, 1, 3]);
});

test('assignCompetitionRanks: 1000-row input is O(n) and well-formed', () => {
	const rows: Array<{ time_seconds: number }> = [];
	for (let i = 0; i < 1000; i++) rows.push({ time_seconds: i });
	const t0 = Date.now();
	const out = assignCompetitionRanks(rows);
	const dt = Date.now() - t0;
	assert.equal(out.length, 1000);
	assert.equal(out[0].rank, 1);
	assert.equal(out[999].rank, 1000);
	assert.ok(dt < 50, `rank pass took ${dt} ms (expected < 50)`);
});

// ─────────── SEGMENT_AGE_BANDS — vs the RPC's regex ───────────

test('SEGMENT_AGE_BANDS: every band the RPC parser accepts', () => {
	// The plpgsql RPC accepts `^[0-9]+-[0-9]+$` OR the literal '75+'.
	// Read the migration and assert every age band matches the regex
	// the RPC will run against it — catches drift between the client
	// list and the server parser.
	const sql = readFileSync(
		resolve(
			'../backend/supabase/migrations/20260829_001_segments_v2_tiered_leaderboards.sql',
		),
		'utf-8',
	);
	const m = sql.match(/p_age_band\s*~\s*'(\^[^']+\$)'/);
	assert.ok(m, 'could not extract age-band regex from migration');
	const rpcAccepts = new RegExp(m![1]);
	for (const band of SEGMENT_AGE_BANDS) {
		assert.ok(
			band === '75+' || rpcAccepts.test(band),
			`band '${band}' would be rejected by the RPC's regex /${m![1]}/`,
		);
	}
});

// ─────────── crownLabel ───────────

test('crownLabel: no filter → "Fastest overall"', () => {
	assert.equal(crownLabel(null, null), 'Fastest overall');
});

test('crownLabel: gender only', () => {
	assert.equal(crownLabel('male', null), 'Fastest man');
	assert.equal(crownLabel('female', null), 'Fastest woman');
	assert.equal(crownLabel('nonbinary', null), 'Fastest nonbinary runner');
});

test('crownLabel: age band only', () => {
	assert.equal(crownLabel(null, '35-39'), 'Fastest 35-39');
	assert.equal(crownLabel(null, '75+'), 'Fastest 75+');
});

test('crownLabel: gender + age band combined', () => {
	assert.equal(crownLabel('female', '30-34'), 'Fastest woman 30-34');
	assert.equal(crownLabel('male', '75+'), 'Fastest man 75+');
	assert.equal(
		crownLabel('nonbinary', '18-19'),
		'Fastest nonbinary runner 18-19',
	);
});
