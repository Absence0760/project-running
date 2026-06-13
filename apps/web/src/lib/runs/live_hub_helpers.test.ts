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
	createReconnectingSocket,
	type SocketLike,
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

test('buildSubscribeUrl — appends ?token= when accessToken provided (audit/livehub C1)', () => {
	const url = buildSubscribeUrl('https://live.threkir.com', 'run-1', 'eyJ.fake.jwt');
	assert.equal(url, 'wss://live.threkir.com/v1/live/run-1/subscribe?token=eyJ.fake.jwt');
});

test('buildSubscribeUrl — URL-encodes the token (defence against JWT-containing-`+`)', () => {
	// Real Supabase JWTs contain `.` and `_` and rarely `+` (base64url
	// → no padding), but a future migration could break that. The URL
	// builder MUST encode whatever it's given so a fluky token byte
	// doesn't break the subscribe.
	const url = buildSubscribeUrl('https://x', 'r', 'a b+c');
	assert.equal(url, 'wss://x/v1/live/r/subscribe?token=a%20b%2Bc');
});

test('buildSubscribeUrl — null / undefined / empty token skips the querystring', () => {
	assert.equal(
		buildSubscribeUrl('https://x', 'r', null),
		'wss://x/v1/live/r/subscribe',
	);
	assert.equal(
		buildSubscribeUrl('https://x', 'r', undefined),
		'wss://x/v1/live/r/subscribe',
	);
	assert.equal(
		buildSubscribeUrl('https://x', 'r', ''),
		'wss://x/v1/live/r/subscribe',
	);
});

// A fake socket the reconnect loop can drive without a real WebSocket.
// Records the URL it was opened with so the test can assert which token
// each (re)connect authorized with.
class FakeSocket implements SocketLike {
	onopen: ((ev: unknown) => void) | null = null;
	onmessage: ((ev: { data: unknown }) => void) | null = null;
	onerror: ((ev: unknown) => void) | null = null;
	onclose: ((ev: unknown) => void) | null = null;
	closed = false;
	constructor(readonly url: string) {}
	close() {
		this.closed = true;
	}
}

test('createReconnectingSocket — reconnect re-reads the token (audit/livehub C1)', () => {
	const opened: FakeSocket[] = [];
	// Token rotates between the first connect and the reconnect — the
	// reconnect MUST authorize with the fresh value, not the captured one.
	const tokens = ['stale.jwt', 'fresh.jwt'];
	let tokenIdx = 0;
	const pendingTimers: Array<() => void> = [];

	const handle = createReconnectingSocket({
		baseUrl: 'https://live.threkir.com',
		runId: 'run-1',
		getToken: () => tokens[Math.min(tokenIdx, tokens.length - 1)],
		createSocket: (url) => {
			const s = new FakeSocket(url);
			opened.push(s);
			return s;
		},
		onPing: () => undefined,
		setTimer: (fn) => {
			pendingTimers.push(fn);
			return 0 as unknown as ReturnType<typeof setTimeout>;
		},
		clearTimer: () => undefined,
	});

	assert.equal(opened.length, 1);
	assert.equal(
		opened[0].url,
		'wss://live.threkir.com/v1/live/run-1/subscribe?token=stale.jwt',
	);

	// The server drops the connection (e.g. the stale token 403s); the
	// session has since refreshed, so the next connect should use it.
	tokenIdx = 1;
	opened[0].onclose?.(null);
	assert.equal(pendingTimers.length, 1, 'an unexpected close schedules a retry');
	pendingTimers[0]();

	assert.equal(opened.length, 2);
	assert.equal(
		opened[1].url,
		'wss://live.threkir.com/v1/live/run-1/subscribe?token=fresh.jwt',
		'the reconnect must rebuild the URL with the current token, not the captured one',
	);

	handle.close();
});

test('createReconnectingSocket — close() suppresses the reconnect loop', () => {
	const opened: FakeSocket[] = [];
	let scheduled = 0;
	const handle = createReconnectingSocket({
		baseUrl: 'https://x',
		runId: 'r',
		getToken: () => 't',
		createSocket: (url) => {
			const s = new FakeSocket(url);
			opened.push(s);
			return s;
		},
		onPing: () => undefined,
		setTimer: (fn) => {
			scheduled += 1;
			void fn;
			return 0 as unknown as ReturnType<typeof setTimeout>;
		},
		clearTimer: () => undefined,
	});

	handle.close();
	assert.equal(opened[0].closed, true);
	// A close that arrives after teardown must not schedule a retry.
	opened[0].onclose?.(null);
	assert.equal(scheduled, 0);
});
