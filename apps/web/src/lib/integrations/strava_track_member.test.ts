// Unit tests for the Strava `Filename` → archive-member resolution.
//
// Invocation:
//   npx tsx --test src/lib/integrations/strava_track_member.test.ts
//
// The behaviour under test is a promise-keeping rule, not a parsing one:
// a row that names a track file the archive does not hold must FAIL and
// be reported, where it used to import silently as a summary-only run
// (decisions.md § 676, matching mobile's § 664).

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { resolveStravaTrackMember } from './strava_track_member';
import { classifyImportFailure } from './import_failures';

const holds = (...names: string[]) => (name: string) => names.includes(name);
const holdsNothing = () => false;

test('an empty Filename is not a broken export — no member, no throw', () => {
	// Strava leaves the column empty for a manually-entered or indoor
	// activity. The archive is never consulted.
	let looked = false;
	const member = resolveStravaTrackMember('', () => {
		looked = true;
		return false;
	});
	assert.deepEqual(member, { kind: 'none' });
	assert.equal(looked, false, 'an empty filename must not hit the archive');
});

test('a member the archive holds resolves to its parser + gzip flag', () => {
	assert.deepEqual(
		resolveStravaTrackMember('activities/123.gpx', holds('activities/123.gpx')),
		{ kind: 'member', parser: 'route', gzipped: false },
	);
	assert.deepEqual(
		resolveStravaTrackMember('activities/123.gpx.gz', holds('activities/123.gpx.gz')),
		{ kind: 'member', parser: 'route', gzipped: true },
	);
	assert.deepEqual(
		resolveStravaTrackMember('activities/123.fit.gz', holds('activities/123.fit.gz')),
		{ kind: 'member', parser: 'fit', gzipped: true },
	);
});

test('a Filename naming a file the archive does not hold throws, never imports trackless', () => {
	assert.throws(
		() => resolveStravaTrackMember('activities/999.gpx', holdsNothing),
		/track file not found in zip: activities\/999\.gpx/,
	);
});

test('the lookup is exact — a same-named file elsewhere in the archive is not it', () => {
	assert.throws(
		() => resolveStravaTrackMember('activities/1.gpx', holds('media/1.gpx')),
		/not found in zip/,
	);
});

test('a member in a format neither parser reads throws rather than importing trackless', () => {
	assert.throws(
		() => resolveStravaTrackMember('activities/1.csv', holds('activities/1.csv')),
		/Unsupported file format: activities\/1\.csv/,
	);
});

// The wording is load-bearing: the report groups by REASON, and "Unknown
// error" would tell a migrating runner nothing about whether re-running
// the import can land the missing runs. It cannot — the member is not in
// the file.
test('both refusals reach the failure report as `unparseable`, not `unknown`', () => {
	for (const thrown of [
		() => resolveStravaTrackMember('activities/9.gpx', holdsNothing),
		() => resolveStravaTrackMember('activities/9.csv', holds('activities/9.csv')),
	]) {
		let err: unknown;
		try {
			thrown();
		} catch (e) {
			err = e;
		}
		assert.ok(err, 'must have thrown');
		assert.equal(classifyImportFailure(err).reason, 'unparseable');
	}
});
