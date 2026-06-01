import type { Run } from '../types';
import { formatISO } from '../training/training';

/**
 * Local-timezone yyyy-mm-dd key for an ISO timestamp. Must match the grid
 * cell key in `CalendarHeatmap.svelte`, which formats each cell's `Date` with
 * the same local `formatISO`. Keying the run buckets by `started_at.slice(0,10)`
 * instead would use the UTC calendar date, so a run recorded in the local
 * evening in a positive-offset timezone would bucket under the next UTC day and
 * land on the wrong cell.
 */
export function localDateKey(isoTimestamp: string): string {
	return formatISO(new Date(isoTimestamp));
}

export function bucketRunsByLocalDay(runs: Run[]): Map<string, number> {
	const map = new Map<string, number>();
	for (const run of runs) {
		const day = localDateKey(run.started_at);
		map.set(day, (map.get(day) ?? 0) + run.distance_m);
	}
	return map;
}
