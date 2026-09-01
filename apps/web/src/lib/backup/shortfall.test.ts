// What /settings/account is allowed to say about a backup that came up
// short. Invocation:
//   npx tsx --test src/lib/backup/shortfall.test.ts
//
// `buildBackupZip` merges the writer's own finding (a track blob that
// would not download) with the caller's (a row read that died half-way,
// decisions § 675/§ 676) into ONE `incomplete` list, and the download
// surface read only the track counts off it. The case these tests exist
// for is the one that produced a false all-clear: an archive short of
// thousands of RUNS, whose tracks all downloaded, rendering "missing 0 of
// 0 GPS tracks".

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { backupShortfall, TRACKS_SECTION } from './shortfall';

test('a whole archive discloses nothing', () => {
	assert.equal(
		backupShortfall({ incomplete: [], blobsWanted: 12, blobsWritten: 12 }),
		null,
	);
});

test('a tracks-only shortfall states the count and names no section', () => {
	const s = backupShortfall({
		incomplete: [TRACKS_SECTION],
		blobsWanted: 9,
		blobsWritten: 7,
	});
	assert.deepEqual(s, { missingTracks: 2, wantedTracks: 9, sections: [] });
});

test('a short ROW read is disclosed even though every track downloaded', () => {
	// The regression this module exists for: the surface used to render
	// `missing 0 of 0 GPS tracks` here, which reads as an all-clear about
	// an archive missing most of the account's history.
	const s = backupShortfall({
		incomplete: ['runs'],
		blobsWanted: 0,
		blobsWritten: 0,
	});
	assert.ok(s, 'a short runs read must be disclosed');
	assert.equal(s.missingTracks, 0, 'no track sentence is earned');
	assert.deepEqual(s.sections, ['runs'], 'the short section must be named');
});

test('a short row read with tracks present still says nothing about tracks', () => {
	const s = backupShortfall({
		incomplete: ['routes'],
		blobsWanted: 250,
		blobsWritten: 250,
	});
	assert.ok(s);
	assert.equal(s.missingTracks, 0);
	assert.deepEqual(s.sections, ['routes']);
});

test('both kinds of shortfall are disclosed together', () => {
	const s = backupShortfall({
		incomplete: ['runs', TRACKS_SECTION],
		blobsWanted: 40,
		blobsWritten: 31,
	});
	assert.ok(s);
	assert.equal(s.missingTracks, 9);
	assert.equal(s.wantedTracks, 40);
	assert.deepEqual(s.sections, ['runs'], 'tracks carries its own count');
});

test('sections are deduped and sorted so the sentence is stable', () => {
	const s = backupShortfall({
		incomplete: ['routes', 'runs', 'routes', 'profile'],
		blobsWanted: 3,
		blobsWritten: 3,
	});
	assert.ok(s);
	assert.deepEqual(s.sections, ['profile', 'routes', 'runs']);
});

test('tracks named with no count to state is listed rather than swallowed', () => {
	// A caller can report the section itself (the writer never does with
	// equal counts). Dropping it here would turn a declared shortfall into
	// an empty disclosure — the exact failure shape being fixed.
	const s = backupShortfall({
		incomplete: [TRACKS_SECTION],
		blobsWanted: 5,
		blobsWritten: 5,
	});
	assert.ok(s);
	assert.equal(s.missingTracks, 0);
	assert.deepEqual(s.sections, [TRACKS_SECTION]);
});

test('a shortfall always earns at least one sentence', () => {
	for (const incomplete of [
		['runs'],
		['routes'],
		['profile'],
		['settings_prefs'],
		[TRACKS_SECTION],
		['runs', TRACKS_SECTION],
	]) {
		for (const [wanted, written] of [
			[0, 0],
			[5, 5],
			[5, 0],
			[5, 3],
		]) {
			const s = backupShortfall({
				incomplete,
				blobsWanted: wanted,
				blobsWritten: written,
			});
			assert.ok(s, `${incomplete.join(',')} @ ${wanted}/${written}`);
			assert.ok(
				s.missingTracks > 0 || s.sections.length > 0,
				`${incomplete.join(',')} @ ${wanted}/${written} disclosed nothing`,
			);
		}
	}
});

test('nonsense counts clamp instead of rendering a negative shortfall', () => {
	const s = backupShortfall({
		incomplete: [TRACKS_SECTION],
		blobsWanted: 2,
		blobsWritten: 9,
	});
	assert.ok(s);
	assert.equal(s.missingTracks, 0);
	assert.equal(s.wantedTracks, 2);

	const nan = backupShortfall({
		incomplete: [TRACKS_SECTION],
		blobsWanted: Number.NaN,
		blobsWritten: Number.NaN,
	});
	assert.ok(nan);
	assert.equal(nan.missingTracks, 0);
	assert.equal(nan.wantedTracks, 0);
});

test('the account page routes its disclosure through this grader', () => {
	// The template is the one place this repo cannot execute, so the
	// binding between the graded shortfall and the two sentences is
	// pinned at the source level.
	const page = readFileSync(
		resolve('src/routes/settings/account/+page.svelte'),
		'utf-8',
	);
	assert.match(
		page,
		/from '\$lib\/backup\/shortfall'/,
		'the page must import the grader',
	);
	const alias =
		page.match(/import \{\s*backupShortfall as (\w+)/)?.[1] ?? 'backupShortfall';
	assert.match(
		page,
		new RegExp(`${alias}\\(archive\\)`),
		'the page must grade the archive rather than reading the blob counts itself',
	);
	assert.match(
		page,
		/settingsAccount\.backupPartialNotice/,
		'the track-count sentence must still be reachable',
	);
	assert.match(
		page,
		/settingsAccount\.backupPartialSections/,
		'a non-track shortfall must have a sentence of its own',
	);
});
