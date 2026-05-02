import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	ageBandFor,
	buildPaceSegments,
	hasTrackTimestamps,
	paceBucketForSpeed,
} from './pace_segments';
import type { TrackPoint } from './types';

/// Mirror of `apps/mobile_android/test/pace_segments_test.dart`. Keep in
/// lockstep — the heatmap colours users see on web and on mobile come
/// from the same algorithm.

function straightTrack(opts: { points: number; stepM: number; stepS: number }): TrackPoint[] {
	const lng = -122;
	const t0 = Date.parse('2026-01-01T00:00:00Z');
	const degPerM = 1 / 111_320;
	const out: TrackPoint[] = [];
	for (let i = 0; i < opts.points; i++) {
		out.push({
			lat: 37 + i * opts.stepM * degPerM,
			lng,
			ts: new Date(t0 + i * opts.stepS * 1000).toISOString(),
		});
	}
	return out;
}

test('paceBucketForSpeed clamps below the slowest break to 0', () => {
	assert.equal(paceBucketForSpeed(0.1, 'run'), 0);
	assert.equal(paceBucketForSpeed(2.1, 'run'), 0);
});

test('paceBucketForSpeed clamps above the fastest break to length', () => {
	assert.equal(paceBucketForSpeed(99, 'run'), 5);
	assert.equal(paceBucketForSpeed(99, 'cycle'), 5);
});

test('paceBucketForSpeed scales with activity', () => {
	// 2.0 m/s sits in run bucket 0 (slowest) but walk bucket 4.
	assert.equal(paceBucketForSpeed(2.0, 'run'), 0);
	assert.equal(paceBucketForSpeed(2.0, 'walk'), 4);
});

test('ageBandFor partitions into thirds', () => {
	assert.equal(ageBandFor(0, 6), 0);
	assert.equal(ageBandFor(2, 6), 1);
	assert.equal(ageBandFor(4, 6), 2);
});

test('ageBandFor on a single segment returns the newest band', () => {
	assert.equal(ageBandFor(0, 1), 2);
});

test('buildPaceSegments returns [] for tracks under 2 points', () => {
	assert.deepEqual(buildPaceSegments([], 'run'), []);
	assert.deepEqual(buildPaceSegments([{ lat: 0, lng: 0 }], 'run'), []);
});

test('hasTrackTimestamps detects whether a heatmap is meaningful', () => {
	assert.equal(hasTrackTimestamps([]), false);
	assert.equal(hasTrackTimestamps([{ lat: 0, lng: 0 }]), false);
	assert.equal(
		hasTrackTimestamps([
			{ lat: 0, lng: 0 },
			{ lat: 0, lng: 0.0001 },
		]),
		false,
	);
	const t0 = new Date('2026-01-01T00:00:00Z').toISOString();
	const t1 = new Date('2026-01-01T00:00:01Z').toISOString();
	assert.equal(
		hasTrackTimestamps([
			{ lat: 0, lng: 0, ts: t0 },
			{ lat: 0, lng: 0.0001, ts: t1 },
		]),
		true,
	);
});

test('buildPaceSegments without timestamps falls back to slowest bucket', () => {
	const track: TrackPoint[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0.0001, lng: 0 },
	];
	const segs = buildPaceSegments(track, 'run');
	assert.equal(segs.length, 1);
	// Slowest bucket → red ramp colour, full alpha (single segment → newest band).
	assert.match(segs[0].color, /^rgba\(239,68,68,1\)$/);
});

test('buildPaceSegments coalesces a uniform-pace track into one polyline per age band', () => {
	// 11 points → 10 segments, all in the same pace bucket. With three
	// age bands, expect 3 polylines, each carrying the same hue but
	// monotonically-increasing alpha.
	const segs = buildPaceSegments(straightTrack({ points: 11, stepM: 3.3, stepS: 1 }), 'run');
	assert.equal(segs.length, 3);
	const hue = (c: string) => c.replace(/rgba\((\d+),(\d+),(\d+),[\d.]+\)/, '$1,$2,$3');
	const alpha = (c: string) => parseFloat(c.split(',').pop()!.replace(')', ''));
	assert.equal(hue(segs[0].color), hue(segs[1].color));
	assert.equal(hue(segs[1].color), hue(segs[2].color));
	assert.ok(alpha(segs[0].color) < alpha(segs[1].color));
	assert.ok(alpha(segs[1].color) < alpha(segs[2].color));
});

test('buildPaceSegments shares a vertex between adjacent runs', () => {
	// Build a track that crosses a bucket boundary in the middle.
	// 3 slow segments (1 m/s, bucket 0) then 3 fast (5 m/s, bucket 5).
	const t0 = Date.parse('2026-01-01T00:00:00Z');
	const degPerM = 1 / 111_320;
	const pts: TrackPoint[] = [];
	let cumLat = 37;
	let cumT = 0;
	for (let i = 0; i < 3; i++) {
		pts.push({ lat: cumLat, lng: -122, ts: new Date(t0 + cumT * 1000).toISOString() });
		cumLat += 1 * degPerM;
		cumT += 1;
	}
	for (let i = 0; i < 4; i++) {
		pts.push({ lat: cumLat, lng: -122, ts: new Date(t0 + cumT * 1000).toISOString() });
		cumLat += 5 * degPerM;
		cumT += 1;
	}
	const segs = buildPaceSegments(pts, 'run');
	// Slow run, fast run — the joining vertex appears in both polylines
	// so the map renders without a visible gap.
	assert.ok(segs.length >= 2);
	const last = segs[0].coords[segs[0].coords.length - 1];
	const first = segs[1].coords[0];
	assert.deepEqual(last, first);
});

test('buildPaceSegments emits rgba strings with descending alpha for older bands', () => {
	const track = straightTrack({ points: 9, stepM: 4, stepS: 1 });
	const segs = buildPaceSegments(track, 'run');
	const firstAlpha = parseFloat(segs[0].color.split(',').pop()!.replace(')', ''));
	const lastAlpha = parseFloat(segs[segs.length - 1].color.split(',').pop()!.replace(')', ''));
	assert.ok(firstAlpha < lastAlpha, `expected first alpha ${firstAlpha} < last ${lastAlpha}`);
});
