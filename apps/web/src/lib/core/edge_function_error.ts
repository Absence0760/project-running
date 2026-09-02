/// Reading a failed `supabase.functions.invoke` for something a person can act on.
///
/// supabase-js reports EVERY non-2xx from an Edge Function as a
/// `FunctionsHttpError` whose `message` is the fixed sentence "Edge Function
/// returned a non-2xx status code"; the function's own `{ error: '<code>' }`
/// envelope rides on `context`, which is the raw `Response`. Surfacing
/// `error.message` therefore renders a statement about our transport in a
/// slot the caller wrote for a reason, and collapses every refusal — sold
/// out, sales closed, a host who cannot take money, a build with no keys, a
/// revoked token, a genuine outage — into one unactionable line.
///
/// The unwrap lived privately in `core/data.ts` and only `cancelEventOrder`
/// used it, so three other money-and-integration surfaces shipped the
/// internal sentence to users. It lives here because four call sites across
/// two modules need it.

/// The machine `error` code out of the envelope, or null when there is no
/// readable body (a relay/fetch failure, a non-JSON error page, an already
/// consumed Response).
export async function edgeFunctionErrorCode(error: unknown): Promise<string | null> {
	const ctx = (error as { context?: Response })?.context;
	if (!ctx || typeof ctx.clone !== 'function') return null;
	try {
		const body = await ctx.clone().json();
		const code = (body as { error?: string })?.error;
		return typeof code === 'string' ? code : null;
	} catch {
		return null;
	}
}

/// What a caller should put in front of a person. The envelope's code when
/// there is one; otherwise the caller's own fallback rather than the
/// FunctionsHttpError's fixed sentence — an HTTP-error shape (it carries the
/// `context` Response) has no message worth showing, so the fallback is
/// strictly better than what it holds.
export async function edgeFunctionErrorMessage(
	error: unknown,
	fallback: string,
): Promise<string> {
	const code = await edgeFunctionErrorCode(error);
	if (code) return code;
	if (error && typeof error === 'object' && 'context' in error) return fallback;
	return error instanceof Error && error.message ? error.message : fallback;
}
