// Guards for file pickers that must stay operable without a mouse.
//
// The idiom is a real <button> that forwards a click to an off-screen
// <input type="file">. The tempting shorthand — a <label> wrapping a
// `hidden` input — has no focusable element in it at all: the input is out
// of the tab order and a label is not a control, so the picker is
// mouse-only and invisible to a screen reader.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('the bulk-import pickers drive their input from a real button', () => {
	const source = read('src/routes/settings/integrations/+page.svelte');
	assert.doesNotMatch(
		source,
		/<label class="zip-btn">/,
		'a label wrapping a hidden input leaves the picker mouse-only',
	);
	for (const ref of ['zipFileInput', 'garminFileInput']) {
		assert.match(
			source,
			new RegExp(`onclick=\\{\\(\\) => ${ref}\\?\\.click\\(\\)\\}`),
			`${ref} must be driven from a button's onclick`,
		);
		assert.match(
			source,
			new RegExp(`bind:this=\\{${ref}\\}`),
			`${ref} must be bound to the file input`,
		);
	}
	assert.doesNotMatch(
		source,
		/<input\s+type="file"[^>]*hidden/,
		'the input stays off-screen via display:none, not the `hidden` attribute',
	);
});

test('the account restore picker keeps the same idiom', () => {
	// Reason: this is the surface the integrations fix was copied from —
	// if it regresses, the pattern has no reference implementation left.
	const source = read('src/routes/settings/account/+page.svelte');
	assert.match(source, /onclick=\{\(\) => restoreFileInput\.click\(\)\}/);
	assert.match(source, /bind:this=\{restoreFileInput\}/);
});
