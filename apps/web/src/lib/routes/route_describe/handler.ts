// Transport-agnostic handler for the AI route-description enhancement.
//
// The templated describer (`$lib/routes/route_description`) is the
// always-works L1 baseline and is rendered for everyone, free or Pro,
// with no network call. This handler is the strictly-additive L4
// enhancement: a Pro perk that asks Claude to turn the templated facts
// into a richer, more evocative paragraph. It is fail-closed on the
// paywall and degrades to the templated text on every failure mode —
// not-Pro, unconfigured key, model error, model refusal, or timeout —
// so the affordance never breaks the baseline.
//
// Wrapped twice, exactly like the coach handler (decisions.md § 53):
//   - apps/web/src/routes/api/coach/route-describe/+server.ts (dev)
//   - apps/web/lambda/coach/src/index.ts routes /route-describe (prod)
//
// Single non-streaming request — a route description is one short
// paragraph, well under the streaming-timeout threshold, so there's no
// SSE protocol here. Always returns JSON.

import Anthropic from '@anthropic-ai/sdk';
import { createClient } from '@supabase/supabase-js';

import {
	assembleEnglish,
	describeRoute,
	type RouteDescriptionInput,
} from '../route_description';
import { parseAuthHeader } from '../../coach/limits';

/**
 * Model + budget for the enhancement. The visible output is one short
 * 2-3 sentence paragraph, but adaptive thinking draws from the same
 * `max_tokens` ceiling — so the cap has to leave room for a thinking
 * block *plus* the paragraph, or the model can spend the budget thinking
 * and return empty text (which would then fall back to the template).
 * 1024 comfortably covers both; the prose itself stays short because the
 * system prompt asks for one paragraph. No streaming — well under the
 * streaming-timeout threshold.
 */
const ROUTE_DESCRIBE_MODEL = 'claude-opus-4-8';
const ROUTE_DESCRIBE_MAX_TOKENS = 1024;

/** Hard wall-clock cap so a slow model call can't hang the request. */
const ROUTE_DESCRIBE_TIMEOUT_MS = 12_000;

/**
 * Cap on the inbound name — the only free-text field that reaches the
 * prompt. The rest of the input is numeric. Names longer than this are
 * almost certainly junk / an injection attempt; truncate rather than
 * reject so a legitimately long name still yields a description.
 */
export const MAX_ROUTE_NAME_CHARS = 200;

export interface RouteDescribeConfig {
	anthropicApiKey: string | undefined;
	publicSupabaseUrl: string;
	publicSupabaseAnonKey: string;
	/** Dev-only escape hatch — see the +server.ts / Lambda gates. */
	bypassPaywallEnabled: boolean;
}

export interface RouteDescribeResult {
	status: number;
	headers: Record<string, string>;
	body: string;
}

function json(
	status: number,
	payload: Record<string, unknown>,
): RouteDescribeResult {
	return {
		status,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(payload),
	};
}

/**
 * Coerce an untrusted request body into a `RouteDescriptionInput`.
 * Returns null when the body can't yield a usable input (no numeric
 * distance). Numbers are passed through to `describeRoute`, which does
 * its own NaN / negative clamping, so we only need shape validation
 * here.
 */
function parseInput(raw: unknown): RouteDescriptionInput | null {
	if (!raw || typeof raw !== 'object') return null;
	const o = raw as Record<string, unknown>;
	if (typeof o.distance_m !== 'number') return null;
	const name =
		typeof o.name === 'string' ? o.name.slice(0, MAX_ROUTE_NAME_CHARS) : 'This route';
	const surface =
		o.surface === 'road' || o.surface === 'trail' || o.surface === 'mixed'
			? o.surface
			: null;
	const pt = (v: unknown): { lat: number; lng: number } | undefined => {
		if (!v || typeof v !== 'object') return undefined;
		const p = v as Record<string, unknown>;
		return typeof p.lat === 'number' && typeof p.lng === 'number'
			? { lat: p.lat, lng: p.lng }
			: undefined;
	};
	return {
		name,
		distanceM: o.distance_m,
		elevationM: typeof o.elevation_m === 'number' ? o.elevation_m : null,
		surface,
		start: pt(o.start),
		end: pt(o.end),
	};
}

const SYSTEM_PROMPT =
	'You write short, vivid descriptions of running routes for a running app. ' +
	'You are given the verified facts about one route (distance, surface, ' +
	'elevation character, shape). Write ONE paragraph of 2-3 sentences that a ' +
	'runner browsing routes would find useful and inviting. Stay strictly ' +
	'grounded in the facts provided — do not invent landmarks, scenery, ' +
	'difficulty ratings, or place names that are not in the facts. Do not use ' +
	'markdown, headings, or bullet points. Return only the paragraph.';

/**
 * Enhance a route description with Claude. Always resolves to a
 * `RouteDescribeResult` carrying a `description` and a `source`
 * (`'ai'` when the model produced it, `'template'` on any fallback) so
 * the client can show the right attribution. Never throws — the
 * templated text is the floor.
 */
export async function handleRouteDescribe(
	authHeader: string | null,
	rawBody: unknown,
	config: RouteDescribeConfig,
): Promise<RouteDescribeResult> {
	const input = parseInput(rawBody);
	if (!input) return json(400, { error: 'invalid route input' });

	// The templated description is computed up front: it's the response
	// on every non-200-worthy branch below, and the prose the model is
	// asked to enhance.
	const parts = describeRoute(input);
	const templated = assembleEnglish(parts, input.name);

	const accessToken = parseAuthHeader(authHeader);
	if (!accessToken) return json(401, { error: 'not authenticated' });

	const supabase = createClient(config.publicSupabaseUrl, config.publicSupabaseAnonKey, {
		global: { headers: { Authorization: `Bearer ${accessToken}` } },
	});
	const userRes = await supabase.auth.getUser(accessToken);
	if (!userRes.data.user) {
		// Mirror the coach handler: log the detail, return a generic 401
		// so the GoTrue error can't be used as a token-shape oracle.
		console.error('[route-describe] auth failed', {
			tokenPrefix: accessToken.slice(0, 20) + '...',
			error: userRes.error?.message ?? 'no user returned',
		});
		return json(401, { error: 'not authenticated' });
	}

	// Paywall gate — the AI enhancement is a Pro perk. Fail-closed: an
	// RPC error or a non-true result leaves the caller on the templated
	// description with a 403, never silently granting the perk. The
	// bypass is honoured only when the wrapper computed it from the
	// dev-only env gates.
	let isPro = false;
	if (config.bypassPaywallEnabled) {
		isPro = true;
	} else {
		const proRes = await supabase.rpc('is_pro');
		if (proRes.error) {
			console.error('[route-describe] is_pro lookup failed', proRes.error);
			return json(500, { error: 'tier check failed', description: templated, source: 'template' });
		}
		isPro = proRes.data === true;
	}
	if (!isPro) {
		// Not an error — the free tier gets the templated description.
		// 200 with source:'template' + upgrade:true lets the UI surface a
		// "Enhance with AI (Pro)" upsell without a failed-request banner.
		return json(200, {
			description: templated,
			source: 'template',
			upgrade: true,
		});
	}

	// Pro path. Missing key → degrade to templated rather than 503 — the
	// runner still gets a description.
	if (!config.anthropicApiKey) {
		console.error('[route-describe] missing ANTHROPIC_API_KEY — serving templated description');
		return json(200, { description: templated, source: 'template' });
	}

	try {
		const anthropic = new Anthropic({ apiKey: config.anthropicApiKey });
		const message = await anthropic.messages.create(
			{
				model: ROUTE_DESCRIBE_MODEL,
				max_tokens: ROUTE_DESCRIBE_MAX_TOKENS,
				thinking: { type: 'adaptive' },
				system: SYSTEM_PROMPT,
				messages: [
					{
						role: 'user',
						content:
							`Facts about the route:\n${templated}\n\n` +
							`Surface: ${parts.surface ?? 'unspecified'}. ` +
							`Elevation character: ${parts.elevation}. ` +
							`Shape: ${parts.shape}.\n\n` +
							'Write the description paragraph now.',
					},
				],
			},
			{ timeout: ROUTE_DESCRIBE_TIMEOUT_MS },
		);

		// Claude Fable/Opus can return stop_reason: "refusal" (HTTP 200,
		// empty/partial content). Check it before reading content[] —
		// degrade to the templated text on a refusal.
		if (message.stop_reason === 'refusal') {
			console.warn('[route-describe] model refused — serving templated description');
			return json(200, { description: templated, source: 'template' });
		}

		const text = message.content
			.filter((b): b is Anthropic.TextBlock => b.type === 'text')
			.map((b) => b.text)
			.join('')
			.trim();

		if (!text) {
			// Empty completion (hit max_tokens before any text, etc.) —
			// fall back rather than show a blank box.
			return json(200, { description: templated, source: 'template' });
		}
		return json(200, { description: text, source: 'ai' });
	} catch (e) {
		// Any provider failure (rate limit, timeout, 5xx, network) →
		// templated description. Layered resilience: the L4 enhancement
		// can never break the L1 baseline.
		console.error('[route-describe] provider call failed — serving templated description', e);
		return json(200, { description: templated, source: 'template' });
	}
}
