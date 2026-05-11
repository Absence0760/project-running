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
export function buildSubscribeUrl(baseUrl: string, runId: string): string {
	const trimmed = trimTrailingSlash(baseUrl);
	const wsBase = trimmed.replace(/^http(s?):\/\//, 'ws$1://');
	return `${wsBase}/v1/live/${encodeURIComponent(runId)}/subscribe`;
}

/// Compute the next reconnect-backoff delay. Caps at 30 s so a
/// flaky bridge or a brief Fly.io restart doesn't blast the hub
/// with reconnect attempts. Pure so the loop math is unit-testable.
export function nextBackoff(prevMs: number): number {
	return Math.min(prevMs * 2, 30_000);
}
