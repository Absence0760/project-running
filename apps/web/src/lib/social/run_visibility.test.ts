import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { privacyDefaultToIsPublic } from './run_visibility';

test('privacyDefaultToIsPublic — only "public" yields a public run', () => {
	assert.equal(privacyDefaultToIsPublic('public'), true);
});

test('privacyDefaultToIsPublic — followers stays private', () => {
	// Runs have no followers-only tier; followers default => private run.
	assert.equal(privacyDefaultToIsPublic('followers'), false);
});

test('privacyDefaultToIsPublic — private stays private', () => {
	assert.equal(privacyDefaultToIsPublic('private'), false);
});

test('privacyDefaultToIsPublic — missing / unknown pref is fail-closed (private)', () => {
	assert.equal(privacyDefaultToIsPublic(null), false);
	assert.equal(privacyDefaultToIsPublic(undefined), false);
	assert.equal(privacyDefaultToIsPublic('nonsense'), false);
	assert.equal(privacyDefaultToIsPublic(''), false);
});
