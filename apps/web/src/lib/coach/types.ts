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

	// Service-role key, used ONLY to persist the assistant message
	// (handler.ts). Since migration 20261122_001 the coach_messages
	// INSERT policy confines clients — and the user-JWT client the
	// handler otherwise uses — to role='user' rows (XSS audit H1), so
	// the assistant turn must be written by an RLS-bypassing role.
	// Optional: if unset (e.g. a dev env that hasn't configured it),
	// assistant persistence is skipped with a logged warning and the
	// rest of the coach flow still works. Never logged, never sent to
	// the provider (system_prompt.test.ts guards prompt leakage).
	supabaseServiceRoleKey?: string;

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

// Both tiers carry a finite daily cap. Pro was previously uncapped;
// it was lowered to 10/day in May 2026 to bound worst-case Anthropic
// spend per stolen Pro session token (~$0.50/day at 10×2048 output
// tokens + ~50k input tokens). Free at 2/day is generous enough to
// let a new user have a real exchange with the coach (one prompt +
// one clarifying follow-up) before deciding whether to upgrade.
// Pro `maxRunsLimit` was lowered from 200 to 75 in audit pass 3.
// 200 runs JSON-serialised in the runner-profile context dump
// dominated input-token cost on every Pro turn — a sustained-abuse
// scenario (50 turns/day × ~500k input tokens) projected to ~$75/day
// per stolen account. 75 runs is enough for an experienced coach
// session to reason about a 12-week training block.
export const TIER_LIMITS = {
	free: { dailyLimit: 2, maxTokens: 768, maxRunsLimit: 30 },
	pro: { dailyLimit: 10, maxTokens: 2048, maxRunsLimit: 75 },
} as const;

export type Tier = keyof typeof TIER_LIMITS;

export function emptyUsage(): ProviderUsage {
	return {
		cache_creation_input_tokens: 0,
		cache_read_input_tokens: 0,
		input_tokens: 0,
		output_tokens: 0,
	};
}
