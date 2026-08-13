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

test('cutoff_clock equal to the start clock resolves to a 24h limit, not 0s', () => {
	const wp = course();
	const total = buildRoadbook(wp, [], { goalSeconds: 3600, model: 'even' }).totalDistM;
	// Start 06:00, overall cutoff expressed as the same wall clock one day on
	// ('06:00') — the natural way to write a 24h limit when the clock field
	// carries no day. Must be 86400 s, not a 0-second window that misses
	// every runner from the gun.
	const rb = buildRoadbook(
		wp,
		[marker(total / 2, 'cutoff', 'Gate', { cutoff_clock: '06:00' })],
		{ goalSeconds: 3600, startClockMin: 360, model: 'even' }
	);
	assert.equal(rb.legs[1].cutoff!.limitElapsedS, 86_400);
	assert.equal(rb.legs[1].cutoff!.status, 'safe');
});

test('cutoff_clock resolves from the start alone, never from the projection', () => {
	const wp = course();
	const total = buildRoadbook(wp, [], { goalSeconds: 1, model: 'even' }).totalDistM;
	// Start 08:00, cutoff clock 14:00 → the limit is hour 6, whoever is running
	// and however slowly. Snapping the day to the nearest projection made the
	// limit move with the goal time: a 40h goal put the projected arrival at
	// hour 30, which pulled the limit out to 14:00 the NEXT day and reported a
	// 24h-blown cutoff as merely tight.
	const limits = [4 * 3600, 10 * 3600, 40 * 3600, 100 * 3600].map(
		(goalSeconds) =>
			buildRoadbook(wp, [marker(total * 0.75, 'cutoff', 'Gate', { cutoff_clock: '14:00' })], {
				goalSeconds,
				startClockMin: 480,
				model: 'even'
			}).legs[1].cutoff!.limitElapsedS
	);
	assert.deepEqual(limits, [21_600, 21_600, 21_600, 21_600]);

	// And the blown cutoff reads as blown: 40h goal → arrival ≈ hour 30 against
	// an hour-6 limit.
	const slow = buildRoadbook(
		wp,
		[marker(total * 0.75, 'cutoff', 'Gate', { cutoff_clock: '14:00' })],
		{ goalSeconds: 40 * 3600, startClockMin: 480, model: 'even' }
	);
	assert.equal(slow.legs[1].cutoff!.status, 'miss');
	assert.ok(slow.legs[1].cutoff!.marginS < -20 * 3600);
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

// A 4 km 25 % climb then 4 km flat, sampled every `spacingM` metres. The
// terrain is fixed; only the file's point density changes.
function climbCourse(spacingM: number): RoadbookWaypoint[] {
	const pts: RoadbookWaypoint[] = [];
	const mPerDegLat = 111_320;
	const climbM = 4000;
	for (let d = 0; d <= climbM * 2; d += spacingM) {
		pts.push({ lat: 45 + d / mPerDegLat, lng: 7, ele: Math.min(d, climbM) * 0.25 });
	}
	return pts;
}

function midArrivalS(wp: RoadbookWaypoint[], model: 'effort' | 'even'): number {
	const rb = buildRoadbook(wp, [marker(4000, 'aid_station', 'Top', {})], {
		goalSeconds: 5400,
		model
	});
	return rb.legs[1].projectedElapsedS;
}

test('effort allocation survives a densely-sampled course', () => {
	// Every point-pair is under MIN_SEGMENT_M here, so grading each pair on its
	// own read the whole climb as flat and effort collapsed onto even pace.
	const dense = climbCourse(3);
	const effort = midArrivalS(dense, 'effort');
	const even = midArrivalS(dense, 'even');
	assert.ok(effort > even * 1.4, `effort ${effort} vs even ${even}`);
});

test('effort allocation is a property of the terrain, not the sampling density', () => {
	const coarse = midArrivalS(climbCourse(20), 'effort');
	for (const spacing of [10, 3, 1]) {
		const dense = midArrivalS(climbCourse(spacing), 'effort');
		assert.ok(
			Math.abs(dense - coarse) / coarse < 0.01,
			`spacing ${spacing}m gave ${dense}s vs ${coarse}s at 20m`
		);
	}
});

test('a trailing sub-threshold segment is graded flat, not amplified', () => {
	// 1 km of flat at 20 m spacing, then one last point 3 m on with a 1 m rise:
	// a 33 % grade no altimeter can support over 3 m. That trailing window never
	// clears MIN_SEGMENT_M, so it must stay flat — grading it on its own span
	// would bill it as ~3.9x effort and pull every arrival before it earlier.
	const wp: RoadbookWaypoint[] = [];
	for (let d = 0; d <= 1000; d += 20) wp.push({ lat: 45 + d / 111_320, lng: 7, ele: 0 });
	wp.push({ lat: 45 + 1003 / 111_320, lng: 7, ele: 1 });
	const mid = [marker(500, 'aid_station', 'Mid', {})];
	const effort = buildRoadbook(wp, mid, { goalSeconds: 5400, model: 'effort' });
	const even = buildRoadbook(wp, mid, { goalSeconds: 5400, model: 'even' });
	assert.ok(effort.hasElevation, 'the effort model must actually be in play');
	assert.ok(
		Math.abs(effort.legs[1].projectedElapsedS - even.legs[1].projectedElapsedS) < 1e-6,
		`effort ${effort.legs[1].projectedElapsedS} vs even ${even.legs[1].projectedElapsedS}`
	);
});

function rbHalf(wp: RoadbookWaypoint[]): number {
	return buildRoadbook(wp, [], { goalSeconds: 1, model: 'even' }).totalDistM / 2;
}
