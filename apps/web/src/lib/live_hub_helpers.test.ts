// Tests for the pure helpers backing the web live-hub client.
// `live_hub.ts` (which imports `$env/dynamic/public`) can't be
// imported under node:test — these helpers carry the testable
// behaviour: URL building + reconnect backoff math.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	trimTrailingSlash,
	buildSnapshotUrl,
	buildSubscribeUrl,
	nextBackoff,
} from './live_hub_helpers';

test('trimTrailingSlash — strips one trailing slash', () => {
	assert.equal(trimTrailingSlash('https://x.com'), 'https://x.com');
	assert.equal(trimTrailingSlash('https://x.com/'), 'https://x.com');
});

test('buildSnapshotUrl — points at /v1/live/{run_id}/snapshot', () => {
	const url = buildSnapshotUrl('https://live.threkir.com', 'run-1');
	assert.equal(url, 'https://live.threkir.com/v1/live/run-1/snapshot');
});

test('buildSnapshotUrl — URL-encodes the run id', () => {
	const url = buildSnapshotUrl('https://live.threkir.com', 'a b/c');
	assert.equal(url, 'https://live.threkir.com/v1/live/a%20b%2Fc/snapshot');
});

test('buildSubscribeUrl — flips https:// to wss://', () => {
	const url = buildSubscribeUrl('https://live.threkir.com', 'run-1');
	assert.equal(url, 'wss://live.threkir.com/v1/live/run-1/subscribe');
});

test('buildSubscribeUrl — flips http:// to ws://', () => {
	const url = buildSubscribeUrl('http://localhost:8080', 'run-1');
	assert.equal(url, 'ws://localhost:8080/v1/live/run-1/subscribe');
});

test('buildSubscribeUrl — strips a trailing slash on base', () => {
	const url = buildSubscribeUrl('https://live.threkir.com/', 'run-1');
	assert.equal(url, 'wss://live.threkir.com/v1/live/run-1/subscribe');
});

test('nextBackoff — doubles up to a 30s cap', () => {
	assert.equal(nextBackoff(500), 1000);
	assert.equal(nextBackoff(1000), 2000);
	assert.equal(nextBackoff(15_000), 30_000);
	assert.equal(nextBackoff(20_000), 30_000);
	assert.equal(nextBackoff(60_000), 30_000);
});
