/// File-level refusals from the bulk importers, carried as data.
///
/// `import_failures.ts` handles the other kind: one ROW of an archive that
/// did not import, classified into a reason and reported beside the
/// activity's own name. A refusal here is the whole file — nothing imports,
/// and this sentence is the only thing the operator gets. It used to be an
/// English `Error` message assigned straight into the page's error slot, so
/// the most informative message in the migration flow was the one string on
/// `/settings/integrations` that never translated.
///
/// The reason is an IDENTIFIER and the specifics travel as data, so the
/// sentence is assembled from the catalogue at the render layer
/// (`i18n/import_refusal_message.ts`) — the split `util/rate_limit_errors.ts`
/// already keeps from `i18n/rate_limit_message.ts`.

export type ImportRefusalReason =
	| 'not_signed_in'
	| 'strava_zip_too_large'
	| 'strava_zip_not_an_export'
	| 'strava_zip_no_rows'
	| 'strava_zip_missing_columns'
	| 'garmin_unsupported_file';

export const IMPORT_REFUSAL_REASONS: readonly ImportRefusalReason[] = [
	'not_signed_in',
	'strava_zip_too_large',
	'strava_zip_not_an_export',
	'strava_zip_no_rows',
	'strava_zip_missing_columns',
	'garmin_unsupported_file',
];

export interface ImportRefusalData {
	/// `strava_zip_too_large`: the archive's own size and the cap it passed,
	/// both in whole megabytes.
	megabytes?: number;
	limitMegabytes?: number;
	/// `strava_zip_missing_columns`: the header cells the export does not
	/// name. Literal `activities.csv` column labels, never translated — the
	/// operator has to find them in a file we did not write.
	columns?: string[];
}

export class ImportRefusedError extends Error {
	readonly reason: ImportRefusalReason;
	readonly data: ImportRefusalData;

	constructor(reason: ImportRefusalReason, data: ImportRefusalData = {}) {
		// The identifier, not a sentence: anything that logs or re-throws
		// this gets the machine-readable reason, the same shape
		// `exchangeStravaCode` rethrows `strava_not_configured` in.
		super(reason);
		this.name = 'ImportRefusedError';
		this.reason = reason;
		this.data = data;
	}
}

/// Narrow a thrown value to a refusal this build can render, or null.
///
/// Read structurally rather than with `instanceof`: the check has to hold
/// for a value that crossed a module boundary, and a reason string this
/// build has no key for must fall through to the framed-generic path rather
/// than render a bare identifier at the reader.
export function asImportRefusal(
	err: unknown,
): { reason: ImportRefusalReason; data: ImportRefusalData } | null {
	if (err === null || typeof err !== 'object') return null;
	const reason = (err as { reason?: unknown }).reason;
	if (typeof reason !== 'string') return null;
	if (!IMPORT_REFUSAL_REASONS.includes(reason as ImportRefusalReason)) return null;
	const data = (err as { data?: unknown }).data;
	return {
		reason: reason as ImportRefusalReason,
		data: data !== null && typeof data === 'object' ? (data as ImportRefusalData) : {},
	};
}
