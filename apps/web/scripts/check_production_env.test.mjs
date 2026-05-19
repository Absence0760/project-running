// Unit tests for the production build-env guard. Run via:
//   node --test apps/web/scripts/check_production_env.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import { checkProductionEnv } from './check_production_env.mjs';

const SCRIPT_PATH = fileURLToPath(new URL('./check_production_env.mjs', import.meta.url));

/**
 * Run the script as its own CLI process. The script's `import.meta.url ===
 * file:${argv[1]}` entry-point guard only fires when invoked as a binary,
 * so the in-process import above wouldn't exercise the process.exit /
 * stderr-write paths; this wrapper covers them.
 *
 * @param {Record<string, string>} extraEnv
 * @returns {{ status: number, stdout: string, stderr: string }}
 */
function runScript(extraEnv) {
	const r = spawnSync(process.execPath, [SCRIPT_PATH], {
		env: {
			// Wipe PUBLIC_* / process inherits so the test starts with a
			// known-empty environment (CI may export these for the build
			// step). Only the keys passed in extraEnv are visible.
			PATH: process.env.PATH,
			...extraEnv,
		},
		encoding: 'utf8',
	});
	return { status: r.status ?? -1, stdout: r.stdout, stderr: r.stderr };
}

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

// ──────────────────── CLI integration ────────────────────
//
// The pure helper has 7 unit cases. The CLI entry block (process.exit,
// stderr write) only fires when the script is invoked as a binary,
// which an in-process import doesn't exercise. These tests spawn the
// script as a subprocess to lock down exit codes + stderr shape so a
// future refactor that swaps `process.exit(1)` for a returned value
// (which CI would silently treat as a passing step) fails loud.

test('CLI exits 0 + prints a proceed banner when env is valid', () => {
	const r = runScript({
		PUBLIC_SUPABASE_URL: 'https://prod-project.supabase.co',
		PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_real_key_12345',
	});
	assert.equal(r.status, 0, `expected exit 0, got ${r.status}. stderr: ${r.stderr}`);
	assert.match(r.stdout, /look real — proceeding/);
	assert.equal(r.stderr, '');
});

test('CLI exits 1 + writes the violation report to stderr when URL is empty', () => {
	const r = runScript({
		PUBLIC_SUPABASE_URL: '',
		PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_real_key_12345',
	});
	assert.equal(r.status, 1, `expected exit 1, got ${r.status}`);
	assert.match(r.stderr, /release-web build refuses to start/);
	assert.match(r.stderr, /PUBLIC_SUPABASE_URL/);
	// Stdout stays quiet on failure — the banner shouldn't pollute the
	// build-log success channel.
	assert.equal(r.stdout, '');
});

test('CLI exits 1 + names both vars when both are missing', () => {
	const r = runScript({});
	assert.equal(r.status, 1);
	assert.match(r.stderr, /PUBLIC_SUPABASE_URL/);
	assert.match(r.stderr, /PUBLIC_SUPABASE_ANON_KEY/);
});

test('CLI exits 1 on the CI placeholder URL', () => {
	const r = runScript({
		PUBLIC_SUPABASE_URL: 'https://placeholder.supabase.co',
		PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_real_key_12345',
	});
	assert.equal(r.status, 1);
	assert.match(r.stderr, /placeholder/i);
});
