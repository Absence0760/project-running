// Unit tests for the Strava export.csv header mapping. The key invariant:
// `type` (coarse run/walk/hike classification) reads "Activity Type", while
// `stravaType` (provenance stored in metadata.strava_activity_type) prefers
// Strava's finer "Sport Type" column so TrailRun / VirtualRun aren't lost.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { indexHeader } from './strava-zip-header';

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
