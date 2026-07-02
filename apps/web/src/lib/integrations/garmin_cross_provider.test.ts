// Cross-provider near-duplicate guard for the Garmin importer. Pre-fix the
// Garmin ZIP importer only deduped against source='garmin' rows, so the same
// activity already present under another source (a Garmin watch auto-uploaded
// to Strava) re-imported as a duplicate.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	CROSS_PROVIDER_DISTANCE_FRACTION,
	CROSS_PROVIDER_START_TOLERANCE_S,
	isCrossProviderDuplicate,
	type RunIdentity,
} from './garmin_dedupe';

const ms = (iso: string) => Date.parse(iso);

test('isCrossProviderDuplicate — exact same start + distance matches', () => {
	const existing: RunIdentity[] = [{ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }];
	assert.equal(
		isCrossProviderDuplicate({ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }, existing),
		true,
	);
});

test('isCrossProviderDuplicate — same effort across providers (start + distance drift) matches', () => {
	// Strava row from an auto-upload; the Garmin ZIP re-import stamps a
	// slightly different start + total distance.
	const existing: RunIdentity[] = [{ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }];
	assert.equal(
		isCrossProviderDuplicate({ startedAtMs: ms('2026-01-01T09:02:00Z'), distanceM: 10300 }, existing),
		true,
	);
});

test('isCrossProviderDuplicate — start beyond tolerance is a distinct run', () => {
	const existing: RunIdentity[] = [{ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }];
	assert.equal(
		isCrossProviderDuplicate({ startedAtMs: ms('2026-01-01T09:05:00Z'), distanceM: 10000 }, existing),
		false,
	);
});

test('isCrossProviderDuplicate — distance beyond fraction is a distinct run', () => {
	const existing: RunIdentity[] = [{ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }];
	assert.equal(
		isCrossProviderDuplicate({ startedAtMs: ms('2026-01-01T09:00:20Z'), distanceM: 12000 }, existing),
		false,
	);
});

test('isCrossProviderDuplicate — empty history + non-finite start never matches', () => {
	assert.equal(
		isCrossProviderDuplicate({ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 }, []),
		false,
	);
	assert.equal(
		isCrossProviderDuplicate({ startedAtMs: NaN, distanceM: 10000 }, [
			{ startedAtMs: ms('2026-01-01T09:00:00Z'), distanceM: 10000 },
		]),
		false,
	);
});

test('cross-provider tolerances match the Deno twin', () => {
	assert.equal(CROSS_PROVIDER_START_TOLERANCE_S, 180);
	assert.equal(CROSS_PROVIDER_DISTANCE_FRACTION, 0.05);
});
