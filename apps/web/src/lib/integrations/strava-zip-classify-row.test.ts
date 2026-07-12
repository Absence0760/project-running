import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifyStravaRow, type RowDisposition } from './strava-zip-disposition';

// The bug this pins: a dropped unsupported activity (Ride/Swim/Yoga) and a
// duplicate were both counted as `skipped`, so the final toast told a
// migrant "already present" about rides/swims that were never imported at
// all. classifyStravaRow must keep the two dispositions distinct.

test('a run is imported, a duplicate run is a duplicate, a ride is unsupported', () => {
	const seen = new Set<string>(['dup-1']);
	assert.equal(classifyStravaRow('Run', 'new-1', seen), 'import');
	assert.equal(classifyStravaRow('Run', 'dup-1', seen), 'duplicate');
	assert.equal(classifyStravaRow('Ride', 'new-2', seen), 'unsupported');
});

test('walk and hike are importable, swim/yoga/weight training are unsupported', () => {
	const seen = new Set<string>();
	assert.equal(classifyStravaRow('Walk', 'a', seen), 'import');
	assert.equal(classifyStravaRow('Trail Run', 'b', seen), 'import');
	assert.equal(classifyStravaRow('Hike', 'c', seen), 'import');
	assert.equal(classifyStravaRow('Swim', 'd', seen), 'unsupported');
	assert.equal(classifyStravaRow('Yoga', 'e', seen), 'unsupported');
	assert.equal(classifyStravaRow('Weight Training', 'f', seen), 'unsupported');
});

test('an unsupported type is dropped even when its id already exists', () => {
	// Ordering: unsupported wins over duplicate, matching the importer loop.
	const seen = new Set<string>(['ride-1']);
	assert.equal(classifyStravaRow('Ride', 'ride-1', seen), 'unsupported');
});

test('a blank activity type falls through to import (never dropped as unsupported)', () => {
	const seen = new Set<string>();
	assert.equal(classifyStravaRow('', 'x', seen), 'import');
});

test('mixed archive: droppedUnsupported and skipped are counted separately', () => {
	// A realistic multi-year Strava export: foot activities, rides/swims,
	// and re-imported duplicates. Reduce the mixed rows the same way the
	// importer loop does and assert the two counters never merge.
	const seen = new Set<string>(['run-old-1', 'run-old-2']);
	const rows: Array<{ type: string; id: string }> = [
		{ type: 'Run', id: 'run-new-1' },
		{ type: 'Run', id: 'run-new-2' },
		{ type: 'Walk', id: 'walk-new-1' },
		{ type: 'Run', id: 'run-old-1' }, // duplicate
		{ type: 'Run', id: 'run-old-2' }, // duplicate
		{ type: 'Ride', id: 'ride-1' }, // unsupported
		{ type: 'Ride', id: 'ride-2' }, // unsupported
		{ type: 'Swim', id: 'swim-1' }, // unsupported
	];

	const counts: Record<RowDisposition, number> = { import: 0, duplicate: 0, unsupported: 0 };
	for (const row of rows) {
		const d = classifyStravaRow(row.type, row.id, seen);
		counts[d]++;
		if (d === 'import') seen.add(row.id);
	}

	assert.equal(counts.import, 3, 'two runs + one walk imported');
	assert.equal(counts.duplicate, 2, 'skipped = true duplicates only');
	assert.equal(counts.unsupported, 3, 'two rides + one swim dropped, distinct from skipped');
	// The whole point: these two must not be conflated.
	assert.notEqual(counts.duplicate, counts.duplicate + counts.unsupported);
});
