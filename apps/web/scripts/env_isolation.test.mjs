import { test } from 'node:test';
import assert from 'node:assert/strict';

import { checkEnvIsolation, formatGuardError } from './env_isolation.mjs';

test('passes when only loopback URLs are set', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
		SUPABASE_URL: 'http://localhost:54321',
		OSRM_URL: 'http://127.0.0.1:5000',
	});
	assert.equal(r.ok, true);
	assert.equal(r.override, false);
	assert.equal(r.findings.length, 0);
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

test('detects multiple findings independently', () => {
	const r = checkEnvIsolation({
		PUBLIC_SUPABASE_URL: 'https://abcdefghijk.supabase.co',
		OSRM_URL: 'https://osrm.prod.example.com',
		STRIPE_SECRET_KEY: 'sk_live_abc',
	});
	assert.equal(r.findings.length, 3);
});
