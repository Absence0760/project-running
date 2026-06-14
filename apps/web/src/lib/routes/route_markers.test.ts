import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	ROUTE_MARKER_KINDS,
	AID_SERVICES,
	kindSpec,
	sortMarkers,
	parseCutoff
} from './route_markers.ts';

test('every kind has a unique key, label key, and hex colour', () => {
	const keys = new Set(ROUTE_MARKER_KINDS.map((k) => k.kind));
	assert.equal(keys.size, ROUTE_MARKER_KINDS.length);
	for (const k of ROUTE_MARKER_KINDS) {
		assert.match(k.color, /^#[0-9a-f]{6}$/);
		assert.ok(k.labelKey.startsWith('routeMarker.kind.'));
	}
});

test('only aid_station carries services; only cutoff carries a cutoff', () => {
	assert.equal(kindSpec('aid_station').hasServices, true);
	assert.equal(kindSpec('aid_station').hasCutoff, false);
	assert.equal(kindSpec('cutoff').hasCutoff, true);
	assert.equal(kindSpec('cutoff').hasServices, false);
	assert.equal(ROUTE_MARKER_KINDS.filter((k) => k.hasServices).length, 1);
	assert.equal(ROUTE_MARKER_KINDS.filter((k) => k.hasCutoff).length, 1);
});

test('kindSpec falls back to custom for an unknown kind', () => {
	assert.equal(kindSpec('gas_station').kind, 'custom');
	assert.equal(kindSpec('aid_station').kind, 'aid_station');
});

test('aid services vocabulary is stable', () => {
	assert.deepEqual(AID_SERVICES, ['water', 'food', 'medical', 'toilets', 'drop_bag']);
});

test('sortMarkers orders by position_m, nulls last, stable by created_at', () => {
	const markers = [
		{ id: 'c', position_m: null, created_at: '2026-01-01T00:00:02Z' },
		{ id: 'a', position_m: 1500, created_at: '2026-01-01T00:00:00Z' },
		{ id: 'd', position_m: null, created_at: '2026-01-01T00:00:01Z' },
		{ id: 'b', position_m: 300, created_at: '2026-01-01T00:00:09Z' }
	];
	assert.deepEqual(
		sortMarkers(markers).map((m) => m.id),
		['b', 'a', 'd', 'c']
	);
});

test('sortMarkers breaks position ties by created_at and does not mutate input', () => {
	const markers = [
		{ id: 'y', position_m: 500, created_at: '2026-01-01T00:00:05Z' },
		{ id: 'x', position_m: 500, created_at: '2026-01-01T00:00:01Z' }
	];
	const sorted = sortMarkers(markers);
	assert.deepEqual(sorted.map((m) => m.id), ['x', 'y']);
	assert.equal(markers[0].id, 'y'); // original untouched
});

test('parseCutoff accepts a valid 24h clock', () => {
	assert.deepEqual(parseCutoff({ cutoff_clock: '14:30' }), { clock: '14:30' });
	assert.deepEqual(parseCutoff({ cutoff_clock: '00:00' }), { clock: '00:00' });
	assert.deepEqual(parseCutoff({ cutoff_clock: '23:59' }), { clock: '23:59' });
});

test('parseCutoff rejects an invalid clock', () => {
	assert.equal(parseCutoff({ cutoff_clock: '24:00' }), null);
	assert.equal(parseCutoff({ cutoff_clock: '9:5' }), null);
	assert.equal(parseCutoff({ cutoff_clock: 'noon' }), null);
});

test('parseCutoff accepts a non-negative elapsed and floors it', () => {
	assert.deepEqual(parseCutoff({ cutoff_elapsed_s: 3600 }), { elapsedS: 3600 });
	assert.deepEqual(parseCutoff({ cutoff_elapsed_s: 90.7 }), { elapsedS: 90 });
	assert.equal(parseCutoff({ cutoff_elapsed_s: -5 }), null);
});

test('parseCutoff merges clock + elapsed and returns null for neither', () => {
	assert.deepEqual(parseCutoff({ cutoff_clock: '06:00', cutoff_elapsed_s: 1800 }), {
		clock: '06:00',
		elapsedS: 1800
	});
	assert.equal(parseCutoff({}), null);
	assert.equal(parseCutoff(null), null);
	assert.equal(parseCutoff('14:30'), null);
});
