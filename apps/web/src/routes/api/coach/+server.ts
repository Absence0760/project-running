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

// Bound on the inbound coach request body. The handler builds the
// full prompt (system + context + messages) and forwards to Anthropic
// — without a cap, a single Pro request could submit megabytes of
// message text per call. 256 KB is comfortable for a long
// conversation history at typical token sizes; legitimate replies
// from the assistant cost the same regardless.
const COACH_BODY_LIMIT_BYTES = 256 * 1024;

export const POST: RequestHandler = async ({ request }) => {
	const provider = (env.COACH_PROVIDER ?? 'anthropic').toLowerCase();
	if (provider !== 'anthropic' && provider !== 'openai') {
		console.error(`[coach] invalid COACH_PROVIDER value: '${provider}'`);
		return new Response(
			JSON.stringify({ error: 'Coach is not configured.' }),
			{ status: 503, headers: { 'content-type': 'application/json' } },
		);
	}

	const rawText = await request.text();
	if (rawText.length > COACH_BODY_LIMIT_BYTES) {
		return new Response(JSON.stringify({ error: 'request too large' }), {
			status: 413,
			headers: { 'content-type': 'application/json' },
		});
	}

	let rawBody: unknown;
	try {
		rawBody = rawText.length === 0 ? null : JSON.parse(rawText);
	} catch {
		return new Response(JSON.stringify({ error: 'invalid JSON' }), {
			status: 400,
			headers: { 'content-type': 'application/json' },
		});
	}

	// BYPASS_PAYWALL is a dev-only escape hatch. The production code
	// path is the AWS Lambda (apps/web/lambda/coach/src/index.ts), which
	// hardcodes `bypassPaywallEnabled: false`; this `+server.ts` is
	// dev-only because adapter-static drops it from the static build.
	// The defence-in-depth gates here exist purely for "in case the
	// adapter changes later":
	//   1. NODE_ENV must NOT be production.
	//   2. The Supabase URL MUST point at the local stack — bypassing
	//      the paywall against a real project would be an operational
	//      incident.
	//   3. BYPASS_PAYWALL must be the literal string 'true'.
	// Any one of these failing forces the bypass off.
	const isLocalSupabase =
		PUBLIC_SUPABASE_URL.includes('127.0.0.1') ||
		PUBLIC_SUPABASE_URL.includes('localhost');
	const isProdEnv = env.NODE_ENV === 'production';
	const bypassPaywallEnabled =
		!isProdEnv && isLocalSupabase && env.BYPASS_PAYWALL === 'true';

	// Mirrors the production Lambda: read the user JWT from
	// `X-Supabase-Authorization` so dev and prod clients send the same
	// header. (Prod can't use `Authorization` — CloudFront's Lambda OAC
	// signs sigv4 in that slot.)
	const result = await handleCoach(request.headers.get('x-supabase-authorization'), rawBody, {
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
