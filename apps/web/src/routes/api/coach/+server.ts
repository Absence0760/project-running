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
// Anthropic prompt-caching layout:
//   system → the coach-persona prompt                       (cache)
//   first user message → plan + recent runs context dump    (cache)
//   subsequent user messages → the live chat                (no cache)
// Two cache breakpoints are enough: anything the user types changes between
// turns, but the static context reshapes only when the plan changes or a
// new run lands. A 20-turn conversation hits the cache 18× with this setup.

import type { RequestHandler } from './$types';
import Anthropic from '@anthropic-ai/sdk';
import { env } from '$env/dynamic/private';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

// Opt out of prerender — this endpoint must run per-request against the
// user's session. Under `adapter-static` this route simply doesn't exist
// (the client handles 404 with a helpful message), and under `adapter-vercel`
// it runs as a serverless function.
export const prerender = false;

const COACH_PROVIDER = (env.COACH_PROVIDER ?? 'anthropic').toLowerCase();
const ANTHROPIC_API_KEY = env.ANTHROPIC_API_KEY;
const OPENAI_BASE_URL = env.OPENAI_BASE_URL ?? 'http://localhost:11434/v1';
const OPENAI_API_KEY = env.OPENAI_API_KEY ?? 'ollama';
const OPENAI_MODEL = env.OPENAI_MODEL ?? 'llama3.2';

interface CoachRequest {
	messages: { role: 'user' | 'assistant'; content: string }[];
	plan_id?: string;
	/// How many recent runs to include in the context dump. Clamped to
	/// [1, 100] server-side so a runaway client can't blow up the prompt.
	/// Defaults to 20 if absent — matches the original behaviour.
	recent_runs_limit?: number;
	access_token: string; // user's Supabase JWT — used to scope the data pull
}

const DEFAULT_RUNS_LIMIT = 20;

/// Tier-aware processing budgets — the concrete shape "Priority
/// processing for Pro users" takes on the web. Free users get a
/// reasonable default; Pro users get a higher response token budget
/// (richer, longer answers), a much larger context cap (more historical
/// runs in view per turn), and no daily message ceiling.
const TIER_LIMITS = {
	free: { dailyLimit: 10, maxTokens: 768, maxRunsLimit: 30 },
	pro:  { dailyLimit: Number.POSITIVE_INFINITY, maxTokens: 2048, maxRunsLimit: 200 },
} as const;
type Tier = keyof typeof TIER_LIMITS;

export const POST: RequestHandler = async ({ request }) => {
	if (COACH_PROVIDER === 'anthropic' && !ANTHROPIC_API_KEY) {
		return new Response(
			JSON.stringify({
				error:
					'Coach is not configured — set ANTHROPIC_API_KEY in the web app env, or set COACH_PROVIDER=openai for a local Ollama-compatible backend.'
			}),
			{ status: 503, headers: { 'content-type': 'application/json' } }
		);
	}
	if (COACH_PROVIDER !== 'anthropic' && COACH_PROVIDER !== 'openai') {
		return new Response(
			JSON.stringify({
				error: `Unknown COACH_PROVIDER='${COACH_PROVIDER}'. Use 'anthropic' or 'openai'.`
			}),
			{ status: 503, headers: { 'content-type': 'application/json' } }
		);
	}

	let body: CoachRequest;
	try {
		body = await request.json();
	} catch {
		return new Response(JSON.stringify({ error: 'invalid JSON' }), {
			status: 400,
			headers: { 'content-type': 'application/json' }
		});
	}

	if (!body.access_token) {
		return new Response(JSON.stringify({ error: 'not authenticated' }), {
			status: 401,
			headers: { 'content-type': 'application/json' }
		});
	}

	// Scope every data read to the caller's JWT so RLS does its job — the
	// server never sees another user's runs or plans.
	const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
		global: { headers: { Authorization: `Bearer ${body.access_token}` } }
	});

	// Resolve the caller's tier first — every downstream limit (daily
	// message cap, response token budget, context window) is derived
	// from it. BYPASS_PAYWALL fast-paths the whole check in dev so you
	// don't burn through quota while iterating on prompts.
	const bypassLimit = env.BYPASS_PAYWALL === 'true';
	let tier: Tier = 'free';
	let usedToday = 0;
	if (!bypassLimit) {
		const { data: { user: authUser } } = await supabase.auth.getUser();
		if (!authUser) {
			return new Response(JSON.stringify({ error: 'not authenticated' }), {
				status: 401,
				headers: { 'content-type': 'application/json' }
			});
		}
		const { data: isPro } = await supabase.rpc('is_user_pro', {
			p_user_id: authUser.id,
		});
		tier = isPro === true ? 'pro' : 'free';

		// Free-tier daily-cap enforcement. Pro skips the increment so
		// usage isn't tracked (and we don't pay an RPC) for unlimited.
		if (tier === 'free') {
			const { data: newCount } = await supabase.rpc('increment_coach_usage', {
				p_user_id: authUser.id,
			});
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
		// Bypass mode reports as `pro` so the UI surfaces the unlimited
		// shape the dev would see in prod when paying for Pro.
		tier = 'pro';
	}

	const limits = TIER_LIMITS[tier];

	const requestedLimit = Number(body.recent_runs_limit ?? DEFAULT_RUNS_LIMIT);
	const runsLimit = Number.isFinite(requestedLimit)
		? Math.min(limits.maxRunsLimit, Math.max(1, Math.trunc(requestedLimit)))
		: DEFAULT_RUNS_LIMIT;

	const context = await buildContext(supabase, body.plan_id ?? null, runsLimit);
	if (context.error) {
		return new Response(JSON.stringify({ error: context.error }), {
			status: 401,
			headers: { 'content-type': 'application/json' }
		});
	}

	const personality = (context.data as Record<string, unknown>)?.runner_context as Record<string, unknown> | undefined;
	const coachStyle = personality?.coach_personality as string | undefined;
	let personalityAddendum = '';
	if (coachStyle === 'drill_sergeant') {
		personalityAddendum = '\n\nTone override: be blunt, demanding, and no-nonsense. Push the runner hard. Short sentences. No coddling. Think military coach.';
	} else if (coachStyle === 'analytical') {
		personalityAddendum = '\n\nTone override: be data-driven and precise. Lead with numbers, percentages, and trends. Cite specific paces, distances, and dates. Think sports scientist.';
	}
	// 'supportive' is the default tone in COACH_SYSTEM_PROMPT — no addendum needed.

	const systemText = COACH_SYSTEM_PROMPT + personalityAddendum;
	const contextPayload =
		'CONTEXT (runner profile, active plan, recent runs):\n' +
		JSON.stringify(context.data, null, 2);

	const headers = {
		'content-type': 'application/json',
		...rateLimitHeaders(tier, usedToday),
	};

	try {
		if (COACH_PROVIDER === 'openai') {
			return await callOpenAI(systemText, contextPayload, body.messages, tier, limits, headers);
		}
		return await callAnthropic(systemText, contextPayload, body.messages, tier, limits, headers);
	} catch (e) {
		const msg = e instanceof Error ? e.message : 'coach call failed';
		return new Response(JSON.stringify({ error: msg }), {
			status: 502,
			headers,
		});
	}
};

/// Standard `X-RateLimit-*` headers + a `X-Coach-Tier` echo so a
/// client can see exactly which budget bucket the request landed in.
/// `Infinity` collapses to the literal string "unlimited" in the
/// remaining + limit fields so HTTP-clean ASCII flows over the wire.
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

// ─────────────────────── Provider: Anthropic ───────────────────────

async function callAnthropic(
	systemText: string,
	contextPayload: string,
	messages: { role: 'user' | 'assistant'; content: string }[],
	tier: Tier,
	limits: typeof TIER_LIMITS[Tier],
	headers: Record<string, string>,
): Promise<Response> {
	const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

	const systemBlocks = [
		{
			type: 'text' as const,
			text: systemText,
			cache_control: { type: 'ephemeral' as const }
		}
	];

	// First user message carries the grounded context; cache_control on it
	// gives a stable prefix that subsequent turns hit.
	const convo = [
		{
			role: 'user' as const,
			content: [
				{
					type: 'text' as const,
					text: contextPayload,
					cache_control: { type: 'ephemeral' as const }
				}
			]
		},
		{
			role: 'assistant' as const,
			content: 'Got it — I have your plan and recent runs in view. Ask away.'
		},
		...messages.map((m) => ({
			role: m.role,
			content: [{ type: 'text' as const, text: m.content }]
		}))
	];

	const res = await anthropic.messages.create({
		model: 'claude-sonnet-4-5',
		max_tokens: limits.maxTokens,
		system: systemBlocks,
		messages: convo
	});
	const text = res.content
		.filter((b) => b.type === 'text')
		.map((b) => (b as { type: 'text'; text: string }).text)
		.join('\n');
	return new Response(
		JSON.stringify({
			reply: text,
			tier,
			limits: {
				daily_limit: Number.isFinite(limits.dailyLimit) ? limits.dailyLimit : null,
				max_tokens: limits.maxTokens,
				max_runs_limit: limits.maxRunsLimit,
			},
			cache: {
				cache_creation_input_tokens: res.usage.cache_creation_input_tokens ?? 0,
				cache_read_input_tokens: res.usage.cache_read_input_tokens ?? 0,
				input_tokens: res.usage.input_tokens,
				output_tokens: res.usage.output_tokens
			}
		}),
		{ headers }
	);
}

// ─────────────────────── Provider: OpenAI-compatible ───────────────────────
//
// Targets any server that implements `POST /v1/chat/completions` with the
// OpenAI request/response shape — Ollama, llama.cpp's server, vLLM, LM
// Studio, OpenAI itself. No prompt caching: the same context is sent every
// turn, which is fine for local dev.

async function callOpenAI(
	systemText: string,
	contextPayload: string,
	messages: { role: 'user' | 'assistant'; content: string }[],
	tier: Tier,
	limits: typeof TIER_LIMITS[Tier],
	headers: Record<string, string>,
): Promise<Response> {
	const convo = [
		{ role: 'system', content: systemText },
		{ role: 'user', content: contextPayload },
		{ role: 'assistant', content: 'Got it — I have your plan and recent runs in view. Ask away.' },
		...messages.map((m) => ({ role: m.role, content: m.content }))
	];

	const res = await fetch(`${OPENAI_BASE_URL.replace(/\/$/, '')}/chat/completions`, {
		method: 'POST',
		headers: {
			'content-type': 'application/json',
			authorization: `Bearer ${OPENAI_API_KEY}`
		},
		body: JSON.stringify({
			model: OPENAI_MODEL,
			messages: convo,
			max_tokens: limits.maxTokens,
			stream: false
		})
	});

	if (!res.ok) {
		const errText = await res.text().catch(() => '');
		throw new Error(`coach upstream ${res.status}: ${errText.slice(0, 400)}`);
	}

	const json = (await res.json()) as {
		choices?: { message?: { content?: string } }[];
		usage?: { prompt_tokens?: number; completion_tokens?: number };
	};
	const text = json.choices?.[0]?.message?.content ?? '';
	return new Response(
		JSON.stringify({
			reply: text,
			tier,
			limits: {
				daily_limit: Number.isFinite(limits.dailyLimit) ? limits.dailyLimit : null,
				max_tokens: limits.maxTokens,
				max_runs_limit: limits.maxRunsLimit,
			},
			cache: {
				cache_creation_input_tokens: 0,
				cache_read_input_tokens: 0,
				input_tokens: json.usage?.prompt_tokens ?? 0,
				output_tokens: json.usage?.completion_tokens ?? 0
			}
		}),
		{ headers }
	);
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
- Assume the runner is an informed adult. Don't hedge every sentence with "if it feels right to you".`;

// ─────────────────────── Context builder ───────────────────────

interface CoachContext {
	data?: unknown;
	error?: string;
}

async function buildContext(
	supabase: SupabaseClient,
	planId: string | null,
	runsLimit: number
): Promise<CoachContext> {
	const { data: { user }, error: uErr } = await supabase.auth.getUser();
	if (uErr || !user) return { error: 'not authenticated' };

	// Pull the active (or specified) plan + its weeks + its workouts, plus
	// the last ~20 runs. RLS scopes all of these to the current user.
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
		.eq('id', user.id)
		.maybeSingle();

	const { data: userSettings } = await supabase
		.from('user_settings')
		.select('prefs')
		.eq('user_id', user.id)
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
			recent_runs: recentRuns ?? []
		}
	};
}
