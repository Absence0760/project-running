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
