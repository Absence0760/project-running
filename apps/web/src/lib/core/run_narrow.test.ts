import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { narrowFullRun, narrowProjectedRun, type RunRow } from './run_narrow';

function row(over: Partial<RunRow> = {}): RunRow {
	return {
		id: 'r1',
		user_id: 'u1',
		started_at: '2026-01-01T06:00:00.000Z',
		distance_m: 5000,
		duration_s: 1800,
		source: 'app',
		activity_type: 'run',
		metadata: null,
		...over,
	} as RunRow;
}

test('narrowFullRun coerces a source the build has never heard of', () => {
	// Reason: the CHECK stops a bad value at write time, but a row written by
	// a newer client carries a vocabulary this build cannot render. `Run`
	// promises the union, so the read has to answer with a member of it.
	assert.equal(narrowFullRun(row({ source: 'quantum-treadmill' })).source, 'app');
	assert.equal(narrowFullRun(row({ source: 'strava' })).source, 'strava');
});

test('narrowFullRun coerces activity_type too, not just source', () => {
	// Reason: `Run` narrows THREE columns and the unnarrowed read applied one.
	// An unknown activity type reached every consumer raw, behind a type
	// promising the union.
	assert.equal(narrowFullRun(row({ activity_type: 'wingsuit' })).activity_type, 'run');
	assert.equal(narrowFullRun(row({ activity_type: 'hike' })).activity_type, 'hike');
});

test('narrowFullRun answers null for a jsonb bag that is not an object', () => {
	// Reason: jsonb admits a string, a number, a boolean and an array.
	// `Run.metadata` is `JsonObject | null` and every consumer indexes it by
	// key, so the four non-object cases have to be answered here.
	assert.equal(narrowFullRun(row({ metadata: [1, 2] })).metadata, null);
	assert.equal(narrowFullRun(row({ metadata: 'steps' })).metadata, null);
	assert.deepEqual(narrowFullRun(row({ metadata: { steps: 900 } })).metadata, { steps: 900 });
});

test('narrowFullRun sets track null — select(*) cannot have read it', () => {
	assert.equal(narrowFullRun(row()).track, null);
});

test('narrowProjectedRun never adds a key the projection did not select', () => {
	// Reason: the narrowed overload returns `Pick<Run, C[number]>`, and since
	// § 1468 `track` cannot be one of those keys. Setting it on every row —
	// which the one shared map used to do — put a property on the object that
	// its own type does not declare and no caller can read.
	const projected = narrowProjectedRun({ started_at: '2026-01-01T06:00:00.000Z' });
	assert.deepEqual(Object.keys(projected).sort(), ['started_at']);
	assert.equal('track' in projected, false);
	assert.equal('source' in projected, false);
	assert.equal('activity_type' in projected, false);
	assert.equal('metadata' in projected, false);
});

test('narrowProjectedRun narrows exactly the narrowable columns it was given', () => {
	const projected = narrowProjectedRun({
		id: 'r1',
		activity_type: 'wingsuit',
		metadata: ['not', 'an', 'object'],
	});
	assert.deepEqual(Object.keys(projected).sort(), ['activity_type', 'id', 'metadata']);
	assert.equal(projected.activity_type, 'run');
	assert.equal(projected.metadata, null);
});

test('a selected-but-empty column is narrowed, not treated as unselected', () => {
	// Reason: `undefined` is the marker for "PostgREST did not send this key".
	// JSON has no such value, so a selected column that is empty — a null
	// `metadata`, an unusable `source` — must still go through the parse and
	// keep its key. Dropping it would lose a column the row type declares.
	// `metadata` is the only one of the three the column allows to be null;
	// the other two are NOT NULL, which is why `undefined` alone can mean
	// "not selected" here.
	const projected = narrowProjectedRun({ source: '', metadata: null });
	assert.equal('source' in projected, true);
	assert.equal(projected.source, 'app');
	assert.equal('metadata' in projected, true);
	assert.equal(projected.metadata, null);
});
