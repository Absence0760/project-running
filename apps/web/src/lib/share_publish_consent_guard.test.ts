// Source-level guard: a "Copy share link" that PUBLISHES must ask first.
//
// Three detail pages mint a public share link, and on all three the link
// only resolves once the row is public — so copying one flips
// `is_public`. Run detail always asked (its ConfirmDialog also warns
// about start/end points); the gym-workout and session-plan pages copied
// the flow but dropped the dialog, each citing the other in a comment as
// precedent. The result was a button labelled "Copy share link" that
// published a private training log world-readable, with a green "Link
// copied" as its only feedback.
//
// The invariant these pin: the button's handler must NOT be the function
// that writes `is_public`; it must be a gate that opens a ConfirmDialog
// for a private row, and the write must live behind that dialog's
// `onconfirm`.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

const PAGES: { path: string; setter: string; state: string }[] = [
	{
		path: 'src/routes/gym/[id]/+page.svelte',
		setter: 'setGymWorkoutPublic',
		state: 'confirmingShare',
	},
	{
		path: 'src/routes/sessions/[id]/+page.svelte',
		setter: 'setSessionPlanPublic',
		state: 'confirmShare',
	},
];

for (const { path, setter, state } of PAGES) {
	test(`${path} confirms before a share link publishes the row`, () => {
		const source = read(path);

		const gate = source.match(/function startShare\(\)[\s\S]*?\n\t\}/);
		assert.ok(gate, `${path} must gate sharing behind startShare()`);
		assert.match(
			gate![0],
			new RegExp(`${state} = true`),
			'a private row must open the confirm dialog, not publish',
		);
		assert.doesNotMatch(
			gate![0],
			new RegExp(`await\\s+${setter}`),
			'the gate must not write is_public itself',
		);

		// The button the user clicks is the gate, never the writer.
		assert.match(source, /onclick=\{startShare\}/, 'the share button must call the gate');
		assert.doesNotMatch(
			source,
			/onclick=\{proceedShare\}/,
			'proceedShare is reachable only through the dialog',
		);

		// And the dialog is what runs the write.
		assert.match(
			source,
			new RegExp(`open=\\{${state}\\}[\\s\\S]*?onconfirm=\\{proceedShare\\}`),
			'the publish must sit behind the ConfirmDialog onconfirm',
		);
	});
}

test('the share-consent copy is localized in all six catalogues', () => {
	const keys = [
		'gym.shareConfirm.title',
		'gym.shareConfirm.body',
		'gym.shareConfirm.action',
		'session.shareConfirm.title',
		'session.shareConfirm.body',
		'session.shareConfirm.action',
	];
	for (const locale of ['en', 'de', 'es', 'fr', 'ja', 'pt-BR']) {
		const source = read(`src/lib/i18n/locales/${locale}.ts`);
		for (const key of keys) {
			assert.ok(source.includes(`"${key}":`), `${key} missing from ${locale}.ts`);
		}
	}
});

test('run detail keeps the share confirm the other two copied', () => {
	// Reason: this is the page the other two were modelled on. If its
	// dialog is ever dropped, the pattern loses its reference
	// implementation and the drift starts again.
	const source = read('src/routes/runs/[id]/+page.svelte');
	assert.match(
		source,
		/open=\{showShareConfirm\}[\s\S]*?onconfirm=\{proceedShare\}/,
		'run detail must keep publishing behind its ConfirmDialog',
	);
});
