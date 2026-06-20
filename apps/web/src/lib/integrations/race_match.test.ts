import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	haversineMetres,
	isRaceMatchCandidate,
	RACE_MATCH_RADIUS_M,
	RACE_MATCH_THRESHOLD,
	raceDistanceBand,
	raceMatchScore
} from './race_match';

test('raceDistanceBand buckets recognised distances', () => {
	assert.equal(raceDistanceBand(5000), '5k');
	assert.equal(raceDistanceBand(10000), '10k');
	assert.equal(raceDistanceBand(21097), 'half');
	assert.equal(raceDistanceBand(42195), 'marathon');
	assert.equal(raceDistanceBand(50000), 'ultra');
	assert.equal(raceDistanceBand(160934), 'ultra');
});

test('raceDistanceBand tolerance edges', () => {
	assert.equal(raceDistanceBand(4500), '5k');
	assert.equal(raceDistanceBand(5500), '5k');
	assert.equal(raceDistanceBand(9000), '10k');
	assert.equal(raceDistanceBand(11000), '10k');
});

test('raceDistanceBand returns null for unrecognised / tiny distances', () => {
	assert.equal(raceDistanceBand(4499), null);
	assert.equal(raceDistanceBand(7000), null); // between 5k and 10k bands
	assert.equal(raceDistanceBand(15000), null); // between 10k and half
	assert.equal(raceDistanceBand(null), null);
	assert.equal(raceDistanceBand(undefined), null);
	assert.equal(raceDistanceBand(NaN), null);
});

test('different calendar day scores 0', () => {
	const score = raceMatchScore(
		{ runDate: '2025-09-20T09:00:00Z', runStartLatLng: null, runDistanceM: 21097 },
		{ race_date: '2025-09-21', distance_m: 21097, distance_m_away: 100 }
	);
	assert.equal(score, 0);
});

test('same day with near start + matching band scores high', () => {
	const score = raceMatchScore(
		{ runDate: '2025-09-21T09:00:00Z', runStartLatLng: { lat: 0, lng: 0 }, runDistanceM: 21097 },
		{ race_date: '2025-09-21', distance_m: 21097, distance_m_away: 200 }
	);
	assert.ok(score > 0.95, `expected near-1, got ${score}`);
});

test('same day only (no proximity, no band) normalises to 1', () => {
	const score = raceMatchScore(
		{ runDate: '2025-09-21', runStartLatLng: null, runDistanceM: null },
		{ race_date: '2025-09-21', distance_m: null, distance_m_away: null }
	);
	// Only the day signal could be evaluated → 0.5 / 0.5 = 1.
	assert.equal(score, 1);
});

test('same day + matching band but no proximity still strong', () => {
	const score = raceMatchScore(
		{ runDate: '2025-09-21', runStartLatLng: null, runDistanceM: 5000 },
		{ race_date: '2025-09-21', distance_m: 5000, distance_m_away: null }
	);
	// (0.5 + 0.2) / (0.5 + 0.2) = 1.
	assert.equal(score, 1);
});

test('same day + mismatched band lowers the score below threshold contribution', () => {
	const score = raceMatchScore(
		{ runDate: '2025-09-21', runStartLatLng: null, runDistanceM: 5000 },
		{ race_date: '2025-09-21', distance_m: 42195, distance_m_away: null }
	);
	// (0.5) / (0.5 + 0.2) ≈ 0.714 — day matched, band did not.
	assert.ok(Math.abs(score - 0.5 / 0.7) < 1e-9, `got ${score}`);
});

test('proximity falloff is linear to the radius edge', () => {
	const half = raceMatchScore(
		{ runDate: '2025-09-21', runStartLatLng: { lat: 0, lng: 0 }, runDistanceM: null },
		{ race_date: '2025-09-21', distance_m: null, distance_m_away: RACE_MATCH_RADIUS_M / 2 }
	);
	// (0.5 + 0.3*0.5) / (0.5 + 0.3) = 0.65 / 0.8.
	assert.ok(Math.abs(half - 0.65 / 0.8) < 1e-9, `got ${half}`);
});

test('start beyond the radius contributes no proximity points', () => {
	const score = raceMatchScore(
		{ runDate: '2025-09-21', runStartLatLng: { lat: 0, lng: 0 }, runDistanceM: null },
		{ race_date: '2025-09-21', distance_m: null, distance_m_away: RACE_MATCH_RADIUS_M * 3 }
	);
	// (0.5 + 0) / (0.5 + 0.3) = 0.625.
	assert.ok(Math.abs(score - 0.5 / 0.8) < 1e-9, `got ${score}`);
});

test('isRaceMatchCandidate gates on the threshold', () => {
	const near = {
		runDate: '2025-09-21',
		runStartLatLng: { lat: 0, lng: 0 },
		runDistanceM: 21097
	};
	assert.equal(
		isRaceMatchCandidate(near, { race_date: '2025-09-21', distance_m: 21097, distance_m_away: 100 }),
		true
	);
	assert.equal(
		isRaceMatchCandidate(near, { race_date: '2025-09-22', distance_m: 21097, distance_m_away: 100 }),
		false
	);
});

test('full ISO timestamp and date-only compare on the calendar day', () => {
	const score = raceMatchScore(
		{ runDate: '2025-09-21T23:59:00Z', runStartLatLng: null, runDistanceM: 10000 },
		{ race_date: '2025-09-21', distance_m: 10000, distance_m_away: null }
	);
	assert.equal(score, 1);
});

test('haversineMetres ~0 for identical points', () => {
	assert.ok(haversineMetres({ lat: 51.5, lng: -0.1 }, { lat: 51.5, lng: -0.1 }) < 1e-6);
});

test('haversineMetres ~111km per degree of latitude', () => {
	const d = haversineMetres({ lat: 0, lng: 0 }, { lat: 1, lng: 0 });
	assert.ok(Math.abs(d - 111195) < 500, `got ${d}`);
});

test('RACE_MATCH_THRESHOLD is the documented 0.5', () => {
	assert.equal(RACE_MATCH_THRESHOLD, 0.5);
});
