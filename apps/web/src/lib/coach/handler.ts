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
	validateCoachMessages,
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
		console.error(
			'[coach] missing ANTHROPIC_API_KEY — set it in the web app env, ' +
				'or set COACH_PROVIDER=openai for a local Ollama-compatible backend.',
		);
		return jsonError(503, 'Coach is not configured.');
	}

	if (config.bypassPaywallEnabled) {
		console.warn(
			'[coach] BYPASS_PAYWALL active — this MUST only run in local dev. ' +
				'If you see this in production logs, the prod-env gate failed.',
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

	// Bound the message-list size + per-message + aggregate content.
	// The constants live in `limits.ts` so the validator can be unit-
	// tested without booting Supabase. Per-message caps differ by role
	// — see `validateCoachMessages` for the rationale.
	const validation = validateCoachMessages(body.messages);
	if (!validation.ok) {
		return jsonError(400, 'invalid messages');
	}

	const supabase = createClient(config.publicSupabaseUrl, config.publicSupabaseAnonKey, {
		global: { headers: { Authorization: `Bearer ${accessToken}` } },
	});

	const userRes = await supabase.auth.getUser(accessToken);
	const authUser = userRes.data.user;
	if (!authUser) {
		// GoTrue's error message can carry internal identifiers and
		// JWT-shape details that give an attacker an oracle for
		// probing token formats. Log them server-side; surface a
		// generic 401 to the client.
		console.error('[coach] auth failed', {
			tokenPrefix: accessToken.slice(0, 20) + '...',
			error: userRes.error?.message ?? 'no user returned',
		});
		return jsonError(401, 'not authenticated');
	}

	// GDPR Art 6(1)(a): refuse to fan out to Anthropic until the data
	// subject has explicitly accepted the first-use disclosure on
	// /coach. Client UI also gates this, but the handler is the load-
	// bearing check — a hand-rolled cURL request must fail closed.
	// See audit/gdpr (2026-05-25).
	//
	// user_profiles.coach_consent_at is not in the public-safe column
	// grant list (migration 20260707_001), so a direct
	// `.select('coach_consent_at')` returns null for the caller's role.
	// Go through the SECURITY DEFINER `get_my_profile()` RPC instead.
	const consentLookup = await supabase.rpc('get_my_profile').maybeSingle();
	if (consentLookup.error) {
		console.error('[coach] consent lookup failed', consentLookup.error);
		return jsonError(500, 'consent check failed');
	}
	if (!consentLookup.data?.coach_consent_at) {
		return jsonError(
			403,
			'Coach consent required. Visit /coach in the app and accept ' +
				'the first-use disclosure before retrying.',
		);
	}

	let tier: Tier = 'free';
	let usedToday = 0;
	if (!config.bypassPaywallEnabled) {
		const { data: isPro } = await supabase.rpc('is_pro');
		tier = isPro === true ? 'pro' : 'free';
		const dailyLimit = TIER_LIMITS[tier].dailyLimit;
		const { data: newCount } = await supabase.rpc('increment_coach_usage', {
			p_user_id: authUser.id,
		});
		usedToday = typeof newCount === 'number' ? newCount : 0;
		// `increment_coach_usage` returns the count AFTER incrementing.
		// `usedToday > dailyLimit` means messages 1..N (= dailyLimit)
		// all ran; the (N+1)th increment lands at `usedToday = N+1`,
		// fails this gate, and no provider call streams. The counter
		// ends at N+1 on a rejected attempt — cosmetic, but the
		// rejection semantics match the per-tier daily contract
		// documented in paywall.md.
		if (usedToday > dailyLimit) {
			const upgradeHint = tier === 'free'
				? ' Upgrade to Pro for a higher daily cap, or come back tomorrow!'
				: ' Come back tomorrow!';
			return {
				kind: 'json',
				status: 429,
				headers: {
					'content-type': 'application/json',
					...rateLimitHeaders(tier, usedToday),
				},
				body: JSON.stringify({
					error: 'daily_limit',
					message: `You've used all ${dailyLimit} coach messages for today.${upgradeHint}`,
					used: usedToday,
					limit: dailyLimit,
					tier,
				}),
			};
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
				daily_limit: limits.dailyLimit,
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
