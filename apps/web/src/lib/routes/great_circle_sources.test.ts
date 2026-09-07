// Where the web tree is allowed to compute a great-circle distance, and why
// each remaining place still does (decisions § 1470).
//
// The tree carried SEVENTEEN of them. Ten took the `atan2` form, six the
// `asin(min(1, sqrt))` form, one the `asin` of a clamped `a` — three spellings
// of one function, differing by at most 8.2e-8 m over the whole globe and
// 2.3e-13 m on a leg under 1.5 km, and differing in exactly one place that
// matters: where rounding pushes the haversine `a` a hair above 1, `sqrt(1-a)`
// is NaN and the `atan2` form answers NaN where the clamped `asin` answers
// half a circumference. That is § 305's recorded near-miss, and it was still
// live in `route_snap.ts` — whose Dart twin has imported the clamped
// `run_stats.dart:haversineMetres` all along, so the phone and the web
// answered differently on the same polyline with nothing able to see it.
//
// ANCHORING. Keyed on the ARC, not on a name, a radius literal or a body
// fingerprint: a great-circle distance has to take an `asin` or an `atan2` of
// a square root, and no rename, reformat or re-derivation removes that.
// `check_shared_reimplementations.mjs` cannot see this class — it groups
// byte-identical bodies, and it says so ("only the two structurally identical
// ones are one group"), which is how fifteen unregistered copies sat under a
// green guard. A bearing's `Math.atan2(y, x)` carries no square root, so
// `turn_cues.ts`'s bearing and `TrackPreview.svelte`'s screen angle are
// outside the anchor by construction rather than by exclusion.
//
// The table is the residue, not a blessing. Every entry but the canonical is
// owed the same move, and each states what is stopping it.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { haversineMetres } from '../runs/run_stats';

const SCAN_ROOT = 'src';

/// An `asin`/`atan2` applied to a square root, with at most one wrapping call
/// (the `Math.min(1, …)` clamp) between them. Whitespace is stripped first, so
/// a reformat cannot hide one.
const ARC_OF_A_SQUARE_ROOT = /Math\.(?:asin|atan2)\([^;]{0,80}?Math\.sqrt\(/g;

/// The canonical, and every place still computing its own.
const GREAT_CIRCLE_SOURCES: { file: string; arcs: number; reason: string }[] = [
	{
		file: 'src/lib/runs/run_stats.ts',
		arcs: 1,
		reason:
			'THE canonical. Exported as `haversineMetres`, clamps `a` into [0, 1] before the arc, and is what `run_stats.dart` computes point for point — so it is the one form both platforms already agree on. Nine Dart modules import it; the web modules that do not yet are below.',
	},
	{
		file: 'src/lib/components/RouteBuilder.svelte',
		arcs: 1,
		reason:
			'Web-only, and already imports the shared distance through `routing_quality.haversineM` under an alias while keeping a private copy beside it. Removing the copy is a components-tree change.',
	},
	{
		file: 'src/lib/components/RunSegmentEfforts.svelte',
		arcs: 1,
		reason:
			'Web-only, and the arc is INLINE in the effort loop rather than in a named function — invisible to `check_shared_reimplementations.mjs`, which does not extract anonymous bodies. A components-tree change.',
	},
	{
		file: 'src/lib/integrations/race_match.ts',
		arcs: 1,
		reason:
			'Half of the `race_match` parity pair, and `race_match.dart` carries its own copy too. Moving only the web half is what the `addDays` registration in `check_shared_reimplementations.mjs` refuses — the two halves move together or not at all.',
	},
	{
		file: 'src/lib/routes/privacy.ts',
		arcs: 1,
		reason:
			'Half of the `privacy` pair, matched by `privacy.dart:_haversine`. Both are the UNCLAMPED `atan2` form, so they agree with each other and the matched move would add the clamp on both sides at once.',
	},
	{
		file: 'src/lib/routes/roadbook.ts',
		arcs: 1,
		reason:
			'Half of the `roadbook` pair, matched by `roadbook.dart:_haversineM`, and carrying a third rail in the watch firmware. Matched move owed.',
	},
	{
		file: 'src/lib/routes/route_description.ts',
		arcs: 1,
		reason:
			'Half of the `route_description` pair, matched by `route_description.dart:_haversineM`. Matched move owed.',
	},
	{
		file: 'src/lib/routes/turn_cues.ts',
		arcs: 1,
		reason:
			'Half of the `turn_cues` pair, matched by `turn_cues.dart:_haversineM`, with a third rail in `apps/custom_watch/core/src/turn_cues.rs`. Matched move owed. The bearing computed in the same module takes an `atan2` of no square root and is not counted here.',
	},
	{
		file: 'src/lib/segments/pace_segments.ts',
		arcs: 1,
		reason:
			'Half of the `pace_segments` pair. The only remaining copy with NO clamp of any kind — `Math.asin(Math.sqrt(h))` is NaN for `h > 1` exactly as the `atan2` form is — so this is the live end of § 305 and the matched move is a fix, not a tidy.',
	},
	{
		file: 'src/lib/segments/segments.ts',
		arcs: 1,
		reason:
			'Half of the `segments` pair, matched by `segments.dart:_haversine`. Matched move owed.',
	},
];

function walk(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(resolve(dir), { withFileTypes: true })) {
		const rel = join(dir, entry.name);
		if (entry.isDirectory()) walk(rel, out);
		else if (/\.(ts|svelte)$/.test(entry.name) && !/\.test\.ts$/.test(entry.name)) out.push(rel);
	}
	return out;
}

function arcCounts(): Map<string, number> {
	const found = new Map<string, number>();
	for (const file of walk(SCAN_ROOT)) {
		const stripped = readFileSync(resolve(file), 'utf-8').replace(/\s+/g, '');
		const hits = stripped.match(ARC_OF_A_SQUARE_ROOT);
		if (hits) found.set(file, hits.length);
	}
	return found;
}

test('no module computes a great-circle distance the table does not know about', () => {
	const declared = new Set(GREAT_CIRCLE_SOURCES.map((s) => s.file));
	const undeclared = [...arcCounts().keys()].filter((f) => !declared.has(f)).sort();
	assert.deepEqual(
		undeclared,
		[],
		`a new copy of the great-circle distance. Import \`haversineMetres\` from \`src/lib/runs/run_stats\` instead; if the module genuinely cannot, add it to GREAT_CIRCLE_SOURCES with the reason: ${undeclared.join(', ')}`,
	);
});

test('every table entry still computes one, and only as many as it claims', () => {
	const found = arcCounts();
	for (const { file, arcs, reason } of GREAT_CIRCLE_SOURCES) {
		assert.equal(
			found.get(file) ?? 0,
			arcs,
			`${file} computes ${found.get(file) ?? 0} great-circle arcs, table says ${arcs}. ` +
				`If it now imports the shared one, delete the entry — a stale reason outlives the ` +
				`condition it describes. Reason on record: ${reason}`,
		);
	}
});

test('the canonical is one module, and it is the one both platforms already share', () => {
	// Stated rather than implied: the table would still pass with two entries
	// calling themselves canonical, and then "the shared one" would be a
	// question rather than an answer.
	const canonical = GREAT_CIRCLE_SOURCES.filter((s) => s.reason.startsWith('THE canonical'));
	assert.equal(canonical.length, 1);
	assert.equal(canonical[0].file, 'src/lib/runs/run_stats.ts');
});

test('the canonical clamps before the arc, which is the whole reason it is the canonical', () => {
	// A behavioural pin, not a reading of the source: every other form in the
	// table answers NaN or throws where `a` rounds past 1, and a consolidation
	// onto an unclamped canonical would have propagated that everywhere at once
	// instead of removing it.
	const d = haversineMetres(-87.5, 0, 87.5, 180);
	assert.ok(Number.isFinite(d), `near-antipodal distance must be a number, got ${d}`);
	assert.ok(d > 20_010_000 && d < 20_020_000, `expected half a circumference, got ${d}`);
});
