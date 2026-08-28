/// What the `strava-import` Edge Function says about a backfill, and how
/// much of it a client may believe.
///
/// The function walks Strava's activity pages until it reaches the end of
/// the lookback window — or until Strava throttles us (429/503), an
/// upstream call fails, a page comes back malformed, or the 20-page
/// safety cap trips. Four of those five exits leave activities in the
/// window unfetched. `complete` is the field that separates them from a
/// finished walk; `rateLimited` names the one cause the runner can act on
/// (wait ~15 minutes) rather than merely retry.
///
/// This matters more than a missing count. The window is measured from
/// `Date.now()`, so the activities a truncated sync skipped stay
/// reachable by a later sync ONLY until they age past `lookbackDays`
/// (90 by default, and neither client offers a way to ask for more). A
/// sync that reports "complete" when it is not is therefore a data loss
/// on a 90-day fuse: it is the report, not the truncation, that stops the
/// runner from syncing again.
///
/// Hence the fail-closed direction, which is deliberately the OPPOSITE of
/// `backup/cloud_export_helpers.ts`'s `cloudExportShortfall` — there an
/// absent `complete` means one of two transports is an older deployment
/// and warning on every export would be its own dishonesty. Here there is
/// one transport, shipped from this repo alongside its callers, and the
/// costs are not symmetric: a false "partial" costs one extra click, a
/// false "complete" costs the runs. So anything this parser cannot read
/// as an explicit `true` is reported as partial.

export interface StravaSyncResult {
	imported: number;
	skipped: number;
	failed: number;
	/// Strava throttled us mid-walk. Implies `complete === false`.
	rateLimited: boolean;
	/// The lookback window was walked to its end. Only an explicit `true`
	/// from the function earns this.
	complete: boolean;
	/// Present on the `connect` response only.
	athleteId: string | null;
	/// An error the function embedded in an otherwise-2xx body. Forces
	/// `complete` false — a body that reports a failure is not evidence
	/// that a window was walked.
	error: string | null;
}

/// A count the function sent. Only a non-negative integer is a count;
/// anything else (a float, a negative, a string, `null`, absent) is a
/// malformed payload and reads as 0 rather than as a number the UI would
/// then state as fact.
function count(value: unknown): number {
	return typeof value === 'number' && Number.isInteger(value) && value >= 0 ? value : 0;
}

function text(value: unknown): string | null {
	if (typeof value !== 'string') return null;
	const trimmed = value.trim();
	return trimmed.length > 0 ? trimmed : null;
}

/// Grade the function's response. Never throws: an unrecognised shape —
/// null, an array, a string, a body from a deployment that predates
/// `complete` — yields zeroed counts and `complete: false`, which every
/// caller renders as "sync again to finish".
export function parseStravaSyncResult(data: unknown): StravaSyncResult {
	if (data === null || typeof data !== 'object' || Array.isArray(data)) {
		return {
			imported: 0,
			skipped: 0,
			failed: 0,
			rateLimited: false,
			complete: false,
			athleteId: null,
			error: null,
		};
	}
	const raw = data as Record<string, unknown>;
	const error = text(raw.error);
	return {
		imported: count(raw.imported),
		skipped: count(raw.skipped),
		failed: count(raw.failed),
		rateLimited: raw.rate_limited === true,
		complete: error === null && raw.complete === true,
		athleteId: text(raw.athlete_id),
		error,
	};
}
