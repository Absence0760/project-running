import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { stripComments } from '../../src/lib/core/strip_comments';

/*
 * A fixture track point may only carry fields the app reads.
 *
 * `insertRun` gzips the array it is handed and puts it in Storage verbatim;
 * `fetchTrack` gunzips and `JSON.parse`s it, and nothing anywhere renames a
 * key. So the fixture's `TrackPoint` and `src/lib/types.ts`'s are ONE wire
 * shape, and a field spelled differently on the fixture side is data no code
 * path ever sees.
 *
 * That is not hypothetical: the timestamp was `t` here and `ts` there for the
 * life of this file, so three specs planted tracks the app read as carrying no
 * timestamps at all — `hasTrackTimestamps` false, no pace heatmap, no segment
 * duration or pace — while every assertion in them passed, because none of
 * them asserted the thing the timestamps were for (decisions § 1404). A type
 * error would have been the ideal catch and there is none available: the
 * fixture's interface is the only declaration a spec's track is checked
 * against, and it was the wrong one.
 *
 * Subset, not equality: the app's `TrackPoint` may carry a field no fixture
 * has ever needed to plant, and requiring the fixture to declare it would be
 * a demand rather than a check. The direction that matters is the one that
 * silently plants nothing.
 */

const HERE = dirname(fileURLToPath(import.meta.url));

/** The optional-and-required field names of the first `TrackPoint` interface. */
function trackPointFields(file: string): string[] {
	const source = stripComments(readFileSync(file, 'utf8'));
	const start = source.indexOf('interface TrackPoint {');
	assert.ok(start >= 0, `${file} no longer declares a TrackPoint interface — this guard reads a stale name.`);
	const body = source.slice(start, source.indexOf('\n}', start));
	return [...body.matchAll(/^\t([A-Za-z_$][\w$]*)\??:/gm)].map(([, name]) => name).sort();
}

const FIXTURE = trackPointFields(join(HERE, 'simulate.ts'));
const APP = trackPointFields(join(HERE, '..', '..', 'src', 'lib', 'types.ts'));

test('the derivation found both declarations', () => {
	assert.ok(FIXTURE.length > 0, 'No fields parsed out of the fixture TrackPoint — the check below is vacuous.');
	assert.ok(APP.length > 0, 'No fields parsed out of the app TrackPoint — the check below is vacuous.');
});

test('every fixture track-point field is one the app reads', () => {
	const unread = FIXTURE.filter((name) => !APP.includes(name));
	assert.deepEqual(
		unread,
		[],
		`These fields exist on the fixture's TrackPoint and on nothing the app reads, so a spec ` +
			`setting them plants data no code path sees: ${unread.join(', ')}. The gzipped object is ` +
			`stored and parsed verbatim — the two declarations are one wire shape.`,
	);
});
