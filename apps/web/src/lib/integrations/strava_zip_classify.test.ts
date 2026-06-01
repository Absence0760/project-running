import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { classifyStravaMember } from './strava-zip-classify';

test('classifyStravaMember — routes the route-file family through parseRouteFile', () => {
	assert.deepEqual(classifyStravaMember('activities/123.gpx'), { parser: 'route', gzipped: false });
	assert.deepEqual(classifyStravaMember('activities/123.tcx'), { parser: 'route', gzipped: false });
	assert.deepEqual(classifyStravaMember('activities/123.kml'), { parser: 'route', gzipped: false });
	assert.deepEqual(classifyStravaMember('activities/123.geojson'), {
		parser: 'route',
		gzipped: false,
	});
	assert.deepEqual(classifyStravaMember('activities/123.GPX.GZ'), { parser: 'route', gzipped: true });
});

test('classifyStravaMember — routes .fit / .fit.gz through the FIT parser (F4)', () => {
	// Before the fix these counted as imported but dropped the track.
	assert.deepEqual(classifyStravaMember('activities/123.fit'), { parser: 'fit', gzipped: false });
	assert.deepEqual(classifyStravaMember('activities/123.fit.gz'), { parser: 'fit', gzipped: true });
	assert.deepEqual(classifyStravaMember('activities/123.FIT.GZ'), { parser: 'fit', gzipped: true });
});

test('classifyStravaMember — unknown members are skipped (trackless, still importable)', () => {
	assert.deepEqual(classifyStravaMember('activities/123.csv'), { parser: null, gzipped: false });
	assert.deepEqual(classifyStravaMember('media/photo.jpg'), { parser: null, gzipped: false });
	assert.deepEqual(classifyStravaMember(''), { parser: null, gzipped: false });
});
