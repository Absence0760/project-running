// Coach endpoint.
//
// Role: "second opinion" on the runner's plan + recent runs. Does NOT
// generate plans or prescribe training — see docs/decisions.md #12.
// Answers "should I run tomorrow?", "am I on pace for my goal?", "my last
// three long runs were slow, what's going on?" — grounded in real data.
//
// Two providers are supported, picked by `COACH_PROVIDER`:
//   - `anthropic` (default): Claude via @anthropic-ai/sdk, with prompt
//     caching on the system prompt + first user message. Used in prod.
//   - `openai`: OpenAI-compatible /v1/chat/completions endpoint. Set
//     `OPENAI_BASE_URL` to point at Ollama (`http://localhost:11434/v1`)
//     or any other compatible server. No prompt caching — the request is
//     re-tokenised every turn. Intended for local development.
//
// Wire format: Server-Sent Events (SSE) for the happy path so the
// client can render tokens as they arrive. Pre-stream failures (auth,
// rate-limit, validation) still return regular JSON with the right
// status code — the client picks the path off `content-type`.
//
// SSE protocol (one event per line, blank line terminates):
//   event: meta   data: { user_message_id, tier, limits }
//   event: token  data: { text }            (zero or more)
//   event: done   data: { assistant_message_id, cache, used_today }
//   event: error  data: { message }         (mid-stream failure)
//
// Modes:
//   - send (default):  insert new user message, run, stream reply
//   - regenerate:      delete from anchor (assistant id) onward, run with
//                      existing user message still in place
//   - edit:            delete from anchor (user id) onward, insert new
//                      user message with edited content, run

import type { RequestHandler } from './$types';
import Anthropic from '@anthropic-ai/sdk';
import { env } from '$env/dynamic/private';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

export const prerender = false;

const COACH_PROVIDER = (env.COACH_PROVIDER ?? 'anthropic').toLowerCase();
const ANTHROPIC_API_KEY = env.ANTHROPIC_API_KEY;
const OPENAI_BASE_URL = env.OPENAI_BASE_URL ?? 'http://localhost:11434/v1';
const OPENAI_API_KEY = env.OPENAI_API_KEY ?? 'ollama';
const OPENAI_MODEL = env.OPENAI_MODEL ?? 'llama3.2';

type CoachMode = 'send' | 'regenerate' | 'edit';

interface CoachRequest {
	messages: { role: 'user' | 'assistant'; content: string }[];
	plan_id?: string;
	recent_runs_limit?: number;
	mode?: CoachMode;
	// Anchor for regenerate / edit. The server deletes this message and
	// every later message in the same (user, plan, archived_at=null)
	// thread before running.
	anchor_message_id?: string;
}

const DEFAULT_RUNS_LIMIT = 20;

const TIER_LIMITS = {
	free: { dailyLimit: 10, maxTokens: 768, maxRunsLimit: 30 },
	pro:  { dailyLimit: Number.POSITIVE_INFINITY, maxTokens: 2048, maxRunsLimit: 200 },
} as const;
type Tier = keyof typeof TIER_LIMITS;

interface ProviderUsage {
	cache_creation_input_tokens: number;
	cache_read_input_tokens: number;
	input_tokens: number;
	output_tokens: number;
}

function emptyUsage(): ProviderUsage {
	return {
		cache_creation_input_tokens: 0,
		cache_read_input_tokens: 0,
		input_tokens: 0,
		output_tokens: 0,
	};
}

interface ProviderStream {
	tokens: AsyncIterable<string>;
	finalUsage: () => Promise<ProviderUsage>;
}

export const POST: RequestHandler = async ({ request }) => {
	if (COACH_PROVIDER === 'anthropic' && !ANTHROPIC_API_KEY) {
		return jsonError(503, 'Coach is not configured — set ANTHROPIC_API_KEY in the web app env, or set COACH_PROVIDER=openai for a local Ollama-compatible backend.');
	}
	if (COACH_PROVIDER !== 'anthropic' && COACH_PROVIDER !== 'openai') {
		return jsonError(503, `Unknown COACH_PROVIDER='${COACH_PROVIDER}'. Use 'anthropic' or 'openai'.`);
	}

	const authHeader = request.headers.get('authorization');
	const accessToken = authHeader?.replace(/^Bearer\s+/i, '');
	if (!accessToken) return jsonError(401, 'not authenticated');

	let body: CoachRequest;
	try {
		body = await request.json();
	} catch {
		return jsonError(400, 'invalid JSON');
	}

	const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
		global: { headers: { Authorization: `Bearer ${accessToken}` } }
	});

	const userRes = await supabase.auth.getUser(accessToken);
	const authUser = userRes.data.user;
	if (!authUser) {
		console.error('[coach] auth failed', {
			tokenPrefix: accessToken.slice(0, 20) + '...',
			error: userRes.error?.message ?? 'no user returned',
		});
		return jsonError(401, 'not authenticated', { detail: userRes.error?.message ?? null });
	}

	// BYPASS_PAYWALL is a dev-only escape hatch. Refuse to honour it
	// when the deployment env reports production — VERCEL_ENV is set
	// to 'production' on Vercel prod, NODE_ENV is set to 'production'
	// on most adapters. .env hygiene is the primary defence; this is
	// the code-level backstop so a stray `BYPASS_PAYWALL=true` in a
	// prod env cannot silently disable the coach quota.
	const isProdEnv =
		env.VERCEL_ENV === 'production' || env.NODE_ENV === 'production';
	const bypassLimit = !isProdEnv && env.BYPASS_PAYWALL === 'true';
	let tier: Tier = 'free';
	let usedToday = 0;
	if (!bypassLimit) {
		const { data: isPro } = await supabase.rpc('is_pro');
		tier = isPro === true ? 'pro' : 'free';
		if (tier === 'free') {
			const { data: newCount } = await supabase.rpc('increment_coach_usage', { p_user_id: authUser.id });
			usedToday = typeof newCount === 'number' ? newCount : 0;
			if (usedToday > TIER_LIMITS.free.dailyLimit) {
				return new Response(
					JSON.stringify({
						error: 'daily_limit',
						message: `You've used all ${TIER_LIMITS.free.dailyLimit} coach messages for today. Upgrade to Pro for unlimited chats, or come back tomorrow!`,
						used: usedToday,
						limit: TIER_LIMITS.free.dailyLimit,
						tier,
					}),
					{
						status: 429,
						headers: {
							'content-type': 'application/json',
							...rateLimitHeaders(tier, usedToday),
						},
					}
				);
			}
		}
	} else {
		tier = 'pro';
	}

	const limits = TIER_LIMITS[tier];

	const requestedLimit = Number(body.recent_runs_limit ?? DEFAULT_RUNS_LIMIT);
	const runsLimit = Number.isFinite(requestedLimit)
		? Math.min(limits.maxRunsLimit, Math.max(1, Math.trunc(requestedLimit)))
		: DEFAULT_RUNS_LIMIT;

	const context = await buildContext(supabase, authUser.id, body.plan_id ?? null, runsLimit);

	const personality = (context.data as Record<string, unknown>)?.runner_context as Record<string, unknown> | undefined;
	const coachStyle = personality?.coach_personality as string | undefined;
	let personalityAddendum = '';
	if (coachStyle === 'drill_sergeant') {
		personalityAddendum = '\n\nTone override: be blunt, demanding, and no-nonsense. Push the runner hard. Short sentences. No coddling. Think military coach.';
	} else if (coachStyle === 'analytical') {
		personalityAddendum = '\n\nTone override: be data-driven and precise. Lead with numbers, percentages, and trends. Cite specific paces, distances, and dates. Think sports scientist.';
	}

	const systemText = COACH_SYSTEM_PROMPT + personalityAddendum;
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
			COACH_PROVIDER === 'openai'
				? streamOpenAI(systemText, contextPayload, body.messages, limits)
				: streamAnthropic(systemText, contextPayload, body.messages, limits);
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
	const stream = new ReadableStream({
		async start(controller) {
			const send = (event: string, data: unknown) => {
				controller.enqueue(
					encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`),
				);
			};

			send('meta', {
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
					send('token', { text: chunk });
				}
			} catch (e) {
				const msg = e instanceof Error ? e.message : 'stream failed';
				send('error', { message: msg });
				controller.close();
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
							user_id: authUser.id,
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

			send('done', {
				assistant_message_id: assistantMessageId,
				cache: usage,
				used_today: usedToday,
			});
			controller.close();
		},
	});

	return new Response(stream, { headers: sseHeaders });
};

function jsonError(status: number, error: string, extra: Record<string, unknown> = {}): Response {
	return new Response(JSON.stringify({ error, ...extra }), {
		status,
		headers: { 'content-type': 'application/json' },
	});
}

function rateLimitHeaders(tier: Tier, usedToday: number): Record<string, string> {
	const limits = TIER_LIMITS[tier];
	const limitStr = Number.isFinite(limits.dailyLimit) ? String(limits.dailyLimit) : 'unlimited';
	const remainingStr = Number.isFinite(limits.dailyLimit)
		? String(Math.max(0, limits.dailyLimit - usedToday))
		: 'unlimited';
	return {
		'X-Coach-Tier': tier,
		'X-RateLimit-Limit': limitStr,
		'X-RateLimit-Remaining': remainingStr,
		'X-RateLimit-MaxTokens': String(limits.maxTokens),
		'X-RateLimit-MaxRuns': String(limits.maxRunsLimit),
	};
}

// ─────────────────────── Provider: Anthropic (streaming) ───────────────────────

function streamAnthropic(
	systemText: string,
	contextPayload: string,
	messages: { role: 'user' | 'assistant'; content: string }[],
	limits: typeof TIER_LIMITS[Tier],
): ProviderStream {
	const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

	const systemBlocks = [
		{
			type: 'text' as const,
			text: systemText,
			cache_control: { type: 'ephemeral' as const },
		},
	];

	const convo = [
		{
			role: 'user' as const,
			content: [
				{
					type: 'text' as const,
					text: contextPayload,
					cache_control: { type: 'ephemeral' as const },
				},
			],
		},
		{
			role: 'assistant' as const,
			content: 'Got it — I have your plan and recent runs in view. Ask away.',
		},
		...messages.map((m) => ({
			role: m.role,
			content: [{ type: 'text' as const, text: m.content }],
		})),
	];

	const stream = anthropic.messages.stream({
		model: 'claude-sonnet-4-5',
		max_tokens: limits.maxTokens,
		system: systemBlocks,
		messages: convo,
	});

	async function* tokens(): AsyncIterable<string> {
		for await (const event of stream) {
			if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
				yield event.delta.text;
			}
		}
	}

	return {
		tokens: tokens(),
		finalUsage: async () => {
			const final = await stream.finalMessage();
			return {
				cache_creation_input_tokens: final.usage.cache_creation_input_tokens ?? 0,
				cache_read_input_tokens: final.usage.cache_read_input_tokens ?? 0,
				input_tokens: final.usage.input_tokens,
				output_tokens: final.usage.output_tokens,
			};
		},
	};
}

// ─────────────────────── Provider: OpenAI-compatible (streaming) ───────────────────────

function streamOpenAI(
	systemText: string,
	contextPayload: string,
	messages: { role: 'user' | 'assistant'; content: string }[],
	limits: typeof TIER_LIMITS[Tier],
): ProviderStream {
	const convo = [
		{ role: 'system', content: systemText },
		{ role: 'user', content: contextPayload },
		{ role: 'assistant', content: 'Got it — I have your plan and recent runs in view. Ask away.' },
		...messages.map((m) => ({ role: m.role, content: m.content })),
	];

	const usage: ProviderUsage = emptyUsage();
	const finalUsageDeferred: { resolve: (u: ProviderUsage) => void; reject: (e: Error) => void } = { resolve: () => {}, reject: () => {} };
	const finalUsagePromise = new Promise<ProviderUsage>((resolve, reject) => {
		finalUsageDeferred.resolve = resolve;
		finalUsageDeferred.reject = reject;
	});

	async function* tokens(): AsyncIterable<string> {
		const res = await fetch(`${OPENAI_BASE_URL.replace(/\/$/, '')}/chat/completions`, {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				authorization: `Bearer ${OPENAI_API_KEY}`,
			},
			body: JSON.stringify({
				model: OPENAI_MODEL,
				messages: convo,
				max_tokens: limits.maxTokens,
				stream: true,
			}),
		});
		if (!res.ok || !res.body) {
			const errText = await res.text().catch(() => '');
			finalUsageDeferred.resolve(usage);
			throw new Error(`coach upstream ${res.status}: ${errText.slice(0, 400)}`);
		}
		const reader = res.body.getReader();
		const decoder = new TextDecoder();
		let buffer = '';
		try {
			while (true) {
				const { value, done } = await reader.read();
				if (done) break;
				buffer += decoder.decode(value, { stream: true });
				let nl: number;
				while ((nl = buffer.indexOf('\n')) !== -1) {
					const line = buffer.slice(0, nl).trim();
					buffer = buffer.slice(nl + 1);
					if (!line.startsWith('data:')) continue;
					const payload = line.slice(5).trim();
					if (payload === '[DONE]') continue;
					try {
						const j = JSON.parse(payload) as {
							choices?: { delta?: { content?: string } }[];
							usage?: { prompt_tokens?: number; completion_tokens?: number };
						};
						const delta = j.choices?.[0]?.delta?.content;
						if (delta) yield delta;
						if (j.usage) {
							usage.input_tokens = j.usage.prompt_tokens ?? usage.input_tokens;
							usage.output_tokens = j.usage.completion_tokens ?? usage.output_tokens;
						}
					} catch (_) {
						/* malformed line — skip */
					}
				}
			}
		} finally {
			finalUsageDeferred.resolve(usage);
		}
	}

	return {
		tokens: tokens(),
		finalUsage: () => finalUsagePromise,
	};
}

// ─────────────────────── System prompt ───────────────────────

const COACH_SYSTEM_PROMPT = `You are a running coach embedded in the user's training app. Your role is deliberately narrow:

- Critique adherence: comment on whether they're hitting their planned sessions, weekly mileage, and pace targets.
- Answer "should I run today/tomorrow?" questions using their plan, recent runs, and any signs of strain (a string of missed sessions, pace drift on easy runs, unusually high mileage the week before, etc.).
- Explain what a workout is designed to achieve and how to execute it.
- Flag red flags gently — a 3-day miss, a long run that's far slower than usual, back-to-back hard days when the plan says easy.
- Use runner_context when available: age (from date_of_birth), resting/max HR and HR zones for effort-level guidance, weekly_mileage_goal_m for progress commentary. If HR zones are set, interpret avg_bpm from runs in terms of those zones.

You do NOT:

- Prescribe brand-new training structures or rewrite their plan. If they want a different plan, direct them to the plan editor or to generate a fresh plan.
- Give medical advice. "See a doctor / physio" is always the safe answer to pain or injury questions.
- Give nutrition or diet prescriptions. You can mention general hydration / fuelling habits but not specific foods, calories, or supplements.
- Invent stats that aren't in the context. If something isn't in the data, say so and ask.

Style:

- Direct, short paragraphs. No preambles, no "Certainly!".
- Use the runner's actual numbers when you can (planned miles, pace, run dates). Cite them like a coach would.
- If the question is out of scope (plan regeneration, nutrition, injury), redirect briefly and move on.
- Metric and imperial: match the unit system the runner is using in the context. If unclear, use km.
- Assume the runner is an informed adult. Don't hedge every sentence with "if it feels right to you".
- Format with markdown when helpful — short bulleted lists for "things to try", **bold** for the one number that matters, fenced code blocks only for actual code or structured data. Don't overuse formatting on a one-sentence answer.
- When you reference a specific run from \`recent_runs\`, link to it with markdown using the run's \`id\`: \`[Apr 25 long run](/runs/<id>)\`. Pick a concise label — a date plus a one-word descriptor of the session is enough. Only link to runs that appear in \`recent_runs\` — never invent a run id. If you mention several runs in a row, link each one.`;

// ─────────────────────── Context builder ───────────────────────

interface CoachContext {
	data?: unknown;
}

async function buildContext(
	supabase: SupabaseClient,
	userId: string,
	planId: string | null,
	runsLimit: number,
): Promise<CoachContext> {
	const { data: plan } = planId
		? await supabase.from('training_plans').select('*').eq('id', planId).maybeSingle()
		: await supabase
				.from('training_plans')
				.select('*')
				.eq('status', 'active')
				.maybeSingle();

	let weeks: unknown[] = [];
	let workouts: unknown[] = [];
	if (plan && typeof plan === 'object' && 'id' in plan) {
		const weekRes = await supabase
			.from('plan_weeks')
			.select('*')
			.eq('plan_id', (plan as { id: string }).id)
			.order('week_index', { ascending: true });
		weeks = weekRes.data ?? [];
		if (weeks.length > 0) {
			const ids = (weeks as { id: string }[]).map((w) => w.id);
			const wkRes = await supabase
				.from('plan_workouts')
				.select('*')
				.in('week_id', ids)
				.order('scheduled_date', { ascending: true });
			workouts = wkRes.data ?? [];
		}
	}

	const { data: recentRuns } = await supabase
		.from('runs')
		.select('id, started_at, distance_m, duration_s, metadata, route_id')
		.order('started_at', { ascending: false })
		.limit(runsLimit);

	const { data: profile } = await supabase
		.from('user_profiles')
		.select('display_name, preferred_unit, subscription_tier')
		.eq('id', userId)
		.maybeSingle();

	const { data: userSettings } = await supabase
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();
	const prefs = (userSettings?.prefs ?? {}) as Record<string, unknown>;

	return {
		data: {
			now_iso: new Date().toISOString(),
			profile: profile ?? null,
			runner_context: {
				date_of_birth: prefs.date_of_birth ?? null,
				resting_hr_bpm: prefs.resting_hr_bpm ?? null,
				max_hr_bpm: prefs.max_hr_bpm ?? null,
				hr_zones: prefs.hr_zones ?? null,
				weekly_mileage_goal_m: prefs.weekly_mileage_goal_m ?? null,
				auto_pause_enabled: prefs.auto_pause_enabled ?? null,
				coach_personality: prefs.coach_personality ?? null,
			},
			plan: plan ?? null,
			plan_weeks: weeks,
			plan_workouts: workouts,
			recent_runs: recentRuns ?? [],
		},
	};
}
