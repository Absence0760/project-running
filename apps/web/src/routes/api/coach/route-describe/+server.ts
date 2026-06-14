// Thin SvelteKit wrapper around `$lib/routes/route_describe/handler`.
// Dev-only — under @sveltejs/adapter-static this `+server.ts` is not
// built; in production the same handler is reached via the coach
// Lambda's `/route-describe` route (decisions.md § 53).
//
// Mirrors the bypass + body-cap + auth-header conventions of the
// sibling `/api/coach/+server.ts`.

import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { handleRouteDescribe } from '$lib/routes/route_describe/handler';
import { checkBodyByteLimit } from '$lib/coach/body';

export const prerender = false;

// A route-describe body is tiny (a few numbers + a name). 32 KB is
// generous and bounds a hostile caller well below the coach cap.
const ROUTE_DESCRIBE_BODY_LIMIT_BYTES = 32 * 1024;

export const POST: RequestHandler = async ({ request }) => {
	const rawArr = await request.arrayBuffer();
	const sizeCheck = checkBodyByteLimit(rawArr, ROUTE_DESCRIBE_BODY_LIMIT_BYTES);
	if (!sizeCheck.ok) {
		return new Response(JSON.stringify({ error: sizeCheck.error }), {
			status: sizeCheck.status,
			headers: { 'content-type': 'application/json' },
		});
	}
	const rawText = new TextDecoder('utf-8').decode(rawArr);

	let rawBody: unknown;
	try {
		rawBody = rawText.length === 0 ? null : JSON.parse(rawText);
	} catch {
		return new Response(JSON.stringify({ error: 'invalid JSON' }), {
			status: 400,
			headers: { 'content-type': 'application/json' },
		});
	}

	// Same dev-only bypass gates as /api/coach (defence-in-depth — this
	// file is dropped from the static prod build):
	//   1. NODE_ENV must NOT be production.
	//   2. Supabase URL MUST point at the local stack.
	//   3. BYPASS_PAYWALL must be the literal string 'true'.
	const isLocalSupabase =
		PUBLIC_SUPABASE_URL.includes('127.0.0.1') ||
		PUBLIC_SUPABASE_URL.includes('localhost');
	const isProdEnv = env.NODE_ENV === 'production';
	const bypassPaywallEnabled =
		!isProdEnv && isLocalSupabase && env.BYPASS_PAYWALL === 'true';

	const result = await handleRouteDescribe(
		request.headers.get('x-supabase-authorization'),
		rawBody,
		{
			anthropicApiKey: env.ANTHROPIC_API_KEY,
			publicSupabaseUrl: PUBLIC_SUPABASE_URL,
			publicSupabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY,
			bypassPaywallEnabled,
		},
	);

	return new Response(result.body, { status: result.status, headers: result.headers });
};
