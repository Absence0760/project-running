import { test } from 'node:test';
import assert from 'node:assert/strict';
import { safeImageSrc } from './safe_image_src.js';

test('safeImageSrc: passes through https URLs', () => {
	assert.equal(
		safeImageSrc('https://cdn.example.com/avatar.png'),
		'https://cdn.example.com/avatar.png',
	);
});

test('safeImageSrc: rejects javascript: scheme', () => {
	assert.equal(safeImageSrc('javascript:alert(1)'), '');
});

test('safeImageSrc: rejects http: (no plaintext image loads)', () => {
	assert.equal(safeImageSrc('http://insecure.example.com/a.png'), '');
});

test('safeImageSrc: rejects data: by default', () => {
	assert.equal(safeImageSrc('data:image/svg+xml,<svg onload=alert(1)>'), '');
});

test('safeImageSrc: rejects blob: by default', () => {
	assert.equal(safeImageSrc('blob:https://app.example.com/abc-123'), '');
});

test('safeImageSrc: allows blob: only when opted in (local preview)', () => {
	assert.equal(
		safeImageSrc('blob:https://app.example.com/abc-123', { allowBlob: true }),
		'blob:https://app.example.com/abc-123',
	);
});

test('safeImageSrc: allows data:image only when opted in', () => {
	assert.equal(
		safeImageSrc('data:image/png;base64,AAAA', { allowData: true }),
		'data:image/png;base64,AAAA',
	);
	// A non-image data: URL is still rejected even with allowData.
	assert.equal(safeImageSrc('data:text/html,<script>', { allowData: true }), '');
});

test('safeImageSrc: null / undefined / empty return empty string', () => {
	assert.equal(safeImageSrc(null), '');
	assert.equal(safeImageSrc(undefined), '');
	assert.equal(safeImageSrc(''), '');
});

test('safeImageSrc: trims surrounding whitespace before matching', () => {
	assert.equal(
		safeImageSrc('  https://cdn.example.com/a.png  '),
		'https://cdn.example.com/a.png',
	);
	// Leading whitespace must not let a hostile scheme slip past the
	// startsWith check.
	assert.equal(safeImageSrc('  javascript:alert(1)'), '');
});
