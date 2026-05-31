// Pure projection helper for the SVG track-preview thumbnails. Lives in
// its own module so the cos(midLat) correction can be unit-tested
// without spinning up a Svelte component. Mirrors `projectTrack` in
// `apps/mobile_android/lib/widgets/track_preview.dart` — keep them in
// lockstep.

import type { TrackPoint } from '../types';

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
	let minLat = points[0].lat;
	let maxLat = points[0].lat;
	let minLng = points[0].lng;
	let maxLng = points[0].lng;
	for (const p of points) {
		if (p.lat < minLat) minLat = p.lat;
		if (p.lat > maxLat) maxLat = p.lat;
		if (p.lng < minLng) minLng = p.lng;
		if (p.lng > maxLng) maxLng = p.lng;
	}
	// A degree of longitude is shorter than a degree of latitude
	// everywhere except the equator — at 51 °N (London) it's only ~62 %
	// of a latitude degree. Scaling lng by cos(midLat) projects the
	// bounding box into equal-distance units.
	const midLat = (minLat + maxLat) / 2;
	const lngScale = Math.abs(Math.cos((midLat * Math.PI) / 180));
	const dLat = maxLat - minLat || 1e-6;
	const dLng = (maxLng - minLng) * lngScale || 1e-6;
	const scaleX = (vbW - pad * 2) / dLng;
	const scaleY = (vbH - pad * 2) / dLat;
	const scale = Math.min(scaleX, scaleY);
	const offX = pad + (vbW - pad * 2 - dLng * scale) / 2;
	const offY = pad + (vbH - pad * 2 - dLat * scale) / 2;
	const out: Projected[] = [];
	for (const p of points) {
		out.push({
			x: offX + (p.lng - minLng) * lngScale * scale,
			// SVG y grows downward; invert latitude so north is up.
			y: offY + (maxLat - p.lat) * scale,
		});
	}
	return out;
}
