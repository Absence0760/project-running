import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildStaticMarkerMapUrl, mapsDirectionsUrl, geoUri } from './static_map';

test('buildStaticMarkerMapUrl centres on lon,lat and adds a marker', () => {
	const url = buildStaticMarkerMapUrl(51.5074, -0.1278, {
		w: 320,
		h: 180,
		style: 'streets-v2',
		key: 'KEY'
	});
	assert.ok(url);
	// MapTiler path is lon,lat,zoom — longitude first.
	assert.match(url!, /\/static\/-0\.12780,51\.50740,14\/320x180@2x\.png/);
	assert.match(url!, /markers=-0\.12780,51\.50740/);
	assert.match(url!, /key=KEY/);
});

test('buildStaticMarkerMapUrl honours a custom zoom', () => {
	const url = buildStaticMarkerMapUrl(10, 20, {
		w: 100,
		h: 100,
		style: 'streets-v2',
		key: 'K',
		zoom: 9
	});
	assert.match(url!, /\/static\/20\.00000,10\.00000,9\//);
});

test('buildStaticMarkerMapUrl returns null without a key', () => {
	assert.equal(
		buildStaticMarkerMapUrl(1, 2, { w: 10, h: 10, style: 's', key: '' }),
		null
	);
});

test('buildStaticMarkerMapUrl rejects out-of-range / non-finite coords', () => {
	const opts = { w: 10, h: 10, style: 's', key: 'K' };
	assert.equal(buildStaticMarkerMapUrl(91, 0, opts), null);
	assert.equal(buildStaticMarkerMapUrl(0, 181, opts), null);
	assert.equal(buildStaticMarkerMapUrl(Number.NaN, 0, opts), null);
});

test('mapsDirectionsUrl builds a universal Google Maps query', () => {
	assert.equal(
		mapsDirectionsUrl(51.5074, -0.1278),
		'https://www.google.com/maps/search/?api=1&query=51.5074,-0.1278'
	);
});

test('geoUri encodes the optional label', () => {
	assert.equal(geoUri(1, 2), 'geo:1,2');
	assert.equal(geoUri(1, 2, 'Town Square'), 'geo:1,2?q=1,2(Town%20Square)');
});
