/// The sentence shown when a bulk import refuses the file outright.
///
/// `integrations/import_refusal.ts` carries the refusal as a reason
/// identifier plus its specifics as data and stops there; the sentence is a
/// per-locale decision, so the reason picks a whole translated string and
/// only the figures are dropped into slots. Same split as
/// `rate_limit_message.ts`, and the lookup arrives as an argument for the
/// same reason: `m` lives in a runes module `tsx --test` cannot compile.
///
/// A thrown value that is NOT one of our refusals still has to say
/// something. It is framed inside `fallbackKey`'s `{error}` slot rather
/// than rendered bare — the shape issue #345 settled for every other error
/// slot on the site, and the reason this function takes the raw value
/// rather than a narrowed one.

import type { MessageKey } from './messages';
import { asImportRefusal, type ImportRefusalReason } from '../integrations/import_refusal';

export type Translate = (key: MessageKey, params?: Record<string, string | number>) => string;

const REASON_KEY: Record<ImportRefusalReason, MessageKey> = {
	not_signed_in: 'importRefusal.notSignedIn',
	strava_zip_too_large: 'importRefusal.stravaZipTooLarge',
	strava_zip_not_an_export: 'importRefusal.stravaZipNotAnExport',
	strava_zip_no_rows: 'importRefusal.stravaZipNoRows',
	strava_zip_missing_columns: 'importRefusal.stravaZipMissingColumns',
	garmin_unsupported_file: 'importRefusal.garminUnsupportedFile',
};

export function importRefusalMessage(
	t: Translate,
	err: unknown,
	fallbackKey: MessageKey,
): string {
	const refusal = asImportRefusal(err);
	if (refusal === null) {
		return t(fallbackKey, { error: err instanceof Error ? err.message : String(err) });
	}
	const { reason, data } = refusal;
	const params: Record<string, string | number> = {};
	if (reason === 'strava_zip_too_large') {
		params.size = data.megabytes ?? 0;
		params.limit = data.limitMegabytes ?? 0;
	}
	if (reason === 'strava_zip_missing_columns') {
		// Joined, not list-formatted: these are literal `activities.csv`
		// header cells the operator has to search a file for, so a locale's
		// conjunction would read as part of a column name.
		params.columns = (data.columns ?? []).join(' / ');
	}
	return t(REASON_KEY[reason], params);
}
