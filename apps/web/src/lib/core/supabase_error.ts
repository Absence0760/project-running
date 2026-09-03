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
