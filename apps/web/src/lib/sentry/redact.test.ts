import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	redactBreadcrumb,
	redactEventSignedUrls,
	redactLiveHubToken,
	redactSignedUrl,
	redactUrl,
} from './redact';

const SIGNED_URL =
	'https://abc.supabase.co/storage/v1/object/sign/runs/abcdef.json.gz?token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.sig';
const SIGNED_URL_REDACTED =
	'https://abc.supabase.co/storage/v1/object/sign/runs/abcdef.json.gz?<redacted>';

// ─────────────── redactSignedUrl ───────────────

test('redactSignedUrl — strips the query string off a signed URL', () => {
	assert.equal(redactSignedUrl(SIGNED_URL), SIGNED_URL_REDACTED);
});

test('redactSignedUrl — leaves non-signed URLs alone', () => {
	const plain = 'https://abc.supabase.co/rest/v1/runs?select=*';
	assert.equal(redactSignedUrl(plain), plain);
});

test('redactSignedUrl — handles a signed URL without a query string', () => {
	const noQuery = 'https://abc.supabase.co/storage/v1/object/sign/runs/abcdef.json.gz';
	assert.equal(redactSignedUrl(noQuery), noQuery);
});

test('redactSignedUrl — covers any private bucket via broad substring match', () => {
	// Run-photos is the canonical caller, but the helper is intentionally
	// non-bucket-specific so a future private bucket added with the same
	// signed-URL pattern is covered without a fix.
	const photos =
		'https://abc.supabase.co/storage/v1/object/sign/run-photos/u1/p1.jpg?token=secret';
	assert.equal(
		redactSignedUrl(photos),
		'https://abc.supabase.co/storage/v1/object/sign/run-photos/u1/p1.jpg?<redacted>',
	);
});

// ─────────────── redactBreadcrumb ───────────────

test('redactBreadcrumb — redacts a fetch breadcrumb url', () => {
	const b = { category: 'fetch', data: { url: SIGNED_URL } };
	const out = redactBreadcrumb(b);
	assert.equal(out.data!.url, SIGNED_URL_REDACTED);
});

test('redactBreadcrumb — redacts a console breadcrumb message', () => {
	// data.ts logs Storage paths via console.warn on delete-failure paths.
	const b = {
		category: 'console',
		message: `[storage] failed to delete ${SIGNED_URL}`,
	};
	const out = redactBreadcrumb(b);
	assert.equal(
		out.message,
		`[storage] failed to delete ${SIGNED_URL_REDACTED}`,
	);
});

test('redactBreadcrumb — leaves a non-URL breadcrumb untouched', () => {
	const b = { category: 'navigation', data: { from: '/runs', to: '/dashboard' } };
	const out = redactBreadcrumb(b);
	assert.deepEqual(out.data, { from: '/runs', to: '/dashboard' });
});

// ─────────────── redactEventSignedUrls ───────────────

test('redactEventSignedUrls — redacts the transaction string', () => {
	const e = { transaction: SIGNED_URL };
	const out = redactEventSignedUrls(e);
	assert.equal(out.transaction, SIGNED_URL_REDACTED);
});

test('redactEventSignedUrls — redacts request.url', () => {
	const e = { request: { url: SIGNED_URL } };
	const out = redactEventSignedUrls(e);
	assert.equal(out.request!.url, SIGNED_URL_REDACTED);
});

test('redactEventSignedUrls — redacts every span.data.url', () => {
	const e = {
		spans: [
			{ data: { url: SIGNED_URL, op: 'http.client' } },
			{ data: { url: 'https://example.com/' } },
		],
	};
	const out = redactEventSignedUrls(e);
	assert.equal(out.spans![0].data!.url, SIGNED_URL_REDACTED);
	assert.equal(out.spans![1].data!.url, 'https://example.com/');
});

test('redactEventSignedUrls — empty event passes through', () => {
	assert.deepEqual(redactEventSignedUrls({}), {});
});

// audit/owasp May 2026 Low #6 — live-hub JWT must not reach Sentry.

const LH_URL =
	'wss://live.threkir.com/v1/live/run-1/subscribe?token=eyJ.fake.jwt&foo=bar';
const LH_URL_REDACTED =
	'wss://live.threkir.com/v1/live/run-1/subscribe?token=<redacted>&foo=bar';

test('redactLiveHubToken — strips ?token= on subscribe URL', () => {
	assert.equal(redactLiveHubToken(LH_URL), LH_URL_REDACTED);
});

test('redactLiveHubToken — strips token= on snapshot URL', () => {
	const u = 'https://live.threkir.com/v1/live/run-1/snapshot?token=jwt';
	assert.equal(
		redactLiveHubToken(u),
		'https://live.threkir.com/v1/live/run-1/snapshot?token=<redacted>',
	);
});

test('redactLiveHubToken — passes through non-livehub URLs unchanged', () => {
	const u = 'https://example.com/?token=safe';
	assert.equal(redactLiveHubToken(u), u);
});

test('redactLiveHubToken — passes through livehub URL without token', () => {
	const u = 'wss://live.threkir.com/v1/live/run-1/subscribe';
	assert.equal(redactLiveHubToken(u), u);
});

test('redactUrl — applies both Storage + live-hub redactors', () => {
	assert.equal(redactUrl(SIGNED_URL), SIGNED_URL_REDACTED);
	assert.equal(redactUrl(LH_URL), LH_URL_REDACTED);
	assert.equal(redactUrl('https://example.com/'), 'https://example.com/');
});

test('redactBreadcrumb — applies live-hub redactor to data.url', () => {
	const b = { category: 'fetch', data: { url: LH_URL } };
	const out = redactBreadcrumb(b);
	assert.equal(out.data!.url, LH_URL_REDACTED);
});

test('redactEventSignedUrls — redacts live-hub URL on request + transaction + spans', () => {
	const e = {
		transaction: LH_URL,
		request: { url: LH_URL },
		spans: [{ data: { url: LH_URL } }],
	};
	const out = redactEventSignedUrls(e);
	assert.equal(out.transaction, LH_URL_REDACTED);
	assert.equal(out.request!.url, LH_URL_REDACTED);
	assert.equal(out.spans![0].data!.url, LH_URL_REDACTED);
});
