import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	redactBreadcrumb,
	redactEventSignedUrls,
	redactSignedUrl,
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
