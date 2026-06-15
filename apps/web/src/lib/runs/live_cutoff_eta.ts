/**
 * Live cutoff ETA — the SPECTATOR-side projection. From a runner's current
 * distance-along-route + recent pace, find the next cutoff ahead and project
 * whether they'll make it (`on` / `tight` / `behind`).
 *
 * Sibling of `checkpoint_projection.ts`: that one grades a race-director's
 * runner from logged aid-station CROSSINGS; this one is the family-at-home view
 * driven by a single live position fix + recent pace. They share the tight
 * threshold (`CUTOFF_TIGHT_S`, re-exported here) so "tight" means the same span
 * on both surfaces.
 *
 * The honesty rule that justifies the extra status: when the live fix is
 * **stale**, return `status: 'unknown'` with a null ETA rather than fabricate an
 * arrival off an 18h-old position — a lost-signal runner must not read as
 * "on pace". An unknown/zero recent pace is treated the same way.
 *
 * The projection is deliberately FLAT pace (no grade adjustment) — the same
 * honest simplification `checkpoint_projection.ts` makes; a future refinement
 * can fold in `gradeFactor` the way `roadbook.ts`'s allocation does. Twin of
 * `apps/mobile_android/lib/live_cutoff_eta.dart` — keep logic, edge cases, and
 * test count in lockstep.
 */
import { CUTOFF_TIGHT_S, type RoadbookLeg } from '../routes/roadbook';

export { CUTOFF_TIGHT_S };

export type LiveCutoffStatus = 'on' | 'tight' | 'behind' | 'unknown';

export interface LiveCutoffInput {
	/** Runner's current distance along the planned route, metres. */
	distAlongRouteM: number;
	/** Runner's current elapsed time since the start, seconds. */
	elapsedS: number;
	/** Recent average pace, seconds per km. Null when not yet known. */
	recentPaceSecPerKm: number | null;
	/** Roadbook legs (reuse the cutoff legs for the limits). */
	legs: RoadbookLeg[];
	/** From live_freshness: the last position fix is stale. */
	stale: boolean;
}

export interface LiveCutoffEta {
	/** The next cutoff checkpoint ahead, or null when none remain (hide the card). */
	checkpoint: { kind: string; label: string } | null;
	/** Distance from the runner to that cutoff, metres (0 when no checkpoint). */
	distanceToM: number;
	/** Projected arrival as elapsed seconds from start; null when unknown. */
	projectedArrivalElapsedS: number | null;
	/** limitElapsedS - projectedArrival; null when unknown. */
	marginS: number | null;
	status: LiveCutoffStatus;
}

export function nextCutoffEta(input: LiveCutoffInput): LiveCutoffEta {
	const ahead = input.legs
		.filter((l) => l.cutoff != null && l.cumDistM > input.distAlongRouteM)
		.sort((a, b) => a.cumDistM - b.cumDistM);

	const leg = ahead[0];
	if (!leg) {
		return {
			checkpoint: null,
			distanceToM: 0,
			projectedArrivalElapsedS: null,
			marginS: null,
			status: 'unknown'
		};
	}

	const checkpoint =
		typeof leg.checkpoint === 'object'
			? { kind: leg.checkpoint.kind, label: leg.checkpoint.label }
			: { kind: 'cutoff', label: '' };
	const distanceToM = leg.cumDistM - input.distAlongRouteM;

	if (input.stale || input.recentPaceSecPerKm == null || input.recentPaceSecPerKm <= 0) {
		return {
			checkpoint,
			distanceToM,
			projectedArrivalElapsedS: null,
			marginS: null,
			status: 'unknown'
		};
	}

	const projectedArrivalElapsedS =
		input.elapsedS + (distanceToM / 1000) * input.recentPaceSecPerKm;
	const marginS = leg.cutoff!.limitElapsedS - projectedArrivalElapsedS;
	const status: LiveCutoffStatus =
		marginS < 0 ? 'behind' : marginS < CUTOFF_TIGHT_S ? 'tight' : 'on';

	return { checkpoint, distanceToM, projectedArrivalElapsedS, marginS, status };
}
