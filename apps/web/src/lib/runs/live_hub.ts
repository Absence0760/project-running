/// Web client for the Go live-hub. When the deploy sets
/// `PUBLIC_LIVE_HUB_URL` (e.g. `https://live.threkir.com`), the
/// spectator page swaps from the legacy Supabase Realtime channel to
/// this WebSocket-streamed source.
///
/// Two helpers:
///   - `fetchLiveSnapshot(runId)` → the room's last-known ping (or
///     null when no pings yet). Used for the late-joiner "show me
///     the runner immediately" path.
///   - `openLiveWebSocket(runId, onPing, onStatus)` → opens a WS
///     subscription. Returns a `close()` function the caller invokes
///     on unmount. Reconnects with exponential backoff on
///     unexpected closes.
///
/// Gated on `PUBLIC_LIVE_HUB_URL` being set — caller checks
/// `isLiveHubConfigured()` first and falls back to the Supabase
/// Realtime path when false.
///
/// Wire shape mirrors `apps/job_worker/internal/livehub/types.go` —
/// keep them in lockstep when extending. Pure helpers (URL building,
/// reconnect-delay math) live in `./live_hub_helpers.ts` so they're
/// testable without the SvelteKit `$env` import.

import { env } from '$env/dynamic/public';
import {
	type LivePing,
	buildSnapshotUrl,
	buildSubscribeUrl,
} from './live_hub_helpers';

export type { LivePing } from './live_hub_helpers';

const PUBLIC_LIVE_HUB_URL = env.PUBLIC_LIVE_HUB_URL ?? '';

export type LiveHubStatus = 'connecting' | 'open' | 'closed';

export function isLiveHubConfigured(): boolean {
	return PUBLIC_LIVE_HUB_URL !== '';
}

/// One-shot fetch of the room's last-known ping. Returns `null` on
/// 204 (room empty / no pings yet) or any non-2xx response. Errors
/// are swallowed — the spectator page falls back to the demo
/// animation if no signal arrives within its 5 s window.
///
/// [accessToken] (the caller's Supabase JWT) is required when the Go
/// authorizer is enabled in prod and the underlying run is private —
/// the hub returns 403 on private runs without a Bearer. Public
/// runs work either way. /audit/livehub May 2026 C1.
export async function fetchLiveSnapshot(
	runId: string,
	accessToken?: string | null,
): Promise<LivePing | null> {
	if (!isLiveHubConfigured()) return null;
	const url = buildSnapshotUrl(PUBLIC_LIVE_HUB_URL, runId);
	try {
		const headers: Record<string, string> = {};
		if (accessToken && accessToken.length > 0) {
			headers['Authorization'] = `Bearer ${accessToken}`;
		}
		const res = await fetch(url, { headers });
		if (res.status === 204) return null;
		if (!res.ok) return null;
		return (await res.json()) as LivePing;
	} catch {
		return null;
	}
}

interface OpenOpts {
	onPing: (p: LivePing) => void;
	onStatus?: (s: LiveHubStatus) => void;
	/// Caller's Supabase JWT, appended to the WS URL as `?token=...`
	/// so the Go authorizer can verify it on the upgrade request.
	/// Browser WebSocket can't set Authorization headers — the
	/// querystring fallback is the only available channel.
	/// /audit/livehub May 2026 C1.
	accessToken?: string | null;
}

/// Open a WebSocket subscription to `/v1/live/{run_id}/subscribe`.
/// The returned `close()` function tears the connection down and
/// suppresses the reconnect loop.
export function openLiveWebSocket(runId: string, opts: OpenOpts): { close: () => void } {
	if (!isLiveHubConfigured()) {
		// Caller is expected to gate on `isLiveHubConfigured()` first,
		// but be defensive: return a no-op closer so misuse doesn't
		// throw.
		return { close: () => undefined };
	}
	const url = buildSubscribeUrl(PUBLIC_LIVE_HUB_URL, runId, opts.accessToken);

	let closed = false;
	let ws: WebSocket | null = null;
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
		try {
			ws = new WebSocket(url);
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
		retryTimer = setTimeout(() => {
			retryTimer = null;
			// Exponential backoff, capped at 30 s. A flaky bridge or a
			// brief Fly.io restart shouldn't blast the hub with reconnects.
			retryMs = Math.min(retryMs * 2, 30_000);
			connect();
		}, retryMs);
	}

	connect();

	return {
		close: () => {
			closed = true;
			if (retryTimer) {
				clearTimeout(retryTimer);
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
