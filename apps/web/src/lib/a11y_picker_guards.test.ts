// Guards for file pickers that must stay operable without a mouse.
//
// The idiom is a real <button> that forwards a click to an off-screen
// <input type="file">. The tempting shorthand — a <label> wrapping a
// `hidden` input — has no focusable element in it at all: the input is out
// of the tab order and a label is not a control, so the picker is
// mouse-only and invisible to a screen reader.
//
// The two named guards below came first, one surface at a time, and the
// shorthand kept reappearing anyway: after the integrations pair was fixed,
// two more sites still carried it — the club-event results CSV import and the
// route-import drop zone, whose own comment already claimed "keyboard users
// use the inner Browse button" while that button was a <label>. So the sweep
// is tree-wide now. A per-file guard only ever protects the file it names.
//
// Invocation:
//   npx tsx --test src/lib/a11y_picker_guards.test.ts

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';

const SRC_ROOT = resolve('src');

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('the bulk-import pickers drive their input from a real button', () => {
	const source = read('src/routes/settings/integrations/+page.svelte');
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
});

test('the account restore picker keeps the same idiom', () => {
	// Reason: this is the surface the integrations fix was copied from —
	// if it regresses, the pattern has no reference implementation left.
	const source = read('src/routes/settings/account/+page.svelte');
	assert.match(source, /onclick=\{\(\) => restoreFileInput\.click\(\)\}/);
	assert.match(source, /bind:this=\{restoreFileInput\}/);
});

// ── Tree-wide: no <label> may wrap a file input ─────────────────────────────
//
// Matched over the element, not a line, because the shorthand is written across
// five lines as often as one. Each <label> is bounded at its OWN closing tag
// before the block is searched — a single lazy regex over the whole file reads
// "some label ... some file input ... some later </label>" as one block and
// convicts a page that merely has both, which is what it did to the club-event
// page on this scan's first run.

function labelWrapsFileInput(source: string): boolean {
	const open = /<label\b/g;
	let hit: RegExpExecArray | null;
	while ((hit = open.exec(source))) {
		const close = source.indexOf('</label>', hit.index);
		if (close === -1) continue;
		if (/<input\b[^>]*type="file"/.test(source.slice(hit.index, close))) return true;
	}
	return false;
}

const SHAPE_FIXTURES: Array<[flagged: boolean, markup: string]> = [
	// The two this round removed, in their original spelling.
	[
		true,
		`<label class="browse-btn">\n\tBrowse files\n\t<input type="file" accept=".gpx" onchange={handleFileSelect} hidden />\n</label>`,
	],
	[
		true,
		`<label class="btn-link import-file">\n\t{name}\n\t<input\n\t\tbind:this={importInput}\n\t\ttype="file"\n\t\thidden\n\t/>\n</label>`,
	],
	// The one-line spelling of the same mistake.
	[true, `<label><input type="file" hidden /> Pick</label>`],
	// Spared: the accessible idiom — the input is a sibling of the button, not
	// a child of a label.
	[
		false,
		`<button type="button" onclick={() => input?.click()}>Pick</button>\n<input bind:this={input} type="file" style="display: none" />`,
	],
	// Spared: an ordinary labelled text field, and a file input that follows a
	// CLOSED label elsewhere on the page.
	[false, `<label><span>Route name</span><input type="text" bind:value={name} /></label>`],
	[
		false,
		`<label><span>Name</span><input type="text" /></label>\n<input type="file" style="display: none" />`,
	],
	// Spared: the shape that convicted the club-event page on the first run —
	// a labelled field, then, much later, an accessible picker.
	[
		false,
		`<label>Caption<input type="text" /></label>\n<button onclick={() => i?.click()}>Add</button>\n<input bind:this={i} type="file" hidden />\n<label>Note<input type="text" /></label>`,
	],
];

test('the label-wrapped-file-input scan flags the mouse-only shape and spares a labelled text field', () => {
	for (const [flagged, markup] of SHAPE_FIXTURES) {
		assert.equal(
			labelWrapsFileInput(markup),
			flagged,
			`the scan must ${flagged ? 'flag' : 'spare'} ${JSON.stringify(markup.slice(0, 60))}`,
		);
	}
});

const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

function svelteFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (SKIP_DIRS.has(entry)) continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) svelteFiles(full, out);
		else if (entry.endsWith('.svelte')) out.push(full);
	}
	return out;
}

test('no surface hides a file input inside a label', () => {
	const files = svelteFiles(SRC_ROOT);
	assert.ok(files.length > 150, `scanned only ${files.length} .svelte files`);
	const offenders: string[] = [];
	let withFileInput = 0;
	for (const file of files) {
		const source = readFileSync(file, 'utf-8');
		if (!source.includes('type="file"')) continue;
		withFileInput++;
		if (labelWrapsFileInput(source)) {
			offenders.push(relative(SRC_ROOT, file).split(sep).join('/'));
		}
	}
	// Assert the population: a scan that found no file inputs at all would
	// pass the check below while proving nothing.
	assert.ok(withFileInput >= 6, `only ${withFileInput} files carry a file input`);
	assert.deepEqual(
		offenders,
		[],
		`these surfaces wrap a file input in a <label>, which leaves the picker ` +
			`mouse-only: ${offenders.join(', ')}. Drive the input from a real <button>.`,
	);
});
