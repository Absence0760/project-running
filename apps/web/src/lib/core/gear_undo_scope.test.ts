import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * The one adopter of the deferred-undo queue must not restore into a list
 * that has moved on (decisions § 984).
 *
 * `createUndoQueue` holds the mutation for the undo window and calls
 * `restore` on undo OR on a commit that later fails. Undo is immediate and
 * safe. The COMMIT can land much later — by which time the runner may have
 * closed the gear modal the snapshot came from and opened another pair's —
 * and a `restore` written as a bare re-assignment then paints gear X's
 * observations into gear Y's open modal.
 *
 * The queue's own contract is unchanged and owes its Dart twin nothing: this
 * is entirely a property of the CALL SITE, which is what the guard scans. The
 * page is a `.svelte` file and cannot be executed under `tsx --test`, so the
 * coverage is source-level — the same shape `strava_zip_strictness.test.ts`
 * uses for its own unexecutable module.
 */

const __dirname = dirname(fileURLToPath(import.meta.url));
const PAGE = resolve(__dirname, '../../routes/settings/gear/+page.svelte');

function stripComments(s: string): string {
	// Reason: line comments are blanked BEFORE block comments are stripped. A
	// `//` containing `/*` is prose to the language but an opening delimiter to
	// the regex, so the other order swallows every line up to the next `*/`
	// (decisions § 971).
	return s
		.split('\n')
		.map((l) => (/^\s*\/\//.test(l) ? '' : l.replace(/\s\/\/.*$/, '')))
		.join('\n')
		.replace(/\/\*[\s\S]*?\*\//g, ' ');
}

function page(): string {
	return stripComments(readFileSync(PAGE, 'utf-8'));
}

function removeWearLogBody(s: string): string {
	const from = s.indexOf('function removeWearLog(');
	assert.notEqual(from, -1, 'removeWearLog not found — did it move?');
	const to = s.indexOf('\n\tlet rotations', from);
	assert.notEqual(to, -1, 'removeWearLog no longer ends where this guard expects');
	return s.slice(from, to);
}

test('the deferred restore refuses when the list it snapshotted is gone', () => {
	const body = removeWearLogBody(page());
	assert.match(body, /restore:\s*\(\)\s*=>\s*\{/, 'the restore callback must still exist');
	const restore = body.slice(body.indexOf('restore:'));
	assert.match(
		restore,
		/if \(wearLogsEpoch !== epoch\) return;/,
		'a restore arriving after the list was replaced must be a no-op — otherwise a ' +
			'commit that fails minutes later repaints one pair\'s observations into ' +
			"whichever pair's modal is open by then",
	);
	// The epoch has to be read BEFORE the queue is handed the callback, or it
	// closes over a live value and always compares equal to itself.
	const deferAt = body.indexOf('deferDestructive(');
	const captureAt = body.indexOf('const epoch = wearLogsEpoch;');
	assert.notEqual(captureAt, -1, 'the epoch must be captured, not read at restore time');
	assert.ok(captureAt < deferAt, 'the epoch must be captured before the destruction is deferred');
});

test('every wear-log write bumps the epoch the restore checks', () => {
	// The guard above is only worth anything if the epoch actually moves. A
	// new assignment written in the obvious shape would compile, run, look
	// right, and silently make the check vacuous for that path.
	const s = page();
	const writes = [...s.matchAll(/\bwearLogs\s*=\s*/g)].map((m) => m.index ?? 0);
	const declaration = s.indexOf('wearLogs = $state');
	const inSetter = s.indexOf('wearLogs = next;');
	assert.notEqual(declaration, -1, 'the wearLogs state declaration not found');
	assert.notEqual(inSetter, -1, 'setWearLogs no longer assigns the list');
	const stray = writes.filter((i) => i !== declaration && i !== inSetter);
	assert.deepEqual(
		stray.map((i) => s.slice(i, s.indexOf('\n', i)).trim()),
		[],
		'every replacement of wearLogs must go through setWearLogs so the epoch moves with it',
	);
	assert.match(
		s,
		/function setWearLogs\([\s\S]{0,120}?wearLogsEpoch \+= 1;/,
		'setWearLogs must bump the epoch',
	);
});
