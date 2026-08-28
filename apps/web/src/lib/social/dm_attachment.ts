/**
 * What a message bubble renders, given the typed route attachment
 * (`direct_messages.route_id`, migration `20270619_001`) and how far its
 * resolution has got.
 *
 * The four states are kept apart deliberately, and two of the separations are
 * the whole point of the module:
 *
 * - `unavailable` never collapses to `text`. A route the reader may not see —
 *   deleted, flipped private, or never visible to them — would then render as
 *   an ordinary message whose body is a share URL that 404s, and the reader
 *   would have no way to tell "this route is gone" from "someone typed a
 *   link". Same rule `fetchDmThread` follows by throwing instead of degrading
 *   to an empty conversation.
 * - `pending` never collapses to `card`. A card drawn before the route
 *   resolves is a route with no name and no trace, which reads as a broken
 *   route rather than as one still loading.
 */

export interface DmRouteCard {
	id: string;
	/// Null when the row's name is blank — the render supplies a localized
	/// fallback rather than an empty heading. `routes.name` is `not null` but
	/// carries no length CHECK, so whitespace is reachable.
	name: string | null;
	distanceM: number | null;
	waypoints: Array<{ lat: number; lng: number }>;
}

export type DmAttachmentResolution =
	| { status: 'pending' }
	| { status: 'resolved'; route: DmRouteCard | null };

export type DmAttachmentView =
	| { kind: 'text' }
	| { kind: 'pending' }
	| { kind: 'card'; route: DmRouteCard }
	| { kind: 'unavailable' };

/// An empty or whitespace id is not an attachment. Treating it as one leaves
/// a skeleton in the thread that nothing will ever resolve.
export function hasDmRouteAttachment(routeId: string | null | undefined): routeId is string {
	return !!routeId && routeId.trim().length > 0;
}

export function dmAttachmentView(
	routeId: string | null | undefined,
	resolution: DmAttachmentResolution | undefined,
): DmAttachmentView {
	if (!hasDmRouteAttachment(routeId)) return { kind: 'text' };
	if (!resolution || resolution.status === 'pending') return { kind: 'pending' };
	return resolution.route ? { kind: 'card', route: resolution.route } : { kind: 'unavailable' };
}

/**
 * Whether the message body says nothing the card does not already say.
 *
 * v1 sent the public `/share/route/[id]` URL AS the body, and v2 keeps doing
 * so — the URL is the forwardable artifact the send dialog explicitly promises
 * the recipient gets, and it is what stays readable in the Art 20 export and
 * in the inbox preview line, neither of which resolves an attachment. On
 * screen it is pure duplication once the card renders, so it is suppressed
 * THERE and nowhere else.
 *
 * The test is deliberately narrow: only a URL pointing at THIS route's own
 * share or detail path is redundant. Anything a human could have typed —
 * including a link to some other route — is the sender's own words and
 * renders beside the card.
 */
export function bodyRestatesAttachment(body: string, routeId: string): boolean {
	const trimmed = body.trim();
	if (!trimmed || !routeId.trim()) return false;
	let path: string;
	try {
		path = new URL(trimmed).pathname;
	} catch {
		return false;
	}
	const normalised = path.replace(/\/+$/, '').toLowerCase();
	const id = routeId.trim().toLowerCase();
	return normalised === `/share/route/${id}` || normalised === `/routes/${id}`;
}

/**
 * Narrow a route read through `fetchRouteById` into what the card draws.
 * The waypoints it hands over are already the reader's own view of the line —
 * unclipped for the owner, privacy-zone-clipped by `clip_route_for_viewer`
 * for everyone else — so this never widens a read; it only drops the columns
 * the card has no use for.
 */
export function dmRouteCardFrom(route: {
	id: string;
	name?: string | null;
	distance_m?: number | string | null;
	waypoints?: unknown;
}): DmRouteCard {
	const name = typeof route.name === 'string' ? route.name.trim() : '';
	const distance = Number(route.distance_m);
	return {
		id: route.id,
		name: name || null,
		distanceM: Number.isFinite(distance) && distance > 0 ? distance : null,
		waypoints: Array.isArray(route.waypoints)
			? (route.waypoints.filter(
					(p): p is { lat: number; lng: number } =>
						!!p &&
						typeof p === 'object' &&
						Number.isFinite((p as { lat?: unknown }).lat) &&
						Number.isFinite((p as { lng?: unknown }).lng),
				) as Array<{ lat: number; lng: number }>)
			: [],
	};
}

/// A card with fewer than two usable points has no line to draw. The trace
/// failing is not the route failing — `fetchClippedRouteForViewer` fails
/// closed to `[]` — so the card still renders its name and distance and only
/// the thumbnail falls back to a placeholder.
export function dmRouteCardHasTrace(card: DmRouteCard): boolean {
	return card.waypoints.length > 1;
}
