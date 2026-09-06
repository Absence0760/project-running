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

/**
 * Grade one arrival against one cutoff, or null when the margin is not a
 * number.
 *
 * The ladder is `marginS < 0 ? miss : marginS < TIGHT ? tight : safe`, and a
 * NaN margin fails BOTH comparisons and lands on the optimistic terminal
 * branch — so a crossing nothing could time was reported to a race director as
 * `safe`, with `marginS: NaN` printed beside it (decisions § 1225). On a
 * cutoff board the only honest answer about an ungradeable crossing is no
 * answer: `ProjectionLeg.cutoff` is already nullable and every consumer
 * renders a null as ungraded.
 */
function gradeCutoff(cutoffS: number, arrivalS: number): CutoffVerdict | null {
	const marginS = cutoffS - arrivalS;
	if (!Number.isFinite(marginS)) return null;
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
		// A crossing whose elapsed time is not a number is not a crossing this
		// module can say anything about — the same sanitisation `positionM` gets
		// one block up. Admitting it made the runner `reached` at that
		// checkpoint and every comparison downstream answered false, which the
		// cutoff ladder reads as `safe`.
		if (!Number.isFinite(x.elapsedS)) continue;
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

	// `lastElapsedS > 0` matters as much as `coveredM > 0`. A stamp at or before
	// the race start (a volunteer's tablet running fast, or the RD firing Go
	// after a start-area checkpoint already scanned) clamps to elapsed 0, and a
	// pace of exactly 0 is finite — so every remaining checkpoint projected an
	// arrival of 0 and graded "safe" with the full cutoff as its margin. An
	// unusable sample must leave future cutoffs ungraded, as a runner with no
	// crossings at all already does.
	const paceSPerM =
		lastElapsedS !== null && lastElapsedS > 0 && coveredM > 0
			? lastElapsedS / coveredM
			: null;

	let blownCutoff = false;
	const legs: ProjectionLeg[] = ordered.map((c) => {
		const actual = byId.get(c.id);
		const reached = actual !== undefined;
		let projected: number | null = null;
		if (!reached && paceSPerM !== null && c.positionM >= coveredM) {
			projected = paceSPerM * c.positionM;
		}

		let cutoff: CutoffVerdict | null = null;
		if (c.cutoffElapsedS !== null) {
			const arrival = reached ? (actual as number) : projected;
			if (arrival !== null) {
				cutoff = gradeCutoff(c.cutoffElapsedS, arrival);
				if (reached && cutoff?.status === 'miss') blownCutoff = true;
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
