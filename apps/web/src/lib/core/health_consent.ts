// Which date of birth a health inference is allowed to use.
//
// `date_of_birth` is two records under one column name (decisions § 718).
// `user_profiles.date_of_birth` is the **age record**: its consumer is the
// under-18 exclusion in `search_user_profiles` / `discoverable_runners_near`,
// a child-protection purpose that does not rest on the runner's consent and
// must not be defeated by declining it — so every entry point writes it
// whenever a date is supplied, with no consent term.
// `user_settings.prefs.date_of_birth` is the **Art 9 health-use mirror**:
// written only under consent, cleared on withdrawal.
//
// Reading the column and feeding it to a health inference — VO2max, HR max,
// calorie targets, age grading, the masters recovery calibration — spends the
// ungated record on the gated purpose. That is Art 9 processing and belongs
// behind `health_data_consent_at`, exactly as `coach/context.ts` re-gates its
// own read of the mirror.
//
// This module is the one place that rule is written down. It takes the
// `get_my_profile()` row a surface already reads (the RPC returns the whole
// row, so the consent stamp arrives with the date — no extra round trip) and
// answers with the date only when consent is on record. Surfaces that read
// the prefs-bag mirror instead need no gate: the mirror already follows
// consent in both directions.
//
// Twin of `apps/mobile_android/lib/health_consent.dart` — keep the rule,
// the states, the precedence, and the test count in lockstep.

/**
 * - `usable`            — a date is on record and consent is too.
 * - `absent`            — no date on record. Nothing to consent about.
 * - `consent_withheld`  — a date is on record but the Art 9 consent is not,
 *                         so a health surface may say why the figure is
 *                         missing rather than render a blank or claim the
 *                         runner never supplied one.
 */
export type HealthUseDobState = 'usable' | 'absent' | 'consent_withheld';

/** Length of a bare `YYYY-MM-DD`; anything shorter cannot be a date. */
const ISO_DATE_LENGTH = 10;

function rowField(row: unknown, key: string): string | null {
	if (!row || typeof row !== 'object') return null;
	const v = (row as Record<string, unknown>)[key];
	return typeof v === 'string' && v.length > 0 ? v : null;
}

/**
 * Grade a `get_my_profile()` row of unknown shape. Fail-closed in both
 * directions: an unreadable row, a missing stamp and an unusable date each
 * withhold the date rather than guess.
 */
export function healthUseDobState(row: unknown): HealthUseDobState {
	const dob = rowField(row, 'date_of_birth');
	if (dob == null || dob.length < ISO_DATE_LENGTH) return 'absent';
	return rowField(row, 'health_data_consent_at') == null ? 'consent_withheld' : 'usable';
}

/**
 * The `YYYY-MM-DD` a health inference may use, or null. Normalised to the
 * leading date so a caller can hand it to `ageFromDob` / `ageGradeForRun`
 * whether the column arrived as a bare date or a full timestamp.
 */
export function healthUseDob(row: unknown): string | null {
	if (healthUseDobState(row) !== 'usable') return null;
	return rowField(row, 'date_of_birth')!.slice(0, ISO_DATE_LENGTH);
}
