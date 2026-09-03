/// What an importer says about how much of a history it read, and how much of
/// it a client may believe.
///
/// `parkrun-import` answers `{ imported, skipped, total, complete }` and
/// `race-results-import` answers `complete` on every success shape. Neither
/// count reveals a shortfall on its own: a parkrun history capped at
/// `MAX_PARKRUN_ROWS` and a finisher field truncated at 2,000 both present as
/// a successful import of everything that was there.
///
/// Fail-closed — anything this parser cannot read as an explicit `true` is
/// reported as partial. One transport per importer, shipped from this repo
/// alongside its callers, so an absent `complete` means a body this build does
/// not recognise rather than an older deployment of a second transport (which
/// is what makes `backup/cloud_export_helpers.ts`'s `cloudExportShortfall`
/// fail the other way). A false "partial" costs a sentence the runner can
/// ignore; a false "complete" tells them a history is whole when it is not.
///
/// The two count/text primitives below are exported because
/// `strava_sync_result.ts` grades the same fields by the same rule — a sync IS
/// an import, and one home for the rule is what stops the two parsers reading
/// the same malformed body differently. `strava_sync_result` composes on this
/// module rather than the reverse: naming the general rule after one provider
/// is what put parkrun and race-results grading in a file called
/// `strava_sync_result` in the first place (decisions § 1014).

/// A count the function sent. Only a non-negative integer is a count;
/// anything else (a float, a negative, a string, `null`, absent) is a
/// malformed payload and reads as 0 rather than as a number the UI would
/// then state as fact.
export function importResponseCount(value: unknown): number {
	return typeof value === 'number' && Number.isInteger(value) && value >= 0 ? value : 0;
}

/// A non-blank string the function sent, trimmed, or null.
export function importResponseText(value: unknown): string | null {
	if (typeof value !== 'string') return null;
	const trimmed = value.trim();
	return trimmed.length > 0 ? trimmed : null;
}

export interface ImportCompleteness {
	imported: number;
	skipped: number;
	/// How many rows the page actually carried, when the function said. Null
	/// when it did not, so a caller can tell "12 of 60" from "12, and there
	/// may be more" rather than printing a fabricated denominator.
	total: number | null;
	/// Only an explicit `true` earns it.
	complete: boolean;
}

/// Grade an importer's response. Never throws.
export function parseImportCompleteness(data: unknown): ImportCompleteness {
	if (data === null || typeof data !== 'object' || Array.isArray(data)) {
		return { imported: 0, skipped: 0, total: null, complete: false };
	}
	const raw = data as Record<string, unknown>;
	const imported = importResponseCount(raw.imported);
	const skipped = importResponseCount(raw.skipped);
	// An embedded error forces partial even beside a `complete: true`, matching
	// `parseStravaSyncResult`: the function answered about a walk it did not
	// finish.
	const complete = importResponseText(raw.error) === null && raw.complete === true;
	const total =
		typeof raw.total === 'number' && Number.isInteger(raw.total) && raw.total >= 0
			? raw.total
			: null;
	return {
		imported,
		skipped,
		// A total below what was already processed is not a total — reporting
		// "12 of 5" is worse than reporting no denominator at all.
		total: total !== null && total >= imported + skipped ? total : null,
		complete,
	};
}
