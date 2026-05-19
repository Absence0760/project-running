// Unit tests for the production build-env guard. Run via:
//   node --test apps/web/scripts/check_production_env.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { checkProductionEnv } from './check_production_env.mjs';

test('passes for a real Supabase URL + non-empty anon key', () => {
	const r = checkProductionEnv({
		PUBLIC_SUPABASE_URL: 'https://prod-project.supabase.co',
		PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_real_key_12345',
	});
	assert.equal(r.ok, true);
	assert.deepEqual(r.findings, []);
});

test('rejects an empty / undefined PUBLIC_SUPABASE_URL', () => {
	const empty = checkProductionEnv({
		PUBLIC_SUPABASE_URL: '',
		PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_real_key_12345',
	});
	assert.equal(empty.ok, false);
	assert.equal(empty.findings[0].envVar, 'PUBLIC_SUPABASE_URL');

	const undef = checkProductionEnv({
		PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_real_key_12345',
	});
	assert.equal(undef.ok, false);
	assert.equal(undef.findings[0].envVar, 'PUBLIC_SUPABASE_URL');
});

test('rejects the CI bundle-budget placeholder URL', () => {
	const r = checkProductionEnv({
		PUBLIC_SUPABASE_URL: 'https://placeholder.supabase.co',
		PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_real_key_12345',
	});
	assert.equal(r.ok, false);
	assert.equal(r.findings[0].envVar, 'PUBLIC_SUPABASE_URL');
	assert.match(r.findings[0].reason, /placeholder/i);
});

test('rejects a loopback URL', () => {
	const cases = [
		'http://127.0.0.1:54321',
		'http://localhost:54321',
		'http://10.0.2.2:54321/',
	];
	for (const url of cases) {
		const r = checkProductionEnv({
			PUBLIC_SUPABASE_URL: url,
			PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_real_key_12345',
		});
		assert.equal(r.ok, false, `expected reject for ${url}`);
		assert.equal(r.findings[0].envVar, 'PUBLIC_SUPABASE_URL');
		assert.match(r.findings[0].reason, /loopback/i);
	}
});

test('rejects an empty PUBLIC_SUPABASE_ANON_KEY independently', () => {
	const r = checkProductionEnv({
		PUBLIC_SUPABASE_URL: 'https://prod-project.supabase.co',
		PUBLIC_SUPABASE_ANON_KEY: '',
	});
	assert.equal(r.ok, false);
	assert.equal(r.findings[0].envVar, 'PUBLIC_SUPABASE_ANON_KEY');
});

test('reports both findings together when both are bad', () => {
	const r = checkProductionEnv({
		PUBLIC_SUPABASE_URL: '',
		PUBLIC_SUPABASE_ANON_KEY: '',
	});
	assert.equal(r.ok, false);
	assert.equal(r.findings.length, 2);
	const vars = r.findings.map((f) => f.envVar).sort();
	assert.deepEqual(vars, ['PUBLIC_SUPABASE_ANON_KEY', 'PUBLIC_SUPABASE_URL']);
});

test('trims whitespace before checking', () => {
	// `   https://prod-project.supabase.co\n` should still validate
	// (CI's `cat <<EOF` sometimes leaves a trailing newline).
	const r = checkProductionEnv({
		PUBLIC_SUPABASE_URL: '   https://prod-project.supabase.co\n',
		PUBLIC_SUPABASE_ANON_KEY: '   sb_publishable_real_key_12345\n',
	});
	assert.equal(r.ok, true);
});
