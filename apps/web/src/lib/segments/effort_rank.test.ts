import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	readRankRows,
	rankPillClass,
	rankPillText,
	UNKNOWN_RANK_TEXT,
} from './effort_rank';

test('rank 1 is the crown', () => {
	assert.equal(rankPillClass(1), 'gold');
	assert.equal(rankPillText(1), '#1');
});

test('an unknown rank is NOT the crown', () => {
	// The regression this module exists for: both clients degraded a missing
	// `segment_effort_ranks` row to `?? 1`, so an unanswered RPC painted the
	// most flattering claim the surface can make. Absent is neutral.
	assert.equal(rankPillClass(null), '');
	assert.notEqual(rankPillClass(null), rankPillClass(1));
});

test('an unknown rank renders a placeholder, never an ordinal', () => {
	assert.equal(rankPillText(null), UNKNOWN_RANK_TEXT);
	assert.ok(!rankPillText(null).includes('#'));
	assert.ok(!rankPillText(null).includes('1'));
});

test('medal tiers', () => {
	assert.equal(rankPillClass(2), 'silver');
	assert.equal(rankPillClass(3), 'silver');
	assert.equal(rankPillClass(4), 'bronze');
	assert.equal(rankPillClass(10), 'bronze');
	assert.equal(rankPillClass(11), '');
	assert.equal(rankPillText(42), '#42');
});

test('a rank that is not a usable ordinal reads as unknown, not as a crown', () => {
	// The RPC returns `1 + count(...)`, so anything else came from a wire
	// coercion going wrong. Fail closed the way an absent row does rather
	// than rendering `#NaN` or crowning a 0.
	for (const bad of [Number.NaN, Number.POSITIVE_INFINITY, 0, -1]) {
		assert.equal(rankPillClass(bad), '', `rankPillClass(${bad})`);
		assert.equal(rankPillText(bad), UNKNOWN_RANK_TEXT, `rankPillText(${bad})`);
	}
});

test('readRankRows indexes the RPC answer by effort id', () => {
	const map = readRankRows([
		{ effort_id: 'a', rank: 1 },
		{ effort_id: 'b', rank: 7 },
	]);
	assert.equal(map.get('a'), 1);
	assert.equal(map.get('b'), 7);
	assert.equal(map.size, 2);
});

test('a failed RPC yields an empty map, and every effort is then unknown', () => {
	// `supabase.rpc` RESOLVES with `{ data: null, error }` — it does not throw —
	// so this is what a 42501 / timeout / 500 actually looks like on web. Under
	// `?? 1` this shape crowned EVERY chip on the page at once.
	for (const failed of [null, undefined, {}, 'boom']) {
		const map = readRankRows(failed);
		assert.equal(map.size, 0);
		assert.equal(map.get('a') ?? null, null);
		assert.equal(rankPillText(map.get('a') ?? null), UNKNOWN_RANK_TEXT);
		assert.equal(rankPillClass(map.get('a') ?? null), '');
	}
});

test('readRankRows drops a row it cannot use rather than seating it at #1', () => {
	const map = readRankRows([
		{ effort_id: 'ok', rank: 3 },
		{ effort_id: 'no-rank' },
		{ effort_id: 'null-rank', rank: null },
		{ effort_id: 'nan-rank', rank: Number.NaN },
		{ effort_id: 'zero-rank', rank: 0 },
		{ effort_id: '', rank: 2 },
		{ rank: 2 },
		null,
		'nonsense',
	]);
	assert.deepEqual([...map.entries()], [['ok', 3]]);
});

test('a numeric rank arriving as a string is still read', () => {
	// PostgREST serialises `numeric` as a string; `rank` is cast to `integer`
	// in the RPC so it arrives as a number today, but the coercion must not be
	// the thing standing between a real standing and a placeholder.
	const map = readRankRows([{ effort_id: 'a', rank: '4' }]);
	assert.equal(map.get('a'), 4);
});

// ── Source guards ──
//
// The degrade this module removes lived at the two `data.ts` call sites and
// at the two pill renders, not in a pure function, so no behavioural test
// could have caught it. Pin the shape the way `contrast_guard.test.ts` pins
// the pill's CSS and `segment_effort_ranks_source_test.dart` pins the Dart
// twin: read the source and assert the old form is gone.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const dataTs = readFileSync(join(here, '../core/data.ts'), 'utf8');
const panel = readFileSync(
	join(here, '../components/RunSegmentEfforts.svelte'),
	'utf8',
);

test('neither rank fetcher degrades a missing row to 1', () => {
	assert.ok(
		!/rankByEffort\.get\([^)]*\)\s*\?\?\s*1/.test(dataTs),
		'data.ts still spends an absent rank as `?? 1` — a false crown',
	);
	const nulled = dataTs.match(/rankByEffort\.get\([^)]*\)\s*\?\?\s*null/g) ?? [];
	assert.equal(
		nulled.length,
		2,
		'both fetchEffortsForRunWithError and fetchGlobalEffortsForRun must map an absent rank to null',
	);
});

test('both rank fetchers read the RPC through readRankRows', () => {
	assert.equal(
		(dataTs.match(/readRankRows\(rankRows\)/g) ?? []).length,
		2,
		'the wire read must be single-sourced so one site cannot keep a laxer coercion',
	);
});

test('the run-detail pills render through the shared mapping', () => {
	assert.ok(
		!/function rankClass/.test(panel),
		'RunSegmentEfforts.svelte must not carry its own rank→medal mapping',
	);
	assert.equal(
		(panel.match(/rankPillClass\(e\.rank\)/g) ?? []).length,
		2,
		'both the route-segment and catalogue pills must use rankPillClass',
	);
	assert.equal(
		(panel.match(/rankPillText\(e\.rank\)/g) ?? []).length,
		2,
		'both pills must render through rankPillText, never `#{e.rank}` raw',
	);
	assert.ok(
		!/#\{e\.rank\}/.test(panel),
		'a raw `#{e.rank}` renders `#null` for an unanswered effort',
	);
});

test('an unknown pill carries an accessible name, not a bare em dash', () => {
	assert.ok(
		panel.includes("m('segmentEfforts.rankUnknown')"),
		'the placeholder glyph needs a localized label for assistive tech',
	);
});
