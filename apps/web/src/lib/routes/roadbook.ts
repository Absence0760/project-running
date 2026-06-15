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
import { parseCutoff } from './route_markers';

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

/** Per-waypoint cumulative distance / grade-adjusted distance / gain / loss. */
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
		const horiz = haversineM(a, b);
		const dEle = a.ele != null && b.ele != null ? b.ele - a.ele : 0;
		// Below the trusted-segment length, GPS/SRTM altitude noise dominates —
		// treat as flat (factor 1) rather than amplify a phantom grade.
		const grade = horiz >= MIN_SEGMENT_M ? dEle / horiz : 0;
		dist.push(dist[i - 1] + horiz);
		gap.push(gap[i - 1] + horiz * gradeFactor(grade));
		gain.push(gain[i - 1] + Math.max(0, dEle));
		loss.push(loss[i - 1] + Math.max(0, -dEle));
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
	cutoffMeta: unknown;
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
		{ pos: 0, checkpoint: 'start', services: [], cutoffMeta: null, isCutoff: false },
		...placed.map((m): Stop => {
			const meta = (m.meta ?? {}) as Record<string, unknown>;
			const services = Array.isArray(meta.services) ? (meta.services as string[]) : [];
			return {
				pos: m.position_m,
				checkpoint: { kind: m.kind, label: m.label },
				services,
				cutoffMeta: m.meta,
				isCutoff: m.kind === 'cutoff'
			};
		}),
		{ pos: totalDistM, checkpoint: 'finish', services: [], cutoffMeta: null, isCutoff: false }
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
			const cutoff = cutoffLimitS(stop.cutoffMeta, opts.startClockMin ?? null);
			if (cutoff != null) {
				const marginS = cutoff - elapsed;
				leg.cutoff = {
					limitElapsedS: cutoff,
					marginS,
					status: marginS < 0 ? 'miss' : marginS < CUTOFF_TIGHT_S ? 'tight' : 'safe'
				};
			}
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
 * Resolve a cutoff marker's `meta` to a limit in elapsed seconds from the
 * start. Prefers `cutoff_elapsed_s`; otherwise derives from `cutoff_clock`
 * minus the start clock (wrapping past midnight). Null when neither resolves.
 */
function cutoffLimitS(meta: unknown, startClockMin: number | null): number | null {
	const cutoff = parseCutoff(meta);
	if (!cutoff) return null;
	if (cutoff.elapsedS !== undefined) return cutoff.elapsedS;
	if (cutoff.clock !== undefined && startClockMin != null) {
		const [h, m] = cutoff.clock.split(':').map(Number);
		let cutoffMin = h * 60 + m;
		// A cutoff clock at or before the start clock is the next day: a 24h+
		// race expressing its overall limit as the start wall-clock one day on
		// (e.g. start 06:00, cutoff '06:00') means 24h, never a 0-second window.
		if (cutoffMin <= startClockMin) cutoffMin += MINUTES_PER_DAY;
		return (cutoffMin - startClockMin) * 60;
	}
	return null;
}
