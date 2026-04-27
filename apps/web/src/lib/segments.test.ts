import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { computeEffortFromTrack } from './segments';
import type { TrackPoint } from './types';

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
