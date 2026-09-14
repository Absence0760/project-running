/// Where the Edge Function tree is allowed to compute a great-circle distance,
/// and why the one place that still does cannot import the canonical.
///
/// THE THIRD ROOT. `apps/web/src/lib/routes/great_circle_sources.test.ts` has
/// scanned `apps/web/src` since decisions § 1470 and
/// `apps/mobile_android/test/great_circle_sources_test.dart` has scanned
/// `apps/mobile_android/lib` since § 1524 — and § 1524 is on record for what a
/// guard over one tree cannot see: `route_snap.dart` imported the clamped
/// helper while `route_snap.ts` computed its own unclamped arc, and each
/// platform read as healthy on its own terms for exactly as long as only one of
/// them was watched. This tree was the remaining unwatched one, and it is not
/// an empty one: § 1525 found `embeddedHaversineM` here in the unclamped
/// `atan2` form, summing the same fifty 100 m legs to 5000.000000000002 m where
/// the two clients summed 4999.999999999998 m, so against a strict window
/// comparison the importer wrote a 5 km best for a track the phone found none
/// in. That one copy is now pinned to an exact sum by `_shared/strava.test.ts`.
/// What nothing could see is a SECOND copy appearing in another function — the
/// shape § 1524 records for the phone — and only a census can.
///
/// ANCHORING. Keyed on the ARC, not on a name, a radius literal or a body
/// fingerprint: a great-circle distance has to take an `asin` or an `atan2` of
/// a square root, and no rename, reformat or re-derivation removes that.
/// Whitespace is stripped before matching, so a line-wrap cannot hide one, and
/// the window stops at a statement boundary so two unrelated lines are not read
/// as one arc. A bearing's `Math.atan2(y, x)` carries no square root and is
/// outside the anchor by construction rather than by exclusion. Deliberately
/// the SAME anchor as the two existing roots: three trees answering one
/// question three ways is the shape this class of guard exists to remove.
///
/// SCOPE is `supabase/functions`, the deployed tree, matching the two siblings'
/// choice of `src` and `lib`. Its two neighbours need nothing and are measured
/// rather than assumed: `apps/backend/scripts` is build tooling that computes
/// no distance at all (0 arcs), and `supabase/migrations` spells every distance
/// as PostGIS `ST_Distance` over `geography` (30 occurrences, no hand-rolled
/// arc), which this anchor cannot express and does not have to.
///
/// TEST FILES are outside the scan on purpose, the same carve-out both siblings
/// make: a suite that reimplements the distance as an independent oracle is the
/// one place a second copy is the point rather than the defect.
///
/// THE BEHAVIOURAL PIN IS HONEST ABOUT ITS REACH, which took measuring. The
/// sibling web guard's `the canonical clamps before the arc` case is VACUOUS —
/// deleting the clamp from `runs/run_stats.ts` leaves all four of its cases
/// green — because the `asin` spelling both trees use is self-clamping over
/// every reachable input: `a` never exceeds 1 by more than one ulp and
/// `Math.sqrt` rounds that back to exactly 1.0. Only the `atan2` spelling
/// distinguishes. The case below therefore says which regression it kills and
/// which it cannot, rather than borrowing the sibling's wording.
///
/// EVERY TEST HERE RESTATES THE POPULATION FLOOR. "No undeclared module
/// computes an arc" and "the matcher still fires" are both satisfied by a tree
/// in which nothing computes anything, which is exactly what the Edge Function
/// vacuity operator (`apps/backend/scripts/check_edge_function_test_vacuity.mjs`)
/// produces — the same reason `_shared/rate_limit_failclosed_guard.test.ts`
/// carries its floor in each case rather than in one.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read
/// supabase/functions/_shared/great_circle_sources.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

import { embeddedHaversineM } from './strava.ts';

/// `supabase/functions/_shared/` -> `supabase/functions/`.
const FUNCTIONS_DIR = new URL('../', import.meta.url).pathname;

/// An `asin`/`atan2` applied to a square root, with at most one wrapping call
/// (the `Math.min(1, …)` clamp) between them.
const ARC_OF_A_SQUARE_ROOT = /Math\.(?:asin|atan2)\([^;]{0,80}?Math\.sqrt\(/g;

interface Source {
	file: string;
	arcs: number;
	reason: string;
}

/// Every place in this tree still computing its own.
const GREAT_CIRCLE_SOURCES: Source[] = [
	{
		file: '_shared/strava.ts',
		arcs: 1,
		reason:
			'THE copy that has to be one. A Deno Edge Function cannot import from `apps/web/src/lib`, ' +
			'and `embeddedHaversineM` is what decides the `fastest_*_s` an IMPORTED run lands with ' +
			'while `runs/run_stats.ts` and `run_stats.dart` decide it for a recorded one. It is those ' +
			'two expression for expression, clamp included, and `_shared/strava.test.ts` pins it to an ' +
			'exact fifty-leg sum rather than to a tolerance — a tolerance is what cannot see the ' +
			'one-ULP divergence of § 1525. A SECOND entry would not have that excuse: every other ' +
			'module in this tree can import this one.',
	},
];

function sourceFiles(): string[] {
	const out: string[] = [];
	const walk = (dir: string, prefix: string) => {
		for (const entry of Deno.readDirSync(dir)) {
			const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
			if (entry.isDirectory) walk(`${dir}${entry.name}/`, rel);
			else if (entry.name.endsWith('.ts') && !entry.name.endsWith('.test.ts')) out.push(rel);
		}
	};
	walk(FUNCTIONS_DIR, '');
	return out.sort();
}

function arcCounts(): Map<string, number> {
	const found = new Map<string, number>();
	for (const file of sourceFiles()) {
		const stripped = Deno.readTextFileSync(`${FUNCTIONS_DIR}${file}`).replace(/\s+/g, '');
		const hits = stripped.match(ARC_OF_A_SQUARE_ROOT);
		if (hits) found.set(file, hits.length);
	}
	return found;
}

/// The floor every case restates. A scan that finds no arc at all satisfies
/// "nothing undeclared computes one" and would score as a passing guard over a
/// tree whose source text has been taken away.
function totalArcs(found: Map<string, number>): number {
	return [...found.values()].reduce((sum, n) => sum + n, 0);
}

Deno.test('no module computes a great-circle distance the table does not know about', () => {
	const found = arcCounts();
	assert(totalArcs(found) >= 1, 'the scan found no great-circle arc at all in this tree');
	const declared = new Set(GREAT_CIRCLE_SOURCES.map((s) => s.file));
	const undeclared = [...found.keys()].filter((f) => !declared.has(f)).sort();
	assertEquals(
		undeclared,
		[],
		'a new copy of the great-circle distance. Import `embeddedHaversineM` from ' +
			'`_shared/strava.ts` instead — it is already the canonical `runs/run_stats.ts` ' +
			'expression for expression. If the module genuinely cannot, add it to ' +
			`GREAT_CIRCLE_SOURCES with the reason: ${undeclared.join(', ')}`,
	);
});

Deno.test('every table entry still computes one, and only as many as it claims', () => {
	const found = arcCounts();
	for (const { file, arcs, reason } of GREAT_CIRCLE_SOURCES) {
		assertEquals(
			found.get(file) ?? 0,
			arcs,
			`${file} computes ${found.get(file) ?? 0} great-circle arcs, table says ${arcs}. ` +
				'If it now imports a shared one, delete the entry — a stale reason outlives the ' +
				`condition it describes. Reason on record: ${reason}`,
		);
	}
});

Deno.test('the scan reaches a real tree, and the matcher still fires on the shape', () => {
	// A scan that silently matches nothing — a moved root, an extension filter
	// broken by a refactor — passes the two cases above for the wrong reason.
	const files = sourceFiles();
	assert(files.length >= 30, `the scan found only ${files.length} modules; the root has moved`);
	assert(files.includes('_shared/strava.ts'), 'the scan no longer reaches the declared module');
	assert(totalArcs(arcCounts()) >= 1, 'the scan found no great-circle arc at all in this tree');

	const sample = 'Math.asin(Math.sqrt(a))Math.asin(Math.min(1,Math.sqrt(a)))' +
		'Math.atan2(Math.sqrt(a),Math.sqrt(1-a))';
	assertEquals(sample.match(ARC_OF_A_SQUARE_ROOT)?.length, 3);
	// A bearing takes an atan2 of no square root and must not be reported.
	assertEquals('Math.atan2(y,x)'.match(ARC_OF_A_SQUARE_ROOT), null);
	// Nor a square root with no arc over it.
	assertEquals('Math.sqrt(a)+Math.sqrt(b)'.match(ARC_OF_A_SQUARE_ROOT), null);
	// Nor two unrelated statements sitting next to each other: the window stops
	// at the statement boundary, so an `asin` on one line and a `sqrt` on the
	// next are not read as one arc.
	assertEquals('Math.asin(x);constb=Math.sqrt(a)'.match(ARC_OF_A_SQUARE_ROOT), null);
});

Deno.test('the one arc this tree keeps answers a number over the whole antipodal family', () => {
	// A behavioural pin, and one that is careful about what it can and cannot
	// prove. The antipodal pairs are where `a` is exactly 1 in exact arithmetic
	// and floating-point rounding alone decides, so they are the only inputs
	// that distinguish the spellings at all.
	//
	// It KILLS a re-spelling back to the unclamped `Math.atan2(sqrt(a),
	// sqrt(1 - a))` — the form this copy carried until § 1525 — which answers
	// NaN on 10 080 of the 258 480 half-degree pairs below.
	//
	// It does NOT kill deleting the clamp from the `asin` spelling, and no test
	// could: measured over 293 216 742 antipodal pairs at 0.013 deg x 0.017 deg,
	// the largest `a` reached in `f64` is 1 + 1 ulp, and `Math.sqrt` halves that
	// excess back to exactly 1.0, so `Math.asin` never sees an argument above 1.
	// `a` cannot go below 0 either — it is `(1 - cos theta) / 2` for a real
	// theta whatever latitudes are passed, and both its terms are products of
	// non-negatives inside the valid range. On this spelling the clamp is
	// unreachable defence in depth; it becomes load-bearing the moment anyone
	// writes the arc the other way, which is exactly what this case watches for.
	let checked = 0;
	for (let lat = -89.5; lat <= 89.5; lat += 0.5) {
		for (let lng = -180; lng < 180; lng += 0.5) {
			const d = embeddedHaversineM(lat, lng, -lat, lng >= 0 ? lng - 180 : lng + 180);
			assert(
				Number.isFinite(d),
				`(${lat}, ${lng}) to its antipode gave ${d}; the arc is not the clamped form`,
			);
			assert(
				d > 20_010_000 && d < 20_020_000,
				`(${lat}, ${lng}) to its antipode gave ${d}, not half a circumference`,
			);
			checked++;
		}
	}
	assertEquals(checked, 258_480);
});
