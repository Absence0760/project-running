import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	bodyRestatesAttachment,
	dmAttachmentView,
	dmRouteCardFrom,
	dmRouteCardHasTrace,
	hasDmRouteAttachment,
	type DmRouteCard
} from './dm_attachment';

const CARD: DmRouteCard = {
	id: 'r1',
	name: 'Cliff Trail Loop',
	distanceM: 8200,
	waypoints: [
		{ lat: 1, lng: 1 },
		{ lat: 2, lng: 2 }
	]
};

test('a message with no attachment renders as plain text', () => {
	assert.deepEqual(dmAttachmentView(null, undefined), { kind: 'text' });
	assert.deepEqual(dmAttachmentView(undefined, undefined), { kind: 'text' });
});

test('a blank route id is not an attachment', () => {
	// Otherwise the bubble sits on a skeleton nothing will ever resolve.
	assert.deepEqual(dmAttachmentView('', { status: 'pending' }), { kind: 'text' });
	assert.deepEqual(dmAttachmentView('   ', { status: 'pending' }), { kind: 'text' });
});

test('an unresolved attachment is pending, never an empty card', () => {
	assert.deepEqual(dmAttachmentView('r1', undefined), { kind: 'pending' });
	assert.deepEqual(dmAttachmentView('r1', { status: 'pending' }), { kind: 'pending' });
});

test('a resolved route renders the card', () => {
	assert.deepEqual(dmAttachmentView('r1', { status: 'resolved', route: CARD }), {
		kind: 'card',
		route: CARD
	});
});

test('a route the reader cannot see says so instead of falling back to text', () => {
	// The body is v1's public share URL, which 404s for exactly this reader.
	// Rendering it as an ordinary message hides that the route is gone.
	assert.deepEqual(dmAttachmentView('r1', { status: 'resolved', route: null }), {
		kind: 'unavailable'
	});
});

test('a blank route name resolves to null so the render can localize a fallback', () => {
	assert.equal(dmRouteCardFrom({ id: 'r1', name: '   ' }).name, null);
	assert.equal(dmRouteCardFrom({ id: 'r1', name: null }).name, null);
	assert.equal(dmRouteCardFrom({ id: 'r1', name: ' Ridge ' }).name, 'Ridge');
});

test('distance comes back as a number, and an unusable one as null', () => {
	// PostgREST serialises `numeric` as a string.
	assert.equal(dmRouteCardFrom({ id: 'r1', distance_m: '8200.00' }).distanceM, 8200);
	assert.equal(dmRouteCardFrom({ id: 'r1', distance_m: null }).distanceM, null);
	assert.equal(dmRouteCardFrom({ id: 'r1', distance_m: 'nope' }).distanceM, null);
	assert.equal(dmRouteCardFrom({ id: 'r1', distance_m: 0 }).distanceM, null);
});

test('waypoints keep only usable points and default to an empty line', () => {
	const card = dmRouteCardFrom({
		id: 'r1',
		waypoints: [{ lat: 1, lng: 1 }, { lat: 'x', lng: 2 }, null, { lat: 2, lng: 2 }]
	});
	assert.deepEqual(card.waypoints, [
		{ lat: 1, lng: 1 },
		{ lat: 2, lng: 2 }
	]);
	assert.deepEqual(dmRouteCardFrom({ id: 'r1' }).waypoints, []);
	assert.deepEqual(dmRouteCardFrom({ id: 'r1', waypoints: 'nope' }).waypoints, []);
});

test('a clipped-to-nothing line still renders the card, only without a trace', () => {
	// fetchClippedRouteForViewer fails closed to []; the route resolving and
	// its polyline resolving are different facts.
	const clippedAway = dmRouteCardFrom({ id: 'r1', name: 'Ridge', distance_m: 5000 });
	assert.equal(dmRouteCardHasTrace(clippedAway), false);
	assert.deepEqual(dmAttachmentView('r1', { status: 'resolved', route: clippedAway }), {
		kind: 'card',
		route: clippedAway
	});
	assert.equal(dmRouteCardHasTrace(CARD), true);
	assert.equal(
		dmRouteCardHasTrace(dmRouteCardFrom({ id: 'r1', waypoints: [{ lat: 1, lng: 1 }] })),
		false
	);
});

test('an attachment id is recognised only when it is not blank', () => {
	assert.equal(hasDmRouteAttachment('r1'), true);
	assert.equal(hasDmRouteAttachment(''), false);
	assert.equal(hasDmRouteAttachment('  '), false);
	assert.equal(hasDmRouteAttachment(null), false);
	assert.equal(hasDmRouteAttachment(undefined), false);
});

const ROUTE_UUID = '1f0f9d2c-7c58-4a1e-9d2b-6b4a8c5e1234';

test("the share URL v1 sends as the body is suppressed once the card draws it", () => {
	assert.equal(
		bodyRestatesAttachment(`https://threkir.com/share/route/${ROUTE_UUID}`, ROUTE_UUID),
		true
	);
	assert.equal(
		bodyRestatesAttachment(`https://threkir.com/share/route/${ROUTE_UUID}/`, ROUTE_UUID),
		true
	);
	assert.equal(bodyRestatesAttachment(`https://threkir.com/routes/${ROUTE_UUID}`, ROUTE_UUID), true);
	// The uuid a client renders and the one Postgres stores can differ in case.
	assert.equal(
		bodyRestatesAttachment(
			`https://threkir.com/share/route/${ROUTE_UUID.toUpperCase()}`,
			ROUTE_UUID
		),
		true
	);
});

test('anything a human could have typed renders beside the card', () => {
	// A note, a bare word, and a link to a DIFFERENT route are all the
	// sender's own words; suppressing them would delete the message.
	assert.equal(bodyRestatesAttachment('try this on Saturday', ROUTE_UUID), false);
	assert.equal(bodyRestatesAttachment(`/share/route/${ROUTE_UUID}`, ROUTE_UUID), false);
	assert.equal(
		bodyRestatesAttachment(
			'https://threkir.com/share/route/00000000-0000-0000-0000-000000000000',
			ROUTE_UUID
		),
		false
	);
	assert.equal(bodyRestatesAttachment(`https://threkir.com/runs/${ROUTE_UUID}`, ROUTE_UUID), false);
	assert.equal(bodyRestatesAttachment('', ROUTE_UUID), false);
	assert.equal(bodyRestatesAttachment(`https://threkir.com/routes/${ROUTE_UUID}`, '  '), false);
});
