// Claude-powered coach endpoint.
//
// Role: "second opinion" on the runner's plan + recent runs. Does NOT
// generate plans or prescribe training — see docs/decisions.md #12.
// Answers "should I run tomorrow?", "am I on pace for my goal?", "my last
// three long runs were slow, what's going on?" — grounded in real data.
//
// Prompt-caching layout:
//   system → the coach-persona prompt                       (cache)
//   first user message → plan + recent runs context dump    (cache)
//   subsequent user messages → the live chat                (no cache)
//
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

const ANTHROPIC_API_KEY = env.ANTHROPIC_API_KEY;

interface CoachRequest {
	messages: { role: 'user' | 'assistant'; content: string }[];
	plan_id?: string;
	access_token: string; // user's Supabase JWT — used to scope the data pull
}

export const POST: RequestHandler = async ({ request }) => {
	if (!ANTHROPIC_API_KEY) {
		return new Response(
			JSON.stringify({
				error:
					'Coach is not configured — set ANTHROPIC_API_KEY in the web app env.'
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

	// Daily usage limit for free users. Pro subscribers are unlimited.
	// BYPASS_PAYWALL skips the check in dev so you don't burn through the
	// quota while iterating on prompts.
	const DAILY_LIMIT = 10;
	const bypassLimit = env.BYPASS_PAYWALL === 'true';
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
		if (isPro !== true) {
			const { data: newCount } = await supabase.rpc('increment_coach_usage', {
				p_user_id: authUser.id,
			});
			if (typeof newCount === 'number' && newCount > DAILY_LIMIT) {
				return new Response(
					JSON.stringify({
						error: 'daily_limit',
						message: `You've used all ${DAILY_LIMIT} coach messages for today. Upgrade to Pro for unlimited chats, or come back tomorrow!`,
						used: newCount,
						limit: DAILY_LIMIT,
					}),
					{ status: 429, headers: { 'content-type': 'application/json' } }
				);
			}
		}
	}

	const context = await buildContext(supabase, body.plan_id ?? null);
	if (context.error) {
		return new Response(JSON.stringify({ error: context.error }), {
			status: 401,
			headers: { 'content-type': 'application/json' }
		});
	}

	const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

	const personality = (context.data as Record<string, unknown>)?.runner_context as Record<string, unknown> | undefined;
	const coachStyle = personality?.coach_personality as string | undefined;
	let personalityAddendum = '';
	if (coachStyle === 'drill_sergeant') {
		personalityAddendum = '\n\nTone override: be blunt, demanding, and no-nonsense. Push the runner hard. Short sentences. No coddling. Think military coach.';
	} else if (coachStyle === 'analytical') {
		personalityAddendum = '\n\nTone override: be data-driven and precise. Lead with numbers, percentages, and trends. Cite specific paces, distances, and dates. Think sports scientist.';
	}
	// 'supportive' is the default tone in COACH_SYSTEM_PROMPT — no addendum needed.

	const systemBlocks = [
		{
			type: 'text' as const,
			text: COACH_SYSTEM_PROMPT + personalityAddendum,
			cache_control: { type: 'ephemeral' as const }
		}
	];

	// First user message sent on every request carries the grounded context.
	// Marked cache_control so repeat turns with the same plan/runs hit a
	// cached prefix; only the chat tail re-tokenises.
	const contextPayload =
		'CONTEXT (runner profile, active plan, recent runs):\n' +
		JSON.stringify(context.data, null, 2);

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
			content:
				'Got it — I have your plan and recent runs in view. Ask away.'
		},
		...body.messages.map((m) => ({
			role: m.role,
			content: [{ type: 'text' as const, text: m.content }]
		}))
	];

	try {
		const res = await anthropic.messages.create({
			model: 'claude-sonnet-4-5',
			max_tokens: 1024,
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
				cache: {
					cache_creation_input_tokens:
						res.usage.cache_creation_input_tokens ?? 0,
					cache_read_input_tokens: res.usage.cache_read_input_tokens ?? 0,
					input_tokens: res.usage.input_tokens,
					output_tokens: res.usage.output_tokens
				}
			}),
			{ headers: { 'content-type': 'application/json' } }
		);
	} catch (e) {
		const msg = e instanceof Error ? e.message : 'coach call failed';
		return new Response(JSON.stringify({ error: msg }), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}
};

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
	planId: string | null
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
		.limit(20);

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
