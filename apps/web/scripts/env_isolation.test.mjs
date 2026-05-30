import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { checkEnvIsolation, formatGuardError } from './env_isolation.mjs';

test('passes when only loopback URLs are set', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
		SUPABASE_URL: 'http://localhost:54321',
		PUBLIC_OSRM_URL: 'http://127.0.0.1:5000',
		OSRM_URL: 'http://127.0.0.1:5000',
	});
	assert.equal(r.ok, true);
	assert.equal(r.override, false);
	assert.equal(r.findings.length, 0);
});

test('fails when PUBLIC_OSRM_URL points at a remote host', () => {
	const r = checkEnvIsolation({
		PUBLIC_OSRM_URL: 'https://osrm.example.com',
	});
	assert.equal(r.ok, false);
	assert.equal(r.findings[0].envVar, 'PUBLIC_OSRM_URL');
});

test('passes when env is empty', () => {
	const r = checkEnvIsolation({});
	assert.equal(r.ok, true);
});

test('fails when PUBLIC_SUPABASE_URL points at a *.supabase.co domain', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'https://abcdefghijk.supabase.co',
	});
	assert.equal(r.ok, false);
	assert.equal(r.findings.length, 1);
	assert.equal(r.findings[0].envVar, 'PUBLIC_SUPABASE_URL');
	assert.equal(r.findings[0].rule, 'remote-host-in-dev');
});

test('fails when SUPABASE_URL points at a custom domain', () => {
	const r = checkEnvIsolation({ SUPABASE_URL: 'https://api.example.com' });
	assert.equal(r.ok, false);
});

test('accepts the Android emulator alias 10.0.2.2', () => {
	const r = checkEnvIsolation({ PUBLIC_SUPABASE_URL: 'http://10.0.2.2:54321' });
	assert.equal(r.ok, true);
});

test('accepts host.docker.internal for Docker-on-Mac/Windows', () => {
	const r = checkEnvIsolation({ PUBLIC_SUPABASE_URL: 'http://host.docker.internal:54321' });
	assert.equal(r.ok, true);
});

test('fails on a live Stripe secret key', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
		STRIPE_SECRET_KEY: 'sk_live_abcdef0123456789',
	});
	assert.equal(r.ok, false);
	assert.equal(r.findings[0].envVar, 'STRIPE_SECRET_KEY');
	assert.equal(r.findings[0].rule, 'live-key-in-dev');
	assert.equal(r.findings[0].value, '<redacted live key>');
});

test('accepts a test Stripe secret key', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
		STRIPE_SECRET_KEY: 'sk_test_abcdef0123456789',
	});
	assert.equal(r.ok, true);
});

test('fails on a live publishable Stripe key', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
		PUBLIC_STRIPE_KEY: 'pk_live_abcdef0123456789',
	});
	assert.equal(r.ok, false);
});

test('ALLOW_PROD_URL_IN_DEV=true bypasses every check', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'https://abcdefghijk.supabase.co',
		STRIPE_SECRET_KEY: 'sk_live_abcdef0123456789',
		ALLOW_PROD_URL_IN_DEV: 'true',
	});
	assert.equal(r.ok, true);
	assert.equal(r.override, true);
});

test('ALLOW_PROD_URL_IN_DEV=false does NOT bypass', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'https://abcdefghijk.supabase.co',
		ALLOW_PROD_URL_IN_DEV: 'false',
	});
	assert.equal(r.ok, false);
});

test('formatGuardError includes the env var name + fix hint', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'https://abcdefghijk.supabase.co',
	});
	const msg = formatGuardError(r, { scope: 'vite' });
	assert.match(msg, /PUBLIC_SUPABASE_URL/);
	assert.match(msg, /loopback URL/);
	assert.match(msg, /ALLOW_PROD_URL_IN_DEV/);
});

test('fails when PUBLIC_LIVE_HUB_URL points at a remote host', () => {
	// The web client reads PUBLIC_LIVE_HUB_URL (bundled at build
	// time). A dev .env with the production live-hub URL would push
	// test pings at the live broadcast service. The Dart twin uses
	// LIVE_HUB_URL via dotenv; both forms must be guarded.
	const r = checkEnvIsolation({
		PUBLIC_LIVE_HUB_URL: 'https://live.threkir.com',
	});
	assert.equal(r.ok, false);
	assert.equal(r.findings[0].envVar, 'PUBLIC_LIVE_HUB_URL');
	assert.equal(r.findings[0].rule, 'remote-host-in-dev');
});

test('accepts a loopback PUBLIC_LIVE_HUB_URL', () => {
	const r = checkEnvIsolation({
		PUBLIC_LIVE_HUB_URL: 'http://127.0.0.1:9090',
	});
	assert.equal(r.ok, true);
});

test('fails when PUBLIC_EXPORT_HUB_URL points at a remote host', () => {
	// The "Cloud export (GPX zip)" button POSTs to
	// `${PUBLIC_EXPORT_HUB_URL}/v1/export` (the Go worker). A dev
	// .env aimed at the prod exporter would write test export jobs
	// into live infra's queue + Storage.
	const r = checkEnvIsolation({
		PUBLIC_EXPORT_HUB_URL: 'https://api.threkir.com',
	});
	assert.equal(r.ok, false);
	assert.equal(r.findings[0].envVar, 'PUBLIC_EXPORT_HUB_URL');
});

test('accepts a loopback PUBLIC_EXPORT_HUB_URL', () => {
	const r = checkEnvIsolation({
		PUBLIC_EXPORT_HUB_URL: 'http://127.0.0.1:8080',
	});
	assert.equal(r.ok, true);
});

test('docs/testing/dev_prod_isolation.md lists every var the helper guards', () => {
	// Reason: the doc and the KNOWN_ENV_VARS list in env_isolation.mjs
	// drifted once (the doc was correct, the helper missed
	// PUBLIC_LIVE_HUB_URL + PUBLIC_EXPORT_HUB_URL — both were real
	// dev → prod misconfiguration risks for the live-hub + cloud-
	// exporter that the guard silently waved through). Pin the lockstep
	// so a future writer who adds a new URL-shaped env var has to
	// update the doc in the same change.
	const helperSrc = readFileSync(
		resolve(import.meta.dirname, 'env_isolation.mjs'),
		'utf-8',
	);
	const helperListBlock = helperSrc.match(/KNOWN_ENV_VARS\s*=\s*\[([\s\S]*?)\];/);
	assert.ok(helperListBlock, 'Could not locate KNOWN_ENV_VARS in env_isolation.mjs.');
	const helperVars = [
		...helperListBlock[1].matchAll(/'([A-Z][A-Z0-9_]*)'/g),
	].map((m) => m[1]);
	assert.ok(helperVars.length >= 7, 'KNOWN_ENV_VARS unexpectedly small.');

	const doc = readFileSync(
		resolve(import.meta.dirname, '../../../docs/testing/dev_prod_isolation.md'),
		'utf-8',
	);
	for (const v of helperVars) {
		assert.match(
			doc,
			new RegExp(`\\b${v}\\b`),
			`docs/testing/dev_prod_isolation.md must mention ${v}. The helper guards it but the doc would silently underdescribe what dev → prod misconfig is caught.`,
		);
	}
});

test('detects multiple findings independently', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'https://abcdefghijk.supabase.co',
		OSRM_URL: 'https://osrm.prod.example.com',
		STRIPE_SECRET_KEY: 'sk_live_abc',
	});
	assert.equal(r.findings.length, 3);
});
