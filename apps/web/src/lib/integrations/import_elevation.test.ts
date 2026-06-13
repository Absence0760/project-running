import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { parseRouteFile, parseEle } from './import';

function geojsonFile(coords: number[][]): File {
	const body = JSON.stringify({
		type: 'Feature',
		properties: { name: 'Ele test' },
		geometry: { type: 'LineString', coordinates: coords },
	});
	return new File([body], 'route.geojson');
}

test('parseEle — preserves a genuine sea-level 0 m reading', () => {
	// The bug: `parseFloat(x) || undefined` dropped 0 because 0 is falsy,
	// conflating "at sea level" with "no elevation recorded".
	assert.equal(parseEle('0'), 0);
	assert.equal(parseEle('0.0'), 0);
	assert.equal(parseEle('-5'), -5); // below sea level (Dead Sea, Death Valley)
	assert.equal(parseEle('123.4'), 123.4);
});

test('parseEle — maps missing / blank / non-numeric to undefined', () => {
	assert.equal(parseEle(null), undefined);
	assert.equal(parseEle(undefined), undefined);
	assert.equal(parseEle(''), undefined);
	assert.equal(parseEle('   '), undefined);
	assert.equal(parseEle('abc'), undefined);
});

test('GeoJSON import — a 0 m third coordinate is kept, not dropped', async () => {
	const routes = await parseRouteFile(geojsonFile([
		[0, 0, 10],
		[0, 0.001, 0], // genuine sea level
	]));
	assert.equal(routes.length, 1);
	assert.equal(routes[0].waypoints[1].ele, 0);
});

test('buildRoute — missing elevation on one point does NOT fabricate climb', async () => {
	// Middle point has no third coordinate (elevation absent). Old code
	// coerced it to 0, computing a 100 m descent then a 100 m climb back —
	// inventing 100 m of gain on a flat plateau.
	const routes = await parseRouteFile(geojsonFile([
		[0, 0, 100],
		[0, 0.001], // no elevation
		[0, 0.002, 100],
	]));
	assert.equal(routes.length, 1);
	assert.equal(routes[0].elevation_m, null, 'no real climb between known points');
});

test('buildRoute — real climb between two known elevations still counts', async () => {
	const routes = await parseRouteFile(geojsonFile([
		[0, 0, 100],
		[0, 0.001, 150],
		[0, 0.002, 120],
	]));
	assert.equal(routes[0].elevation_m, 50, 'only the +50 climb counts, the -30 descent is ignored');
});
