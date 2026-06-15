/**
 * Checkpoint cutoff projection — from a runner's actual aid-station crossings,
 * project arrival at every remaining checkpoint and grade each cutoff
 * safe / tight / miss.
 *
 * This is the live-results companion to `roadbook.ts`: the roadbook projects a
 * crew schedule from a goal time BEFORE the race; this projects from the
 * crossings logged DURING it. Both grade cutoffs on the same scale, so the
 * verdict type + tight threshold are imported from `roadbook.ts` rather than
 * redefined (one source of truth for "what counts as tight").
 *
 * The pace model is deliberately simple and honest: average pace from the start
 * to the last checkpoint actually reached, extrapolated linearly to the
 * remaining distance. It does not (yet) grade-adjust the remaining legs — a
 * future refinement can fold in `gradeFactor` the way the roadbook does.
 *
 * Shared by the organiser live-results / cutoff board (race_director_ops.md P2)
 * and the predictive live tracker (predictive_live_tracking.md). Pure +
 * framework-free. Twin of `apps/mobile_android/lib/checkpoint_projection.dart`
 * — keep the projection, cutoff rules, edge cases, and test count in lockstep.
 */
import { CUTOFF_TIGHT_S, type CutoffStatus } from './../routes/roadbook';

export { CUTOFF_TIGHT_S };
export type { CutoffStatus };

export interface ProjectionCheckpoint {
	id: string;
	/** Distance along the course from the start, metres. */
	positionM: number;
	/** Cutoff as elapsed seconds from the race start. Null = no cutoff here. */
	cutoffElapsedS: number | null;
}

export interface ProjectionCrossing {
	checkpointId: string;
	/** Arrival (in_time) as elapsed seconds from the race start. */
	elapsedS: number;
}

export type RunnerStatus = 'racing' | 'finished' | 'dnf';

export interface CutoffVerdict {
	marginS: number;
	status: CutoffStatus;
}

export interface ProjectionLeg {
	checkpointId: string;
	positionM: number;
	reached: boolean;
	/** Elapsed seconds at the actual crossing, when reached. */
	actualElapsedS: number | null;
	/** Linearly-projected elapsed seconds, when not yet reached + pace known. */
	projectedElapsedS: number | null;
	cutoffElapsedS: number | null;
	/** Cutoff grade against the actual (reached) or projected (future) arrival. */
	cutoff: CutoffVerdict | null;
}

export interface RunnerProjection {
	legs: ProjectionLeg[];
	lastCheckpointId: string | null;
	lastElapsedS: number | null;
	/** Distance covered to the last reached checkpoint, metres. */
	coveredM: number;
	/** Average seconds per metre to the last reached checkpoint. Null until 1+. */
	paceSPerM: number | null;
	status: RunnerStatus;
}

function gradeCutoff(cutoffS: number, arrivalS: number): CutoffVerdict {
	const marginS = cutoffS - arrivalS;
	return {
		marginS,
		status: marginS < 0 ? 'miss' : marginS < CUTOFF_TIGHT_S ? 'tight' : 'safe'
	};
}

/**
 * Project a single runner from their crossings.
 *
 * `checkpoints` are ordered by `positionM` ascending here (callers needn't
 * pre-sort). A checkpoint with a NaN/negative position is treated as 0.
 */
export function projectRunner(
	checkpoints: ProjectionCheckpoint[],
	crossings: ProjectionCrossing[]
): RunnerProjection {
	const ordered = [...checkpoints]
		.map((c) => ({ ...c, positionM: Number.isFinite(c.positionM) ? Math.max(0, c.positionM) : 0 }))
		.sort((a, b) => a.positionM - b.positionM);

	const byId = new Map<string, number>();
	for (const x of crossings) {
		// Keep the earliest stamp if a checkpoint somehow has two (merge already
		// happened server-side, but be defensive).
		const prev = byId.get(x.checkpointId);
		if (prev === undefined || x.elapsedS < prev) byId.set(x.checkpointId, x.elapsedS);
	}

	// Last reached checkpoint = the reached one with the greatest position.
	let lastCheckpointId: string | null = null;
	let lastElapsedS: number | null = null;
	let coveredM = 0;
	for (const c of ordered) {
		const e = byId.get(c.id);
		if (e === undefined) continue;
		if (lastElapsedS === null || c.positionM >= coveredM) {
			lastCheckpointId = c.id;
			lastElapsedS = e;
			coveredM = c.positionM;
		}
	}

	const paceSPerM =
		lastElapsedS !== null && coveredM > 0 ? lastElapsedS / coveredM : null;

	let blownCutoff = false;
	const legs: ProjectionLeg[] = ordered.map((c) => {
		const actual = byId.get(c.id);
		const reached = actual !== undefined;
		let projected: number | null = null;
		if (!reached && paceSPerM !== null && c.positionM > coveredM) {
			projected = paceSPerM * c.positionM;
		}

		let cutoff: CutoffVerdict | null = null;
		if (c.cutoffElapsedS !== null) {
			const arrival = reached ? (actual as number) : projected;
			if (arrival !== null) {
				cutoff = gradeCutoff(c.cutoffElapsedS, arrival);
				if (reached && cutoff.status === 'miss') blownCutoff = true;
			}
		}

		return {
			checkpointId: c.id,
			positionM: c.positionM,
			reached,
			actualElapsedS: reached ? (actual as number) : null,
			projectedElapsedS: projected,
			cutoffElapsedS: c.cutoffElapsedS,
			cutoff
		};
	});

	const reachedLast =
		ordered.length > 0 && lastCheckpointId === ordered[ordered.length - 1].id;
	const status: RunnerStatus = blownCutoff
		? 'dnf'
		: reachedLast
			? 'finished'
			: 'racing';

	return { legs, lastCheckpointId, lastElapsedS, coveredM, paceSPerM, status };
}
