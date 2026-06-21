import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Source-level guard: every NotificationKind has a verbFor + linkFor case in
// BOTH the bell popover and the inbox list. The bug this pins: the DB CHECK
// allows kinds (event_reminder, achievement, challenge_complete, content_hidden)
// that the two switch statements never handled, so verbFor() fell through and
// returned undefined — a blank, dead notification row that still counted toward
// the unread badge. A new kind added to the type/CHECK must get rendered.
//
// The components use Svelte $state runes so they can't run under raw tsx — this
// reads the source instead of executing it.

const here = dirname(fileURLToPath(import.meta.url));
const read = (p: string) => readFileSync(resolve(here, p), 'utf8');

const types = read('../types.ts');
const bell = read('./NotificationBell.svelte');
const list = read('./NotificationsList.svelte');

function notificationKinds(): string[] {
	// Parse the union members from `export type NotificationKind = | 'a' | 'b' ...`
	const start = types.indexOf('export type NotificationKind');
	assert.ok(start >= 0, 'NotificationKind union not found in types.ts');
	const decl = types.slice(start, types.indexOf(';', start));
	const kinds = Array.from(decl.matchAll(/'([a-z_]+)'/g)).map((m) => m[1]);
	assert.ok(kinds.length >= 14, `expected the full kind union, got ${kinds.length}`);
	return kinds;
}

const KINDS = notificationKinds();

for (const [name, src] of [
	['NotificationBell', bell],
	['NotificationsList', list],
] as const) {
	test(`${name}.verbFor handles every NotificationKind (no blank rows)`, () => {
		const start = src.indexOf('function verbFor');
		assert.ok(start >= 0, `${name} has no verbFor`);
		const body = src.slice(start, src.indexOf('\n\tfunction ', start + 1));
		for (const kind of KINDS) {
			assert.match(
				body,
				new RegExp(`case '${kind}':`),
				`${name}.verbFor must have a case for '${kind}' — an unhandled kind renders a blank notification`,
			);
		}
	});

	test(`${name}.linkFor handles every NotificationKind (no dead clicks)`, () => {
		const start = src.indexOf('function linkFor');
		assert.ok(start >= 0, `${name} has no linkFor`);
		const body = src.slice(start, src.indexOf('\n\tfunction ', start + 1));
		for (const kind of KINDS) {
			assert.match(
				body,
				new RegExp(`case '${kind}':`),
				`${name}.linkFor must have a case for '${kind}'`,
			);
		}
		// A default arm keeps a future kind from falling through to undefined.
		assert.match(body, /default:/, `${name}.linkFor must have a default arm`);
	});
}
