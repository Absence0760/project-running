// Guards for pages that must follow the light/dark theme rather than
// hard-coding a colour. app.css carries a full token set and a shared
// button vocabulary; a page that paints its own white surface under themed
// ink is legible in exactly one theme.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('/safety/confirm draws on theme tokens, not a fixed white card', () => {
	// Reason: the card hard-coded `background: #fff` under `--color-text`
	// ink, so in dark mode near-white text sat on a white card and the whole
	// page was unreadable. This is the anonymous page an emergency contact
	// lands on from an email — there is no navigation and no account behind
	// it, so an unreadable card is a contact that never gets confirmed.
	//
	// Its local `.btn-primary` copy — which app.css explicitly forbids —
	// hard-coded `color: #fff`, and the dark theme's primary fill is a light
	// peach, so the CTA failed in dark too.
	const source = read('src/routes/safety/confirm/+page.svelte');
	const style = source.slice(source.indexOf('<style>'));
	assert.doesNotMatch(style, /#fff\b/i, 'no fixed white on a themed page');
	assert.match(style, /background: var\(--color-surface\);/, 'the card takes the surface token');
	assert.doesNotMatch(
		style,
		/\.btn-primary \{/,
		'app.css owns .btn-primary — a local copy drifts out of the theme',
	);
});
