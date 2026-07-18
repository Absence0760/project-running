export interface OrdinalCheckpoint {
	id: string;
	ordinal: number;
}

export interface ReorderDeps {
	update: (id: string, patch: { ordinal: number }) => Promise<unknown>;
	reload: () => Promise<void>;
}

/** Swap two checkpoints' ordinals to reorder. The (event_id, ordinal) unique
 *  constraint forbids a transient collision, so park `a` at a temp ordinal
 *  first, then settle `b` into `a`'s slot and `a` into `b`'s. The three writes
 *  are NOT transactional, so a mid-sequence failure leaves a partial swap on
 *  the server; `reload` re-reads authoritative state on both the success and
 *  the failure path so the in-memory list can never show the pre-swap order
 *  over a half-applied server swap. Rethrows so the caller can surface a toast. */
export async function swapCheckpointOrdinals(
	checkpoints: readonly OrdinalCheckpoint[],
	index: number,
	dir: -1 | 1,
	deps: ReorderDeps
): Promise<void> {
	const a = checkpoints[index];
	const b = checkpoints[index + dir];
	const temp = Math.max(...checkpoints.map((c) => c.ordinal)) + 1000;
	try {
		await deps.update(a.id, { ordinal: temp });
		await deps.update(b.id, { ordinal: a.ordinal });
		await deps.update(a.id, { ordinal: b.ordinal });
		await deps.reload();
	} catch (e) {
		await deps.reload();
		throw e;
	}
}
