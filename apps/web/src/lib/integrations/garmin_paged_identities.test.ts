// Paged identity collection for the cross-provider dedupe guard. Pre-fix the
// guard did a bare `.select().eq('user_id', uid)` which PostgREST silently
// caps at 1000 rows — so a pro with 1000+ runs compared against an arbitrary
// slice and re-imported duplicates anyway. `collectRunIdentities` pages the
// read the same way `fetchRuns` does. These pin the paging + stop conditions.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	collectRunIdentities,
	RUN_IDENTITY_PAGE_SIZE,
	type RawRunRow,
} from './garmin_dedupe';

/// A fake paged source of `count` runs, one second apart, so we can assert the
/// loop pulls EVERY page (not just the first PostgREST cap) and records each
/// call's [from, to] range.
function pagedSource(count: number, pageSize: number) {
	const rows: RawRunRow[] = Array.from({ length: count }, (_, i) => ({
		started_at: new Date(Date.UTC(2026, 0, 1, 0, 0, i)).toISOString(),
		distance_m: 5000 + i,
	}));
	const calls: Array<[number, number]> = [];
	const fetchPage = async (from: number, to: number): Promise<RawRunRow[] | null> => {
		calls.push([from, to]);
		return rows.slice(from, Math.min(to + 1, count));
	};
	return { fetchPage, calls };
}

test('collectRunIdentities — a single sub-page fetch stops after one call', async () => {
	const { fetchPage, calls } = pagedSource(10, 1000);
	const ids = await collectRunIdentities(fetchPage);
	assert.equal(ids.length, 10);
	assert.equal(calls.length, 1);
	assert.deepEqual(calls[0], [0, 999]);
});

test('collectRunIdentities — 1200 runs are ALL collected across two pages (not capped at 1000)', async () => {
	const { fetchPage, calls } = pagedSource(1200, 1000);
	const ids = await collectRunIdentities(fetchPage);
	assert.equal(ids.length, 1200, 'every run must be compared, not just the first 1000');
	assert.equal(calls.length, 2);
	assert.deepEqual(calls[0], [0, 999]);
	assert.deepEqual(calls[1], [1000, 1999]);
});

test('collectRunIdentities — an exact full page is followed by one more (empty) page', async () => {
	const { fetchPage, calls } = pagedSource(1000, 1000);
	const ids = await collectRunIdentities(fetchPage);
	assert.equal(ids.length, 1000);
	// A full 1000-row page can't distinguish "exactly 1000" from "more to
	// come", so the loop fetches once more and gets an empty page.
	assert.equal(calls.length, 2);
});

test('collectRunIdentities — a page error stops the loop without throwing', async () => {
	let call = 0;
	const ids = await collectRunIdentities(async () => {
		call++;
		return call === 1 ? [{ started_at: '2026-01-01T09:00:00Z', distance_m: 5000 }] : null;
	}, 1);
	// pageSize 1 → first page returns 1 row (== pageSize, keep going), second
	// page errors (null) → stop. Exactly one identity collected.
	assert.equal(ids.length, 1);
});

test('collectRunIdentities — non-finite start times are dropped', async () => {
	const ids = await collectRunIdentities(async () => [
		{ started_at: 'not-a-date', distance_m: 5000 },
		{ started_at: null, distance_m: 5000 },
		{ started_at: '2026-01-01T09:00:00Z', distance_m: 5000 },
	]);
	assert.equal(ids.length, 1);
	assert.equal(ids[0].distanceM, 5000);
});

test('RUN_IDENTITY_PAGE_SIZE matches PostgREST cap', () => {
	assert.equal(RUN_IDENTITY_PAGE_SIZE, 1000);
});
