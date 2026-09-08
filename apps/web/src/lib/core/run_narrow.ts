// The read-side narrowing a `runs` row goes through before it is a `Run`.
//
// Split out of `core/data.ts` so it can be run rather than only read: that
// module evaluates the `supabase` singleton and `$env/static/public` at
// import, so everything in it is pinned by source guards. Which key a
// projection may carry is a runtime rule, and a runtime rule earns a runtime
// test.

import type { Database } from '../database.types';
import {
	parseRunSource,
	parseActivityType,
	parseRunMetadata,
	type Run,
	type TrackPoint
} from '../types';

export type RunRow = Database['public']['Tables']['runs']['Row'];

/// One whole `runs` row as the `Run` a consumer reads — the ONE normaliser
/// this table has, per the house rule that the several reads of a table cannot
/// drift into doing different subsets of the narrowing.
///
/// The three columns are the ones the `Run` overlay types more narrowly than
/// the column does: `source` and `activity_type` are CHECK-constrained unions
/// the generated row types as bare strings, and `metadata` is jsonb typed
/// `Json`, which admits a scalar and an array as well as a bag every reader
/// will index into. A read that declares `Run` and applies fewer than three of
/// these is promising a vocabulary it never checked — which is what the
/// unnarrowed `fetchRuns` did, with its own partial copy of this function,
/// until its rows stopped being `any[]` and the compiler could see it
/// (§ 1519).
///
/// `track` is a parameter rather than a default because it is not a column:
/// `fetchRunById` lazily downloads it from Storage, and a read that selected
/// every column still cannot have read it, so that read passes null.
///
/// Only a read that selects every column can use this. The windowed
/// projections (`fetchRunsForDashboard`, `fetchRunsForRecap`) carry their own
/// row shapes — see § 1330 — and narrow through `asProjectedRun`.
export function asRun(row: RunRow, track: TrackPoint[] | null): Run {
	return {
		...row,
		source: parseRunSource(row.source),
		activity_type: parseActivityType(row.activity_type),
		metadata: parseRunMetadata(row.metadata),
		track
	};
}

/// The same three narrows against a projection, which carries only the columns
/// the caller asked for. Each is applied if and only if the column is present:
/// a key PostgREST did not send is a key the row type does not declare, so
/// adding one would invent a value for a column this read never looked at —
/// which is what the blanket `track: null` did on every narrowed row (§ 1520).
/// `undefined` is exactly "not selected": JSON has no such value, so a
/// selected-but-empty column arrives as `null` and is narrowed like any other.
export function asProjectedRun({
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
