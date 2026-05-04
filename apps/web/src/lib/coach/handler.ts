// Transport-agnostic coach handler. Wrapped twice:
//   - apps/web/src/routes/api/coach/+server.ts (SvelteKit dev route)
//   - apps/web/lambda/coach/src/index.ts (AWS Lambda Function URL,
//     production)
//
// See decisions.md § 53 for the wiring rationale.
//
// SSE protocol on the happy path (one event per line, blank line
// terminates each event):
//   event: meta   data: { user_message_id, tier, limits }
//   event: token  data: { text }            (zero or more)
//   event: done   data: { assistant_message_id, cache, used_today }
//   event: error  data: { message }         (mid-stream failure)
//
// Pre-stream failures (auth, rate-limit, validation) return regular
// JSON via `kind: 'json'` on the result — the client picks the path
// off `content-type`.

import { createClient } from '@supabase/supabase-js';
import { buildContext } from './context';
import {
	clampRunsLimit,
	jsonError as buildJsonError,
	parseAuthHeader,
	personalityAddendum,
	rateLimitHeaders,
} from './limits';
import { streamAnthropic, streamOpenAI } from './providers';
import { COACH_SYSTEM_PROMPT } from './system_prompt';
import {
	TIER_LIMITS,
	emptyUsage,
	type CoachConfig,
	type CoachMode,
	type CoachRequestBody,
	type CoachResult,
	type ProviderStream,
	type ProviderUsage,
	type Tier,
} from './types';

export async function handleCoach(
	authHeader: string | null,
	rawBody: unknown,
	config: CoachConfig,
): Promise<CoachResult> {
	if (config.provider === 'anthropic' && !config.anthropicApiKey) {
		return jsonError(
			503,
			'Coach is not configured — set ANTHROPIC_API_KEY in the web app env, or set COACH_PROVIDER=openai for a local Ollama-compatible backend.',
		);
	}

	const accessToken = parseAuthHeader(authHeader);
	if (!accessToken) return jsonError(401, 'not authenticated');

	let body: CoachRequestBody;
	if (rawBody && typeof rawBody === 'object') {
		body = rawBody as CoachRequestBody;
	} else {
		return jsonError(400, 'invalid JSON');
	}

	const supabase = createClient(config.publicSupabaseUrl, config.publicSupabaseAnonKey, {
		global: { headers: { Authorization: `Bearer ${accessToken}` } },
	});

	const userRes = await supabase.auth.getUser(accessToken);
	const authUser = userRes.data.user;
	if (!authUser) {
		console.error('[coach] auth failed', {
			tokenPrefix: accessToken.slice(0, 20) + '...',
			error: userRes.error?.message ?? 'no user returned',
		});
		return jsonError(401, 'not authenticated', {
			detail: userRes.error?.message ?? null,
		});
	}

	let tier: Tier = 'free';
	let usedToday = 0;
	if (!config.bypassPaywallEnabled) {
		const { data: isPro } = await supabase.rpc('is_pro');
		tier = isPro === true ? 'pro' : 'free';
		if (tier === 'free') {
			const { data: newCount } = await supabase.rpc('increment_coach_usage', {
				p_user_id: authUser.id,
			});
			usedToday = typeof newCount === 'number' ? newCount : 0;
			if (usedToday > TIER_LIMITS.free.dailyLimit) {
				return {
					kind: 'json',
					status: 429,
					headers: {
						'content-type': 'application/json',
						...rateLimitHeaders(tier, usedToday),
					},
					body: JSON.stringify({
						error: 'daily_limit',
						message: `You've used all ${TIER_LIMITS.free.dailyLimit} coach messages for today. Upgrade to Pro for unlimited chats, or come back tomorrow!`,
						used: usedToday,
						limit: TIER_LIMITS.free.dailyLimit,
						tier,
					}),
				};
			}
		}
	} else {
		tier = 'pro';
	}

	const limits = TIER_LIMITS[tier];

	const runsLimit = clampRunsLimit(body.recent_runs_limit, tier);

	const context = await buildContext(supabase, authUser.id, body.plan_id ?? null, runsLimit);

	const personality = (context.data as Record<string, unknown>)?.runner_context as
		| Record<string, unknown>
		| undefined;
	const coachStyle = personality?.coach_personality as string | undefined;
	const systemText = COACH_SYSTEM_PROMPT + personalityAddendum(coachStyle);
	const contextPayload =
		'CONTEXT (runner profile, active plan, recent runs):\n' +
		JSON.stringify(context.data, null, 2);

	// Truncate the active thread first if regenerate / edit asked for it.
	// Anchor + everything after it goes (within the active thread for
	// this user × plan). RLS scopes the delete to the caller.
	const mode: CoachMode = body.mode ?? 'send';
	if ((mode === 'regenerate' || mode === 'edit') && body.anchor_message_id) {
		const { data: anchor } = await supabase
			.from('coach_messages')
			.select('created_at')
			.eq('id', body.anchor_message_id)
			.maybeSingle();
		if (anchor?.created_at) {
			const delQuery = supabase
				.from('coach_messages')
				.delete()
				.eq('user_id', authUser.id)
				.is('archived_at', null)
				.gte('created_at', anchor.created_at);
			const { error: delErr } = body.plan_id
				? await delQuery.eq('plan_id', body.plan_id)
				: await delQuery.is('plan_id', null);
			if (delErr) console.error('[coach] truncate failed', delErr);
		}
	}

	// Insert the new user message (send + edit modes). Regenerate keeps
	// the existing user message untouched.
	let userMessageId: string | null = null;
	if (mode === 'send' || mode === 'edit') {
		const lastUser = [...body.messages].reverse().find((m) => m.role === 'user');
		if (lastUser) {
			const { data, error: insertErr } = await supabase
				.from('coach_messages')
				.insert({
					user_id: authUser.id,
					plan_id: body.plan_id ?? null,
					role: 'user',
					content: lastUser.content,
				})
				.select('id')
				.single();
			if (insertErr) console.error('[coach] persist user msg failed', insertErr);
			else userMessageId = data?.id ?? null;
		}
	}

	let providerStream: ProviderStream;
	try {
		providerStream =
			config.provider === 'openai'
				? streamOpenAI(
						config.openaiBaseUrl ?? 'http://localhost:11434/v1',
						config.openaiApiKey ?? 'ollama',
						config.openaiModel ?? 'llama3.2',
						systemText,
						contextPayload,
						body.messages,
						limits,
					)
				: streamAnthropic(
						config.anthropicApiKey!,
						systemText,
						contextPayload,
						body.messages,
						limits,
					);
	} catch (e) {
		const msg = e instanceof Error ? e.message : 'coach call failed';
		return jsonError(502, msg);
	}

	const sseHeaders: Record<string, string> = {
		'content-type': 'text/event-stream; charset=utf-8',
		'cache-control': 'no-cache, no-transform',
		'x-accel-buffering': 'no',
		...rateLimitHeaders(tier, usedToday),
	};

	const encoder = new TextEncoder();
	const userIdForStream = authUser.id;
	async function* sseStream(): AsyncIterable<Uint8Array> {
		const sendEvent = (event: string, data: unknown): Uint8Array =>
			encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);

		yield sendEvent('meta', {
			user_message_id: userMessageId,
			tier,
			limits: {
				daily_limit: Number.isFinite(limits.dailyLimit) ? limits.dailyLimit : null,
				max_tokens: limits.maxTokens,
				max_runs_limit: limits.maxRunsLimit,
			},
		});

		let accumulated = '';
		try {
			for await (const chunk of providerStream.tokens) {
				if (!chunk) continue;
				accumulated += chunk;
				yield sendEvent('token', { text: chunk });
			}
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'stream failed';
			yield sendEvent('error', { message: msg });
			return;
		}

		let usage: ProviderUsage = emptyUsage();
		try {
			usage = await providerStream.finalUsage();
		} catch (_) {
			/* usage is best-effort */
		}

		let assistantMessageId: string | null = null;
		if (accumulated) {
			try {
				const { data, error: insertErr } = await supabase
					.from('coach_messages')
					.insert({
						user_id: userIdForStream,
						plan_id: body.plan_id ?? null,
						role: 'assistant',
						content: accumulated,
					})
					.select('id')
					.single();
				if (insertErr) console.error('[coach] persist assistant failed', insertErr);
				else assistantMessageId = data?.id ?? null;
			} catch (e) {
				console.error('[coach] persist assistant exception', e);
			}
		}

		yield sendEvent('done', {
			assistant_message_id: assistantMessageId,
			cache: usage,
			used_today: usedToday,
		});
	}

	return {
		kind: 'sse',
		status: 200,
		headers: sseHeaders,
		body: sseStream(),
	};
}

function jsonError(
	status: number,
	error: string,
	extra: Record<string, unknown> = {},
): CoachResult {
	return buildJsonError(status, error, extra) as CoachResult;
}
