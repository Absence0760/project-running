// Transport-agnostic handler for the AI route-request enhancement — the
// REQUEST half of the AI route assistant (the DESCRIBE half lives in
// `$lib/routes/route_describe/handler`). It turns a plain-English request
// ("a flat 10k loop avoiding main roads") into a STRICTLY-VALIDATED
// constraints object the existing deterministic generator already
// understands.
//
// Hard line (docs/features/ai_route_assistant.md § Core principle): the
// LLM is the interface, not the router. It only extracts intent via
// tool-use; the graph engine owns correctness. Every extracted field is
// re-validated / clamped server-side in `validateConstraints` before it
// can reach the generator — a hallucinated number is dropped, never
// executed.
//
// Pro-gated, fail-closed: an unknown Pro status (RPC error) makes the
// feature unavailable rather than silently granting it. The manual form
// is unaffected on every failure mode (the NL box is purely additive),
// so this handler returns a structured error and the client keeps the
// manual generator working.
//
// Wrapped twice, exactly like the route-describe + coach handlers
// (decisions.md § 53):
//   - apps/web/src/routes/api/coach/route-request/+server.ts (dev)
//   - apps/web/lambda/coach/src/index.ts routes /route-request (prod)
//
// Single non-streaming tool-use request — one small constraint object,
// well under the streaming-timeout threshold. Always returns JSON.

import Anthropic from '@anthropic-ai/sdk';
import { createClient } from '@supabase/supabase-js';

import { parseAuthHeader } from '../../coach/limits';
import { validateConstraints, type RouteConstraints } from './constraints';

/// Matches the model used by route-describe + the coach (decisions.md;
/// claude-api skill: default to Opus 4.8 with adaptive thinking).
const ROUTE_REQUEST_MODEL = 'claude-opus-4-8';

/// Tool-use output is one small JSON object; adaptive thinking draws from
/// the same ceiling, so leave headroom for a thinking block plus the
/// tool_use block. 1024 mirrors route-describe.
const ROUTE_REQUEST_MAX_TOKENS = 1024;

/// Hard wall-clock cap so a slow model call can't hang the request.
const ROUTE_REQUEST_TIMEOUT_MS = 12_000;

/// Cap on the inbound NL string — the only free-text field that reaches
/// the prompt. A request longer than this is junk or an injection
/// attempt; truncate rather than reject so a verbose-but-legitimate
/// request still yields constraints.
export const MAX_REQUEST_TEXT_CHARS = 600;

export interface RouteRequestConfig {
	anthropicApiKey: string | undefined;
	publicSupabaseUrl: string;
	publicSupabaseAnonKey: string;
	/// Dev-only escape hatch — see the +server.ts / Lambda gates.
	bypassPaywallEnabled: boolean;
}

export interface RouteRequestResult {
	status: number;
	headers: Record<string, string>;
	body: string;
}

function json(status: number, payload: Record<string, unknown>): RouteRequestResult {
	return {
		status,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(payload),
	};
}

interface ParsedInput {
	requestText: string;
	/// Caller's location context, passed verbatim into the prompt as a
	/// human hint only ("near my current location"). It does NOT set the
	/// generator's start point — that stays the user's explicit pick /
	/// map centre on the client. We never send raw coordinates to the
	/// model: a place label is enough for intent and avoids egressing a
	/// precise location into the prompt (privacy: same posture as the
	/// coach, sub-processor already disclosed).
	locationLabel: string | null;
}

function parseInput(raw: unknown): ParsedInput | null {
	if (!raw || typeof raw !== 'object') return null;
	const o = raw as Record<string, unknown>;
	if (typeof o.request !== 'string') return null;
	const requestText = o.request.trim().slice(0, MAX_REQUEST_TEXT_CHARS);
	if (requestText.length === 0) return null;
	const locationLabel =
		typeof o.location_label === 'string' && o.location_label.trim().length > 0
			? o.location_label.trim().slice(0, MAX_REQUEST_TEXT_CHARS)
			: null;
	return { requestText, locationLabel };
}

const SYSTEM_PROMPT =
	'You translate a runner\'s plain-English route request into structured ' +
	'generation constraints for a route-planning app. You do NOT plan or ' +
	'describe routes — you only extract the request into the tool schema. ' +
	'Always call the extract_route_constraints tool exactly once. Infer ' +
	'distance in METRES (e.g. "10k" = 10000, "a couple of miles" = 3200). ' +
	'Map "loop"/"round trip back to start" to loop, "out and back" to ' +
	'out_and_back, and a request that names a different finish to ' +
	'point_to_point. Map "avoid main roads/highways/busy roads/traffic" to ' +
	'avoid_highways=true. Map "trail/off-road/park paths" to surface trail, ' +
	'"roads/pavement/sidewalk" to road, and a mix to mixed. Omit any field ' +
	'the request does not specify — do not guess.';

const EXTRACT_TOOL: Anthropic.Tool = {
	name: 'extract_route_constraints',
	description:
		'Record the route-generation constraints extracted from the user\'s ' +
		'request. Only include fields the request actually specifies.',
	input_schema: {
		type: 'object',
		properties: {
			distance_m: {
				type: 'number',
				description:
					'Target distance in metres. Convert km/miles to metres. Omit if unspecified.',
			},
			shape: {
				type: 'string',
				enum: ['loop', 'out_and_back', 'point_to_point'],
				description: 'Route shape. Omit if unspecified.',
			},
			surface: {
				type: 'string',
				enum: ['road', 'trail', 'mixed'],
				description: 'Preferred surface. Omit if unspecified.',
			},
			avoid_highways: {
				type: 'boolean',
				description:
					'True when the runner wants to avoid main / busy roads and highways. Omit if unspecified.',
			},
		},
	},
};

/**
 * Extract validated route-generation constraints from an NL request.
 * Always resolves to a `RouteRequestResult`. The success body carries a
 * `constraints` object (already clamped/whitelisted) the client maps onto
 * the generator form. Never throws — but, unlike route-describe, there is
 * no deterministic fallback for the request side (the manual form IS the
 * fallback), so non-Pro / failure paths return a structured non-200 the
 * client treats as "NL unavailable, keep using the manual form".
 */
export async function handleRouteRequest(
	authHeader: string | null,
	rawBody: unknown,
	config: RouteRequestConfig,
): Promise<RouteRequestResult> {
	const input = parseInput(rawBody);
	if (!input) return json(400, { error: 'invalid route request' });

	const accessToken = parseAuthHeader(authHeader);
	if (!accessToken) return json(401, { error: 'not authenticated' });

	const supabase = createClient(config.publicSupabaseUrl, config.publicSupabaseAnonKey, {
		global: { headers: { Authorization: `Bearer ${accessToken}` } },
	});
	const userRes = await supabase.auth.getUser(accessToken);
	if (!userRes.data.user) {
		// Mirror the coach / route-describe handlers: log the detail,
		// return a generic 401 so the GoTrue error can't be used as a
		// token-shape oracle.
		console.error('[route-request] auth failed', {
			tokenPrefix: accessToken.slice(0, 20) + '...',
			error: userRes.error?.message ?? 'no user returned',
		});
		return json(401, { error: 'not authenticated' });
	}

	// Paywall gate — fail-closed. An RPC error or a non-true result leaves
	// the caller WITHOUT the perk (the manual form still works). The
	// bypass is honoured only when the wrapper computed it from the
	// dev-only env gates.
	let isPro = false;
	if (config.bypassPaywallEnabled) {
		isPro = true;
	} else {
		const proRes = await supabase.rpc('is_pro');
		if (proRes.error) {
			console.error('[route-request] is_pro lookup failed', proRes.error);
			return json(503, { error: 'route assistant unavailable' });
		}
		isPro = proRes.data === true;
	}
	if (!isPro) {
		// 403 + upgrade:true lets the UI surface a "Pro" upsell on the NL
		// box without implying the manual form failed.
		return json(403, { error: 'pro required', upgrade: true });
	}

	// Pro path. Missing key → 503 (operator config). The client keeps the
	// manual form; there is no deterministic constraint extraction to fall
	// back to.
	if (!config.anthropicApiKey) {
		console.error('[route-request] missing ANTHROPIC_API_KEY');
		return json(503, { error: 'route assistant unavailable' });
	}

	try {
		const anthropic = new Anthropic({ apiKey: config.anthropicApiKey });
		const userContent =
			`Runner's request: ${input.requestText}\n\n` +
			(input.locationLabel
				? `Approximate location: ${input.locationLabel}.\n\n`
				: '') +
			'Call extract_route_constraints with what the request specifies.';

		const message = await anthropic.messages.create(
			{
				model: ROUTE_REQUEST_MODEL,
				max_tokens: ROUTE_REQUEST_MAX_TOKENS,
				thinking: { type: 'adaptive' },
				system: SYSTEM_PROMPT,
				// Force the tool so the output is a typed constraint object,
				// never prose. tool_choice pins the single extraction tool.
				tools: [EXTRACT_TOOL],
				tool_choice: { type: 'tool', name: EXTRACT_TOOL.name },
				messages: [{ role: 'user', content: userContent }],
			},
			{ timeout: ROUTE_REQUEST_TIMEOUT_MS },
		);

		// A safety refusal (HTTP 200, stop_reason: "refusal") yields no
		// usable tool call — surface it as unavailable, manual form unaffected.
		if (message.stop_reason === 'refusal') {
			console.warn('[route-request] model refused');
			return json(422, { error: 'could not understand request' });
		}

		const toolUse = message.content.find(
			(b): b is Anthropic.ToolUseBlock =>
				b.type === 'tool_use' && b.name === EXTRACT_TOOL.name,
		);
		if (!toolUse) {
			// Forced tool_choice should guarantee a tool_use block; if the
			// model still didn't produce one, treat the request as
			// un-extractable rather than 500-ing.
			console.warn('[route-request] no tool_use block in model response');
			return json(422, { error: 'could not understand request' });
		}

		// The single trust boundary: the model's raw input is clamped /
		// whitelisted here before it reaches the client (and the generator).
		const constraints: RouteConstraints = validateConstraints(toolUse.input);
		return json(200, { constraints });
	} catch (e) {
		// Any provider failure (rate limit, timeout, 5xx, network) → 503.
		// The NL box shows "unavailable, use the form"; the manual
		// generator is untouched.
		console.error('[route-request] provider call failed', e);
		return json(503, { error: 'route assistant unavailable' });
	}
}
