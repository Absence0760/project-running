// Unit tests for the Strava export.csv header mapping. The key invariant:
// `type` (coarse run/walk/hike classification) reads "Activity Type", while
// `stravaType` (provenance stored in metadata.strava_activity_type) prefers
// Strava's finer "Sport Type" column so TrailRun / VirtualRun aren't lost.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { indexHeader, stravaDistanceMetres } from './strava-zip-header';

// Real Strava exports carry two numeric blocks: a summary block whose
// "Distance" follows the athlete's display unit (km OR miles) and a raw block
// (~col 18) whose "Distance" is always metres. The header below is trimmed to
// the columns the importer reads but keeps both Distance columns in place.
const twoBlockHeader = [
	'Activity ID', // 0
	'Activity Date', // 1
	'Activity Name', // 2
	'Activity Type', // 3
	'Elapsed Time', // 4
	'Distance', // 5 — summary block, display unit
	'Filename', // 6
	'Moving Time', // 7
	'Distance', // 8 — raw block, always metres
	'Elevation Gain', // 9
];

test('stravaType prefers the Sport Type column when present', () => {
	const header = ['Activity ID', 'Activity Type', 'Sport Type', 'Activity Date'];
	const idx = indexHeader(header);
	assert.equal(idx.type, 1, 'type must point at coarse Activity Type');
	assert.equal(idx.stravaType, 2, 'stravaType must point at the finer Sport Type');
});

test('stravaType falls back to Activity Type on legacy exports', () => {
	const header = ['Activity ID', 'Activity Type', 'Activity Date'];
	const idx = indexHeader(header);
	assert.equal(idx.stravaType, 1, 'legacy exports without Sport Type fall back to Activity Type');
});

test('matching is case- and whitespace-insensitive', () => {
	const header = ['activity id', '  Sport Type  ', 'Activity Type'];
	const idx = indexHeader(header);
	assert.equal(idx.stravaType, 1, 'Sport Type should match despite padding/case');
});

test('two Distance columns: the raw-block (metres) column is preferred', () => {
	const idx = indexHeader(twoBlockHeader);
	assert.equal(idx.distance, 5, 'display-unit Distance is the first occurrence');
	assert.equal(idx.distanceMetres, 8, 'raw-block Distance is the second occurrence');
	assert.equal(idx.distanceIsMiles, false);
});

test('imperial export imports the correct metric distance from the raw column', () => {
	// A 5.00 mi run: summary "Distance" is 5.0 (miles), raw "Distance" is the
	// true 8046.72 m. The old ×1000-km path produced 5000 m (~1.6x short).
	const idx = indexHeader(twoBlockHeader);
	const row = ['1', 'Apr 9, 2026', 'Run', 'Run', '3600', '5.0', 'a.gpx', '3400', '8046.72', '120'];
	assert.equal(Math.round(stravaDistanceMetres(row, idx)), 8047);
});

test('metric export is unchanged — raw column is already metres', () => {
	const idx = indexHeader(twoBlockHeader);
	// 8.05 km run: summary "Distance" 8.05 (km), raw 8050 m.
	const row = ['1', 'Apr 9, 2026', 'Run', 'Run', '3600', '8.05', 'a.gpx', '3400', '8050', '120'];
	assert.equal(Math.round(stravaDistanceMetres(row, idx)), 8050);
});

test('single bare Distance column falls back to the km assumption', () => {
	const header = ['Activity ID', 'Activity Date', 'Distance', 'Filename'];
	const idx = indexHeader(header);
	assert.equal(idx.distance, 2);
	assert.equal(idx.distanceMetres, -1);
	assert.equal(idx.distanceIsMiles, false);
	const row = ['1', 'Apr 9, 2026', '8.5', 'a.gpx'];
	assert.equal(stravaDistanceMetres(row, idx), 8500);
});

test('explicit "Distance in Miles" header is honoured as miles', () => {
	const header = ['Activity ID', 'Activity Date', 'Distance in Miles', 'Filename'];
	const idx = indexHeader(header);
	assert.equal(idx.distance, 2);
	assert.equal(idx.distanceMetres, -1);
	assert.equal(idx.distanceIsMiles, true);
	const row = ['1', 'Apr 9, 2026', '5', 'a.gpx'];
	assert.equal(Math.round(stravaDistanceMetres(row, idx)), 8047);
});

test('explicit "Distance in Kilometers" header is km', () => {
	const header = ['Activity ID', 'Distance in Kilometers', 'Filename'];
	const idx = indexHeader(header);
	assert.equal(idx.distance, 1);
	assert.equal(idx.distanceIsMiles, false);
	assert.equal(stravaDistanceMetres(['1', '10', 'a.gpx'], idx), 10000);
});
