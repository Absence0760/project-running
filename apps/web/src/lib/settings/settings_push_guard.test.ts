// Source-level guard pinning the issue #234 fix. user_settings /
// user_device_settings rows are client-provisioned, so a push that does
// read-merge-UPDATE against a missing row matches 0 rows and reports
// success: the change is neither stored nor queued (the pending queue
// only fires on throw), the cache is stamped as pushed, and the next
// load reverts the setting. These bags carry privacy_zones (server-side
// track clipping) and safety_overdue_minutes (the pg_cron overdue
// escalation), so a silent drop is a privacy/safety failure. The push
// must stay an UPSERT, and the loadSettings auto-provision writes must
// stay error-checked.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const source = readFileSync(resolve('src/lib/settings/settings.ts'), 'utf-8');

function fnBody(name: string): string {
	const start = source.indexOf(`async function ${name}(`);
	assert.notEqual(start, -1, `${name} missing from settings.ts`);
	const next = source.indexOf('\nasync function ', start + 1);
	return next === -1 ? source.slice(start) : source.slice(start, next);
}

test('pushUniversal upserts user_settings (0-row update hole, #234)', () => {
	const body = fnBody('pushUniversal');
	assert.match(body, /\.upsert\(/, 'pushUniversal must upsert');
	assert.doesNotMatch(
		body,
		/\.update\(/,
		'pushUniversal must not use .update() — a missing row 0-row no-ops',
	);
});

test('pushDevice upserts user_device_settings with the NOT NULL platform', () => {
	const body = fnBody('pushDevice');
	assert.match(body, /\.upsert\(/, 'pushDevice must upsert');
	assert.doesNotMatch(
		body,
		/\.update\(/,
		'pushDevice must not use .update() — a missing row 0-row no-ops',
	);
	assert.match(
		body,
		/platform:\s*detectPlatform\(\)/,
		'the insert arm needs platform (NOT NULL) or a first-write 23502s',
	);
});

test('loadSettings error-checks the auto-provision upserts', () => {
	const body = fnBody('loadSettings');
	const provisionChecks = body.match(/provRes\.error\)\s*throw\s+provRes\.error/g) ?? [];
	assert.equal(
		provisionChecks.length,
		2,
		'both auto-provision upserts (universal + device) must throw on error',
	);
});
