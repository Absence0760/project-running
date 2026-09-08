// The read-side narrowing a `runs` row goes through before it is a `Run`.
//
// Split out of `core/data.ts` so it can be run rather than only read: that
// module evaluates the `supabase` singleton and `$env/static/public` at
// import, so everything in it is pinned by source guards. Which key a
// projection may carry is a runtime rule, and a runtime rule earns a runtime
// test.

import type { Database } from '../database.types';
import { parseRunSource, parseActivityType, parseRunMetadata, type Run } from '../types';

export type RunRow = Database['public']['Tables']['runs']['Row'];

/// The three `runs` columns the `Run` overlay types more narrowly than the
/// column does: two CHECK-constrained `text`s and a jsonb bag. A read that
/// declares `Run` and applies fewer than three of these is promising a
/// vocabulary it never checked — which is what the unnarrowed `fetchRuns`
/// did until its rows stopped being `any[]` and the compiler could see it
/// (§ 1519).
export function narrowFullRun(r: RunRow): Run {
	return {
		...r,
		source: parseRunSource(r.source),
		activity_type: parseActivityType(r.activity_type),
		metadata: parseRunMetadata(r.metadata),
		// A lazy Storage download, never a column, so `*` cannot have read it.
		track: null,
	};
}

/// The same three narrows against a projection, which carries only the columns
/// the caller asked for. Each is applied if and only if the column is present:
/// a key PostgREST did not send is a key the row type does not declare, so
/// adding one would invent a value for a column this read never looked at —
/// which is what the blanket `track: null` did on every narrowed row (§ 1520).
/// `undefined` is exactly "not selected": JSON has no such value, so a
/// selected-but-empty column arrives as `null` and is narrowed like any other.
export function narrowProjectedRun({
	source,
	activity_type,
	metadata,
	...rest
}: Partial<RunRow>): Partial<Run> {
	return {
		...rest,
		...(source !== undefined ? { source: parseRunSource(source) } : {}),
		...(activity_type !== undefined ? { activity_type: parseActivityType(activity_type) } : {}),
		...(metadata !== undefined ? { metadata: parseRunMetadata(metadata) } : {}),
	};
}
