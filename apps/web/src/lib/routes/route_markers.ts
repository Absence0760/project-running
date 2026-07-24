/**
 * Course markers on a route — aid stations, cutoffs, crew/parking access,
 * hazards, notes, climbs (migration 20270129_001, route_markers table).
 *
 * Pure, locale- and unit-agnostic logic shared by the map layer and the
 * course-schedule list: the kind catalogue (one source of truth for pin
 * colour + which detail fields a kind carries), schedule ordering, the
 * aid-service vocabulary, and cutoff + target-time parse/validation.
 *
 * Distance formatting is deliberately NOT here — the render layer formats
 * `position_m` through the viewer's km/mi preference (units.svelte.ts on
 * web, the Dart formatter on mobile). The per-platform icon glyph is also
 * chosen at the render layer; this catalogue carries only the shared hex
 * colour + i18n label key so a pin looks the same on both platforms.
 *
 * Twin of `apps/mobile_android/lib/route_markers.dart` — keep the kind
 * set, colours, service vocabulary, ordering, cutoff/target rules, edge
 * cases, and test count in lockstep.
 */

export type RouteMarkerKind =
	| 'aid_station'
	| 'cutoff'
	| 'crew_access'
	| 'hazard'
	| 'note'
	| 'climb'
	| 'custom';

/** Which optional detail fields a kind's `meta` bag carries. */
export interface RouteMarkerKindSpec {
	kind: RouteMarkerKind;
	/** i18n key under `routeMarker.kind.*`. */
	labelKey: string;
	/** Shared pin colour (hex) so the map looks identical across platforms. */
	color: string;
	/** Aid services checklist (water / food / …) applies. */
	hasServices: boolean;
	/** A cutoff time (clock and/or elapsed) applies. */
	hasCutoff: boolean;
}

export const ROUTE_MARKER_KINDS: RouteMarkerKindSpec[] = [
	{ kind: 'aid_station', labelKey: 'routeMarker.kind.aid_station', color: '#0e9f6e', hasServices: true, hasCutoff: false },
	{ kind: 'cutoff', labelKey: 'routeMarker.kind.cutoff', color: '#e02424', hasServices: false, hasCutoff: true },
	{ kind: 'crew_access', labelKey: 'routeMarker.kind.crew_access', color: '#3f83f8', hasServices: false, hasCutoff: false },
	{ kind: 'hazard', labelKey: 'routeMarker.kind.hazard', color: '#ff5a1f', hasServices: false, hasCutoff: false },
	{ kind: 'note', labelKey: 'routeMarker.kind.note', color: '#9061f9', hasServices: false, hasCutoff: false },
	{ kind: 'climb', labelKey: 'routeMarker.kind.climb', color: '#c27803', hasServices: false, hasCutoff: false },
	{ kind: 'custom', labelKey: 'routeMarker.kind.custom', color: '#6b7280', hasServices: false, hasCutoff: false }
];

/**
 * A marker is OFFICIAL when it was dropped by the route owner
 * (`marker.user_id === route.user_id`) — authoritative course furniture
 * every viewer who can see the route sees. Any other marker is a
 * viewer's PERSONAL overlay, private to its author. Per the RLS contract
 * (update/delete are own-markers-only), an official marker is read-only
 * to everyone but the owner, so the render layer badges it as the route
 * owner's and hides edit/delete on it from a non-author.
 */
export function isOfficialMarker(
	marker: { user_id: string },
	routeOwnerId: string | null | undefined
): boolean {
	return routeOwnerId != null && marker.user_id === routeOwnerId;
}

const KIND_BY_KEY = new Map<RouteMarkerKind, RouteMarkerKindSpec>(
	ROUTE_MARKER_KINDS.map((k) => [k.kind, k])
);

/** Spec for a kind, falling back to `custom` for an unknown value. */
export function kindSpec(kind: string): RouteMarkerKindSpec {
	return KIND_BY_KEY.get(kind as RouteMarkerKind) ?? KIND_BY_KEY.get('custom')!;
}

/** Aid-station service vocabulary (stored in `meta.services`). */
export type AidService = 'water' | 'food' | 'medical' | 'toilets' | 'drop_bag';

export const AID_SERVICES: AidService[] = ['water', 'food', 'medical', 'toilets', 'drop_bag'];

/** Minimal shape the ordering + summarising helpers need. */
export interface MarkerLike {
	position_m: number | null;
	created_at: string;
}

/**
 * Course-schedule order: by distance along the route (nulls — markers on a
 * route with no geom yet — sort last), then by insertion time so two
 * markers at the same point keep a stable order.
 */
export function sortMarkers<T extends MarkerLike>(markers: T[]): T[] {
	return [...markers].sort((a, b) => {
		if (a.position_m == null && b.position_m == null) {
			return a.created_at.localeCompare(b.created_at);
		}
		if (a.position_m == null) return 1;
		if (b.position_m == null) return -1;
		if (a.position_m !== b.position_m) return a.position_m - b.position_m;
		return a.created_at.localeCompare(b.created_at);
	});
}

export interface CutoffParts {
	/** Wall-clock cutoff "HH:MM" (24h), when set. */
	clock?: string;
	/** Elapsed-time cutoff in seconds from the start, when set. */
	elapsedS?: number;
}

const CLOCK_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

/**
 * Validate + normalise a marker's cutoff `meta` into `CutoffParts`.
 * Returns null when neither a valid clock nor a valid elapsed is present,
 * so callers render a cutoff chip only for a real cutoff. Both platforms
 * must agree on what counts as valid so a cutoff shows identically.
 */
export function parseCutoff(meta: unknown): CutoffParts | null {
	if (meta == null || typeof meta !== 'object') return null;
	const bag = meta as Record<string, unknown>;
	const out: CutoffParts = {};

	const clock = bag.cutoff_clock;
	if (typeof clock === 'string' && CLOCK_RE.test(clock)) {
		out.clock = clock;
	}

	const elapsed = bag.cutoff_elapsed_s;
	if (typeof elapsed === 'number' && Number.isFinite(elapsed) && elapsed >= 0) {
		out.elapsedS = Math.floor(elapsed);
	}

	return out.clock !== undefined || out.elapsedS !== undefined ? out : null;
}

export interface TargetParts {
	/** Wall-clock target "HH:MM" (24h), when set. */
	clock?: string;
	/** Elapsed-time target in seconds from the start, when set. */
	elapsedS?: number;
}

/**
 * Validate + normalise a marker's target-time `meta` into `TargetParts` —
 * the pacing goal a runner aims to reach the marker by, mirroring
 * `parseCutoff`. Any kind may carry a target. Returns null when neither a
 * valid clock nor a valid elapsed is present.
 */
export function parseTarget(meta: unknown): TargetParts | null {
	if (meta == null || typeof meta !== 'object') return null;
	const bag = meta as Record<string, unknown>;
	const out: TargetParts = {};

	const clock = bag.target_clock;
	if (typeof clock === 'string' && CLOCK_RE.test(clock)) {
		out.clock = clock;
	}

	const elapsed = bag.target_elapsed_s;
	if (typeof elapsed === 'number' && Number.isFinite(elapsed) && elapsed >= 0) {
		out.elapsedS = Math.floor(elapsed);
	}

	return out.clock !== undefined || out.elapsedS !== undefined ? out : null;
}
