// Pure projection helper for the SVG track-preview thumbnails. Lives in
// its own module so the cos(midLat) correction can be unit-tested
// without spinning up a Svelte component. Mirrors `projectTrack` in
// `apps/mobile_android/lib/widgets/track_preview.dart` — keep them in
// lockstep.

import type { TrackPoint } from '../types';
import { unwrapLonDeg } from './geo';

export interface Projected {
	x: number;
	y: number;
}

/// Project `points` into a `[0, vbW] × [0, vbH]` viewBox with a
/// `cos(midLat)` longitude correction so a square loop at any latitude
/// renders square instead of a horizontally-stretched rectangle.
///
/// `pad` is the inset margin on every side of the viewBox (default 4).
/// Returns an empty array for tracks with fewer than two points.
export function projectTrack(
	points: TrackPoint[],
	vbW: number,
	vbH: number,
	pad = 4,
): Projected[] {
	if (points.length < 2) return [];
	// Longitudes are expressed on the first point's side of the antimeridian,
	// so a track that crosses it spans its own width instead of ~360° (which
	// collapsed the fitted scale to a dot). Identity inside a hemisphere.
	const refLng = points[0].lng;
	let minLat = points[0].lat;
	let maxLat = points[0].lat;
	let minLng = refLng;
	let maxLng = refLng;
	for (const p of points) {
		if (p.lat < minLat) minLat = p.lat;
		if (p.lat > maxLat) maxLat = p.lat;
		const lng = unwrapLonDeg(refLng, p.lng);
		if (lng < minLng) minLng = lng;
		if (lng > maxLng) maxLng = lng;
	}
	// A degree of longitude is shorter than a degree of latitude
	// everywhere except the equator — at 51 °N (London) it's only ~62 %
	// of a latitude degree. Scaling lng by cos(midLat) projects the
	// bounding box into equal-distance units.
	const midLat = (minLat + maxLat) / 2;
	const lngScale = Math.abs(Math.cos((midLat * Math.PI) / 180));
	// A degenerate or non-finite span collapses to the epsilon rather than
	// producing an absurd scale. `|| 1e-6` alone was falsy-only, so it caught an
	// exact 0 but let a 1e-7 span through at a 10x different scale from the Dart
	// twin's `max(span, 1e-6)`; `max` alone propagated NaN, which `||` absorbed.
	// Both sides now clamp AND reject non-finite, so neither failure remains.
	const dLat = spanOrEpsilon(maxLat - minLat);
	const dLng = spanOrEpsilon((maxLng - minLng) * lngScale);
	const scaleX = (vbW - pad * 2) / dLng;
	const scaleY = (vbH - pad * 2) / dLat;
	const scale = Math.min(scaleX, scaleY);
	const offX = pad + (vbW - pad * 2 - dLng * scale) / 2;
	const offY = pad + (vbH - pad * 2 - dLat * scale) / 2;
	const out: Projected[] = [];
	for (const p of points) {
		out.push({
			x: offX + (unwrapLonDeg(refLng, p.lng) - minLng) * lngScale * scale,
			// SVG y grows downward; invert latitude so north is up.
			y: offY + (maxLat - p.lat) * scale,
		});
	}
	return out;
}

/// True iff the track's bounding-box diagonal exceeds ~5 m — i.e. it is
/// worth drawing at thumbnail scale. A runner who hits Start + Stop
/// indoors uploads a non-empty array of near-identical fixes; without
/// this gate the thumbnail projects them all onto a single pixel and
/// renders a meaningless dot. The few-metre threshold rejects GPS
/// jitter without throwing away genuinely tiny laps. Longitudes are
/// unwrapped onto the first fix's side of the antimeridian first — a
/// raw min/max reads a jitter cluster AT the line as a 359.99° span,
/// which defeated the gate for exactly the stationary case it exists
/// to catch. Mirrors `isTrackRenderable` in
/// `apps/mobile_android/lib/widgets/track_preview.dart` — keep in
/// lockstep.
export function isTrackRenderable(track: TrackPoint[]): boolean {
	if (!track || track.length < 2) return false;
	const refLng = track[0].lng;
	let minLat = track[0].lat;
	let maxLat = track[0].lat;
	let minLng = refLng;
	let maxLng = refLng;
	for (const p of track) {
		if (p.lat < minLat) minLat = p.lat;
		if (p.lat > maxLat) maxLat = p.lat;
		const lng = unwrapLonDeg(refLng, p.lng);
		if (lng < minLng) minLng = lng;
		if (lng > maxLng) maxLng = lng;
	}
	const dLatM = (maxLat - minLat) * 111_320;
	const dLngM = (maxLng - minLng) * 111_320 * Math.cos((minLat * Math.PI) / 180);
	return Math.hypot(dLatM, dLngM) > 5;
}

/// A positive, finite span for the projection scale. Mirrors `_spanOrEpsilon`
/// in `track_preview.dart`.
function spanOrEpsilon(v: number): number {
	return Number.isFinite(v) && v > 1e-6 ? v : 1e-6;
}
