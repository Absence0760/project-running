import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { stripComments } from '../../src/lib/core/strip_comments';
import { storageFailure } from './simulate';

/*
 * A Storage failure in a fixture has to say WHICH object failed and HOW.
 *
 * The one occurrence on record read `simulate.insertRun track upload failed:
 * An invalid response was received from the upstream server` and nothing
 * else. That is Kong's 502 body: it names no bucket, no path and no status,
 * so the reader cannot tell "Storage refused this object" from "Storage was
 * not answering" — and the second is what actually happened (decisions
 * § 1403). An unattributable seeding error reads as a spec defect, which is
 * the expensive way to be wrong about a flake.
 *
 * Two claims. The first is about the sentence itself; the second is that
 * every Storage throw in `simulate.ts` goes through the one builder, because
 * a second hand-rolled `${err.message}` is exactly how the first one got
 * there. The second is a coverage claim, so it is allowed to read the source:
 * it fails when a throw exists that the builder does not shape, not when a
 * particular spelling changes.
 */

const HERE = dirname(fileURLToPath(import.meta.url));
const SIMULATE = join(HERE, 'simulate.ts');

test('the message names the bucket, the path and the status', () => {
	const msg = storageFailure('insertRun track upload', 'runs', 'user/run.json.gz', {
		message: 'An invalid response was received from the upstream server',
		statusCode: '502',
	}).message;
	assert.match(msg, /insertRun track upload/);
	assert.match(msg, /bucket runs/);
	assert.match(msg, /path user\/run\.json\.gz/);
	assert.match(msg, /status 502/);
	assert.match(msg, /An invalid response was received from the upstream server/);
});

test('a failure carrying no status still names the object', () => {
	// supabase-js types the error as `StorageError`, which carries only a
	// message; only the `StorageApiError` subclass has the status. So the
	// status has to be optional, and its absence must not swallow the rest.
	const msg = storageFailure('insertMatchedTrack upload', 'runs', 'user/run.matched.json.gz', {
		message: 'Network request failed',
	}).message;
	assert.match(msg, /bucket runs/);
	assert.match(msg, /path user\/run\.matched\.json\.gz/);
	assert.doesNotMatch(msg, /status/);
	assert.match(msg, /Network request failed/);
});

test('every upload error in simulate.ts is reported through the builder', () => {
	const source = stripComments(readFileSync(SIMULATE, 'utf8'));
	// Each upload binds its own error variable; the guard follows THOSE
	// bindings rather than a spelling, so it tracks whatever the code calls
	// them. Row-update errors are deliberately out of scope: PostgREST already
	// says what it refused, and "bucket runs, path ..." would be a lie about a
	// failure that never touched Storage.
	const uploads = [
		...source.matchAll(/const \{\s*error:\s*([A-Za-z_$][\w$]*)\s*\}[\s\S]{0,240}?\.upload\s*\(/g),
	].map(([, name]) => name);
	assert.ok(
		uploads.length > 0,
		'No upload in simulate.ts binds an error — the assertions below are vacuous until this finds them.',
	);

	const unshaped = uploads.filter(
		(name) => !new RegExp(`storageFailure\\([^)]*\\b${name}\\b`).test(source),
	);
	assert.deepEqual(
		unshaped,
		[],
		`These upload errors never reach storageFailure, so they name neither the object nor the ` +
			`status: ${unshaped.join(', ')}`,
	);

	const interpolated = uploads.filter((name) =>
		new RegExp(`\\$\\{\\s*${name}\\??\\.message`).test(source),
	);
	assert.deepEqual(
		interpolated,
		[],
		`These upload errors are interpolated into a hand-rolled message somewhere as well: ` +
			`${interpolated.join(', ')}`,
	);
});
