import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	isTrackRenderable,
	MIN_RENDERABLE_SPAN_M,
	projectTrack,
} from './track_projection';
import type { TrackPoint } from '../types';

/// Mirror of `apps/mobile_android/test/track_preview_test.dart`'s
/// `projectTrack` group. The mobile and web thumbnails share the
/// projection so a route saved on the web shows the same shape on
/// the mobile list — keep the two test suites in lockstep.

test('projectTrack returns [] for tracks under 2 points', () => {
	assert.deepEqual(projectTrack([], 100, 100), []);
	assert.deepEqual(projectTrack([{ lat: 0, lng: 0 }], 100, 100), []);
});

test('a square 100 m loop at 51 °N renders square, not a stretched rectangle', () => {
	const dLat = 100 / 111_320;
	// 100 m / (111_320 * cos(51°)) per longitude degree.
	const dLng = 100 / (111_320 * 0.629320391); // cos(51°) ≈ 0.629
	const points: TrackPoint[] = [
		{ lat: 51.5074, lng: -0.1278 },
		{ lat: 51.5074 + dLat, lng: -0.1278 },
		{ lat: 51.5074 + dLat, lng: -0.1278 + dLng },
		{ lat: 51.5074, lng: -0.1278 + dLng },
		{ lat: 51.5074, lng: -0.1278 },
	];
	const projected = projectTrack(points, 240, 100);
	let minX = projected[0].x,
		maxX = projected[0].x,
		minY = projected[0].y,
		maxY = projected[0].y;
	for (const p of projected) {
		if (p.x < minX) minX = p.x;
		if (p.x > maxX) maxX = p.x;
		if (p.y < minY) minY = p.y;
		if (p.y > maxY) maxY = p.y;
	}
	const width = maxX - minX;
	const height = maxY - minY;
	// Without the cos correction this loop would render ~60 % wider
	// than tall — exactly what users were seeing on the new mobile
	// thumbnails before this fix landed.
	assert.ok(
		Math.abs(width - height) / height < 0.02,
		`A 100 m × 100 m loop at 51 °N must render square. width=${width} height=${height}`,
	);
});

test('preserves the diagonal length of a degenerate horizontal segment', () => {
	const projected = projectTrack(
		[
			{ lat: 0, lng: 0 },
			{ lat: 0, lng: 0.01 },
		],
		100,
		100,
	);
	assert.equal(projected.length, 2);
	assert.ok(Math.abs(projected[0].y - projected[1].y) < 1e-6);
});

test('honours custom pad value', () => {
	// With pad = 0 the projected box should fill the entire viewBox
	// modulo the smaller scale axis. With pad = 20 the box shrinks.
	const points: TrackPoint[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0.001, lng: 0.001 },
	];
	const tight = projectTrack(points, 100, 100, 0);
	const padded = projectTrack(points, 100, 100, 20);
	const tightSpan = Math.abs(tight[1].x - tight[0].x);
	const paddedSpan = Math.abs(padded[1].x - padded[0].x);
	assert.ok(paddedSpan < tightSpan, `padded ${paddedSpan} should be < tight ${tightSpan}`);
});

test('a track across the antimeridian fits its own width, not the whole world', () => {
	// A 0.01° x 0.01° box straddling the line. Its longitudes span 0.01°,
	// not the 359.99° a raw min/max reads, so the fit is the same one the
	// identical box a degree west of the line gets.
	const across: TrackPoint[] = [
		{ lat: 0, lng: 179.995 },
		{ lat: 0.01, lng: 179.995 },
		{ lat: 0.01, lng: -179.995 },
		{ lat: 0, lng: -179.995 },
	];
	const west: TrackPoint[] = [
		{ lat: 0, lng: 178.995 },
		{ lat: 0.01, lng: 178.995 },
		{ lat: 0.01, lng: 179.005 },
		{ lat: 0, lng: 179.005 },
	];
	const a = projectTrack(across, 100, 100);
	const w = projectTrack(west, 100, 100);
	assert.equal(a.length, 4);
	for (let i = 0; i < a.length; i++) {
		assert.ok(Math.abs(a[i].x - w[i].x) < 1e-6, `x[${i}] ${a[i].x} vs ${w[i].x}`);
		assert.ok(Math.abs(a[i].y - w[i].y) < 1e-6, `y[${i}] ${a[i].y} vs ${w[i].y}`);
	}
	// And the box actually uses the panel rather than collapsing to a dot.
	assert.ok(Math.abs(a[2].x - a[0].x) > 50, `span ${Math.abs(a[2].x - a[0].x)}`);
});

test('isTrackRenderable rejects empty, single-point, and sub-5 m jitter tracks', () => {
	assert.equal(isTrackRenderable([]), false);
	assert.equal(isTrackRenderable([{ lat: 51.5074, lng: -0.1278 }]), false);
	// ~1 m diagonal — GPS noise from a stationary device.
	assert.equal(
		isTrackRenderable([
			{ lat: 51.5074, lng: -0.1278 },
			{ lat: 51.5074009, lng: -0.1278009 },
		]),
		false,
	);
});

test('the renderable gate sits exactly at the named span', () => {
	// Two claims, failing to different mutations. The VALUE is pinned flat
	// because the number is one of three rails — the Dart twin's
	// `kMinRenderableSpanM` and the firmware's `MIN_RENDERABLE_SPAN_M` —
	// held together by check_watch_wire_vectors.mjs, which can only read a
	// rail whose constant is named.
	assert.equal(MIN_RENDERABLE_SPAN_M, 5);
	// And the constant is the number actually COMPARED, not one declared
	// beside a literal that has drifted from it. A degree of latitude is
	// 111,320 m under the same flat approximation the gate uses, so these
	// two tracks bracket the threshold from either side by 1 cm.
	const deg = (m: number) => m / 111_320;
	assert.equal(
		isTrackRenderable([
			{ lat: 0, lng: 0 },
			{ lat: deg(MIN_RENDERABLE_SPAN_M - 0.01), lng: 0 },
		]),
		false,
	);
	assert.equal(
		isTrackRenderable([
			{ lat: 0, lng: 0 },
			{ lat: deg(MIN_RENDERABLE_SPAN_M + 0.01), lng: 0 },
		]),
		true,
	);
});

test('isTrackRenderable accepts a tiny but genuine lap', () => {
	// ~14 m diagonal — small but real.
	assert.equal(
		isTrackRenderable([
			{ lat: 51.5074, lng: -0.1278 },
			{ lat: 51.50749, lng: -0.12781 },
		]),
		true,
	);
});

test('isTrackRenderable rejects a stationary jitter cluster on the antimeridian', () => {
	// ~2 m of jitter straddling 180°. The raw min/max span read 359.99°
	// (~40,000 km), so the gate passed exactly the standing-still case it
	// exists to catch and the thumbnail drew the meaningless dot.
	assert.equal(
		isTrackRenderable([
			{ lat: 0, lng: 179.999992 },
			{ lat: 0, lng: -179.999992 },
			{ lat: 0.000009, lng: 179.999995 },
		]),
		false,
	);
});

test('isTrackRenderable accepts a genuine run crossing the antimeridian', () => {
	assert.equal(
		isTrackRenderable([
			{ lat: 0, lng: 179.9995 },
			{ lat: 0, lng: -179.9995 },
		]),
		true,
	);
});
