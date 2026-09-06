/// Extract only the log-safe fields from a Supabase/PostgREST error.
/// `.code` + `.message` are safe to log; `.details` and `.hint` can
/// echo row fragments — on the coach path the caller's chat content is
/// Art 9 health/injury data, and on the route paths it is location —
/// and the raw object must never reach CloudWatch.
///
/// Lives here rather than beside its first caller so a server handler
/// can scrub a log line without importing the coach handler (and the
/// Anthropic SDK behind it). Mirrors the `.code`/`.message` pattern used
/// in rate_limit_errors.ts + the Edge Functions, and is the shape the
/// edge_function_guards.test.ts raw-object ban enforces. /audit/pii-in-logs.
export function supabaseErrorFields(
	err: { code?: string; message?: string } | null | undefined,
): { code: string | undefined; message: string | undefined } {
	return { code: err?.code, message: err?.message };
}

/// SQLSTATE 23505 — `unique_violation`. Postgres raises it when an insert
/// re-states a row that already exists, which for every join-shaped write in
/// this app (bookmark a route, join a club, follow a runner, join a challenge)
/// is the SUCCESS case restated: a double-tap, a stale list whose "joined"
/// flag was computed before someone else's tab wrote the row, an offline
/// replay. Absorbing it is the difference between a no-op and a raw failure
/// toast on a button the user has already succeeded at pressing.
///
/// One predicate rather than a comparison against the literal at each site:
/// the sites drifted, and `joinChallenge` was the one that never got it.
export function isDuplicateKeyError(
	err: { code?: string | null } | null | undefined,
): boolean {
	return err?.code === '23505';
}
