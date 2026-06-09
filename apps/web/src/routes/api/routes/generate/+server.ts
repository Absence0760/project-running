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

	// GRAPHHOPPER_URL is a server-only env (never PUBLIC_): the browser routes
	// generation through this endpoint, so user start-coordinates never reach
	// the engine directly. Unset → the handler returns 501 and the client falls
	// back to its in-browser OSRM heuristic.
	const result = await handleGenerate(rawBody, {
		graphhopperUrl: env.GRAPHHOPPER_URL,
		graphhopperApiKey: env.GRAPHHOPPER_API_KEY,
	});
	return json(result.status, result.body);
};
