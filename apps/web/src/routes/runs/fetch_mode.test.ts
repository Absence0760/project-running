import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { runsFetchMode, PAGINATED_SORT_KEY, type RunsFetchModeInput } from './fetch_mode';

const browse: RunsFetchModeInput = {
	effectiveDateRange: 'all',
	sourceFilter: 'all',
	activityFilter: 'all',
	sortKey: 'newest',
};

test('the unnarrowed, unreordered browse view paginates', () => {
	assert.equal(runsFetchMode(browse), 'paginated');
});

test('any narrowing forces a full fetch', () => {
	assert.equal(runsFetchMode({ ...browse, effectiveDateRange: 'week' }), 'full');
	assert.equal(runsFetchMode({ ...browse, sourceFilter: 'strava' }), 'full');
	assert.equal(runsFetchMode({ ...browse, activityFilter: 'cycle' }), 'full');
});

// The regression this file exists for: `fetchRuns` pages by `started_at`
// descending, so a client-side re-sort over a paginated window ranks only the
// rows already in memory. "All time · Longest" reported the longest of the
// newest 50 runs and hid a marathon from two years ago; "Oldest" showed a run
// from last month. Every key that disagrees with the server's order must
// pull the whole history first.
for (const sortKey of ['oldest', 'longest', 'fastest']) {
	test(`sorting by ${sortKey} forces a full fetch even with no filter`, () => {
		assert.equal(runsFetchMode({ ...browse, sortKey }), 'full');
	});
}

test('only the server-order sort key may paginate', () => {
	assert.equal(PAGINATED_SORT_KEY, 'newest');
	assert.equal(runsFetchMode({ ...browse, sortKey: PAGINATED_SORT_KEY }), 'paginated');
});

test('a narrowed view stays full even on the server-order sort key', () => {
	assert.equal(
		runsFetchMode({ ...browse, sourceFilter: 'strava', sortKey: 'newest' }),
		'full',
	);
});

test('an unknown sort key fails closed to the full fetch', () => {
	assert.equal(runsFetchMode({ ...browse, sortKey: '' }), 'full');
});
