// Thin SvelteKit wrapper around `$lib/routes/generate/handler`. Dev-only —
// under `@sveltejs/adapter-static` (the canonical adapter, see decisions §53)
// this `+server.ts` is not built. In production the same handler is reached via
// `apps/web/lambda/generate-route/src/index.ts`, fronted by CloudFront's
// `/api/routes/generate*` behaviour.
//
// The shared core lives at `$lib/routes/generate/handler.ts`; this file just
// adapts the SvelteKit `Request` to the core's transport-agnostic signature.

import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { handleGenerate } from '$lib/routes/generate/handler';

export const prerender = false;

// Bound on the inbound body. The only fields are a start coordinate, a target
// distance, and an optional seed count — a few dozen bytes. 4 KB is generous
// and stops a malformed client from streaming a large body into JSON.parse.
const BODY_LIMIT_BYTES = 4 * 1024;

function json(status: number, body: unknown): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { 'content-type': 'application/json' },
	});
}

export const POST: RequestHandler = async ({ request }) => {
	const rawArr = await request.arrayBuffer();
	if (rawArr.byteLength > BODY_LIMIT_BYTES) {
		return json(413, { error: 'request body too large' });
	}
	let rawBody: unknown;
	try {
		const text = new TextDecoder('utf-8').decode(rawArr);
		rawBody = text.length === 0 ? null : JSON.parse(text);
	} catch {
		return json(400, { error: 'invalid JSON' });
	}

	// Same dev-only bypass gates as /api/coach (defence-in-depth — this
	// file is dropped from the static prod build):
	//   1. NODE_ENV must NOT be production.
	//   2. Supabase URL MUST point at the local stack.
	//   3. BYPASS_PAYWALL must be the literal string 'true'.
	const isLocalSupabase =
		PUBLIC_SUPABASE_URL.includes('127.0.0.1') || PUBLIC_SUPABASE_URL.includes('localhost');
	const isProdEnv = env.NODE_ENV === 'production';
	const bypassPaywallEnabled = !isProdEnv && isLocalSupabase && env.BYPASS_PAYWALL === 'true';

	// GRAPH_CYCLE_URL + GRAPHHOPPER_URL are server-only envs (never PUBLIC_): the
	// browser routes generation through this endpoint, so user start-coordinates
	// never reach an engine directly. Both unset → the handler returns 501 and
	// the client falls back to its in-browser OSRM heuristic.
	const result = await handleGenerate(request.headers.get('x-supabase-authorization'), rawBody, {
		// graph_cycle sidecar — the v3 graph-cycle generator, tried FIRST.
		graphCycleUrl: env.GRAPH_CYCLE_URL,
		graphCycleApiKey: env.GRAPH_CYCLE_API_KEY,
		graphhopperUrl: env.GRAPHHOPPER_URL,
		graphhopperApiKey: env.GRAPHHOPPER_API_KEY,
		publicSupabaseUrl: PUBLIC_SUPABASE_URL,
		publicSupabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY,
		bypassPaywallEnabled,
	});
	return json(result.status, result.body);
};
