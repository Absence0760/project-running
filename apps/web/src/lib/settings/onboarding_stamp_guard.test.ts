// Source-level guard pinning the issue #227 fix. user_profiles rows are
// client-provisioned, so the onboarding stamp writes (Skip-onboarding +
// the final Open-dashboard finish) that did a plain UPDATE against a
// missing row matched 0 rows and reported success: the page navigated to
// /dashboard, the layout gate re-read a still-null onboarded_at, and the
// user bounced back to step 1 of /onboarding with every answer lost.
// Both exits must route through the row-count-verified stampProfile
// (update().select('id') + insert fallback, ADR 248), and neither exit
// may silently return when auth hydration fails — the silent bail made
// the button do nothing with no feedback.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const source = readFileSync(
	resolve('src/routes/onboarding/+page.svelte'),
	'utf-8',
);

function fnBody(name: string): string {
	const start = source.indexOf(`async function ${name}(`);
	assert.notEqual(start, -1, `${name} missing from onboarding/+page.svelte`);
	const next = source.indexOf('\n\tasync function ', start + 1);
	return next === -1 ? source.slice(start) : source.slice(start, next);
}

test('stampProfile verifies the row count and falls back to insert (#227)', () => {
	const body = fnBody('stampProfile');
	assert.match(
		body,
		/\.update\(profileUpdate\)[\s\S]*?\.select\('id'\)/,
		'the stamp update must select the updated id so 0 rows is detectable',
	);
	assert.match(
		body,
		/updatedRows\?\.length[\s\S]*?\.insert\(/,
		'a 0-row update must fall back to inserting the profile row',
	);
});

test('skipOnboarding routes through stampProfile and never bails silently', () => {
	const body = fnBody('skipOnboarding');
	assert.match(body, /await stampProfile\(/, 'skip must use the verified stamp');
	assert.doesNotMatch(
		body,
		/ensureAuthUser\(\)\)\)\s*return;/,
		'an auth-hydration failure must surface a toast, not a silent return',
	);
});

test('finishAndExit routes through stampProfile and never bails silently', () => {
	const body = fnBody('finishAndExit');
	assert.match(body, /stampProfile\(profileUpdate\)/, 'finish must use the verified stamp');
	assert.doesNotMatch(
		body,
		/ensureAuthUser\(\)\)\)\s*return;/,
		'an auth-hydration failure must surface a toast, not a silent return',
	);
});
