/// The sentence a throttled caller reads, assembled from the catalogue.
///
/// `util/rate_limit_errors.ts` (the Dart-parity half) parses the postgres
/// P0001 into `{bucket, seconds}` and stops there, because both halves of
/// the sentence are per-locale decisions: the activity is a clause whose
/// verb inflects, and the wait pluralises. So the bucket picks a whole
/// translated sentence and the wait is the one noun phrase dropped into
/// it — a slot that survives every locale we ship, where a `{activity}`
/// slot would not (German puts the verb second and the object last).
///
/// The lookup arrives as an argument rather than being imported: `m` lives
/// in a runes module the `tsx --test` runner cannot compile, and this file
/// is where the mapping worth testing is. It mirrors mobile's
/// `rateLimitMessage(l10n, info)` — the render glue is per-platform (the
/// key strings differ by convention), and unlike the parser it is NOT part
/// of the enforced lockstep. decisions.md § 744.

import type { MessageKey } from './messages';
import { parseRateLimitError, type RateLimitInfo } from '../util/rate_limit_errors';

export type Translate = (key: MessageKey, params?: Record<string, string | number>) => string;

/// Every bucket `enforce_create_rate_limit` is called with today. The two
/// direct-message buckets (a 30/60 s burst and a 250/3600 s hour cap,
/// decisions § 737) share one sentence: which of the two windows refused
/// is our accounting, not something to explain to a sender. So do the two
/// plan-adopt paths, which are the same act from two libraries.
const BUCKET_KEY: Record<string, MessageKey> = {
	create_club: 'rateLimit.createClub',
	create_route: 'rateLimit.createRoute',
	create_report: 'rateLimit.createReport',
	clone_plan_template: 'rateLimit.adoptPlan',
	clone_public_plan: 'rateLimit.adoptPlan',
	clone_session_template: 'rateLimit.adoptSessionPlan',
	clone_gym_routine_template: 'rateLimit.adoptGymRoutine',
	publish_gym_routine_as_template: 'rateLimit.publishRoutine',
	send_direct_message: 'rateLimit.sendMessage',
	send_direct_message_burst: 'rateLimit.sendMessage',
};

/// Above this the wait reads better in minutes, rounded up so we never
/// invite a retry that is still inside the window.
const MINUTE_CUTOFF_S = 90;

export function rateLimitWait(t: Translate, seconds: number | null): string {
	if (seconds === null) return t('rateLimit.waitSoon');
	if (seconds < MINUTE_CUTOFF_S) return t('rateLimit.waitSeconds', { n: seconds });
	return t('rateLimit.waitMinutes', { n: Math.ceil(seconds / 60) });
}

export function rateLimitMessage(t: Translate, info: RateLimitInfo): string {
	const key = BUCKET_KEY[info.bucket] ?? 'rateLimit.generic';
	return t(key, { wait: rateLimitWait(t, info.seconds) });
}

/// Parse-and-render in one call, for the data-layer wrappers that rethrow
/// the friendly string. Null when the error is not a rate-limit refusal,
/// so the caller rethrows the original rather than masking it.
export function rateLimitErrorMessage(
	t: Translate,
	err: { code?: string; message?: string } | null | undefined,
): string | null {
	const info = parseRateLimitError(err);
	return info === null ? null : rateLimitMessage(t, info);
}
