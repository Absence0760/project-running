import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Source-level guard: every NotificationKind has a verbFor case in BOTH the
// bell popover and the inbox list. The bug this pins: the DB CHECK allows kinds
// (event_reminder, achievement, challenge_complete, content_hidden) that the
// switch statements never handled, so verbFor() fell through and returned
// undefined — a blank, dead notification row that still counted toward the
// unread badge. A new kind added to the type/CHECK must get rendered.
//
// linkFor lives once in $lib/social/notification_link and is executed directly
// by notification_link.test.ts, so its per-kind coverage is asserted there;
// this file's linkFor guard just checks that shared helper still handles every
// kind + keeps a default arm.
//
// The components use Svelte $state runes so they can't run under raw tsx — this
// reads the source instead of executing it. verbFor stays per-component because
// its message keys are namespaced (notificationBell.* vs notificationsList.*).

const here = dirname(fileURLToPath(import.meta.url));
const read = (p: string) => readFileSync(resolve(here, p), 'utf8');

const types = read('../types.ts');
const bell = read('./NotificationBell.svelte');
const list = read('./NotificationsList.svelte');
const linkHelper = read('../social/notification_link.ts');

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
}

test('notificationLinkFor handles every NotificationKind (no dead clicks)', () => {
	const start = linkHelper.indexOf('function notificationLinkFor');
	assert.ok(start >= 0, 'notification_link.ts has no notificationLinkFor');
	const body = linkHelper.slice(start);
	for (const kind of KINDS) {
		assert.match(
			body,
			new RegExp(`case '${kind}':`),
			`notificationLinkFor must have a case for '${kind}'`,
		);
	}
	// A default arm keeps a future kind from falling through to undefined.
	assert.match(body, /default:/, 'notificationLinkFor must have a default arm');
});
