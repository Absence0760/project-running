import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	qualifyingAttempts,
	summariseHistory,
	formatSignedDelta,
	type RouteHistoryRun,
} from './route_history.js';

const baseRun = (over: Partial<RouteHistoryRun>): RouteHistoryRun => ({
	id: crypto.randomUUID(),
	route_id: 'route-1',
	distance_m: 5000,
	duration_s: 1500,
	metadata: null,
	...over,
});

test('qualifyingAttempts excludes runs without a route_id', () => {
	const me = baseRun({ id: 'me', route_id: null });
	const others = [baseRun({ id: 'a' }), baseRun({ id: 'b' })];
	assert.deepEqual(qualifyingAttempts(me, others), []);
});

test('qualifyingAttempts filters to same route_id', () => {
	const me = baseRun({ id: 'me', route_id: 'route-1' });
	const others = [
		baseRun({ id: 'same', route_id: 'route-1' }),
		baseRun({ id: 'different', route_id: 'route-2' }),
	];
	const got = qualifyingAttempts(me, others);
	assert.equal(got.length, 1);
	assert.equal(got[0].id, 'same');
});

test('qualifyingAttempts excludes runs under 100 m', () => {
	const me = baseRun({ id: 'me' });
	const others = [
		baseRun({ id: 'long', distance_m: 5000 }),
		baseRun({ id: 'tiny', distance_m: 50 }),
	];
	const got = qualifyingAttempts(me, others);
	assert.equal(got.length, 1);
	assert.equal(got[0].id, 'long');
});

test('qualifyingAttempts filters by activity_type (defaulting to run)', () => {
	const me = baseRun({ id: 'me' }); // metadata null → defaults to 'run'
	const others = [
		baseRun({ id: 'run', metadata: { activity_type: 'run' } }),
		baseRun({ id: 'walk', metadata: { activity_type: 'walk' } }),
		baseRun({ id: 'undef' }), // also 'run'
	];
	const got = qualifyingAttempts(me, others);
	assert.deepEqual(
		got.map((r) => r.id).sort(),
		['run', 'undef'],
	);
});

test('qualifyingAttempts sorts by duration ascending', () => {
	const me = baseRun({ id: 'me' });
	const others = [
		baseRun({ id: 'slow', duration_s: 2000 }),
		baseRun({ id: 'fast', duration_s: 1200 }),
		baseRun({ id: 'medium', duration_s: 1600 }),
	];
	const got = qualifyingAttempts(me, others);
	assert.deepEqual(
		got.map((r) => r.id),
		['fast', 'medium', 'slow'],
	);
});

test('summariseHistory returns null for fewer than 2 attempts', () => {
	const only = [baseRun({ id: 'me', duration_s: 1500 })];
	assert.equal(summariseHistory('me', only), null);
});

test('summariseHistory marks PB correctly', () => {
	const attempts = [
		baseRun({ id: 'me', duration_s: 1200 }),
		baseRun({ id: 'old', duration_s: 1500 }),
	];
	const s = summariseHistory('me', attempts)!;
	assert.equal(s.isPb, true);
	assert.equal(s.rank, 1);
	assert.equal(s.total, 2);
	assert.equal(s.deltaSeconds, 0);
});

test('summariseHistory computes delta and rank for non-PB run', () => {
	const attempts = [
		baseRun({ id: 'pb', duration_s: 1200 }),
		baseRun({ id: 'me', duration_s: 1283 }),
		baseRun({ id: 'slow', duration_s: 1500 }),
	];
	const s = summariseHistory('me', attempts)!;
	assert.equal(s.isPb, false);
	assert.equal(s.rank, 2);
	assert.equal(s.total, 3);
	assert.equal(s.deltaSeconds, 83);
	assert.equal(s.pb.id, 'pb');
});

test('summariseHistory returns null when current run is not in attempts list', () => {
	const attempts = [
		baseRun({ id: 'a', duration_s: 1200 }),
		baseRun({ id: 'b', duration_s: 1500 }),
	];
	assert.equal(summariseHistory('not-in-list', attempts), null);
});

test('formatSignedDelta renders signs and unit boundaries', () => {
	assert.equal(formatSignedDelta(0), '0:00');
	assert.equal(formatSignedDelta(5), '+0:05');
	assert.equal(formatSignedDelta(-5), '−0:05');
	assert.equal(formatSignedDelta(83), '+1:23');
	assert.equal(formatSignedDelta(-3725), '−1:02:05');
});
