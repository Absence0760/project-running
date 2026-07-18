/// Pure normalisation helpers used by `data.ts`. Lifted into their own
/// module so the trim-and-null contract can be unit-tested without
/// pulling in the Supabase client (which `data.ts` imports at top
/// level and can't safely run under `node:test`).
///
/// Every helper mirrors the JS `s?.trim() || null` pattern used
/// throughout `data.ts`. Dart-side counterparts live in
/// `apps/mobile_android/lib/social_service.dart` (`buildCreateClubBody`,
/// `buildCreateEventBody`) and `apps/mobile_android/lib/training_service.dart`
/// (`trimToNull`); the test suites on both sides pin the same
/// edge cases (null / empty / whitespace / "0" truthiness / emoji).

/// Trim a string and collapse empty-after-trim to null. Mirrors
/// `s?.trim() || null`. Pulled out so it can be reused without the
/// `||` truthiness ambiguity at every call site.
export function trimOrNull(s: string | null | undefined): string | null {
	if (s == null) return null;
	const t = s.trim();
	return t.length > 0 ? t : null;
}

/// Normalise the `fields` patch handed to `updateRunMetadata`.
/// Trims every string value; empty-after-trim keys are dropped from
/// the patch entirely (so clearing the field via the run-detail edit
/// dialog actually removes the metadata key rather than leaving a
/// stale `""` behind).
///
/// Returns a partial object; callers spread it into the existing
/// metadata bag with the cleared keys explicitly deleted beforehand.
export function normaliseRunMetadataFields(fields: {
	title?: string;
	notes?: string;
}): { title?: string; notes?: string } {
	const out: { title?: string; notes?: string } = {};
	for (const key of ['title', 'notes'] as const) {
		const value = fields[key];
		if (typeof value !== 'string') continue;
		const trimmed = value.trim();
		if (trimmed.length > 0) out[key] = trimmed;
	}
	return out;
}

/// Apply an `updateRunMetadata` patch on top of an existing metadata
/// bag with the cleared keys explicitly removed. Returns the new
/// metadata object. Pure — no I/O. Tests pin the contract.
export function applyRunMetadataPatch(
	current: Record<string, unknown> | null | undefined,
	fields: { title?: string; notes?: string },
	now: string,
): Record<string, unknown> {
	const base = current ?? {};
	const next: Record<string, unknown> = { ...base };
	// Drop any key the caller is patching, then re-add normalised
	// values. This is how a whitespace-only edit clears the key
	// instead of writing `""`.
	for (const key of Object.keys(fields)) {
		delete next[key];
	}
	Object.assign(next, normaliseRunMetadataFields(fields));
	next.last_modified_at = now;
	return next;
}

/// The `runs.metadata.global_segments_scored_count` stamp: the number
/// of active `global_segments` a run's catalogue efforts were last
/// computed against. Lets the run-detail backfill skip the expensive
/// 500-row catalogue fetch + client-side haversine match on every view
/// once a run is scored, while still re-scoring when the (deliberately
/// growing) catalogue gains segments. Value-only (no view timestamp) so
/// the key carries no per-run private signal — the catalogue size is
/// identical for every run and public — and needs no `public_runs`
/// strip.
export function readGlobalSegmentsScoredCount(
	metadata: Record<string, unknown> | null | undefined,
): number | null {
	if (!metadata || typeof metadata !== 'object') return null;
	const count = (metadata as Record<string, unknown>).global_segments_scored_count;
	if (typeof count !== 'number' || !Number.isFinite(count) || count < 0) return null;
	return count;
}

/// Decide whether a run needs its global-segment efforts (re)computed.
/// True when the run was never scored, when the stamp is unreadable,
/// or when the active catalogue has grown past the count the run was
/// last scored against. `activeCount` null (an unknown / failed count
/// query) fails open to true — better to re-score once than to never
/// score a run whose catalogue size we couldn't read.
export function shouldRescoreGlobalSegments(
	metadata: Record<string, unknown> | null | undefined,
	activeCount: number | null | undefined,
): boolean {
	const scored = readGlobalSegmentsScoredCount(metadata);
	if (scored == null) return true;
	if (typeof activeCount !== 'number' || !Number.isFinite(activeCount)) return true;
	return activeCount > scored;
}

/// Merge the `global_segments_scored_count` stamp into a run's metadata
/// bag without clobbering the rest of it. Pure — the caller writes the
/// result back.
export function stampGlobalSegmentsScored(
	metadata: Record<string, unknown> | null | undefined,
	catalogueCount: number,
): Record<string, unknown> {
	const base = metadata ?? {};
	return { ...base, global_segments_scored_count: catalogueCount };
}

/// Normalise the `notes` field of a plan-workout update patch. Trims
/// and collapses empty-after-trim to null. Caller is responsible for
/// only invoking this when `notes` is present in the patch.
export function normalisePlanWorkoutNotes(
	value: string | null | undefined,
): string | null | undefined {
	if (value == null) return value;
	const t = value.trim();
	return t.length > 0 ? t : null;
}
