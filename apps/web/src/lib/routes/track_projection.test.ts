import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { projectTrack } from './track_projection';
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
