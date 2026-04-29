import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseRunSource, type RunSource } from './types';

// Cross-platform contract test for the canonical watch-run payload.
//
// The fixture at `fixtures/watch_run_payload.json` (repo root) is shared
// with the Flutter test (apps/mobile_android + mobile_ios under
// test/watch_payload_fixture_test.dart) and the Wear OS test
// (apps/watch_wear under WatchRunPayloadFixtureTest.kt). All three
// platforms read the same file and must agree on the shape. If you
// change a field, update both other tests in the same commit.
//
// Web doesn't decode watch payloads (the watch path goes through Dart on
// iOS or directly to Supabase from Wear OS). What web does is read the
// resulting rows. So the web side of the contract is structural: the
// source must parse, the metadata keys web reads (activity_type,
// avg_bpm) must be present, and the laps shape must match the registry.

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = join(__dirname, '..', '..', '..', '..', 'fixtures', 'watch_run_payload.json');

type Fixture = {
	payload: { source: string; activity_type: string };
	expectedRow: { source: string; duration_s: number; distance_m: number };
	expectedMetadata: {
		activity_type: string;
		avg_bpm: number;
		laps: Array<{
			index: number;
			start_offset_s: number;
			distance_m: number;
			duration_s: number;
		}>;
	};
	expectedTrackCount: number;
	expectedFirstPointBpm: number;
};

const fixture = JSON.parse(readFileSync(FIXTURE_PATH, 'utf-8')) as Fixture;

test('fixture source parses to a valid RunSource', () => {
	const parsed: RunSource = parseRunSource(fixture.expectedRow.source);
	assert.equal(parsed, fixture.expectedRow.source);
	assert.equal(parsed, 'watch');
});

test('fixture metadata.activity_type is one of the registered values', () => {
	// Match docs/metadata.md § activity_type.
	const allowed = new Set(['run', 'walk', 'hike', 'cycle']);
	assert.ok(
		allowed.has(fixture.expectedMetadata.activity_type),
		`activity_type=${fixture.expectedMetadata.activity_type} not in registered set`,
	);
});

test('fixture metadata.avg_bpm is a positive number', () => {
	assert.equal(typeof fixture.expectedMetadata.avg_bpm, 'number');
	assert.ok(fixture.expectedMetadata.avg_bpm > 0);
});

test('fixture laps use canonical per-lap-delta shape', () => {
	// Per docs/metadata.md § laps: index (int), start_offset_s (int),
	// distance_m (number), duration_s (int). start_offset_s of the first
	// lap is 0 (cumulative-BEFORE), and subsequent laps' start_offset_s
	// equals the running total of prior duration_s values.
	const laps = fixture.expectedMetadata.laps;
	assert.ok(laps.length >= 2, 'fixture must have ≥ 2 laps to test offset accumulation');
	assert.equal(laps[0].start_offset_s, 0, 'first lap must start at offset 0');
	let runningOffset = 0;
	for (const lap of laps) {
		assert.equal(typeof lap.index, 'number');
		assert.equal(typeof lap.start_offset_s, 'number');
		assert.equal(typeof lap.distance_m, 'number');
		assert.equal(typeof lap.duration_s, 'number');
		assert.equal(
			lap.start_offset_s,
			runningOffset,
			`lap ${lap.index}: start_offset_s should equal cumulative duration of prior laps`,
		);
		runningOffset += lap.duration_s;
	}
});

test('fixture row source matches payload source', () => {
	// If these drift, the watch ingestion pipeline misclassifies runs.
	assert.equal(fixture.payload.source, fixture.expectedRow.source);
});

test('fixture activity_type matches between payload and metadata', () => {
	assert.equal(
		fixture.payload.activity_type,
		fixture.expectedMetadata.activity_type,
		'payload activity_type must equal what lands in metadata',
	);
});
