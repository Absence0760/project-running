// Network glue for the route-builder "Describe the route you want" box —
// the REQUEST half of the AI route assistant. It posts the user's NL
// request (plus an optional location label) to the Pro-gated extractor
// endpoint and resolves to a validated `RouteConstraints` object the page
// maps onto the generator form.
//
// Unlike route_describe_client (which has a templated baseline and treats
// a 200/template as the normal not-Pro shape), the request side has NO
// deterministic fallback — the manual form IS the fallback. So this
// throws a typed `RouteRequestError` on every non-200, and the caller
// keeps the manual generator working. It refreshes the JWT once on a 401,
// mirroring CoachChat + route_describe_client.

import { supabase } from '../core/supabase';
import type { RouteConstraints } from './route_request/constraints';

export type { RouteConstraints } from './route_request/constraints';

/// Kinds the UI distinguishes: `upgrade` shows the Pro upsell, everything
/// else shows a generic "couldn't read that — use the form" hint. Keeping
/// these typed (not string-matched HTTP codes) lets the page branch
/// cleanly.
export type RouteRequestErrorKind =
	| 'not_authenticated'
	| 'upgrade'
	| 'invalid'
	| 'not_understood'
	| 'unavailable';

export class RouteRequestError extends Error {
	kind: RouteRequestErrorKind;
	constructor(kind: RouteRequestErrorKind, message?: string) {
		super(message ?? kind);
		this.name = 'RouteRequestError';
		this.kind = kind;
	}
}

function errorForStatus(status: number): RouteRequestErrorKind {
	if (status === 401) return 'not_authenticated';
	if (status === 403) return 'upgrade';
	if (status === 400) return 'invalid';
	if (status === 422) return 'not_understood';
	return 'unavailable';
}

/**
 * Extract validated route-generation constraints from a plain-English
 * request. Resolves with the constraints on success; throws a
 * `RouteRequestError` on any failure (the caller keeps the manual form).
 */
export async function requestRouteConstraints(
	request: string,
	locationLabel?: string | null,
): Promise<RouteConstraints> {
	const body = JSON.stringify({
		request,
		location_label: locationLabel ?? null,
	});
	const post = (token: string) =>
		fetch('/api/coach/route-request', {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				'X-Supabase-Authorization': `Bearer ${token}`,
			},
			body,
		});

	let token = (await supabase.auth.getSession()).data.session?.access_token;
	if (!token) throw new RouteRequestError('not_authenticated');

	let res = await post(token);
	if (res.status === 401) {
		// Stale JWT — refresh once and replay, same as CoachChat.
		try {
			const refreshed = await supabase.auth.refreshSession();
			token = refreshed.data.session?.access_token ?? token;
			res = await post(token);
		} catch (_) {
			/* fall through to the status check below */
		}
	}

	if (!res.ok) {
		throw new RouteRequestError(errorForStatus(res.status));
	}

	const data = (await res.json().catch(() => null)) as {
		constraints?: RouteConstraints;
	} | null;
	if (!data || typeof data.constraints !== 'object' || data.constraints === null) {
		throw new RouteRequestError('unavailable');
	}
	return data.constraints;
}
