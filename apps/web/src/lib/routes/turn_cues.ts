/**
 * Pure geometric turn-cue generator for a planned polyline. TS twin of
 * `apps/mobile_android/lib/turn_cues.dart` — keep the two in lockstep
 * (algorithm, edge cases, test counts). Add to the parity-pair list in
 * CLAUDE.md when you grow it.
 *
 * The offline-first turn-by-turn baseline (decisions §169): turns are
 * derived purely from the saved line's geometry — the bearing change at
 * each vertex — with no routing service, no network, and no key. It
 * announces *geometric* bends ("turn left"), not road-name-aware
 * instructions ("turn onto Oak St"); that is the deliberate trade for an
 * always-works offline cue list that the recorder can play back with zero
 * connectivity. An optional external routing engine could later replace
 * the generator with a parsed named-road step list, falling back to this
 * when offline — this file stays the L1 baseline.
 */
export interface TurnCueWaypoint {
	lat: number;
	lng: number;
}

export type TurnDirection =
	| 'left'
	| 'right'
	| 'slight_left'
	| 'slight_right'
	| 'straight'
	| 'uturn';

export interface TurnCue {
	/// Distance along the route, in metres from the start, at the turn vertex.
	positionM: number;
	/// Bearing (degrees, 0–360, 0 = north) approaching the vertex.
	bearingInDeg: number;
	/// Bearing leaving the vertex.
	bearingOutDeg: number;
	direction: TurnDirection;
	/// Alias of positionM kept explicit for the cue-firing consumer.
	distanceFromStartM: number;
}

export interface TurnCueOptions {
	/// Suppress vertices whose absolute bearing change is below this — GPS /
	/// drawing noise on a roughly-straight line. Default 30°.
	minTurnAngleDeg?: number;
	/// Merge a vertex into the previous cue when it falls within this many
	/// metres of it (coincident / densely-sampled vertices). Default 15 m.
	mergeWithinM?: number;
}

const DEFAULT_MIN_TURN_ANGLE_DEG = 30;
const DEFAULT_MERGE_WITHIN_M = 15;
const SLIGHT_MAX_DEG = 45;
const UTURN_MIN_DEG = 150;

/**
 * Generate an ordered list of turn cues from `waypoints`. A cue is emitted
 * at each interior vertex whose bearing change exceeds `minTurnAngleDeg`,
 * classified by signed turn angle into left/right/slight/uturn. Coincident
 * vertices and vertices within `mergeWithinM` of the previous cue are merged
 * so a densely-sampled corner produces one cue, not a burst. Returns `[]`
 * for a straight line or fewer than 3 waypoints (no interior vertex to turn
 * at).
 */
export function generateTurnCues(
	waypoints: TurnCueWaypoint[],
	options: TurnCueOptions = {},
): TurnCue[] {
	const minAngle = options.minTurnAngleDeg ?? DEFAULT_MIN_TURN_ANGLE_DEG;
	const mergeWithin = options.mergeWithinM ?? DEFAULT_MERGE_WITHIN_M;
	if (waypoints.length < 3) return [];

	// Collapse coincident / sub-merge-distance vertices first, carrying the
	// cumulative distance of each surviving vertex along the ORIGINAL line. A
	// duplicated or densely-sampled corner then presents as a single vertex with
	// a well-defined entry/exit bearing, so it fires one cue instead of a burst
	// of zero-length-leg skips.
	const collapsed: { wp: TurnCueWaypoint; cumM: number }[] = [];
	let cum = 0;
	collapsed.push({ wp: waypoints[0], cumM: 0 });
	for (let i = 1; i < waypoints.length; i++) {
		cum += haversineM(waypoints[i - 1], waypoints[i]);
		const prev = collapsed[collapsed.length - 1];
		if (cum - prev.cumM <= mergeWithin) {
			// Within merge distance of the kept vertex: advance the kept vertex to
			// this point so the exit bearing reflects where the line actually goes,
			// but keep the earlier cumulative position.
			prev.wp = waypoints[i];
			continue;
		}
		collapsed.push({ wp: waypoints[i], cumM: cum });
	}
	if (collapsed.length < 3) return [];

	const cues: TurnCue[] = [];
	for (let i = 1; i < collapsed.length - 1; i++) {
		const bearingIn = bearingDeg(collapsed[i - 1].wp, collapsed[i].wp);
		const bearingOut = bearingDeg(collapsed[i].wp, collapsed[i + 1].wp);
		const delta = signedTurn(bearingIn, bearingOut);
		if (Math.abs(delta) < minAngle) continue;

		const positionM = collapsed[i].cumM;
		cues.push({
			positionM,
			bearingInDeg: bearingIn,
			bearingOutDeg: bearingOut,
			direction: classify(delta),
			distanceFromStartM: positionM,
		});
	}
	return cues;
}

/// Signed turn angle in degrees, (-180, 180]. Positive = right turn
/// (clockwise), negative = left turn — matching compass convention.
function signedTurn(bearingIn: number, bearingOut: number): number {
	let d = bearingOut - bearingIn;
	while (d > 180) d -= 360;
	while (d <= -180) d += 360;
	return d;
}

function classify(delta: number): TurnDirection {
	const a = Math.abs(delta);
	if (a >= UTURN_MIN_DEG) return 'uturn';
	if (delta > 0) return a <= SLIGHT_MAX_DEG ? 'slight_right' : 'right';
	return a <= SLIGHT_MAX_DEG ? 'slight_left' : 'left';
}

function bearingDeg(a: TurnCueWaypoint, b: TurnCueWaypoint): number {
	const deg = Math.PI / 180;
	const lat1 = a.lat * deg;
	const lat2 = b.lat * deg;
	const dLng = (b.lng - a.lng) * deg;
	const y = Math.sin(dLng) * Math.cos(lat2);
	const x =
		Math.cos(lat1) * Math.sin(lat2) -
		Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
	const brng = Math.atan2(y, x) / deg;
	return (brng + 360) % 360;
}

function haversineM(a: TurnCueWaypoint, b: TurnCueWaypoint): number {
	const r = 6_371_000;
	const deg = Math.PI / 180;
	const dLat = (b.lat - a.lat) * deg;
	const dLng = (b.lng - a.lng) * deg;
	const h =
		Math.sin(dLat / 2) * Math.sin(dLat / 2) +
		Math.cos(a.lat * deg) *
			Math.cos(b.lat * deg) *
			Math.sin(dLng / 2) *
			Math.sin(dLng / 2);
	return r * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
}
