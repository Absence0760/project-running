// The Strava ZIP importer's promise-keeping, at the call site.
// Invocation:
//   npx tsx --test src/lib/integrations/strava_zip_strictness.test.ts
//
// `resolveStravaTrackMember` decides whether an archive kept the promise
// its `activities.csv` row made, and its own suite pins every refusal.
// None of that binds `strava-zip.ts`, which imports supabase-js and so is
// unexecutable here: the defect decisions § 676 fixed was a `try {} catch
// (_) { /* keep row without track */ }` around the two parsers, and
// re-adding one restores a silent trackless import of a run the archive
// promised a track for. A swallow compiles, reads as defensive, and is
// invisible to every other test in the tree.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const IMPORTER = 'src/lib/integrations/strava-zip.ts';

/// Comments are stripped before every scan below: the prose in this file
/// names the very shapes being refused ("an early return here would…"),
/// so a guard reading the raw text would answer about the comment.
function stripComments(s: string): string {
	return s.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/[^\n]*/g, '$1');
}

function source(): string {
	return stripComments(readFileSync(resolve(IMPORTER), 'utf-8'));
}

function importOneBody(s: string): string {
	const from = s.indexOf('async function importOne(');
	assert.notEqual(from, -1, 'importOne not found — did it move?');
	const to = s.indexOf('const metadata: Record<string, unknown>', from);
	assert.notEqual(to, -1, 'the track block no longer ends where this guard expects');
	return s.slice(from, to);
}

test('the row resolves its member through the shared decision', () => {
	const s = source();
	assert.match(
		s,
		/resolveStravaTrackMember\(filename,/,
		'importOne must ask the shared resolver whether the archive kept the promise',
	);
	assert.doesNotMatch(
		s,
		/classifyStravaMember\(/,
		'the raw classifier bypasses the missing-member refusal — go through the resolver',
	);
});

test('neither parser call is wrapped in a catch that would import trackless', () => {
	const body = importOneBody(source());
	assert.match(body, /parseFitBuffer\(/, 'the FIT branch must still exist');
	assert.match(body, /parseRouteFile\(/, 'the GPX/TCX branch must still exist');
	assert.doesNotMatch(
		body,
		/\bcatch\b/,
		'a catch in the track block turns an unreadable member into a silent ' +
			'summary-only import — the run reads as complete and the archive is ' +
			'never re-imported (decisions § 676)',
	);
	assert.doesNotMatch(
		body,
		/\.catch\(/,
		'a promise-level catch swallows the same refusal',
	);
});

test('the one deliberate leniency is decompression, and it does not skip saveRun', () => {
	const body = importOneBody(source());
	// `gunzipBlob` cannot tell a corrupt member from a browser with no
	// `DecompressionStream`, so a failure imports trackless rather than
	// failing every gzipped row of a five-year export. It must set the
	// flag, not return early — an early return skips saveRun while the
	// caller still counts the row as imported (the phantom-import bug).
	const gunzipAt = body.indexOf('gunzipBlob(');
	assert.notEqual(gunzipAt, -1, 'the gzip branch must still exist');
	const branch = body.slice(gunzipAt);
	assert.match(branch, /canParse = false/, 'a failed inflate must fall through to a trackless import');
	assert.doesNotMatch(
		branch.slice(0, branch.indexOf('if (canParse)')),
		/\breturn\b/,
		'a failed inflate must not return early past saveRun',
	);
});

test('a refused row is counted and reported, not merely logged', () => {
	const s = source();
	const loop = s.slice(
		s.indexOf('const { droppedPhotos } = await importOne('),
		s.indexOf('async function importOne('),
	);
	assert.ok(loop.length > 0, 'the per-row call site not found');
	assert.match(loop, /catch \(err\)/, 'the per-row catch must survive');
	assert.match(loop, /progress\.failed\+\+/, 'a refused row must not read as imported');
	assert.match(
		loop,
		/recordImportFailure\(/,
		'the refusal must reach ImportFailureReport with its reason',
	);
	assert.doesNotMatch(
		loop,
		/progress\.imported\+\+[\s\S]*?catch \(err\)[\s\S]*?progress\.imported\+\+/,
		'a refused row must never increment the imported count',
	);
});
