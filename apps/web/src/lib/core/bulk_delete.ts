import { chunk } from '../social/feed_merge';

export const DELETE_RUNS_CONCURRENCY = 8;

/// Runs `deleteFn` across `ids` in bounded `concurrency`-sized waves,
/// preserving the `Promise.allSettled` partial-failure contract (one
/// rejection doesn't abort the rest) and the per-id ordering within a
/// wave. Returns the ids whose deletion rejected. Extracted from
/// `deleteRuns` in data.ts so the concurrency bound is unit-testable
/// without importing the Supabase-backed data module (issue #343).
export async function deleteRunsBounded(
	ids: string[],
	deleteFn: (id: string) => Promise<void>,
	concurrency = DELETE_RUNS_CONCURRENCY,
): Promise<{ failed: string[] }> {
	if (ids.length === 0) return { failed: [] };
	const failed: string[] = [];
	for (const batch of chunk(ids, concurrency)) {
		const results = await Promise.allSettled(batch.map((id) => deleteFn(id)));
		for (let i = 0; i < results.length; i++) {
			if (results[i].status === 'rejected') failed.push(batch[i]);
		}
	}
	return { failed };
}
