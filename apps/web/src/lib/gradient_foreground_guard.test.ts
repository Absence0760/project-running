// A gradient is a FILL, and its palest stop sets the ink. § 503 ruled that a
// status token is a foreground or a fill but never both; the same argument
// applies to a multi-stop ramp, and it is the case § 519 caught white-on-
// gradient at 2.081:1 — the identical figure § 511 measured under
// `.btn-primary`. The defect recurs because a ramp is eyeballed against its
// first stop: `linear-gradient(150deg, #2C5F6E 0%, …, #F2A07B 100%)` under
// white copy looks right at the top of the pane and is 2.081:1 at the bottom.
//
// So the ramps are read OUT OF THE SOURCE here rather than restated: every
// stop of every text-bearing gradient is extracted from the declaration and
// measured against the foreground the same rule declares, and a future edit
// that lightens one stop fails. § 511's warning that "a floor read out of the
// tree inherits every blind spot of the pattern it reads with" is why each
// entry carries `stops` — the expected stop COUNT — so a ramp the regex fails
// to parse cannot pass by matching nothing.
//
// A translucent veil drawn OVER a ramp lightens what the ink lands on, so
// each entry declares its veils and every stop is measured bare and under
// each veil at that veil's own peak. The two radial veils on the login pane
// are anchored at opposite corners (30%/20% and 80%/90%, both transparent by
// 55%), so they are measured one at a time rather than stacked: stacking them
// would assert a composite that no pixel of the pane actually shows.
//
// Invocation:
//   npx tsx --test src/lib/gradient_foreground_guard.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SRC_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function channels(hex: string): [number, number, number] {
	const s = hex.replace('#', '');
	return [0, 2, 4].map((i) => parseInt(s.slice(i, i + 2), 16) / 255) as [
		number,
		number,
		number,
	];
}

function relativeLuminance(hex: string): number {
	const [r, g, b] = channels(hex).map((c) =>
		c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4),
	);
	return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a: string, b: string): number {
	const la = relativeLuminance(a);
	const lb = relativeLuminance(b);
	return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

function composite(fg: string, bg: string, alpha: number): string {
	const f = channels(fg);
	const b = channels(bg);
	return (
		'#' +
		f
			.map((v, i) => Math.round((v * alpha + b[i] * (1 - alpha)) * 255))
			.map((v) => v.toString(16).padStart(2, '0'))
			.join('')
	);
}

type Veil = { colour: string; alpha: number; why: string };

type Ramp = {
	file: string;
	/// Unique substring of the gradient DECLARATION line.
	anchor: string;
	/// How many stops the ramp must have, so a parse failure cannot pass.
	stops: number;
	/// The ink drawn on it, and the floor that ink owes.
	ink: string;
	floor: number;
	/// Translucent layers painted over the ramp, each measured alone at its
	/// own peak alpha.
	veils?: Veil[];
	why: string;
};

const RAMPS: Ramp[] = [
	{
		file: 'routes/login/+page.svelte',
		anchor: 'background: linear-gradient(150deg,',
		stops: 3,
		ink: '#FFFFFF',
		floor: 4.5,
		veils: [
			{ colour: '#FFFFFF', alpha: 0.18, why: '.brand-pane::before sheen at 30%/20%' },
			{ colour: '#B9A7E8', alpha: 0.35, why: '.brand-pane::after lilac at 80%/90%' },
		],
		why: 'the sign-in brand pane carries the product copy',
	},
	{
		file: 'routes/runs/[id]/+page.svelte',
		anchor: 'background: linear-gradient(135deg, #9B4A24',
		stops: 3,
		ink: '#FFFFFF',
		floor: 4.5,
		why: 'the 1080x1080 share card rasterises to a PNG that leaves the device',
	},
	{
		file: 'routes/+page.svelte',
		anchor: 'background: linear-gradient(150deg, #0F172A',
		stops: 4,
		ink: 'rgba(255, 255, 255, 0.85)',
		floor: 4.5,
		why: 'the marketing hero headline + subhead',
	},
	{
		file: 'routes/+page.svelte',
		anchor: 'background: linear-gradient(135deg, #1E1B4B',
		stops: 2,
		ink: '#ffffff',
		floor: 4.5,
		why: 'the closing call-to-action block',
	},
];

/// Resolve an `rgba(255, 255, 255, a)` ink against the stop it is drawn on —
/// a translucent white IS a lightened version of its background, which is
/// exactly how the hero subhead came to read 3.284:1.
function inkOver(ink: string, stop: string): string {
	const rgba = ink.match(
		/rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)/,
	);
	if (!rgba) return ink;
	const hex =
		'#' +
		[rgba[1], rgba[2], rgba[3]]
			.map((c) => Number(c).toString(16).padStart(2, '0'))
			.join('');
	return composite(hex, stop, Number(rgba[4]));
}

function rampLine(file: string, anchor: string): string {
	const source = readFileSync(join(SRC_ROOT, file), 'utf-8');
	const lines = source.split('\n').filter((l) => l.includes(anchor));
	assert.equal(
		lines.length,
		1,
		`${file}: expected exactly one line containing ${JSON.stringify(anchor)}, ` +
			`found ${lines.length}. If the ramp moved, move its anchor with it — a ` +
			`guard that silently matches nothing is worse than no guard.`,
	);
	return lines[0];
}

test('every text-bearing gradient clears its ink at every stop', () => {
	for (const ramp of RAMPS) {
		const line = rampLine(ramp.file, ramp.anchor);
		const stops = [...line.matchAll(/#([0-9a-fA-F]{6})(?![0-9a-fA-F])/g)].map(
			(m) => `#${m[1]}`,
		);
		assert.equal(
			stops.length,
			ramp.stops,
			`${ramp.file} (${ramp.why}): parsed ${stops.length} stops, expected ` +
				`${ramp.stops}. Line was:\n${line.trim()}`,
		);
		for (const stop of stops) {
			const grounds: Array<[string, string]> = [[stop, 'bare']];
			for (const veil of ramp.veils ?? []) {
				grounds.push([
					composite(veil.colour, stop, veil.alpha),
					`under ${veil.why}`,
				]);
			}
			for (const [ground, where] of grounds) {
				const ratio = contrast(inkOver(ramp.ink, ground), ground);
				assert.ok(
					ratio >= ramp.floor,
					`${ramp.file} (${ramp.why}): ink ${ramp.ink} on stop ${stop} ` +
						`${where} reads ${ratio.toFixed(3)}:1, below ${ramp.floor}. A ` +
						`gradient's PALEST stop sets its ink — deepen the stop or ` +
						`darken the ink.`,
				);
			}
		}
	}
});

test('the fix direction is real: the pre-fix stops still fail', () => {
	// Both halves of the defect this closes, so nobody re-lightens a ramp on
	// the theory that the numbers above were always fine.
	assert.ok(contrast('#FFFFFF', '#F2A07B') < 2.1, 'the peach --gradient-primary tail');
	assert.ok(contrast('#FFFFFF', '#B9A7E8') < 2.2, 'the lilac stop it becomes in dark');
	assert.ok(contrast(inkOver('rgba(255, 255, 255, 0.65)', '#7C3AED'), '#7C3AED') < 3.3);
});

test('no primary-action button paints a frozen ink on a gradient fill', () => {
	// The generalisation of § 511's `.btn-primary` finding: a gradient token
	// passes through a pale stop in one theme or the other, so a button label
	// on one cannot be a literal. `--color-on-primary` is the pair.
	const login = readFileSync(join(SRC_ROOT, 'routes/login/+page.svelte'), 'utf-8');
	// The selector appears more than once (a responsive variant only sets
	// geometry), so pick the block that actually paints.
	const blocks = [...login.matchAll(/\.btn-email\s*\{([^}]*)\}/g)].map((m) => m[1]);
	assert.ok(blocks.length > 0, 'login is missing the .btn-email rule');
	const painting = blocks.filter((b) => /background\s*:/.test(b));
	assert.equal(painting.length, 1, 'exactly one .btn-email block sets a fill');
	for (const block of blocks) {
		assert.doesNotMatch(
			block,
			/var\(--gradient-primary\)/,
			`.btn-email must not fill with --gradient-primary, whose palest stop ` +
				`(#F2A07B light / #B9A7E8 dark) reads 2.081 / 2.153:1 under any ` +
				`white label. Block was:\n${block}`,
		);
	}
	assert.match(painting[0], /color:\s*var\(--color-on-primary\)/);
});
