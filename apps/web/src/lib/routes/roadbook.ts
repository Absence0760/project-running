/**
 * Race roadbook — the crew sheet a route's course markers + a goal time imply.
 *
 * Given a route's waypoints, its course markers (aid stations / cutoffs / crew
 * access), and a goal finish time, `buildRoadbook` produces the per-checkpoint
 * schedule ultra crews currently build by hand: cumulative distance, projected
 * arrival (elapsed + wall clock), cutoff margin, and per-leg vert.
 *
 * The differentiator over even splits: goal time is allocated by
 * **grade-adjusted effort** (`gradeFactor`, Minetti) — the climbs get
 * proportionally more time than the flats — not by even distance. With no
 * elevation data the effort model degrades cleanly to even pace.
 *
 * Pure + framework-free. Twin of `apps/mobile_android/lib/roadbook.dart` —
 * keep the allocation, cutoff rules, edge cases, and test count in lockstep.
 */
import { gradeFactor, MIN_SEGMENT_M } from '../runs/grade_adjusted_pace';
import { parseCutoff, parseTarget, type CutoffParts } from './route_markers';

export interface RoadbookWaypoint {
	lat: number;
	lng: number;
	ele?: number | null;
}

export interface RoadbookMarker {
	/** Distance along the route from the start, metres. Null = no geom yet. */
	position_m: number | null;
	kind: string;
	label: string;
	meta: unknown;
}

export type PacingModel = 'effort' | 'even';

export interface RoadbookOptions {
	goalSeconds: number;
	/** Race start, minutes past local midnight. Omit for elapsed-only. */
	startClockMin?: number | null;
	model: PacingModel;
}

export type CutoffStatus = 'safe' | 'tight' | 'miss';

export interface RoadbookCutoff {
	limitElapsedS: number;
	marginS: number;
	status: CutoffStatus;
}

export type TargetStatus = 'ahead' | 'on' | 'behind';

export interface RoadbookTarget {
	targetElapsedS: number;
	/** Signed like `RoadbookCutoff.marginS` — positive is time in hand. */
	marginS: number;
	status: TargetStatus;
}

export type Checkpoint = 'start' | 'finish' | { kind: string; label: string };

export interface RoadbookLeg {
	checkpoint: Checkpoint;
	cumDistM: number;
	legDistM: number;
	legGainM: number;
	legLossM: number;
	projectedElapsedS: number;
	/** Wall-clock arrival, minutes past midnight (mod 1440). Absent if no start. */
	projectedClockMin?: number;
	cutoff?: RoadbookCutoff;
	target?: RoadbookTarget;
	services: string[];
}

export interface Roadbook {
	legs: RoadbookLeg[];
	totalDistM: number;
	totalGainM: number;
	totalSeconds: number;
	hasElevation: boolean;
}

/** A cutoff within this many seconds of the projection is "tight", not "safe". */
export const CUTOFF_TIGHT_S = 30 * 60;

/**
 * How close to a checkpoint's target time still reads as "on schedule".
 *
 * Unlike the cutoff band this is proportional, because a target is read at the
 * scale of the race: two minutes down at a 30-minute checkpoint is a real
 * problem, and two minutes down at hour twenty of a 200-miler is noise. A flat
 * band would report every ultra checkpoint as off-plan and every 10K one as on
 * it. The floor keeps an early checkpoint from being graded to the second.
 */
export const TARGET_BAND_FRACTION = 0.01;
export const TARGET_BAND_FLOOR_S = 60;

export function targetBandS(targetElapsedS: number): number {
	return Math.max(TARGET_BAND_FLOOR_S, targetElapsedS * TARGET_BAND_FRACTION);
}

const MINUTES_PER_DAY = 1440;

function haversineM(a: RoadbookWaypoint, b: RoadbookWaypoint): number {
	const r = 6_371_000;
	const deg = Math.PI / 180;
	const dLat = (b.lat - a.lat) * deg;
	const dLng = (b.lng - a.lng) * deg;
	const h =
		Math.sin(dLat / 2) ** 2 +
		Math.cos(a.lat * deg) * Math.cos(b.lat * deg) * Math.sin(dLng / 2) ** 2;
	return r * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
}

interface Cumulative {
	dist: number[];
	gap: number[];
	gain: number[];
	loss: number[];
	hasElevation: boolean;
}

/**
 * Per-waypoint cumulative distance / grade-adjusted distance / gain / loss.
 *
 * The grade behind `gap` is measured over an **anchored window** that
 * accumulates horizontal distance until it clears `MIN_SEGMENT_M`, the same
 * walk `gradeAdjustedPaceSecPerKm` performs — not over each point-pair. Below
 * the trusted length GPS/SRTM altitude noise dominates, so a short pair's grade
 * can't be believed; the window carries the pair forward instead of discarding
 * its climb. Zeroing each short pair's grade instead (as this did) collapsed
 * effort allocation to even pace on any densely-sampled course — a GPX at 3 m
 * spacing has no pair that clears 5 m — while `hasElevation` and `totalGainM`
 * still reported the full climb, so nothing signalled the degradation.
 */
function walk(waypoints: RoadbookWaypoint[]): Cumulative {
	const dist = [0];
	const gap = [0];
	const gain = [0];
	const loss = [0];
	const eles = new Set<number>();
	for (const w of waypoints) if (w.ele != null) eles.add(w.ele);

	for (let i = 1; i < waypoints.length; i++) {
		const a = waypoints[i - 1];
		const b = waypoints[i];
		const dEle = a.ele != null && b.ele != null ? b.ele - a.ele : 0;
		dist.push(dist[i - 1] + haversineM(a, b));
		gain.push(gain[i - 1] + Math.max(0, dEle));
		loss.push(loss[i - 1] + Math.max(0, -dEle));
	}

	let anchor = 0;
	for (let i = 1; i < waypoints.length; i++) {
		const span = dist[i] - dist[anchor];
		const isLast = i === waypoints.length - 1;
		if (span < MIN_SEGMENT_M && !isLast) continue;
		const a = waypoints[anchor];
		const b = waypoints[i];
		// A trailing window that never cleared the trusted length is the last
		// few metres of the track — grade it flat rather than amplify noise.
		const factor =
			span >= MIN_SEGMENT_M && a.ele != null && b.ele != null
				? gradeFactor((b.ele - a.ele) / span)
				: 1;
		for (let k = anchor + 1; k <= i; k++) gap.push(gap[k - 1] + (dist[k] - dist[k - 1]) * factor);
		anchor = i;
	}

	return { dist, gap, gain, loss, hasElevation: eles.size >= 2 };
}

/** Linear-interpolate a cumulative array at a target distance along the route. */
function valueAt(cum: number[], dist: number[], target: number): number {
	const total = dist[dist.length - 1];
	if (target <= 0) return cum[0];
	if (target >= total) return cum[cum.length - 1];
	for (let i = 1; i < dist.length; i++) {
		if (target <= dist[i]) {
			const span = dist[i] - dist[i - 1];
			const t = span <= 0 ? 0 : (target - dist[i - 1]) / span;
			return cum[i - 1] + (cum[i] - cum[i - 1]) * t;
		}
	}
	return cum[cum.length - 1];
}

interface Stop {
	pos: number;
	checkpoint: Checkpoint;
	services: string[];
	meta: unknown;
	isCutoff: boolean;
}

/**
 * Build the roadbook. Checkpoints are: synthetic start (0), each marker with a
 * non-null `position_m` (ordered by distance), and synthetic finish (total).
 */
export function buildRoadbook(
	waypoints: RoadbookWaypoint[],
	markers: RoadbookMarker[],
	opts: RoadbookOptions
): Roadbook {
	const cum = walk(waypoints);
	const totalDistM = cum.dist[cum.dist.length - 1] ?? 0;
	const totalGainM = cum.gain[cum.gain.length - 1] ?? 0;
	const goal = Math.max(0, opts.goalSeconds);

	const placed = markers
		.filter((m) => m.position_m != null)
		.map((m) => ({ ...m, position_m: Math.min(totalDistM, Math.max(0, m.position_m as number)) }))
		.sort((a, b) => a.position_m - b.position_m);

	const stops: Stop[] = [
		{ pos: 0, checkpoint: 'start', services: [], meta: null, isCutoff: false },
		...placed.map((m): Stop => {
			const meta = (m.meta ?? {}) as Record<string, unknown>;
			const services = Array.isArray(meta.services) ? (meta.services as string[]) : [];
			return {
				pos: m.position_m,
				checkpoint: { kind: m.kind, label: m.label },
				services,
				meta: m.meta,
				isCutoff: m.kind === 'cutoff'
			};
		}),
		{ pos: totalDistM, checkpoint: 'finish', services: [], meta: null, isCutoff: false }
	];

	// Allocation metric per leg: grade-adjusted distance (effort) or raw
	// distance (even). Degrade to even when there's no elevation.
	const useEffort = opts.model === 'effort' && cum.hasElevation;
	const metricAt = (pos: number) =>
		useEffort ? valueAt(cum.gap, cum.dist, pos) : pos;
	const totalMetric = metricAt(totalDistM);

	const legs: RoadbookLeg[] = [];
	let prevPos = 0;
	let prevGain = 0;
	let prevLoss = 0;
	let prevMetric = 0;
	let elapsed = 0;

	for (const stop of stops) {
		const cumGain = valueAt(cum.gain, cum.dist, stop.pos);
		const cumLoss = valueAt(cum.loss, cum.dist, stop.pos);
		const metric = metricAt(stop.pos);
		const legMetric = metric - prevMetric;
		const legTime = totalMetric > 0 ? (goal * legMetric) / totalMetric : 0;
		elapsed += legTime;

		const leg: RoadbookLeg = {
			checkpoint: stop.checkpoint,
			cumDistM: stop.pos,
			legDistM: stop.pos - prevPos,
			legGainM: cumGain - prevGain,
			legLossM: cumLoss - prevLoss,
			projectedElapsedS: elapsed,
			services: stop.services
		};

		if (opts.startClockMin != null) {
			leg.projectedClockMin =
				(((opts.startClockMin + elapsed / 60) % MINUTES_PER_DAY) + MINUTES_PER_DAY) %
				MINUTES_PER_DAY;
		}

		if (stop.isCutoff) {
			const cutoff = limitFromParts(parseCutoff(stop.meta), opts.startClockMin ?? null);
			if (cutoff != null) {
				const marginS = cutoff - elapsed;
				leg.cutoff = {
					limitElapsedS: cutoff,
					marginS,
					status: marginS < 0 ? 'miss' : marginS < CUTOFF_TIGHT_S ? 'tight' : 'safe'
				};
			}
		}

		const target = limitFromParts(parseTarget(stop.meta), opts.startClockMin ?? null);
		if (target != null) {
			const marginS = target - elapsed;
			const band = targetBandS(target);
			leg.target = {
				targetElapsedS: target,
				marginS,
				status: marginS > band ? 'ahead' : marginS < -band ? 'behind' : 'on'
			};
		}

		legs.push(leg);
		prevPos = stop.pos;
		prevGain = cumGain;
		prevLoss = cumLoss;
		prevMetric = metric;
	}

	return {
		legs,
		totalDistM,
		totalGainM,
		totalSeconds: goal,
		hasElevation: cum.hasElevation
	};
}

/**
 * Resolve a cutoff's or a target's parsed `meta` to elapsed seconds from the
 * start. Prefers the elapsed form; otherwise derives from the clock form minus
 * the start clock. Null when neither resolves.
 *
 * A clock field carries no day, so it resolves to that wall clock's first
 * occurrence after the race start and nothing else — a clock equal to the
 * start reads as the 24h limit it is meant to express, never a 0-second
 * window. A limit past 24h has to be written as the elapsed field, the only
 * one that carries a day.
 *
 * The day was previously snapped to whichever whole day sat nearest the leg's
 * projected arrival, which made the limit a function of the goal time: a
 * slower goal pushed the projection over a day boundary and turned a blown
 * cutoff into "safe, 12h to spare", and two spectators of the same live run
 * saw different limits for the same checkpoint. A cutoff is a property of the
 * race, so it may not depend on how fast anyone is expected to run. A target
 * is a property of the plan, and takes the same rule so the two cannot
 * disagree about what "06:00" means on the same row.
 */
function limitFromParts(parts: CutoffParts | null, startClockMin: number | null): number | null {
	if (!parts) return null;
	if (parts.elapsedS !== undefined) return parts.elapsedS;
	if (parts.clock !== undefined && startClockMin != null) {
		const [h, m] = parts.clock.split(':').map(Number);
		let baseMin = h * 60 + m - startClockMin;
		if (baseMin <= 0) baseMin += MINUTES_PER_DAY;
		return baseMin * 60;
	}
	return null;
}
