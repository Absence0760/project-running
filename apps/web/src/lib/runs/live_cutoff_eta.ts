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
 * can fold in `gradeFactor` the way `roadbook.ts`'s allocation does.
 *
 * `requiredPaceSecPerKm` is the flip side of the projection: the flat pace the
 * runner must average over the remaining distance to arrive exactly at the
 * limit. Unlike the ETA it does NOT depend on recent pace, so it is still
 * computed when the fix is stale or pace is unknown — a runner with no recent
 * pace still deserves "you need 6:30s to make it". It is null when there is no
 * checkpoint, when the cutoff is < 50 m away (too close for a meaningful
 * pace), or when the limit has already passed (no pace can make it).
 *
 * A null `distAlongRouteM` means the runner has not been located on the course
 * at all (no fix yet, or a fix that would not project onto the line). There is
 * then no way to know which cutoff is *next*, so the whole result collapses to
 * the no-checkpoint shape. A caller that substituted 0 would instead name the
 * FIRST cutoff and state a distance-to-go measured from the start line — a
 * spectator whose runner is at km 80 would read "Aid 1, 12 km to go".
 * Twin of `apps/mobile_android/lib/live_cutoff_eta.dart` — keep logic, edge
 * cases, and test count in lockstep.
 */
import { CUTOFF_TIGHT_S, type RoadbookLeg } from '../routes/roadbook';

export { CUTOFF_TIGHT_S };

export type LiveCutoffStatus = 'on' | 'tight' | 'behind' | 'unknown';

export interface LiveCutoffInput {
	/**
	 * Runner's current distance along the planned route, metres. Null when the
	 * runner has not been located on the course yet — never substitute 0.
	 */
	distAlongRouteM: number | null;
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
	/**
	 * Flat pace (s/km) needed over the remaining distance to hit the limit
	 * exactly; independent of recent pace, so present even when status is
	 * 'unknown'. Null when no checkpoint, < 50 m out, or the limit has passed.
	 */
	requiredPaceSecPerKm: number | null;
	/**
	 * The cutoff's limit is already in the past — no pace can make it. The
	 * explicit flag exists because requiredPaceSecPerKm is null for TWO
	 * reasons (limit passed / too close to project a meaningful pace) and a
	 * "you cannot make it" surface must never fire from the second.
	 */
	limitPassed: boolean;
	status: LiveCutoffStatus;
}

export function nextCutoffEta(input: LiveCutoffInput): LiveCutoffEta {
	const along = input.distAlongRouteM;
	const ahead =
		along == null || !Number.isFinite(along)
			? []
			: input.legs
					.filter((l) => l.cutoff != null && l.cumDistM > along)
					.sort((a, b) => a.cumDistM - b.cumDistM);

	const leg = ahead[0];
	if (!leg) {
		return {
			checkpoint: null,
			distanceToM: 0,
			projectedArrivalElapsedS: null,
			marginS: null,
			requiredPaceSecPerKm: null,
			limitPassed: false,
			status: 'unknown'
		};
	}

	const checkpoint =
		typeof leg.checkpoint === 'object'
			? { kind: leg.checkpoint.kind, label: leg.checkpoint.label }
			: { kind: 'cutoff', label: '' };
	const distanceToM = leg.cumDistM - along!;
	const remainingS = leg.cutoff!.limitElapsedS - input.elapsedS;
	const limitPassed = remainingS <= 0;
	const requiredPaceSecPerKm =
		distanceToM >= 50 && remainingS > 0 ? remainingS / (distanceToM / 1000) : null;

	if (
		input.stale ||
		input.recentPaceSecPerKm == null ||
		!Number.isFinite(input.recentPaceSecPerKm) ||
		input.recentPaceSecPerKm <= 0
	) {
		return {
			checkpoint,
			distanceToM,
			projectedArrivalElapsedS: null,
			marginS: null,
			requiredPaceSecPerKm,
			limitPassed,
			status: 'unknown'
		};
	}

	const projectedArrivalElapsedS =
		input.elapsedS + (distanceToM / 1000) * input.recentPaceSecPerKm;
	const marginS = leg.cutoff!.limitElapsedS - projectedArrivalElapsedS;
	const status: LiveCutoffStatus =
		marginS < 0 ? 'behind' : marginS < CUTOFF_TIGHT_S ? 'tight' : 'on';

	return {
		checkpoint,
		distanceToM,
		projectedArrivalElapsedS,
		marginS,
		requiredPaceSecPerKm,
		limitPassed,
		status
	};
}
