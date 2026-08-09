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
