import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Guards the app-shell RTL readiness that audit/i18n-readiness (2026-05-30)
 * graded Critical (W-10): the shell frame was pinned to the physical left
 * (margin-left / left / border-right), so an RTL locale (Arabic, Hebrew,
 * Persian, Urdu) would render content overlapping the sidebar. The shell now
 * uses CSS logical properties so flipping <html dir="rtl"> mirrors it.
 *
 * Scope note: this pins the SHELL only. The component-level physical-property
 * sweep + the dir-from-locale wiring ride with the i18n framework (W-1, High,
 * a scheduled project) — RTL can't be activated or visually verified until a
 * locale signal exists, and logical-property edits are invisible in LTR.
 */

const webRoot = resolve(import.meta.dirname, '..', '..');
const layout = readFileSync(resolve(webRoot, 'src', 'routes', '+layout.svelte'), 'utf-8');
const appHtml = readFileSync(resolve(webRoot, 'src', 'app.html'), 'utf-8');

test('the shell offsets the main content with a logical property', () => {
	assert.ok(
		layout.includes('margin-inline-start: var(--sidebar-width)'),
		'.main-content must offset the sidebar with margin-inline-start (RTL-aware).',
	);
	assert.ok(
		!/margin-left:\s*var\(--sidebar-width\)/.test(layout),
		'.main-content must not use physical margin-left for the sidebar offset — ' +
			'it overlaps content in RTL. Use margin-inline-start.',
	);
});

test('the sidebar pins to the inline-start edge, not the physical left', () => {
	assert.ok(
		layout.includes('inset-inline-start: 0'),
		'.sidebar must pin with inset-inline-start so it flips to the right in RTL.',
	);
	assert.ok(
		layout.includes('border-inline-end: 1px solid var(--sidebar-border)'),
		'.sidebar divider must be border-inline-end, not border-right.',
	);
});

test('no physical-direction CSS remains in the app shell', () => {
	// The shell is the page frame every route inherits; keeping it free of
	// physical-direction properties is the high-value RTL guarantee.
	for (const prop of [
		'margin-left',
		'margin-right',
		'padding-left',
		'padding-right',
		'border-left',
		'border-right',
	]) {
		assert.ok(
			!new RegExp(`${prop}:`).test(layout),
			`+layout.svelte must not use physical ${prop} — use the inline-logical ` +
				`equivalent (margin-inline-*, padding-inline-*, border-inline-*).`,
		);
	}
});

test('<html> carries an explicit dir switch-point', () => {
	assert.ok(
		/<html\s+[^>]*\bdir="(ltr|rtl)"/.test(appHtml),
		'app.html <html> must carry an explicit dir attribute — the single point ' +
			'the i18n framework flips to mirror the (already logical) shell.',
	);
});
