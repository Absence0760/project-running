/// Server-side track-preview SVG builder for the /og/route/[id].png
/// endpoint. Pure string concatenation so unit tests can pin the
/// wire shape without running the PNG renderer. Mirrors the
/// `TrackPreview.svelte` look (green-start / red-end caps, single
/// polyline) but at a larger size suited to the og:image card —
/// the unfurl card is rendered at ~1200×630 (Twitter
/// summary_large_image + Facebook recommended), so we ship a 1200×630
/// canvas with a centered track viewport.

import type { TrackPoint } from './types';
import { projectTrack } from './track_projection';

const W = 1200;
const H = 630;
const PAD = 40; // inset margin so the track doesn't hug the edges

const BG = '#ffffff';
const FG = '#3b82f6'; // brand blue
const FG_WIDTH = 8;
const START_FILL = '#16a34a'; // green
const END_FILL = '#dc2626'; // red
const TEXT_FILL = '#0f172a'; // slate-900
const TEXT_MUTED = '#64748b'; // slate-500

export type RouteImageInput = {
	name?: string | null;
	distance_m?: number | null;
	surface?: string | null;
	track: TrackPoint[];
};

/// Build the og:image SVG for a route. Returns a `<svg>` string that
/// resvg-js can render to PNG. Tracks with <2 points fall back to a
/// title-only card (no polyline) so we don't crash on degenerate
/// data.
export function buildRouteOgSvg(input: RouteImageInput): string {
	const parts: string[] = [];
	parts.push(
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">`,
	);
	parts.push(`<rect width="${W}" height="${H}" fill="${BG}"/>`);

	// Top-left: site name strap.
	parts.push(
		`<text x="${PAD}" y="${PAD + 24}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="28" font-weight="700" fill="${FG}">Threkir</text>`,
	);

	// Track polyline — projected into the lower-right 800×500 viewport.
	if (input.track.length >= 2) {
		const trackW = 800;
		const trackH = 500;
		const trackX = W - trackW - PAD;
		const trackY = H - trackH - PAD;
		const projected = projectTrack(input.track, trackW, trackH, 8);
		if (projected.length >= 2) {
			const d = projected
				.map((p, i) => `${i === 0 ? 'M' : 'L'}${(trackX + p.x).toFixed(1)},${(trackY + p.y).toFixed(1)}`)
				.join(' ');
			parts.push(
				`<path d="${d}" stroke="${FG}" stroke-width="${FG_WIDTH}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`,
			);
			// Start/end caps.
			const start = projected[0];
			const end = projected[projected.length - 1];
			parts.push(
				`<circle cx="${(trackX + start.x).toFixed(1)}" cy="${(trackY + start.y).toFixed(1)}" r="10" fill="${START_FILL}"/>`,
			);
			parts.push(
				`<circle cx="${(trackX + end.x).toFixed(1)}" cy="${(trackY + end.y).toFixed(1)}" r="10" fill="${END_FILL}"/>`,
			);
		}
	}

	// Title block, lower-left. Wraps at ~30 chars by truncating —
	// the SVG renderer doesn't reflow text and a route name longer
	// than two lines would overlap the polyline. 90 chars caps it at
	// a reasonable two-line display.
	const name = (input.name ?? '').trim() || 'Untitled route';
	const meta = buildMetaLine(input.distance_m, input.surface);
	const titleY = H - 160;
	parts.push(
		`<text x="${PAD}" y="${titleY}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="56" font-weight="700" fill="${TEXT_FILL}">${xmlEscape(truncate(name, 30))}</text>`,
	);
	if (meta) {
		parts.push(
			`<text x="${PAD}" y="${titleY + 60}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="36" font-weight="500" fill="${TEXT_MUTED}">${xmlEscape(meta)}</text>`,
		);
	}

	parts.push('</svg>');
	return parts.join('');
}

export function buildMetaLine(
	distanceM: number | null | undefined,
	surface: string | null | undefined,
): string {
	const bits: string[] = [];
	if (distanceM != null && Number.isFinite(distanceM) && distanceM >= 0) {
		const km = distanceM / 1000;
		const digits = km >= 21 ? 2 : 1;
		bits.push(`${km.toFixed(digits)} km`);
	}
	if (surface) bits.push(surface);
	return bits.join(' · ');
}

export function truncate(s: string, max: number): string {
	if (s.length <= max) return s;
	return s.slice(0, Math.max(0, max - 1)).trimEnd() + '…';
}

export function xmlEscape(s: string): string {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}
