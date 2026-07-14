// Thin SvelteKit wrapper around `$lib/routes/osrm_proxy/handler`. Dev-only —
// under `@sveltejs/adapter-static` (the canonical adapter, see decisions §53)
// this `+server.ts` is not built. In production the same handler is reached
// via `apps/web/lambda/osrm-proxy/src/index.ts`, fronted by CloudFront's
// `/api/routes/osrm*` behaviour.
//
// The shared core lives at `$lib/routes/osrm_proxy/handler.ts`; this file just
// adapts the SvelteKit `Request` to the core's transport-agnostic signature.

import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { handleOsrmProxy } from '$lib/routes/osrm_proxy/handler';

export const prerender = false;

function json(status: number, body: unknown): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { 'content-type': 'application/json' },
	});
}

export const GET: RequestHandler = async ({ request, params, url }) => {
	const query: Record<string, string | undefined> = {};
	for (const [k, v] of url.searchParams) query[k] = v;

	// Demo fallback is a local-dev convenience ONLY: this file is dropped from
	// the static prod build, and the NODE_ENV gate is defence-in-depth on top
	// (same posture as /api/coach's bypass gates). The Lambda wrapper never
	// falls back — an unset OSRM_URL is a 501 there.
	const allowDemoFallback = env.NODE_ENV !== 'production';

	const result = await handleOsrmProxy(
		request.headers.get('x-supabase-authorization'),
		params.path,
		query,
		{
			osrmUrl: env.OSRM_URL,
			allowDemoFallback,
			publicSupabaseUrl: PUBLIC_SUPABASE_URL,
			publicSupabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY,
		},
	);
	return json(result.status, result.body);
};
