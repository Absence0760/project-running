import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Source-level guard: the notifications bell badge stays LIVE after a
// "mark all read". The bug this pins: both mark-all handlers used to call
// notificationStore.clear(), which tears down the Realtime channel as part
// of the logout-only teardown. After marking all read the subscription was
// dead, so newly-arriving kudos/comments/follows no longer bumped the badge
// until a full reload. The fix split the responsibilities: markAllRead()
// zeroes the count WITHOUT unsubscribing; clear() (logout) still unsubscribes.
//
// The store uses Svelte $state runes, so it can't run under raw tsx — these
// assertions read the source instead of executing it.

const here = dirname(fileURLToPath(import.meta.url));
const read = (p: string) => readFileSync(resolve(here, p), 'utf8');

const store = read('./notifications.svelte.ts');
const bell = read('../components/NotificationBell.svelte');
const list = read('../components/NotificationsList.svelte');

test('store keeps markAllRead (no-unsubscribe) distinct from clear (logout teardown)', () => {
	assert.match(
		store,
		/markAllRead\s*\(\s*\)\s*\{[^}]*unreadCount\s*=\s*0/,
		'markAllRead() must zero the unread count',
	);
	// clear() must still tear the channel down (logout path).
	assert.match(
		store,
		/clear\s*\(\s*\)\s*\{[^}]*unsubscribe\(\)/,
		'clear() must still unsubscribe — it is the logout teardown',
	);
	// markAllRead() must NOT unsubscribe. Bound the slice to the next method's
	// doc-comment marker (not the first `}`) so a future nested-brace refactor
	// of markAllRead can't shrink the window and hide a buried unsubscribe().
	const afterMarkAll = store.slice(store.indexOf('markAllRead('));
	const nextMethod = afterMarkAll.indexOf('///', 1);
	const markAllBody = afterMarkAll.slice(0, nextMethod > 0 ? nextMethod : afterMarkAll.length);
	assert.doesNotMatch(
		markAllBody,
		/unsubscribe\(\)/,
		'markAllRead() must NOT unsubscribe — that kills live updates after mark-all',
	);
});

for (const [name, src] of [
	['NotificationBell', bell],
	['NotificationsList', list],
] as const) {
	test(`${name} mark-all uses markAllRead, never clear (which would drop the subscription)`, () => {
		const handler = src.slice(src.indexOf('handleMarkAll'));
		const body = handler.slice(0, handler.indexOf('linkFor') > 0 ? handler.indexOf('linkFor') : 600);
		assert.match(
			body,
			/notificationStore\.markAllRead\(\)/,
			`${name}.handleMarkAll must call notificationStore.markAllRead()`,
		);
		assert.doesNotMatch(
			body,
			/notificationStore\.clear\(\)/,
			`${name}.handleMarkAll must NOT call notificationStore.clear() — clear() unsubscribes the Realtime channel, killing live badge updates for the rest of the session`,
		);
	});
}
