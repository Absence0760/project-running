import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildRoadbook, type RoadbookMarker, type RoadbookWaypoint } from '../routes/roadbook';
import { nextCutoffEta, CUTOFF_TIGHT_S, type LiveCutoffInput } from './live_cutoff_eta';

// A flat ~40 km line east along the equator (no elevation → even pacing). The
// haversine of one degree of longitude at the equator is ~111.32 km, so a small
// lng span gives a known distance.
function flatRoute(metres: number, steps = 20): RoadbookWaypoint[] {
	const totalDeg = metres / 111_320;
	const out: RoadbookWaypoint[] = [];
	for (let i = 0; i <= steps; i++) out.push({ lat: 0, lng: (totalDeg * i) / steps });
	return out;
}

// Build legs with two cutoffs: ~20 km (limit 7200 s) and ~40 km (limit 18000 s).
function legsWithTwoCutoffs() {
	const waypoints = flatRoute(40_000);
	const markers: RoadbookMarker[] = [
		{ position_m: 20_000, kind: 'cutoff', label: 'Halfway', meta: { cutoff_elapsed_s: 7_200 } },
		{ position_m: 40_000, kind: 'cutoff', label: 'Finish gate', meta: { cutoff_elapsed_s: 18_000 } }
	];
	return buildRoadbook(waypoints, markers, { goalSeconds: 16_000, model: 'even' }).legs;
}

function input(over: Partial<LiveCutoffInput>): LiveCutoffInput {
	return {
		distAlongRouteM: 10_000,
		elapsedS: 3_600,
		recentPaceSecPerKm: 360,
		legs: legsWithTwoCutoffs(),
		stale: false,
		...over
	};
}

test('on-pace projection grades the next cutoff "on"', () => {
	// 10 km to the 20 km cutoff at 360 s/km = 3600 s more; arrive at 7200 == limit.
	// margin 0 is tight, so go faster to land comfortably under.
	const eta = nextCutoffEta(input({ recentPaceSecPerKm: 180 }));
	assert.equal(eta.checkpoint?.label, 'Halfway');
	// distanceToM = 20000 - 10000 = 10000
	assert.equal(eta.distanceToM, 10_000);
	// arrival = 3600 + 10*180 = 5400; margin = 7200 - 5400 = 1800 > tight
	assert.equal(eta.projectedArrivalElapsedS, 5_400);
	assert.equal(eta.marginS, 1_800);
	assert.equal(eta.status, 'on');
	assert.ok(eta.marginS! >= CUTOFF_TIGHT_S);
});

test('a margin just under the tight threshold grades "tight"', () => {
	// Want margin = CUTOFF_TIGHT_S - 1 = 1799. arrival = 7200 - 1799 = 5401.
	// 5401 = 3600 + 10*pace → pace = 180.1 s/km.
	const eta = nextCutoffEta(input({ recentPaceSecPerKm: 180.1 }));
	assert.equal(eta.status, 'tight');
	assert.ok(eta.marginS! > 0 && eta.marginS! < CUTOFF_TIGHT_S);
});

test('a negative margin grades "behind"', () => {
	// pace 540 s/km → arrival = 3600 + 10*540 = 9000 > 7200 limit → margin -1800.
	const eta = nextCutoffEta(input({ recentPaceSecPerKm: 540 }));
	assert.equal(eta.status, 'behind');
	assert.equal(eta.projectedArrivalElapsedS, 9_000);
	assert.equal(eta.marginS, -1_800);
});

test('a stale live fix returns unknown with no fabricated ETA', () => {
	const eta = nextCutoffEta(input({ stale: true, recentPaceSecPerKm: 180 }));
	assert.equal(eta.status, 'unknown');
	assert.equal(eta.projectedArrivalElapsedS, null);
	assert.equal(eta.marginS, null);
	// still names the checkpoint + distance so the card can show "next cutoff ahead"
	assert.equal(eta.checkpoint?.label, 'Halfway');
	assert.equal(eta.distanceToM, 10_000);
});

test('null pace returns unknown', () => {
	const eta = nextCutoffEta(input({ recentPaceSecPerKm: null }));
	assert.equal(eta.status, 'unknown');
	assert.equal(eta.projectedArrivalElapsedS, null);
	assert.equal(eta.marginS, null);
});

test('zero (or negative) pace returns unknown', () => {
	const eta = nextCutoffEta(input({ recentPaceSecPerKm: 0 }));
	assert.equal(eta.status, 'unknown');
	assert.equal(eta.projectedArrivalElapsedS, null);
});

test('a non-finite pace returns unknown, never a fabricated on-pace ETA', () => {
	for (const pace of [Number.NaN, Number.POSITIVE_INFINITY]) {
		const eta = nextCutoffEta(input({ recentPaceSecPerKm: pace }));
		assert.equal(eta.status, 'unknown');
		assert.equal(eta.projectedArrivalElapsedS, null);
	}
});

test('a runner past the last cutoff has no checkpoint and is unknown', () => {
	const eta = nextCutoffEta(input({ distAlongRouteM: 40_000 }));
	assert.equal(eta.checkpoint, null);
	assert.equal(eta.distanceToM, 0);
	assert.equal(eta.projectedArrivalElapsedS, null);
	assert.equal(eta.marginS, null);
	assert.equal(eta.status, 'unknown');
});

test('picks the NEAREST cutoff ahead when several remain', () => {
	const eta = nextCutoffEta(input({ distAlongRouteM: 5_000 }));
	assert.equal(eta.checkpoint?.label, 'Halfway');
	assert.equal(eta.distanceToM, 15_000); // 20000 - 5000, not the 40k gate
});

test('ignores cutoffs already behind the runner', () => {
	// Past the 20 km cutoff → next ahead is the 40 km finish gate. The roadbook
	// clamps the marker to the haversine-walked total (~40 km within rounding),
	// so assert the distance is in the right neighbourhood, not exact.
	const eta = nextCutoffEta(input({ distAlongRouteM: 25_000 }));
	assert.equal(eta.checkpoint?.label, 'Finish gate');
	assert.ok(Math.abs(eta.distanceToM - 15_000) < 100); // ~40000 - 25000
});
