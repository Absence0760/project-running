// Source-level guard on the realtime handlers whose trigger rate is set by
// ROW COUNT rather than by user activity.
//
// Postgres logical replication emits one change event per row, so a single
// statement that touches N rows reaches the browser as N separate handler
// calls. A handler that re-reads a whole collection per call therefore costs
// O(N) round trips and O(N^2) rows transferred for one server-side write —
// the organiser importing a mass-participation results sheet, or a runner
// clearing a few hundred unread notifications. Each of these handlers must
// coalesce a burst into one refetch (CoalescingRefetcher, live_refetch.ts),
// never fetch directly.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const LIVE_EVENT = readFileSync(
	resolve('src/routes/live/event/[id]/[instance]/+page.svelte'),
	'utf-8',
);

const NOTIFICATION_STORE = readFileSync(
	resolve('src/lib/stores/notifications.svelte.ts'),
	'utf-8',
);

/** The single `.on('postgres_changes', ...)` block naming `table`. */
function handlerFor(source: string, table: string): string {
	const start = source.indexOf('function subscribe()');
	assert.notEqual(start, -1, 'the page must build its subscriptions in subscribe()');
	const end = source.indexOf('.subscribe();', start);
	const blocks = source
		.slice(start, end)
		.split('.on(')
		.filter((b) => b.includes(`table: '${table}'`));
	assert.equal(blocks.length, 1, `expected exactly one subscription on ${table}`);
	return blocks[0];
}

test('live/event: the results subscription coalesces instead of refetching per row', () => {
	const handler = handlerFor(LIVE_EVENT, 'event_results');
	assert.match(
		handler,
		/resultsRefetcher\?\.trigger\(\)/,
		'the event_results handler must trigger the coalescing refetcher',
	);
	assert.doesNotMatch(
		handler,
		/await fetchEventResults\(/,
		'the event_results handler must not fetch the whole results set per changed row',
	);
	assert.doesNotMatch(
		handler,
		/await buildProfiles\(/,
		'the event_results handler must not rebuild every profile per changed row',
	);
});

test('live/event: the ping subscription coalesces too', () => {
	const handler = handlerFor(LIVE_EVENT, 'race_pings');
	assert.match(
		handler,
		/pingRefetcher\?\.trigger\(\)/,
		'the race_pings handler must trigger the coalescing refetcher',
	);
});

test('live/event: both refetchers are disposed on destroy', () => {
	const at = LIVE_EVENT.indexOf('onDestroy(');
	assert.notEqual(at, -1, 'the page must tear its subscriptions down');
	const teardown = LIVE_EVENT.slice(at, at + 400);
	assert.match(teardown, /pingRefetcher\?\.dispose\(\)/);
	assert.match(teardown, /resultsRefetcher\?\.dispose\(\)/);
});

/** The single `.on('postgres_changes', ...)` block for `event` in the store. */
function storeHandlerFor(event: 'INSERT' | 'UPDATE' | 'DELETE'): string {
	const start = NOTIFICATION_STORE.indexOf('subscribe(userId: string)');
	assert.notEqual(start, -1, 'the store must build its subscription in subscribe()');
	const end = NOTIFICATION_STORE.indexOf('.subscribe();', start);
	const blocks = NOTIFICATION_STORE.slice(start, end)
		.split('.on(')
		.filter((b) => b.includes(`event: '${event}'`));
	assert.equal(blocks.length, 1, `expected exactly one ${event} subscription`);
	return blocks[0];
}

test('notifications: read and dismiss events coalesce into one count query', () => {
	// "Mark all read" updates every unread row in one statement, and dismiss
	// deletes a whole page — so these two handlers are called once per ROW
	// cleared. Each used to run its own exact-count query.
	for (const event of ['UPDATE', 'DELETE'] as const) {
		const handler = storeHandlerFor(event);
		assert.match(
			handler,
			/#refetcher\.trigger\(\)/,
			`the ${event} handler must trigger the coalescing refetcher`,
		);
		assert.doesNotMatch(
			handler,
			/this\.refresh\(\)/,
			`the ${event} handler must not run a count query per changed row`,
		);
	}
});

test('notifications: an arriving notification still bumps the badge locally', () => {
	// The INSERT handler is per-notification by nature, and costs nothing —
	// coalescing it would only delay the badge.
	const handler = storeHandlerFor('INSERT');
	assert.match(handler, /this\.unreadCount \+= 1/);
	assert.doesNotMatch(handler, /#refetcher/);
});

test('notifications: tearing the channel down cancels any scheduled refetch', () => {
	const at = NOTIFICATION_STORE.indexOf('unsubscribe() {');
	assert.notEqual(at, -1);
	assert.match(
		NOTIFICATION_STORE.slice(at, at + 300),
		/#refetcher\.dispose\(\)/,
		'unsubscribe must dispose the refetcher so a pending timer cannot outlive the channel',
	);
});
