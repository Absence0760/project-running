import { test } from 'node:test';
import assert from 'node:assert/strict';

import { isLiveBroadcast } from './live_broadcast';

test('a live stub (0 duration, never concluded) reads as live', () => {
	assert.equal(isLiveBroadcast({ duration_s: 0, concluded_at: null }), true);
});

test('a finished run is never live', () => {
	assert.equal(isLiveBroadcast({ duration_s: 3600, concluded_at: null }), false);
});

test('concluded_at wins over a stale zero duration', () => {
	// The recorder stamps concluded_at after the final save; if that save
	// somehow left duration at 0, the run is still over.
	assert.equal(
		isLiveBroadcast({ duration_s: 0, concluded_at: '2026-08-05T10:00:00Z' }),
		false,
	);
	assert.equal(
		isLiveBroadcast({ duration_s: 3600, concluded_at: '2026-08-05T10:00:00Z' }),
		false,
	);
});

test('missing row / missing duration degrade to not-live (fail closed)', () => {
	assert.equal(isLiveBroadcast(null), false);
	assert.equal(isLiveBroadcast(undefined), false);
	assert.equal(isLiveBroadcast({}), false);
	assert.equal(isLiveBroadcast({ duration_s: null, concluded_at: null }), false);
});

test('an empty-string concluded_at is treated as absent, not concluded', () => {
	assert.equal(isLiveBroadcast({ duration_s: 0, concluded_at: '' }), true);
});

test('a negative duration cannot pass as a finished run', () => {
	assert.equal(isLiveBroadcast({ duration_s: -1, concluded_at: null }), true);
});
