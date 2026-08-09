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

// The same silent-drop family, one layer up: every push failure used to
// be caught bare and queued as "offline", so a refused write (RLS, CHECK,
// expired JWT) returned normally, the page said "Saved", and the pending
// queue retried the doomed write on every refresh forever.

function exportedFnBody(name: string): string {
	const start = source.indexOf(`export async function ${name}(`);
	assert.notEqual(start, -1, `${name} missing from settings.ts`);
	const next = source.indexOf('\nexport async function ', start + 1);
	const end = source.indexOf('\nasync function ', start + 1);
	const stop = [next, end].filter((i) => i !== -1).sort((a, b) => a - b)[0] ?? source.length;
	return source.slice(start, stop);
}

for (const name of ['updateUniversal', 'updateDevice']) {
	test(`${name} routes its push through pushOrQueue, so a refusal surfaces`, () => {
		const body = exportedFnBody(name);
		assert.match(body, /pushOrQueue\(/, `${name} must not decide queue-vs-throw inline`);
		assert.match(body, /rollback:/, 'a refused write must undo the optimistic cache write');
		assert.doesNotMatch(
			body,
			/catch\s*[({]/,
			`${name} must not swallow the push failure — a rejection has to reach the caller`,
		);
	});
}

test('every push failure is thrown as a classified SettingsWriteError', () => {
	for (const name of ['pushUniversal', 'pushDevice']) {
		const body = fnBody(name);
		const throws = body.match(/throw new SettingsWriteError\(/g) ?? [];
		assert.equal(
			throws.length,
			2,
			`${name} must classify both the read and the upsert failure — a bare throw reads as a bug, and bugs surface instead of queueing`,
		);
	}
});

test('drainPending drops a rejected entry instead of retrying it forever', () => {
	const body = fnBody('drainPending');
	assert.match(body, /drainQueue\(/, 'drainPending must use the classified drain');
	assert.doesNotMatch(
		body,
		/catch\s*[({]/,
		'a bare catch here stops the drain on a doomed entry and blocks every later change behind it',
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
