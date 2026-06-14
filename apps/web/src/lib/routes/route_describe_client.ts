// Network glue for the route-detail "Describe this route" affordance.
//
// The pure, locale/unit-aware templated renderer lives in
// `route_description.ts` (`localisedTemplate`) so it stays free of the
// SvelteKit `$env` graph and unit-testable. This module is the part that
// needs the Supabase client + fetch: it posts the route's stats to the
// Pro-gated enhancement endpoint and resolves to `{ description, source,
// upgrade }`. It refreshes the JWT once on a 401, mirroring CoachChat.
// The endpoint itself degrades to the templated text on every failure,
// so a 200 with `source:'template'` is the normal not-Pro / fallback
// shape; callers only treat a non-200 (or a thrown fetch) as a hard
// error and keep the locally-rendered baseline.

import { supabase } from '../core/supabase';
import type { RouteDescriptionInput } from './route_description';

export interface AiDescriptionResult {
	description: string;
	/** 'ai' when the model produced it, 'template' on any server fallback. */
	source: 'ai' | 'template';
	/** True when the server declined because the caller isn't Pro. */
	upgrade: boolean;
}

/** Map the route's stored fields into the endpoint's request body. */
function toBody(input: RouteDescriptionInput): Record<string, unknown> {
	return {
		name: input.name,
		distance_m: input.distanceM,
		elevation_m: input.elevationM,
		surface: input.surface,
		start: input.start ?? null,
		end: input.end ?? null,
	};
}

/**
 * Request an AI-enhanced description. Throws only on a non-200 response
 * or a network failure — a 200 with `source:'template'` (not-Pro, or the
 * server's own fallback) is a normal, non-throwing result.
 */
export async function requestAiDescription(
	input: RouteDescriptionInput,
): Promise<AiDescriptionResult> {
	const post = (token: string) =>
		fetch('/api/coach/route-describe', {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				'X-Supabase-Authorization': `Bearer ${token}`,
			},
			body: JSON.stringify(toBody(input)),
		});

	let token = (await supabase.auth.getSession()).data.session?.access_token;
	if (!token) throw new Error('not_authenticated');

	let res = await post(token);
	if (res.status === 401) {
		// Stale JWT — refresh once and replay, same as CoachChat.
		try {
			const refreshed = await supabase.auth.refreshSession();
			token = refreshed.data.session?.access_token ?? token;
			res = await post(token);
		} catch (_) {
			/* fall through to the error check below */
		}
	}

	if (!res.ok) {
		throw new Error(`route_describe_failed_${res.status}`);
	}
	const json = (await res.json()) as {
		description?: string;
		source?: string;
		upgrade?: boolean;
	};
	if (typeof json.description !== 'string') {
		throw new Error('route_describe_malformed');
	}
	return {
		description: json.description,
		source: json.source === 'ai' ? 'ai' : 'template',
		upgrade: json.upgrade === true,
	};
}
