// The one contract the whole route-design preference feature rests on
// (decisions.md § 795 / § 796): a preference is an enhancement layered on the
// route, and the route is the contract. It may bias a loop; it may never deny
// one. And it may never advertise itself as honoured on any path where the
// served loop did not actually honour it — "echoing `req.preference` back
// would have been free and wrong", because a client repeating the ask would
// tell the runner their quiet route was quiet on no evidence at all.
//
// `generate.test.ts` and `graph_cycle.test.ts` pin these branch by branch.
// This file states them as PROPERTIES over the whole vocabulary and every
// engine shape, so a later branch cannot be added that satisfies its own case
// and violates the rule.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { handleGenerate } from './handler';
import { ROUTE_PREFERENCES, buildCustomModel, type Fetcher, type RoutePreference } from './graphhopper';
import { parsePreferenceApplied } from './graph_cycle';

const GC = 'http://gc.local';
const GH = 'http://gh.local';
const AUTH = 'Bearer test-token';
const GATE_CFG = {
	publicSupabaseUrl: 'http://127.0.0.1:54321',
	publicSupabaseAnonKey: 'sb_publishable_fake_local_anon_key',
	bypassPaywallEnabled: false,
};
const asPro = async () => 'pro' as const;
const START = { lat: 0, lng: 0 };
const TARGET = 5000;

function squareLoop(half: number): [number, number][] {
	return [
		[-half, -half],
		[half, -half],
		[half, half],
		[-half, half],
		[-half, -half],
	];
}

function json(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { 'content-type': 'application/json' },
	});
}

function gcFound(distanceM: number, preferenceApplied?: string): Response {
	return json({
		found: true,
		coordinates: squareLoop(0.0056),
		distanceM,
		areaEfficiency: 0.6,
		largestClean: null,
		...(preferenceApplied === undefined ? {} : { preferenceApplied }),
	});
}

const gcLoopPoor = () => json({ found: false, largestClean: null });
const ghLoop = (distanceM: number) =>
	json({ paths: [{ distance: distanceM, points: { coordinates: squareLoop(0.0056) } }] });

function byEngine(onCycle: Fetcher, onRoundTrip: Fetcher): Fetcher {
	return (url, init) => (url.includes('/cycle') ? onCycle(url, init) : onRoundTrip(url, init));
}

async function generate(preference: RoutePreference | undefined, fetcher: Fetcher, cfg: object) {
	return handleGenerate(
		AUTH,
		{
			start: START,
			targetDistanceM: TARGET,
			seeds: 2,
			...(preference ? { preference } : {}),
		},
		{ ...GATE_CFG, ...cfg },
		{ fetcher, proChecker: asPro },
	);
}

// --- never deny ------------------------------------------------------------

test('no preference turns a servable route into a refusal, on any engine shape', async () => {
	// Every combination of (preference, what the sidecar does, what round_trip
	// does) that serves a route WITHOUT a preference must serve one WITH it.
	// The sidecar's own retry and the handler's plain re-race are what make
	// that true; asserting the outcome rather than the branch is the point.
	const shapes: [string, () => Fetcher][] = [
		[
			'sidecar serves',
			() => byEngine(async () => gcFound(5050), async () => ghLoop(5000)),
		],
		[
			'sidecar loop-poor, round_trip serves',
			() => byEngine(async () => gcLoopPoor(), async () => ghLoop(5000)),
		],
		[
			'sidecar down, round_trip serves',
			() =>
				byEngine(
					async () => {
						throw new Error('ECONNREFUSED');
					},
					async () => ghLoop(5000),
				),
		],
		[
			'sidecar refuses the preference field, retries clean',
			() => {
				let seen = 0;
				return byEngine(
					async (_u, init) => {
						seen++;
						const body = String(init?.body ?? '');
						if (body.includes('preference')) {
							return new Response('json: unknown field "preference"', { status: 400 });
						}
						return gcFound(5050);
					},
					async () => ghLoop(5000),
				);
			},
		],
		[
			'the weighted round_trip race finds nothing, the plain one serves',
			() => {
				return byEngine(
					async () => gcLoopPoor(),
					async (_u, init) =>
						init?.method === 'POST'
							? json({ message: 'no route' }, 400)
							: ghLoop(5000),
				);
			},
		],
	];

	for (const [label, makeFetcher] of shapes) {
		const baseline = await generate(undefined, makeFetcher(), {
			graphCycleUrl: GC,
			graphhopperUrl: GH,
		});
		assert.equal(baseline.status, 200, `${label}: baseline did not serve`);
		for (const pref of ROUTE_PREFERENCES) {
			const withPref = await generate(pref, makeFetcher(), {
				graphCycleUrl: GC,
				graphhopperUrl: GH,
			});
			assert.equal(
				withPref.status,
				200,
				`${label} + ${pref}: a preference denied a route the plain search served`,
			);
		}
	}
});

test('a preference never changes the served geometry into something shorter or empty', async () => {
	// The never-deny retry is only honest if what it serves is a real route.
	// A 200 carrying two points and no distance would satisfy the status
	// assertion above and be useless.
	for (const pref of ROUTE_PREFERENCES) {
		const res = await generate(
			pref,
			byEngine(async () => gcLoopPoor(), async () => ghLoop(5000)),
			{ graphCycleUrl: GC, graphhopperUrl: GH },
		);
		assert.equal(res.status, 200);
		if (res.status !== 200) continue;
		assert.ok(Array.isArray(res.body.coordinates));
		assert.ok(res.body.coordinates.length >= 2, `${pref}: degenerate polyline`);
		assert.ok((res.body.distanceM ?? 0) > 0, `${pref}: no distance`);
	}
});

// --- never claim what was not applied --------------------------------------

test('a preference is claimed only when the SERVING engine names the same one', async () => {
	// Three ways to be wrong, all pinned: naming a different preference,
	// naming one the request never carried, and naming one on a loop the
	// unweighted retry found.
	const cases: [string, string | undefined, RoutePreference | undefined, boolean][] = [
		['exact agreement', 'quiet', 'quiet', true],
		['sidecar names a different one', 'scenic', 'quiet', false],
		['sidecar names one nobody asked for', 'scenic', undefined, false],
		['sidecar names nothing (unweighted retry served)', undefined, 'quiet', false],
		['sidecar names an unknown token', 'hilly', 'quiet', false],
		['sidecar names a non-string', undefined, 'quiet', false],
	];
	for (const [label, applied, asked, expectClaim] of cases) {
		const res = await generate(
			asked,
			byEngine(async () => gcFound(5050, applied), async () => ghLoop(5000)),
			{ graphCycleUrl: GC, graphhopperUrl: GH },
		);
		assert.equal(res.status, 200, label);
		if (res.status !== 200) continue;
		assert.equal(
			res.body.preferenceApplied,
			expectClaim ? asked : undefined,
			`${label}: preferenceApplied was ${String(res.body.preferenceApplied)}`,
		);
	}
});

test('every preference the sidecar can honour round-trips through the body', async () => {
	for (const pref of ROUTE_PREFERENCES) {
		const res = await generate(
			pref,
			byEngine(async () => gcFound(5050, pref), async () => ghLoop(5000)),
			{ graphCycleUrl: GC, graphhopperUrl: GH },
		);
		assert.equal(res.status, 200, pref);
		if (res.status === 200) assert.equal(res.body.preferenceApplied, pref, pref);
	}
});

test('round_trip claims only a preference GraphHopper could express as a model', async () => {
	// `cul_de_sac` is a claim about the SHAPE of the assembled loop, so
	// `buildCustomModel` returns null and round_trip runs plain — it must
	// therefore never report the preference as applied, on any path.
	assert.equal(buildCustomModel('cul_de_sac'), null);
	for (const pref of ROUTE_PREFERENCES) {
		const res = await generate(
			pref,
			byEngine(async () => gcLoopPoor(), async () => ghLoop(5000)),
			{ graphCycleUrl: GC, graphhopperUrl: GH },
		);
		assert.equal(res.status, 200, pref);
		if (res.status !== 200) continue;
		const expressible = buildCustomModel(pref) !== null;
		assert.equal(
			res.body.preferenceApplied,
			expressible ? pref : undefined,
			`${pref}: round_trip claimed a preference it ${expressible ? 'should' : 'cannot'} express`,
		);
	}
});

test('the in-browser fallback path claims nothing: an unreached server names no preference', async () => {
	// No engine configured at all is a 501, and the page then falls through to
	// the in-browser heuristic, which honours no preference whatsoever. There
	// is no body to read a claim out of, which is what makes "absent means not
	// applied" the only safe grading on the client.
	const res = await generate('quiet', async () => ghLoop(5000), {});
	assert.equal(res.status, 501);
	assert.ok(!('preferenceApplied' in (res.body as object)));
});

test('parsePreferenceApplied fails closed on every shape a sidecar could send', () => {
	for (const pref of ROUTE_PREFERENCES) {
		assert.equal(parsePreferenceApplied({ preferenceApplied: pref }), pref);
	}
	const rejected: unknown[] = [
		null,
		undefined,
		{},
		{ preferenceApplied: null },
		{ preferenceApplied: undefined },
		{ preferenceApplied: '' },
		{ preferenceApplied: 'QUIET' },
		{ preferenceApplied: 'quiet ' },
		{ preferenceApplied: 'cul-de-sac' },
		{ preferenceApplied: 'hilly' },
		{ preferenceApplied: 1 },
		{ preferenceApplied: true },
		{ preferenceApplied: ['quiet'] },
		{ preferenceApplied: { value: 'quiet' } },
		'quiet',
		42,
	];
	for (const shape of rejected) {
		assert.equal(
			parsePreferenceApplied(shape),
			null,
			`accepted ${JSON.stringify(shape)}`,
		);
	}
});

// --- the request boundary ---------------------------------------------------

test('an unrecognised preference is dropped, never 400d, and never forwarded', async () => {
	// A stale or garbled knob must never block route generation, and it must
	// not reach an engine as a token it cannot route.
	const bodies: string[] = [];
	const fetcher = byEngine(
		async (_u, init) => {
			bodies.push(String(init?.body ?? ''));
			return gcFound(5050, 'quiet');
		},
		async () => ghLoop(5000),
	);
	for (const bogus of ['hilly', 'QUIET', 'cul-de-sac', '', 'null', 'quiet;scenic']) {
		bodies.length = 0;
		const res = await handleGenerate(
			AUTH,
			{ start: START, targetDistanceM: TARGET, seeds: 1, preference: bogus },
			{ ...GATE_CFG, graphCycleUrl: GC, graphhopperUrl: GH },
			{ fetcher, proChecker: asPro },
		);
		assert.equal(res.status, 200, bogus);
		assert.ok(!bodies[0].includes('preference'), `${bogus} was forwarded to the sidecar`);
		// And a sidecar that volunteers a preference cannot make the request
		// look like it carried one.
		if (res.status === 200) assert.equal(res.body.preferenceApplied, undefined, bogus);
	}
});

test('a non-string preference is dropped as firmly as an unknown string', async () => {
	const fetcher = byEngine(async () => gcFound(5050, 'quiet'), async () => ghLoop(5000));
	for (const bogus of [1, true, null, {}, ['quiet']]) {
		const res = await handleGenerate(
			AUTH,
			{ start: START, targetDistanceM: TARGET, seeds: 1, preference: bogus },
			{ ...GATE_CFG, graphCycleUrl: GC, graphhopperUrl: GH },
			{ fetcher, proChecker: asPro },
		);
		assert.equal(res.status, 200, JSON.stringify(bogus));
		if (res.status === 200) {
			assert.equal(res.body.preferenceApplied, undefined, JSON.stringify(bogus));
		}
	}
});

test('every custom model is a soft weight — no multiplier may disconnect the graph', () => {
	// § 795: weights are soft only, because a hard filter can disconnect a
	// buildable neighbourhood into "no loop" and the fallback then serves a
	// WORSE route than the unbiased search would.
	for (const pref of ROUTE_PREFERENCES) {
		const model = buildCustomModel(pref);
		if (model === null) continue;
		assert.ok(model.priority.length > 0, `${pref}: an empty model is not a preference`);
		for (const clause of model.priority) {
			assert.ok(
				Number.isFinite(clause.multiply_by),
				`${pref}: non-finite multiplier ${clause.multiply_by}`,
			);
			assert.ok(clause.multiply_by > 0, `${pref}: ${clause.multiply_by} removes an edge`);
			// Only `road_class`, because the deployed engine declares just the
			// foot-profile encoded values and naming one it lacks fails the
			// WHOLE request — which the never-deny retry would then hide.
			const condition = clause.if ?? clause.else_if ?? '';
			assert.match(condition, /^road_class == [A-Z_]+$/, `${pref}: ${condition}`);
		}
	}
	assert.equal(buildCustomModel(undefined), null);
});
