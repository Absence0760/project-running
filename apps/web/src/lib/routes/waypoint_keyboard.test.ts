import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	NUDGE_STEP_LARGE_M,
	NUDGE_STEP_M,
	nudgeLatLng,
	waypointKeyAction,
} from './waypoint_keyboard';

const plain = (key: string) => ({ key, altKey: false, shiftKey: false });
const alt = (key: string, shiftKey = false) => ({ key, altKey: true, shiftKey });

test('arrow keys rove focus with wraparound', () => {
	assert.deepEqual(waypointKeyAction(plain('ArrowDown'), 0, 3), { type: 'focus', index: 1 });
	assert.deepEqual(waypointKeyAction(plain('ArrowDown'), 2, 3), { type: 'focus', index: 0 });
	assert.deepEqual(waypointKeyAction(plain('ArrowUp'), 0, 3), { type: 'focus', index: 2 });
	assert.deepEqual(waypointKeyAction(plain('Home'), 2, 3), { type: 'focus', index: 0 });
	assert.deepEqual(waypointKeyAction(plain('End'), 0, 3), { type: 'focus', index: 2 });
});

test('empty list produces no focus action', () => {
	assert.equal(waypointKeyAction(plain('ArrowDown'), 0, 0), null);
});

test('delete and backspace remove; enter and space activate', () => {
	assert.deepEqual(waypointKeyAction(plain('Delete'), 1, 3), { type: 'remove' });
	assert.deepEqual(waypointKeyAction(plain('Backspace'), 1, 3), { type: 'remove' });
	assert.deepEqual(waypointKeyAction(plain('Enter'), 1, 3), { type: 'activate' });
	assert.deepEqual(waypointKeyAction(plain(' '), 1, 3), { type: 'activate' });
});

test('alt+arrows nudge geographically, shift scales the step', () => {
	assert.deepEqual(waypointKeyAction(alt('ArrowUp'), 0, 3), {
		type: 'nudge',
		dNorthM: NUDGE_STEP_M,
		dEastM: 0,
	});
	assert.deepEqual(waypointKeyAction(alt('ArrowDown', true), 0, 3), {
		type: 'nudge',
		dNorthM: -NUDGE_STEP_LARGE_M,
		dEastM: 0,
	});
	assert.deepEqual(waypointKeyAction(alt('ArrowRight'), 0, 3), {
		type: 'nudge',
		dNorthM: 0,
		dEastM: NUDGE_STEP_M,
	});
	assert.deepEqual(waypointKeyAction(alt('ArrowLeft'), 0, 3), {
		type: 'nudge',
		dNorthM: 0,
		dEastM: -NUDGE_STEP_M,
	});
});

test('non-navigation keys pass through', () => {
	assert.equal(waypointKeyAction(plain('Tab'), 0, 3), null);
	assert.equal(waypointKeyAction(plain('a'), 0, 3), null);
	assert.equal(waypointKeyAction(alt('Delete'), 0, 3), null);
});

test('nudge north moves latitude only', () => {
	const p = nudgeLatLng({ lat: 51.5, lng: -0.12 }, 111.32, 0);
	assert.ok(Math.abs(p.lat - 51.501) < 1e-6);
	assert.equal(p.lng, -0.12);
});

test('nudge east shrinks with cos(lat)', () => {
	const equator = nudgeLatLng({ lat: 0, lng: 10 }, 0, 111.32);
	assert.ok(Math.abs(equator.lng - 10.001) < 1e-6);
	// At 60°N the same metres cover twice the longitude degrees.
	const north = nudgeLatLng({ lat: 60, lng: 10 }, 0, 111.32);
	assert.ok(Math.abs(north.lng - 10.002) < 1e-5);
});

test('latitude clamps at the mercator band and longitude wraps', () => {
	assert.equal(nudgeLatLng({ lat: 84.9999, lng: 0 }, 100000, 0).lat, 85);
	assert.equal(nudgeLatLng({ lat: -84.9999, lng: 0 }, -100000, 0).lat, -85);
	const wrapped = nudgeLatLng({ lat: 0, lng: 179.9999 }, 0, 111.32);
	assert.ok(wrapped.lng < -179.99);
});

test('polar cosine clamp keeps the eastward step finite', () => {
	const p = nudgeLatLng({ lat: 89.999, lng: 0 }, 0, NUDGE_STEP_M);
	assert.ok(Math.abs(p.lng) < 1);
});
