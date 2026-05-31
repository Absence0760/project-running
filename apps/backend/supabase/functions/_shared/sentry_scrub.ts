// Data-minimisation for Edge Function Sentry capture.
//
// Edge Functions run server-side, so they can't see the browser's
// cookie-consent state — there is no per-request consent gate to apply
// (unlike the web hooks). The lawful basis for server-side error
// monitoring is **legitimate interest** (operational security +
// reliability; GDPR Recital 49), recorded in
// docs/compliance/sub-processors.md.
//
// Legitimate interest still demands data minimisation (Art 5(1)(c)).
// The live risk is PostgREST errors: supabase-js surfaces a plain
// object `{ message, details, hint, code }`, and `details` / `hint`
// routinely embed the offending ROW's values (e.g. "Key (email)=
// (a@b.com) already exists"). The console path already logs only
// `.message` for this reason; this helper applies the same discipline
// to what reaches Sentry — capture the message + SQLSTATE code (enough
// to triage the error class) and drop the row-bearing `details`/`hint`.
// Real `Error` instances pass through unchanged (their stack is the
// triage value and carries no row data).
//
// audit-findings 2026-05-30 High [third-party-data-flows].

interface PostgrestLikeError {
	message: string;
	code?: string;
	details?: unknown;
	hint?: unknown;
}

function isPostgrestLikeError(err: unknown): err is PostgrestLikeError {
	return (
		typeof err === 'object' &&
		err !== null &&
		!(err instanceof Error) &&
		typeof (err as Record<string, unknown>).message === 'string' &&
		// Must carry at least one of the row-bearing / SQLSTATE fields to
		// be treated as a PostgREST error rather than an arbitrary object.
		('details' in err || 'hint' in err || 'code' in err)
	);
}

// Return a value safe to hand to Sentry.captureException: an Error
// carrying only the message (+ SQLSTATE code) for PostgREST-shaped
// errors, so the row-bearing details/hint never leave the database
// boundary. Everything else is returned unchanged.
export function sanitizeErrorForCapture(err: unknown): unknown {
	if (!isPostgrestLikeError(err)) return err;
	const code = typeof err.code === 'string' && err.code.length > 0 ? ` [${err.code}]` : '';
	const safe = new Error(`${err.message}${code}`);
	safe.name = 'PostgrestError';
	return safe;
}
