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
 *
 * A turn is the NET direction change accumulated within `mergeWithinM`
 * metres of where the turning starts, reported at the vertex where that
 * turning passes its halfway point. The two knobs then read as one
 * sentence: at least `minTurnAngleDeg` of direction change within
 * `mergeWithinM` metres is a turn; anything slacker is a curve and is not
 * announced. Every bearing is measured on a segment that TOUCHES the
 * vertex it is measured at, never one that spans it: a segment drawn
 * across a corner carries half that corner's angle and none of its
 * position.
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
	/// Bearing (degrees, 0–360, 0 = north) approaching the turn.
	bearingInDeg: number;
	/// Bearing leaving the turn.
	bearingOutDeg: number;
	direction: TurnDirection;
	/// Alias of positionM kept explicit for the cue-firing consumer.
	distanceFromStartM: number;
}

export interface TurnCueOptions {
	/// Suppress turns whose accumulated direction change is below this — GPS /
	/// drawing noise on a roughly-straight line. Default 30°.
	minTurnAngleDeg?: number;
	/// The window one turn is accumulated over: vertices within this many
	/// metres of where the turning starts belong to the same turn, so a
	/// densely-sampled or rounded corner fires once at its full angle.
	/// Default 15 m.
	mergeWithinM?: number;
}

const DEFAULT_MIN_TURN_ANGLE_DEG = 30;
const DEFAULT_MERGE_WITHIN_M = 15;
const SLIGHT_MAX_DEG = 45;
const UTURN_MIN_DEG = 150;
/// A leg shorter than this carries no usable bearing, so its far vertex is
/// dropped. Far below any route's vertex resolution, so dropping it cannot
/// move a corner.
const MIN_LEG_M = 0.05;
/// A vertex bending less than this does not open a turn window. A corner
/// built from bends this small would need more vertices inside one window
/// than any drawn or imported route carries.
const TURN_EPSILON_DEG = 0.5;

interface Bend {
	positionM: number;
	bearingInDeg: number;
	bearingOutDeg: number;
	deltaDeg: number;
}

/**
 * Generate an ordered list of turn cues from `waypoints`. Returns `[]` for a
 * straight line or fewer than 3 waypoints (no interior vertex to turn at).
 */
export function generateTurnCues(
	waypoints: TurnCueWaypoint[],
	options: TurnCueOptions = {},
): TurnCue[] {
	const minAngle = options.minTurnAngleDeg ?? DEFAULT_MIN_TURN_ANGLE_DEG;
	const mergeWithin = options.mergeWithinM ?? DEFAULT_MERGE_WITHIN_M;
	if (waypoints.length < 3) return [];

	const pts: { wp: TurnCueWaypoint; cumM: number }[] = [
		{ wp: waypoints[0], cumM: 0 },
	];
	let cum = 0;
	for (let i = 1; i < waypoints.length; i++) {
		cum += haversineM(waypoints[i - 1], waypoints[i]);
		if (cum - pts[pts.length - 1].cumM < MIN_LEG_M) continue;
		pts.push({ wp: waypoints[i], cumM: cum });
	}
	if (pts.length < 3) return [];

	const bends: Bend[] = [];
	for (let i = 1; i < pts.length - 1; i++) {
		const bearingInDeg = bearingDeg(pts[i - 1].wp, pts[i].wp);
		const bearingOutDeg = bearingDeg(pts[i].wp, pts[i + 1].wp);
		bends.push({
			positionM: pts[i].cumM,
			bearingInDeg,
			bearingOutDeg,
			deltaDeg: signedTurn(bearingInDeg, bearingOutDeg),
		});
	}

	const cues: TurnCue[] = [];
	let i = 0;
	while (i < bends.length) {
		if (Math.abs(bends[i].deltaDeg) < TURN_EPSILON_DEG) {
			i++;
			continue;
		}
		let net = 0;
		let swept = 0;
		let end = i;
		while (
			end < bends.length &&
			bends[end].positionM - bends[i].positionM <= mergeWithin
		) {
			net += bends[end].deltaDeg;
			swept += Math.abs(bends[end].deltaDeg);
			end++;
		}
		if (Math.abs(net) < minAngle) {
			// Not a turn over this window. Slide by one rather than consuming the
			// window, so a corner that starts just inside it still opens its own.
			i++;
			continue;
		}
		let run = 0;
		let positionM = bends[i].positionM;
		for (let k = i; k < end; k++) {
			run += Math.abs(bends[k].deltaDeg);
			if (run * 2 >= swept) {
				positionM = bends[k].positionM;
				break;
			}
		}
		cues.push({
			positionM,
			bearingInDeg: bends[i].bearingInDeg,
			bearingOutDeg: bends[end - 1].bearingOutDeg,
			direction: classify(net),
			distanceFromStartM: positionM,
		});
		i = end;
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
