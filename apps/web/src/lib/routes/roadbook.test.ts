import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildRoadbook, type RoadbookWaypoint, type RoadbookMarker } from './roadbook';

// ~1 km of waypoints heading north from (0,0). Each 0.001° lat ≈ 111 m.
// Build a flat first half and a climbing second half so the effort model has
// something to bite on.
function course(): RoadbookWaypoint[] {
	const pts: RoadbookWaypoint[] = [];
	for (let i = 0; i <= 18; i++) {
		// 18 steps × ~111 m ≈ 2 km total.
		const climbing = i > 9;
		const ele = climbing ? (i - 9) * 30 : 0; // second half climbs 30 m per step
		pts.push({ lat: i * 0.001, lng: 0, ele });
	}
	return pts;
}

function marker(pos: number | null, kind: string, label: string, meta: unknown = {}): RoadbookMarker {
	return { position_m: pos, kind, label, meta };
}

test('legs run start → markers (ordered) → finish', () => {
	const wp = course();
	const rb = buildRoadbook(
		wp,
		[marker(1500, 'aid_station', 'Aid 2'), marker(500, 'aid_station', 'Aid 1')],
		{ goalSeconds: 3600, model: 'even' }
	);
	assert.equal(rb.legs.length, 4);
	assert.equal(rb.legs[0].checkpoint, 'start');
	assert.deepEqual(rb.legs[1].checkpoint, { kind: 'aid_station', label: 'Aid 1' });
	assert.deepEqual(rb.legs[2].checkpoint, { kind: 'aid_station', label: 'Aid 2' });
	assert.equal(rb.legs[3].checkpoint, 'finish');
	// cumulative distance is monotonic and ends at the total.
	assert.ok(rb.legs[1].cumDistM < rb.legs[2].cumDistM);
	assert.equal(rb.legs[3].cumDistM, rb.totalDistM);
});

test('even model splits goal time proportional to distance', () => {
	const wp = course();
	const rb = buildRoadbook(wp, [marker(rbHalf(wp), 'aid_station', 'Mid')], {
		goalSeconds: 4000,
		model: 'even'
	});
	// Mid is at half distance → projected elapsed ≈ half the goal.
	const mid = rb.legs[1].projectedElapsedS;
	assert.ok(Math.abs(mid - 2000) < 50, `mid elapsed ${mid}`);
	assert.equal(Math.round(rb.legs[2].projectedElapsedS), 4000);
});

test('effort model gives the climb leg more time than even pace', () => {
	const wp = course();
	const total = buildRoadbook(wp, [], { goalSeconds: 3600, model: 'even' }).totalDistM;
	const mid = total / 2;
	const even = buildRoadbook(wp, [marker(mid, 'aid_station', 'Mid')], {
		goalSeconds: 3600,
		model: 'even'
	});
	const effort = buildRoadbook(wp, [marker(mid, 'aid_station', 'Mid')], {
		goalSeconds: 3600,
		model: 'effort'
	});
	// The first half is flat, the second half climbs. Under effort the flat
	// first half should be reached SOONER (less of the budget) than under even.
	assert.ok(
		effort.legs[1].projectedElapsedS < even.legs[1].projectedElapsedS,
		`effort mid ${effort.legs[1].projectedElapsedS} should be < even mid ${even.legs[1].projectedElapsedS}`
	);
	// Both still finish at the goal.
	assert.equal(Math.round(effort.legs[2].projectedElapsedS), 3600);
});

test('effort degrades to even when there is no elevation', () => {
	const flat: RoadbookWaypoint[] = Array.from({ length: 11 }, (_, i) => ({
		lat: i * 0.001,
		lng: 0
	}));
	const mid = buildRoadbook(flat, [], { goalSeconds: 3600, model: 'even' }).totalDistM / 2;
	const even = buildRoadbook(flat, [marker(mid, 'aid_station', 'Mid')], {
		goalSeconds: 3600,
		model: 'even'
	});
	const effort = buildRoadbook(flat, [marker(mid, 'aid_station', 'Mid')], {
		goalSeconds: 3600,
		model: 'effort'
	});
	assert.equal(effort.hasElevation, false);
	assert.equal(
		Math.round(effort.legs[1].projectedElapsedS),
		Math.round(even.legs[1].projectedElapsedS)
	);
});

test('cutoff from cutoff_elapsed_s yields a margin and status', () => {
	const wp = course();
	const total = buildRoadbook(wp, [], { goalSeconds: 3600, model: 'even' }).totalDistM;
	const rb = buildRoadbook(
		wp,
		[marker(total / 2, 'cutoff', 'Gate', { cutoff_elapsed_s: 2000 })],
		{ goalSeconds: 3600, model: 'even' }
	);
	const gate = rb.legs[1];
	assert.ok(gate.cutoff);
	assert.equal(gate.cutoff!.limitElapsedS, 2000);
	// Mid elapsed ≈ 1800 → margin ≈ +200 → tight (within 30 min).
	assert.ok(gate.cutoff!.marginS > 0 && gate.cutoff!.marginS < 30 * 60);
	assert.equal(gate.cutoff!.status, 'tight');
});

test('a too-slow goal turns a cutoff red (miss)', () => {
	const wp = course();
	const total = buildRoadbook(wp, [], { goalSeconds: 3600, model: 'even' }).totalDistM;
	const rb = buildRoadbook(
		wp,
		[marker(total / 2, 'cutoff', 'Gate', { cutoff_elapsed_s: 600 })],
		{ goalSeconds: 7200, model: 'even' } // slow goal → reach mid at ~3600 > 600
	);
	assert.equal(rb.legs[1].cutoff!.status, 'miss');
	assert.ok(rb.legs[1].cutoff!.marginS < 0);
});

test('cutoff from cutoff_clock needs a start clock', () => {
	const wp = course();
	const total = buildRoadbook(wp, [], { goalSeconds: 3600, model: 'even' }).totalDistM;
	// Start 06:00 (360 min). Cutoff clock 06:45 → limit 2700 s.
	const rb = buildRoadbook(
		wp,
		[marker(total / 2, 'cutoff', 'Gate', { cutoff_clock: '06:45' })],
		{ goalSeconds: 3600, startClockMin: 360, model: 'even' }
	);
	assert.equal(rb.legs[1].cutoff!.limitElapsedS, 2700);
	// Without a start clock the clock-only cutoff can't resolve.
	const noStart = buildRoadbook(
		wp,
		[marker(total / 2, 'cutoff', 'Gate', { cutoff_clock: '06:45' })],
		{ goalSeconds: 3600, model: 'even' }
	);
	assert.equal(noStart.legs[1].cutoff, undefined);
});

test('projected clock advances from the start and wraps past midnight', () => {
	const wp = course();
	const rb = buildRoadbook(wp, [], { goalSeconds: 3600, startClockMin: 23 * 60 + 30, model: 'even' });
	// Start 23:30, +60 min finish → 00:30 next day → 30 min past midnight.
	assert.equal(Math.round(rb.legs[1].projectedClockMin!), 30);
});

test('markers with null position_m are dropped from the schedule', () => {
	const wp = course();
	const rb = buildRoadbook(
		wp,
		[marker(null, 'aid_station', 'Floating'), marker(500, 'aid_station', 'Real')],
		{ goalSeconds: 3600, model: 'even' }
	);
	assert.equal(rb.legs.length, 3); // start, Real, finish
	assert.deepEqual(rb.legs[1].checkpoint, { kind: 'aid_station', label: 'Real' });
});

test('aid services flow through to the leg', () => {
	const wp = course();
	const rb = buildRoadbook(
		wp,
		[marker(500, 'aid_station', 'Aid', { services: ['water', 'food'] })],
		{ goalSeconds: 3600, model: 'even' }
	);
	assert.deepEqual(rb.legs[1].services, ['water', 'food']);
});

function rbHalf(wp: RoadbookWaypoint[]): number {
	return buildRoadbook(wp, [], { goalSeconds: 1, model: 'even' }).totalDistM / 2;
}
