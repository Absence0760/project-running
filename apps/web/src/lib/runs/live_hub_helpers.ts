/// Pure helpers extracted from `live_hub.ts` so they're testable
/// without the SvelteKit `$env/dynamic/public` import. The wire
/// shape mirrors `apps/job_worker/internal/livehub/types.go` — keep
/// them in lockstep when extending.

export interface LivePing {
	lat: number;
	lng: number;
	distance_m?: number | null;
	elapsed_s?: number | null;
	bpm?: number | null;
	ele?: number | null;
	sent_at_ms?: number;
	/// True for the single privacy-zone last-seen ping: a ~1 km-coarsened
	/// in-zone fix the DB trigger keeps for SAR (migration 20270121_001).
	/// The spectator surface must render it as approximate, never as a
	/// precise current position.
	coarse?: boolean | null;
}

/// Strip a trailing slash from a base URL so concatenated paths
/// don't double up.
export function trimTrailingSlash(s: string): string {
	return s.endsWith('/') ? s.slice(0, -1) : s;
}

/// Build the snapshot endpoint URL for [runId] against [baseUrl].
export function buildSnapshotUrl(baseUrl: string, runId: string): string {
	return `${trimTrailingSlash(baseUrl)}/v1/live/${encodeURIComponent(runId)}/snapshot`;
}

/// Build the WebSocket subscription URL for [runId] against [baseUrl].
/// Flips `http(s)://` to `ws(s)://` per the WebSocket scheme rule.
/// When [accessToken] is provided, it is appended as `?token=<jwt>`
/// so the Go authorizer can read it via querystring fallback — the
/// browser WebSocket API can't set headers on the upgrade. Mobile +
/// server-to-server callers use the Authorization header instead.
/// /audit/livehub May 2026 C1.
export function buildSubscribeUrl(
	baseUrl: string,
	runId: string,
	accessToken?: string | null,
): string {
	const trimmed = trimTrailingSlash(baseUrl);
	const wsBase = trimmed.replace(/^http(s?):\/\//, 'ws$1://');
	const base = `${wsBase}/v1/live/${encodeURIComponent(runId)}/subscribe`;
	if (accessToken && accessToken.length > 0) {
		return `${base}?token=${encodeURIComponent(accessToken)}`;
	}
	return base;
}

/// Compute the next reconnect-backoff delay. Caps at 30 s so a
/// flaky bridge or a brief Fly.io restart doesn't blast the hub
/// with reconnect attempts. Pure so the loop math is unit-testable.
export function nextBackoff(prevMs: number): number {
	return Math.min(prevMs * 2, 30_000);
}

export type LiveHubStatus = 'connecting' | 'open' | 'closed';

/// Minimal WebSocket surface the reconnect loop drives. Lets the loop
/// be unit-tested with a fake socket — the real `WebSocket` global
/// satisfies it structurally.
export interface SocketLike {
	onopen: ((ev: Event) => void) | null;
	onmessage: ((ev: MessageEvent) => void) | null;
	onerror: ((ev: Event) => void) | null;
	onclose: ((ev: CloseEvent) => void) | null;
	close(): void;
}

export interface ReconnectingSocketOpts {
	baseUrl: string;
	runId: string;
	/// Re-read on EVERY (re)connect so a reconnect after the access
	/// token has rotated authorizes with the current JWT, not the one
	/// captured when the page first loaded. A static string would 403
	/// on a private run after the original token expires (~1 h) and
	/// then spin in the backoff loop forever. /audit/livehub May 2026 C1.
	getToken: () => string | null | undefined;
	/// Builds the platform socket. Injected so the loop is testable
	/// without a real `WebSocket`; production passes
	/// `(url) => new WebSocket(url)`.
	createSocket: (url: string) => SocketLike;
	onPing: (p: LivePing) => void;
	onStatus?: (s: LiveHubStatus) => void;
	setTimer?: (fn: () => void, ms: number) => ReturnType<typeof setTimeout>;
	clearTimer?: (h: ReturnType<typeof setTimeout>) => void;
}

/// Open a self-reconnecting WebSocket subscription with exponential
/// backoff. The auth token is re-read from `getToken` on each connect
/// — including reconnects — so a long-lived spectator tab recovers
/// after the original JWT expires instead of looping on a stale 403.
/// Returns a `close()` that tears down the socket and suppresses the
/// reconnect loop. Env-free + injectable so the loop is unit-testable.
export function createReconnectingSocket(opts: ReconnectingSocketOpts): { close: () => void } {
	const setTimer = opts.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
	const clearTimer = opts.clearTimer ?? ((h) => clearTimeout(h));

	let closed = false;
	let ws: SocketLike | null = null;
	let retryMs = 500;
	let retryTimer: ReturnType<typeof setTimeout> | null = null;

	function emitStatus(s: LiveHubStatus) {
		try {
			opts.onStatus?.(s);
		} catch {
			// Status callbacks are advisory — don't let a buggy handler
			// take down the connection.
		}
	}

	function connect() {
		if (closed) return;
		emitStatus('connecting');
		const url = buildSubscribeUrl(opts.baseUrl, opts.runId, opts.getToken());
		try {
			ws = opts.createSocket(url);
		} catch {
			scheduleRetry();
			return;
		}
		ws.onopen = () => {
			retryMs = 500; // reset backoff on a clean open
			emitStatus('open');
		};
		ws.onmessage = (ev) => {
			try {
				const p = JSON.parse(ev.data as string) as LivePing;
				opts.onPing(p);
			} catch {
				// Drop malformed frames — server sends JSON only, but
				// be defensive: a corrupt frame must not kill the loop.
			}
		};
		ws.onerror = () => {
			// `onclose` fires next; defer the reconnect there so we
			// don't double-schedule.
		};
		ws.onclose = () => {
			emitStatus('closed');
			ws = null;
			if (!closed) scheduleRetry();
		};
	}

	function scheduleRetry() {
		if (closed) return;
		retryTimer = setTimer(() => {
			retryTimer = null;
			retryMs = nextBackoff(retryMs);
			connect();
		}, retryMs);
	}

	connect();

	return {
		close: () => {
			closed = true;
			if (retryTimer) {
				clearTimer(retryTimer);
				retryTimer = null;
			}
			if (ws) {
				try {
					ws.close();
				} catch {
					// best-effort
				}
				ws = null;
			}
		},
	};
}
