/**
 * Service-role cross-checks that fail as THEMSELVES.
 *
 * A spec's backend assertion is two claims stacked: that the read reached the
 * database, and that what came back is what the feature should have written.
 * `const { data } = await admin.from(...)` collapses them — the error is
 * discarded, an absent result becomes `null`, and the `?? 0` / `?? []` at the
 * assertion renders that absence as a legitimate value. Two failure modes come
 * out of that, and the quieter one is the worse:
 *
 *   - A failed read against a non-zero expectation FAILS, blaming the feature.
 *     `expect(Number(rollup?.total_distance_m ?? 0)).toBe(6000)` reports
 *     `Expected: 6000, Received: 0` and reads exactly like a broken derived
 *     cache, so the debugging goes to the trigger rather than to the read.
 *   - A failed read against a zero/empty expectation PASSES.
 *     `expect(rows ?? []).toEqual([])` is satisfied by a read that never
 *     reached the table, which is how an RLS negative assertion stops
 *     asserting anything while staying green.
 *
 * These helpers keep the two claims apart: the read either produces rows or
 * throws naming itself, and the `expect` that follows is only ever about the
 * feature. Same reasoning as `fetchMySafetyContacts` reporting its error
 * instead of degrading to `[]` (decisions.md § 720), applied to the harness.
 */

type ReadError = { message: string; code?: string };

/**
 * The shape every postgrest-js response has, loose enough that the row type is
 * read back off the response rather than inferred into it. Matching a
 * `{ data: T; error: null }` parameter against postgrest's own discriminated
 * union lets `T` bind to the FAILURE arm's `null`, which collapses every field
 * read downstream to `never`; an indexed access cannot.
 */
type ReadResponse = { data: unknown; error: ReadError | null };
type RowsResponse = { data: readonly unknown[] | null; error: ReadError | null };

function describe(what: string, error: ReadError): string {
	const code = error.code ? ` [${error.code}]` : '';
	return `${what}: the read itself failed${code} — ${error.message}`;
}

/**
 * Rows from a query that may legitimately match none. Zero rows is a real
 * answer and comes back as `[]`; a read that could not run throws.
 */
export async function readRows<R extends RowsResponse>(
	what: string,
	query: PromiseLike<R>
): Promise<NonNullable<R['data']>> {
	const { data, error } = await query;
	if (error) throw new Error(describe(what, error));
	if (data === null) throw new Error(`${what}: the read returned no rows array and no error.`);
	return data as NonNullable<R['data']>;
}

/**
 * The one row a `.single()` promises. A missing row throws as a missing row
 * rather than being coalesced into a zero the caller then asserts against.
 */
export async function readRow<R extends ReadResponse>(
	what: string,
	query: PromiseLike<R>
): Promise<NonNullable<R['data']>> {
	const { data, error } = await query;
	// PGRST116 is `.single()`'s "not exactly one row": the read worked and the
	// row is absent. Said separately because it points at the write, not the read.
	if (error?.code === 'PGRST116') {
		throw new Error(`${what}: expected exactly one row, the table had none — ${error.message}`);
	}
	if (error) throw new Error(describe(what, error));
	if (data === null || data === undefined) {
		throw new Error(`${what}: expected exactly one row, got none.`);
	}
	return data as NonNullable<R['data']>;
}

/**
 * A row whose ABSENCE is the thing under test — a deleted record, an
 * unclaimed result. Returns `null` for "not there" and throws for "could not
 * look", so the two stay distinguishable at the assertion.
 */
export async function readMaybeRow<R extends ReadResponse>(
	what: string,
	query: PromiseLike<R>
): Promise<NonNullable<R['data']> | null> {
	const { data, error } = await query;
	if (error?.code === 'PGRST116') return null;
	if (error) throw new Error(describe(what, error));
	return (data ?? null) as NonNullable<R['data']> | null;
}

/**
 * The row count from a `{ count: 'exact', head: true }` probe. `count` is
 * nullable on the wire, and a `?? 0` at the call site turns a failed probe
 * into a confident zero — the same swallow one field over.
 */
export async function readCount(
	what: string,
	query: PromiseLike<{ count: number | null; error: ReadError | null }>
): Promise<number> {
	const { count, error } = await query;
	if (error) throw new Error(describe(what, error));
	if (count === null) throw new Error(`${what}: the count probe returned no count and no error.`);
	return count;
}
