import assert from 'node:assert/strict';
import { test } from 'node:test';

import { gearBackfillCandidates, gearPurchaseSince, type GearBackfillRun } from './gear_backfill';

// Mirrors `apps/mobile_android/test/gear_backfill_test.dart` case for case.
// The Dart twin's `since` is a local-midnight DateTime from the date picker;
// here it is the epoch-ms `gearPurchaseSince` produces from the same date, so
// both sides compare the same instants.

const PURCHASED = '2026-01-01';
const since = gearPurchaseSince(PURCHASED) as number;

function run(
	id: string,
	localDate: string,
	activityType?: string | null,
): GearBackfillRun {
	// Build the instant from LOCAL calendar parts so the fixtures mean the
	// same thing in every timezone the suite runs in.
	const [y, mo, d] = localDate.split('-').map(Number);
	return {
		id,
		started_at: new Date(y, mo - 1, d, 12, 0, 0).toISOString(),
		activity_type: activityType ?? null,
	};
}

const ids = (rows: GearBackfillRun[]) => rows.map((r) => r.id);

test('gearBackfillCandidates: returns empty for empty input', () => {
	assert.deepEqual(gearBackfillCandidates({ gearKind: 'shoe', sinceMs: since, runs: [] }), []);
});

test('gearBackfillCandidates: shoe gear matches running activities (run / walk / hike)', () => {
	const runs = [
		run('r1', '2026-01-05', 'run'),
		run('r2', '2026-01-05', 'walk'),
		run('r3', '2026-01-05', 'hike'),
		run('r4', '2026-01-05', 'cycle'),
	];
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'shoe', sinceMs: since, runs })),
		['r1', 'r2', 'r3'],
	);
});

test('gearBackfillCandidates: bike gear matches only cycle activities', () => {
	const runs = [
		run('r1', '2026-01-05', 'run'),
		run('r2', '2026-01-05', 'cycle'),
		run('r3', '2026-01-05', 'walk'),
	];
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'bike', sinceMs: since, runs })),
		['r2'],
	);
});

test('gearBackfillCandidates: runs missing activity_type default to "run" — included for shoes', () => {
	const runs = [run('r1', '2026-01-05')];
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'shoe', sinceMs: since, runs })),
		['r1'],
	);
});

test('gearBackfillCandidates: runs before "since" are excluded', () => {
	const runs = [run('before', '2025-12-28', 'run'), run('after', '2026-01-05', 'run')];
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'shoe', sinceMs: since, runs })),
		['after'],
	);
});

test('gearBackfillCandidates: a run started exactly at "since" is included (boundary)', () => {
	const exact: GearBackfillRun = {
		id: 'exact',
		started_at: new Date(since).toISOString(),
		activity_type: 'run',
	};
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'shoe', sinceMs: since, runs: [exact] })),
		['exact'],
	);
});

test('gearBackfillCandidates: results are sorted newest-first', () => {
	const runs = [
		run('mid', '2026-01-05', 'run'),
		run('old', '2026-01-02', 'run'),
		run('new', '2026-01-10', 'run'),
	];
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'shoe', sinceMs: since, runs })),
		['new', 'mid', 'old'],
	);
});

test('gearBackfillCandidates: case-insensitive activity_type match', () => {
	const runs = [run('r1', '2026-01-05', 'Run'), run('r2', '2026-01-05', 'CYCLE')];
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'shoe', sinceMs: since, runs })),
		['r1'],
	);
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'bike', sinceMs: since, runs })),
		['r2'],
	);
});

test('gearBackfillCandidates: a stroller run is offered for shoes, never for bikes', () => {
	// `stroller` is in runs_activity_type_check and the auto_tag_default_gear
	// trigger maps it to a SHOE (everything that isn't cycle is), so a stroller
	// run is auto-tagged with the runner's current pair at insert. An
	// enumerated {run, walk, hike} allowlist dropped it from the backfill offer
	// — the trigger and the prompt disagreeing about the same run.
	const runs = [run('stroll', '2026-01-05', 'stroller')];
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'shoe', sinceMs: since, runs })),
		['stroll'],
	);
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'bike', sinceMs: since, runs })),
		[],
	);
});

test('gearBackfillCandidates: the shoe set is derived as "not cycle", not enumerated', () => {
	// The durable half of the case above. A value the CHECK grows tomorrow must
	// be covered the day it lands, without anyone remembering to edit this
	// helper — so an activity nobody here has heard of is foot-powered, exactly
	// as the trigger's `else 'shoe'` treats it. Re-enumerating the shoe set
	// fails here even if `stroller` is remembered.
	const runs = [run('future', '2026-01-05', 'snowshoe')];
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'shoe', sinceMs: since, runs })),
		['future'],
	);
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'bike', sinceMs: since, runs })),
		[],
	);
});

test('gearBackfillCandidates: unknown gear kind falls through to shoe semantics', () => {
	// Defensive — keeps the helper from silently returning empty if a future
	// gear kind ("strap"?) leaks into the call.
	const runs = [run('r1', '2026-01-05', 'run')];
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'unknown', sinceMs: since, runs })),
		['r1'],
	);
});

// Web-only case (no Dart mirror): Dart's `DateTime` is parsed at the model
// boundary and can't be malformed by the time the helper sees it, whereas
// `started_at` reaches this helper as a raw string from PostgREST.
test('gearBackfillCandidates: a run with an unparseable started_at is dropped, not guessed', () => {
	const runs: GearBackfillRun[] = [
		{ id: 'bad', started_at: 'not-a-date', activity_type: 'run' },
		run('good', '2026-01-05', 'run'),
	];
	assert.deepEqual(
		ids(gearBackfillCandidates({ gearKind: 'shoe', sinceMs: since, runs })),
		['good'],
	);
});

test('gearPurchaseSince: resolves a date-only value to LOCAL midnight', () => {
	const ms = gearPurchaseSince('2026-01-01');
	assert.ok(ms != null);
	const d = new Date(ms);
	assert.equal(d.getFullYear(), 2026);
	assert.equal(d.getMonth(), 0);
	assert.equal(d.getDate(), 1);
	assert.equal(d.getHours(), 0);
	assert.equal(d.getMinutes(), 0);
});

test('gearPurchaseSince: null / empty / malformed input has no window', () => {
	assert.equal(gearPurchaseSince(null), null);
	assert.equal(gearPurchaseSince(undefined), null);
	assert.equal(gearPurchaseSince(''), null);
	assert.equal(gearPurchaseSince('last tuesday'), null);
});

test('gearPurchaseSince: tolerates a full timestamp, keeping the calendar day', () => {
	const ms = gearPurchaseSince('2026-03-09T14:32:00Z');
	assert.ok(ms != null);
	const d = new Date(ms);
	assert.equal(d.getDate(), 9);
	assert.equal(d.getHours(), 0);
});
