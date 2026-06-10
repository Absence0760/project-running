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

/**
 * Sum each local day's distance into a `localDateKey -> metres` map.
 *
 * `sinceMs` is an absolute epoch-ms cutoff: runs that started before it are
 * skipped. The heatmap only ever renders a fixed window of recent weeks, so
 * bucketing the entire history just to discard the out-of-window part — and
 * then spreading the whole map into `Math.max` — is work that grows unbounded
 * with account age. Passing the grid's first-day timestamp keeps both the
 * loop's productive work and the returned map bounded to the visible window.
 * Defaults to `-Infinity` (bucket everything) so non-windowed callers are
 * unaffected. perf-hunt 2026-06-10.
 */
export function bucketRunsByLocalDay(runs: Run[], sinceMs = -Infinity): Map<string, number> {
	const map = new Map<string, number>();
	for (const run of runs) {
		const dt = new Date(run.started_at);
		if (dt.getTime() < sinceMs) continue;
		const day = formatISO(dt);
		map.set(day, (map.get(day) ?? 0) + run.distance_m);
	}
	return map;
}
