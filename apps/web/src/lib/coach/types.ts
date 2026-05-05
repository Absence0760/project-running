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

	// Pre-computed by the caller from env (VERCEL_ENV, NODE_ENV,
	// BYPASS_PAYWALL). True iff the bypass is honoured. The handler
	// trusts this — it does NOT re-read env. The caller is responsible
	// for the prod-env gate.
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

export const TIER_LIMITS = {
	free: { dailyLimit: 5, maxTokens: 768, maxRunsLimit: 30 },
	pro: { dailyLimit: Number.POSITIVE_INFINITY, maxTokens: 2048, maxRunsLimit: 200 },
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
