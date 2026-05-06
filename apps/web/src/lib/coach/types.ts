// Shared types for the coach handler. Same shapes used by:
//   - apps/web/src/routes/api/coach/+server.ts (SvelteKit, dev-only —
//     under adapter-static this route is not built)
//   - apps/web/lambda/coach/src/index.ts (AWS Lambda Function URL
//     handler with response streaming, prod)
//
// See decisions.md § 53.

export type CoachMode = 'send' | 'regenerate' | 'edit';

export interface CoachRequestBody {
	messages: { role: 'user' | 'assistant'; content: string }[];
	plan_id?: string;
	recent_runs_limit?: number;
	mode?: CoachMode;
	// Anchor for regenerate / edit. The server deletes this message and
	// every later message in the same (user, plan, archived_at=null)
	// thread before running.
	anchor_message_id?: string;
}

export interface CoachConfig {
	// 'anthropic' (default, prod) or 'openai' (Ollama/OpenAI-compatible
	// for local dev). Read from COACH_PROVIDER env var.
	provider: 'anthropic' | 'openai';

	// Anthropic-only.
	anthropicApiKey?: string;

	// OpenAI-compatible-only. baseUrl points at e.g. http://localhost:11434/v1
	// for Ollama. apiKey + model carry through to the request body.
	openaiBaseUrl?: string;
	openaiApiKey?: string;
	openaiModel?: string;

	// Used by both providers — the Lambda calls Supabase as the user
	// (forwards their JWT) for paywall checks, quota increments, and
	// context reads.
	publicSupabaseUrl: string;
	publicSupabaseAnonKey: string;

	// Pre-computed by the caller. True iff the bypass is honoured. The
	// caller is responsible for the prod-env gate (NODE_ENV check +
	// localhost-Supabase check in the SvelteKit dev wrapper; hardcoded
	// `false` in the production Lambda). The handler does not re-read
	// env, but it logs a loud warning when this is true so any
	// accidental prod activation shows up immediately in CloudWatch.
	bypassPaywallEnabled: boolean;
}

export type CoachResult =
	| {
			// Pre-stream failure (auth, rate-limit, validation). Plain
			// JSON response, no streaming.
			kind: 'json';
			status: number;
			headers: Record<string, string>;
			body: string;
	  }
	| {
			// Happy path. SSE stream of one event per line, blank line
			// terminates each event.
			kind: 'sse';
			status: 200;
			headers: Record<string, string>;
			body: AsyncIterable<Uint8Array>;
	  };

export interface ProviderUsage {
	cache_creation_input_tokens: number;
	cache_read_input_tokens: number;
	input_tokens: number;
	output_tokens: number;
}

export interface ProviderStream {
	tokens: AsyncIterable<string>;
	finalUsage: () => Promise<ProviderUsage>;
}

// Pro `maxRunsLimit` was lowered from 200 to 75 in audit pass 3.
// 200 runs JSON-serialised in the runner-profile context dump
// dominated input-token cost on every Pro turn — a sustained-abuse
// scenario (50 turns/day × ~500k input tokens) projected to ~$75/day
// per stolen account. 75 runs is enough for an experienced coach
// session to reason about a 12-week training block.
export const TIER_LIMITS = {
	free: { dailyLimit: 5, maxTokens: 768, maxRunsLimit: 30 },
	pro: { dailyLimit: Number.POSITIVE_INFINITY, maxTokens: 2048, maxRunsLimit: 75 },
} as const;

// Per-user-id rate limit applied to Pro callers, decoupled from the
// daily cap (which is unlimited for Pro). 60 turns / hour is well
// above legitimate use (a sustained chat is ~6 turns / hour at most)
// but bounds a stolen Pro session token to one Lambda execution every
// minute — within the WAF rate limit and the reserved concurrency
// cap. Free callers are already capped at 5/day so this gate doesn't
// fire for them; the hourly window plus the daily cap is the floor.
export const PRO_HOURLY_RATE_LIMIT = 60;

export type Tier = keyof typeof TIER_LIMITS;

export function emptyUsage(): ProviderUsage {
	return {
		cache_creation_input_tokens: 0,
		cache_read_input_tokens: 0,
		input_tokens: 0,
		output_tokens: 0,
	};
}
