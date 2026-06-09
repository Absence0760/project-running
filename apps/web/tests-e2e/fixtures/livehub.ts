/**
 * Test-side client for the Go live-hub booted by
 * tests-e2e/scripts/start-livehub.sh. Used only by the WebSocket
 * spectator spec (live/spectator_websocket.spec.ts), which runs under
 * the dedicated playwright.livehub.config.ts — the hub is NOT up for
 * the sharded suite, so don't import this from other specs.
 *
 * The push wire shape mirrors `apps/job_worker/internal/livehub/types.go`
 * (`Ping`). The hub rejects unknown fields, so only send the keys
 * below.
 */

/// Base URL of the locally-booted hub. The dedicated config + CI job
/// pin port 8099; set LIVEHUB_E2E_PORT (honoured by both this fixture
/// and playwright.livehub.config.ts) to move it, or LIVEHUB_E2E_URL to
/// point at a hub running elsewhere entirely.
export const LIVEHUB_URL =
	process.env.LIVEHUB_E2E_URL ??
	`http://127.0.0.1:${process.env.LIVEHUB_E2E_PORT ?? '8099'}`;

export interface PushPing {
	lat: number;
	lng: number;
	distance_m?: number;
	elapsed_s?: number;
	bpm?: number;
	ele?: number;
}

/// POST a ping to the hub the way the mobile recorder does. The hub is
/// booted in permissive (auth-OFF) mode by start-livehub.sh — it
/// exports SUPABASE_JWT_SECRET="" to shadow the committed
/// .env.development default, so the authorizer is nil and no
/// Authorization header is needed. Throws on a non-2xx so a misbehaving
/// hub fails the test loudly rather than silently dropping the
/// assertion's signal.
export async function pushLivePing(runId: string, ping: PushPing): Promise<void> {
	const url = `${LIVEHUB_URL}/v1/live/${encodeURIComponent(runId)}/push`;
	const res = await fetch(url, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(ping)
	});
	if (!res.ok) {
		throw new Error(`pushLivePing ${res.status}: ${await res.text()}`);
	}
	// The hub answers 202 with { ok, clipped?, subscribers_sent }. A
	// privacy-zone clip returns ok:true but clipped:true and never
	// publishes — surface it so a test that accidentally plants an
	// in-zone point fails here instead of timing out on a badge that
	// never flips.
	const body = (await res.json()) as { clipped?: boolean };
	if (body.clipped) {
		throw new Error(
			`pushLivePing for ${runId} was clipped by the privacy-zone filter — ` +
				`use coordinates clear of the seeded zone`
		);
	}
}
