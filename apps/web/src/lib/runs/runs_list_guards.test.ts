// Source guards over the /runs list toolbar and its back-navigation snapshot.
//
// Both defects here are invisible to the type checker. A hand-written subset of
// a union typechecks perfectly, and a snapshot payload that omits a field is
// just a smaller object. Only the source says whether the list of sources the
// runner is offered is the list the column allows, and whether what the page
// captured is what it restores.
//
// Runs with cwd = apps/web, like the other source guards in this directory.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from '../core/strip_comments';
import { RUN_SOURCES } from './source_badge';

const page = stripComments(readFileSync(resolve('src/routes/runs/+page.svelte'), 'utf-8'));

function block(marker: string, end: string): string {
	const start = page.indexOf(marker);
	assert.ok(start >= 0, `${marker} moved`);
	const stop = page.indexOf(end, start);
	assert.ok(stop > start, `could not find the end of the ${marker} block`);
	return page.slice(start, stop);
}

test('the source filter offers every source the column allows', () => {
	// The dropdown listed `all / app / strava / parkrun / healthkit` against a
	// CHECK that allows eight, so a Wear OS or Apple Watch runner saw a "Watch"
	// badge on every card and no Watch option to filter by -- and the same for
	// a Garmin ZIP import, a Health Connect sync and imported race results.
	const sources = block('const sources = $derived', '\n\tconst activities');
	const literals = [...sources.matchAll(/value: '([^']+)'/g)].map((m) => m[1]);
	assert.deepEqual(
		literals,
		['all'],
		'the source list must be derived from RUN_SOURCES, not hand-enumerated -- ' +
			`found hard-coded values ${literals.join(', ')}`,
	);
	assert.match(
		sources,
		/RUN_SOURCES/,
		'the source list must spread RUN_SOURCES so a new CHECK value cannot be omitted',
	);
	// The map that names them is a `Record<RunSource, string>`, so tsc refuses
	// an incomplete one; this pins that every source actually has a name there.
	const labels = block('const sourceFilterLabels = $derived', '\n\tconst sources');
	for (const s of RUN_SOURCES) {
		assert.match(labels, new RegExp(`\\b${s}:`), `no filter label for the '${s}' source`);
	}
});

test('the back-nav snapshot restores every field it captures', () => {
	// `renderLimit` was component state and not in the payload, and the reset
	// effect fired on the restore's own filter writes -- so a list expanded to
	// 200 cards came back as 50, the document was a quarter of its captured
	// height, and the scroll the restore then re-applied clamped to the top.
	const captured = [...block('capture: () => ({', '}),').matchAll(/^\t{3}(\w+)[,:]/gm)].map(
		(m) => m[1],
	);
	assert.ok(captured.includes('renderLimit'), 'renderLimit must be captured');
	const restore = block('restore: (s) => {', '\n\t};');
	for (const field of captured) {
		assert.match(
			restore,
			new RegExp(`\\b${field}\\b`),
			`the snapshot captures \`${field}\` and never restores it`,
		);
	}
});

test('a restore does not trip the render-window reset', () => {
	// The reset has to compare the filter set rather than fire on any write to
	// it: a restore ASSIGNS the filters, which is a write like any other.
	const effect = block('let renderWindowKey', 'const sourceFilterLabels');
	assert.match(
		effect,
		/if \(key === renderWindowKey\) return;/,
		'the reset must skip when the filter set is unchanged',
	);
	assert.match(
		block('restore: (s) => {', '\n\t};'),
		/renderWindowKey = renderWindowSignature\(\);/,
		'restore must adopt the restored filter set as the window it belongs to',
	);
});
