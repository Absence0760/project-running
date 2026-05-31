/// Server-side run-share SVG builder for /og/run/[id].png. Pure
/// string concatenation so unit tests can pin the wire shape
/// without running the PNG renderer.
///
/// Design differs from `og_route_image.ts` in one place: routes have
/// waypoints in the row body already (the page's `+page.ts` fetches
/// them), runs do NOT — the track is a gzipped JSON blob in the
/// `runs` Storage bucket reachable only via the
/// `clip-public-track` Edge Function (decisions §33). Calling the EF
/// for every public run at build time would make the build a hot
/// loop; we render the card without a polyline and lean on the
/// stats / runner name / brand strap instead. A future iteration can
/// invoke the EF and add the polyline if the build-time cost stays
/// acceptable.

import { formatDateStable, formatKmStable } from './share_meta';

const W = 1200;
const H = 630;
const PAD = 40;

const BG = '#ffffff';
const BRAND = '#3b82f6'; // brand blue
const STAT_FILL = '#0f172a'; // slate-900
const META_FILL = '#64748b'; // slate-500

export type RunImageInput = {
	distance_m?: number | null;
	duration_s?: number | null;
	started_at?: string | null;
	source?: string | null;
	displayName?: string | null;
};

/// Build the og:image SVG for a run share page. Returns a `<svg>`
/// string that resvg-js can render to PNG. The card focuses on the
/// stats: large distance numeral, runner attribution if available,
/// date below.
export function buildRunOgSvg(input: RunImageInput): string {
	const parts: string[] = [];
	parts.push(
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">`,
	);
	parts.push(`<rect width="${W}" height="${H}" fill="${BG}"/>`);

	// Brand strap, top-left.
	parts.push(
		`<text x="${PAD}" y="${PAD + 24}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="28" font-weight="700" fill="${BRAND}">Threkir</text>`,
	);

	// Main stat — distance, centred horizontally. The 1200×630 canvas
	// scales to ~600 px for a confident, unfurl-card-style hero.
	const km = formatKmStable(input.distance_m);
	const heroText = km || 'Run';
	parts.push(
		`<text x="${W / 2}" y="${H / 2 + 20}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="180" font-weight="800" fill="${STAT_FILL}" text-anchor="middle">${xmlEscape(heroText)}</text>`,
	);

	// Sub-line: "by NAME on DATE" — composed from whatever bits are
	// present. Trims down gracefully if one signal is null.
	const sub = buildSubline(input);
	if (sub) {
		parts.push(
			`<text x="${W / 2}" y="${H / 2 + 100}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="44" font-weight="500" fill="${META_FILL}" text-anchor="middle">${xmlEscape(sub)}</text>`,
		);
	}

	// Source tag (strava / parkrun / etc) bottom-right when present.
	if (input.source) {
		parts.push(
			`<text x="${W - PAD}" y="${H - PAD}" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="28" font-weight="600" fill="${META_FILL}" text-anchor="end">${xmlEscape(input.source)}</text>`,
		);
	}

	parts.push('</svg>');
	return parts.join('');
}

export function buildSubline(input: RunImageInput): string {
	const date = formatDateStable(input.started_at);
	const by = input.displayName?.trim() || '';
	if (by && date) return `by ${by} on ${date}`;
	if (by) return `by ${by}`;
	if (date) return date;
	return '';
}

export function xmlEscape(s: string): string {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}
