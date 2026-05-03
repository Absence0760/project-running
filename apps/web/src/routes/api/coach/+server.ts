// Thin SvelteKit wrapper around `$lib/coach/handler`. Dev-only — under
// `@sveltejs/adapter-static` (the canonical adapter, see decisions
// § 53), this `+server.ts` is not built. In production the same
// handler is reached via `apps/web/lambda/coach/src/index.ts`, fronted
// by CloudFront's `/api/coach/*` behaviour.
//
// The shared core lives at `$lib/coach/handler.ts`; this file just
// adapts the SvelteKit `Request` to the core's transport-agnostic
// signature and returns a streaming `Response` for SSE.

import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { handleCoach } from '$lib/coach/handler';

export const prerender = false;

export const POST: RequestHandler = async ({ request }) => {
	const provider = (env.COACH_PROVIDER ?? 'anthropic').toLowerCase();
	if (provider !== 'anthropic' && provider !== 'openai') {
		return new Response(
			JSON.stringify({ error: `Unknown COACH_PROVIDER='${provider}'. Use 'anthropic' or 'openai'.` }),
			{ status: 503, headers: { 'content-type': 'application/json' } },
		);
	}

	let rawBody: unknown;
	try {
		rawBody = await request.json();
	} catch {
		return new Response(JSON.stringify({ error: 'invalid JSON' }), {
			status: 400,
			headers: { 'content-type': 'application/json' },
		});
	}

	// BYPASS_PAYWALL is a dev-only escape hatch. Refuse to honour it
	// when the deployment env reports production — VERCEL_ENV is set to
	// 'production' on Vercel prod, NODE_ENV is set to 'production' on
	// most adapters. .env hygiene is the primary defence; this is the
	// code-level backstop so a stray `BYPASS_PAYWALL=true` in a prod
	// env cannot silently disable the coach quota.
	const isProdEnv = env.VERCEL_ENV === 'production' || env.NODE_ENV === 'production';
	const bypassPaywallEnabled = !isProdEnv && env.BYPASS_PAYWALL === 'true';

	const result = await handleCoach(request.headers.get('authorization'), rawBody, {
		provider,
		anthropicApiKey: env.ANTHROPIC_API_KEY,
		openaiBaseUrl: env.OPENAI_BASE_URL ?? 'http://localhost:11434/v1',
		openaiApiKey: env.OPENAI_API_KEY ?? 'ollama',
		openaiModel: env.OPENAI_MODEL ?? 'llama3.2',
		publicSupabaseUrl: PUBLIC_SUPABASE_URL,
		publicSupabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY,
		bypassPaywallEnabled,
	});

	if (result.kind === 'json') {
		return new Response(result.body, { status: result.status, headers: result.headers });
	}

	const stream = new ReadableStream({
		async start(controller) {
			try {
				for await (const chunk of result.body) {
					controller.enqueue(chunk);
				}
			} finally {
				controller.close();
			}
		},
	});
	return new Response(stream, { status: result.status, headers: result.headers });
};
