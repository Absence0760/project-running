/**
 * Checkpoint board grouping — turn a flat list of checkpoint crossings into
 * one projected runner per identity, ready for the organiser live-results board
 * (race_director_ops.md P2) and the public results page (P4).
 *
 * This is the glue between the raw crossing rows and the pure
 * `projectRunner` cutoff model in `checkpoint_projection.ts`: it groups
 * crossings by runner identity (account user_id, else bib), converts each
 * crossing's `in_time` into elapsed-seconds-from-the-race-start, and runs the
 * projection. The projection math itself is NOT re-derived here — it stays the
 * single source of truth in `checkpoint_projection.ts`.
 *
 * Pure + framework-free so it is node:test-runnable. Web-only (the mobile
 * volunteer screen doesn't render the board), so no Dart twin.
 */
import {
	projectRunner,
	type ProjectionCheckpoint,
	type RunnerProjection
} from './checkpoint_projection';

export interface BoardCheckpoint {
	id: string;
	name: string;
	ordinal: number;
	positionM: number | null;
	cutoffElapsedS: number | null;
}

export interface BoardCrossing {
	checkpointId: string;
	userId: string | null;
	bib: string | null;
	runnerName: string | null;
	/** ISO timestamp of the in stamp, or null if only an out stamp exists. */
	inTime: string | null;
}

export interface BoardRunner {
	/** Stable identity key: user_id when present, else `bib:<bib>`. */
	key: string;
	userId: string | null;
	bib: string | null;
	name: string | null;
	projection: RunnerProjection;
}

/** Identity key for grouping: an account row keys on its user_id; a bib-only
 *  row keys on its bib (prefixed so a bib that looks like a uuid can't collide
 *  with an account). The crossing identity CHECK guarantees one is non-null. */
export function crossingKey(c: { userId: string | null; bib: string | null }): string {
	return c.userId ?? `bib:${c.bib ?? ''}`;
}

/**
 * Group crossings by runner and project each against the checkpoints.
 *
 * `raceStartMs` is the wall-clock race start (epoch ms) used to convert each
 * crossing's `in_time` into elapsed seconds. A crossing without an `in_time`
 * (out-only stamp) contributes no elapsed sample for that checkpoint — the
 * runner is simply not "reached" there until an in-time arrives.
 *
 * Returns runners sorted by progress: furthest covered first, then earliest
 * last-stamp (the leader), with not-yet-started runners last.
 */
export function buildBoard(
	checkpoints: BoardCheckpoint[],
	crossings: BoardCrossing[],
	raceStartMs: number
): BoardRunner[] {
	const projCheckpoints: ProjectionCheckpoint[] = checkpoints.map((c) => ({
		id: c.id,
		positionM: c.positionM ?? 0,
		cutoffElapsedS: c.cutoffElapsedS
	}));

	const grouped = new Map<
		string,
		{ userId: string | null; bib: string | null; name: string | null; crossings: BoardCrossing[] }
	>();
	for (const c of crossings) {
		const key = crossingKey(c);
		let g = grouped.get(key);
		if (!g) {
			g = { userId: c.userId, bib: c.bib, name: c.runnerName, crossings: [] };
			grouped.set(key, g);
		}
		// Prefer the first non-empty runner name seen for this identity.
		if (!g.name && c.runnerName) g.name = c.runnerName;
		g.crossings.push(c);
	}

	const runners: BoardRunner[] = [];
	for (const [key, g] of grouped) {
		const projCrossings = g.crossings
			.filter((c) => c.inTime !== null)
			.map((c) => ({
				checkpointId: c.checkpointId,
				elapsedS: Math.max(0, (new Date(c.inTime as string).getTime() - raceStartMs) / 1000)
			}));
		runners.push({
			key,
			userId: g.userId,
			bib: g.bib,
			name: g.name,
			projection: projectRunner(projCheckpoints, projCrossings)
		});
	}

	runners.sort((a, b) => {
		const cov = b.projection.coveredM - a.projection.coveredM;
		if (cov !== 0) return cov;
		const al = a.projection.lastElapsedS ?? Infinity;
		const bl = b.projection.lastElapsedS ?? Infinity;
		return al - bl;
	});
	return runners;
}
