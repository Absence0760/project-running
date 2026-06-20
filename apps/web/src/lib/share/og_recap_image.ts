/// Server-side recap-share SVG builder for /og/recap/[id].png. Pure string
/// concatenation so unit tests can pin the wire shape without running the
/// PNG renderer. 1200×630 (matches og_run_image.ts) — distinct from the
/// 1080² client share card in recap_share_image.ts, which is the in-app
/// OS-share-sheet artifact.
///
/// Renders ONLY the aggregate, non-track numbers frozen into the public
/// recap snapshot (distance, runs, longest, streak, top week, climbed) —
/// no GPS, no per-run rows — mirroring og_run_image.ts's no-polyline
/// discipline.

/// The aggregate fields the OG card reads off a frozen snapshot. A loose
/// shape (not the full YearInRunningRecap) so a snapshot from an older or
/// newer build still renders what it can.
export type RecapOgInput = {
	year?: number | null;
	month?: number | null;
	totalDistanceM?: number | null;
	runCount?: number | null;
	longestRunM?: number | null;
	bestStreakDays?: number | null;
	topWeekDistanceM?: number | null;
	totalElevationM?: number | null;
	displayName?: string | null;
	/** Pre-formatted period label (e.g. "March 2026"); falls back to the year. */
	periodLabel?: string | null;
};

const W = 1200;
const H = 630;
const PAD = 64;

const BG = '#0f172a'; // slate-900
const BRAND = '#60a5fa';
const HERO_FILL = '#ffffff';
const LABEL_FILL = '#94a3b8'; // slate-400
const STAT_FILL = '#e2e8f0'; // slate-200

function fmtDistanceKm(meters: number | null | undefined, unit: 'km' | 'mi'): string {
	const m = meters ?? 0;
	if (unit === 'mi') return `${(m / 1609.344).toFixed(0)} mi`;
	return `${(m / 1000).toFixed(0)} km`;
}

export function xmlEscape(s: string): string {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}

/// Build the og:image SVG for a public recap share page. `unit` defaults to
/// km (the og:image is served to crawlers, not a logged-in user, so there's
/// no preference to read — km is the canonical storage unit and the most
/// common locale default).
export function buildRecapOgSvg(input: RecapOgInput, unit: 'km' | 'mi' = 'km'): string {
	const F = 'system-ui,-apple-system,Segoe UI,Roboto,sans-serif';
	const parts: string[] = [];
	parts.push(
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">`,
	);
	parts.push(`<rect width="${W}" height="${H}" fill="${BG}"/>`);

	// Brand strap, top-left.
	parts.push(
		`<text x="${PAD}" y="${PAD + 24}" font-family="${F}" font-size="32" font-weight="800" fill="${BRAND}">Threkir</text>`,
	);

	// Kicker.
	const period = (input.periodLabel ?? (input.year != null ? String(input.year) : '')).trim();
	const kicker = period ? `MY ${period.toUpperCase()} IN RUNNING` : 'MY YEAR IN RUNNING';
	parts.push(
		`<text x="${PAD}" y="${PAD + 84}" font-family="${F}" font-size="28" font-weight="700" fill="${LABEL_FILL}" letter-spacing="3">${xmlEscape(kicker)}</text>`,
	);

	// Hero — total distance.
	parts.push(
		`<text x="${PAD}" y="${PAD + 230}" font-family="${F}" font-size="150" font-weight="900" fill="${HERO_FILL}">${xmlEscape(fmtDistanceKm(input.totalDistanceM, unit))}</text>`,
	);

	// Subhead — run count (+ attribution).
	const n = Math.max(0, Math.trunc(input.runCount ?? 0));
	const runWord = n === 1 ? 'run' : 'runs';
	const by = input.displayName?.trim();
	const subhead = by ? `${n} ${runWord} · ${by}` : `across ${n} ${runWord}`;
	parts.push(
		`<text x="${PAD}" y="${PAD + 296}" font-family="${F}" font-size="40" font-weight="600" fill="${STAT_FILL}">${xmlEscape(subhead)}</text>`,
	);

	// Stat row along the bottom — three headline cells.
	const cells: Array<{ label: string; value: string }> = [
		{ label: 'LONGEST', value: fmtDistanceKm(input.longestRunM, unit) },
		{ label: 'BEST STREAK', value: `${Math.max(0, Math.trunc(input.bestStreakDays ?? 0))} days` },
		{ label: 'TOP WEEK', value: fmtDistanceKm(input.topWeekDistanceM, unit) },
	];
	const rowY = H - PAD - 40;
	const colW = (W - PAD * 2) / 3;
	cells.forEach((cell, i) => {
		const x = PAD + i * colW;
		parts.push(
			`<text x="${x}" y="${rowY}" font-family="${F}" font-size="24" font-weight="700" fill="${LABEL_FILL}" letter-spacing="2">${xmlEscape(cell.label)}</text>`,
		);
		parts.push(
			`<text x="${x}" y="${rowY + 46}" font-family="${F}" font-size="48" font-weight="800" fill="${STAT_FILL}">${xmlEscape(cell.value)}</text>`,
		);
	});

	parts.push('</svg>');
	return parts.join('');
}
