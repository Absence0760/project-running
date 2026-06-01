/// Client-side year-in-running share-card SVG builder. Unlike
/// `og_run_image.ts` (a build-time / Lambda OG unfurl for PUBLIC run
/// pages) the recap is personal data with no public URL, so this card
/// is rendered in the browser and handed to the OS share sheet or a
/// download — never served as an og:image. Pure string concatenation
/// so unit tests can pin the wire shape without a renderer, and so the
/// page can rasterise it to PNG via an offscreen canvas.

import type { YearInRunningRecap } from '../runs/recap';

const SIZE = 1080; // square — friendliest aspect for social shares
const PAD = 72;

const BG = '#0f172a'; // slate-900 — confident dark card
const BRAND = '#60a5fa'; // brand blue, lightened for dark bg
const HERO_FILL = '#ffffff';
const LABEL_FILL = '#94a3b8'; // slate-400
const STAT_FILL = '#e2e8f0'; // slate-200

function fmtDistance(meters: number, unit: 'km' | 'mi'): string {
	if (unit === 'mi') return `${(meters / 1609.344).toFixed(0)} mi`;
	return `${(meters / 1000).toFixed(0)} km`;
}

function fmtDuration(seconds: number): string {
	const h = Math.floor(seconds / 3600);
	const m = Math.floor((seconds % 3600) / 60);
	if (h > 0) return `${h}h ${m}m`;
	return `${m}m`;
}

// The recap card is rendered in the viewer's own browser (offscreen
// canvas → PNG), never served as a shared og:image, so it should follow
// the runtime locale for grouped numbers rather than pinning en-US.
// `navigator.language` when available, `undefined` (host default) when
// running under the unit-test harness.
function localeNumber(n: number): string {
	const locale = typeof navigator !== 'undefined' ? navigator.language : undefined;
	return new Intl.NumberFormat(locale).format(n);
}

function xmlEscape(s: string): string {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}

type StatCell = { label: string; value: string };

function statCells(recap: YearInRunningRecap, unit: 'km' | 'mi'): StatCell[] {
	const activeMonths = recap.monthly.filter((m) => m.runCount > 0).length;
	return [
		{ label: 'Longest run', value: fmtDistance(recap.longestRunM, unit) },
		{ label: 'On foot', value: fmtDuration(recap.totalDurationS) },
		{ label: 'Best streak', value: `${recap.bestStreakDays} days` },
		{
			label: 'Top week',
			value: fmtDistance(recap.topWeek?.distanceM ?? 0, unit),
		},
		{
			label: 'Climbed',
			value: `${localeNumber(Math.round(recap.totalElevationM))} m`,
		},
		{
			label: 'Active months',
			value: `${activeMonths} / 12`,
		},
	];
}

/// Build the share-card SVG for a year-in-running recap. Returns an
/// `<svg>` string sized for a 1080×1080 social card. The page
/// rasterises it to PNG before sharing / downloading.
export function buildRecapShareSvg(recap: YearInRunningRecap, unit: 'km' | 'mi'): string {
	const F = 'system-ui,-apple-system,Segoe UI,Roboto,sans-serif';
	const parts: string[] = [];
	parts.push(
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}" width="${SIZE}" height="${SIZE}">`,
	);
	parts.push(`<rect width="${SIZE}" height="${SIZE}" fill="${BG}"/>`);

	// Brand strap, top-left.
	parts.push(
		`<text x="${PAD}" y="${PAD + 28}" font-family="${F}" font-size="40" font-weight="800" fill="${BRAND}">Threkir</text>`,
	);

	// Kicker.
	parts.push(
		`<text x="${PAD}" y="${PAD + 110}" font-family="${F}" font-size="34" font-weight="700" fill="${LABEL_FILL}" letter-spacing="3">MY ${recap.year} IN RUNNING</text>`,
	);

	// Hero — total distance.
	parts.push(
		`<text x="${PAD}" y="${PAD + 280}" font-family="${F}" font-size="200" font-weight="900" fill="${HERO_FILL}">${xmlEscape(fmtDistance(recap.totalDistanceM, unit))}</text>`,
	);

	// Subhead — run count.
	const runWord = recap.runCount === 1 ? 'run' : 'runs';
	parts.push(
		`<text x="${PAD}" y="${PAD + 350}" font-family="${F}" font-size="44" font-weight="600" fill="${STAT_FILL}">across ${recap.runCount} ${runWord}</text>`,
	);

	// Stat grid — 2 columns × 3 rows in the lower half.
	const cells = statCells(recap, unit);
	const gridTop = PAD + 440;
	const colW = (SIZE - PAD * 2) / 2;
	const rowH = 150;
	cells.forEach((cell, i) => {
		const col = i % 2;
		const row = Math.floor(i / 2);
		const x = PAD + col * colW;
		const y = gridTop + row * rowH;
		parts.push(
			`<text x="${x}" y="${y}" font-family="${F}" font-size="28" font-weight="700" fill="${LABEL_FILL}" letter-spacing="2">${xmlEscape(cell.label.toUpperCase())}</text>`,
		);
		parts.push(
			`<text x="${x}" y="${y + 58}" font-family="${F}" font-size="64" font-weight="800" fill="${STAT_FILL}">${xmlEscape(cell.value)}</text>`,
		);
	});

	parts.push('</svg>');
	return parts.join('');
}
