/// Validates a post-sign-in `return_to` target so it can only ever
/// point back at our own origin. The login page reads an attacker-
/// controllable `?return_to=` off the URL; a naive `startsWith('/')`
/// check passes protocol-relative (`//evil.com`) and backslash-
/// confusion (`/\evil.com`, `/\/evil.com`) values that the browser
/// resolves to a different origin — an open-redirect that turns the
/// trusted /login page into a phishing hop.
///
/// Returns a same-origin path (path + query + hash, never an absolute
/// URL) when the candidate is a safe internal destination, otherwise
/// the `/dashboard` fallback. Pure + unit-tested; the login page wraps
/// it so the validation can't drift between the $effect redirect and
/// the explicit submit-handler goto.

export const DEFAULT_RETURN_TO = '/dashboard';

export function safeReturnTo(
	raw: string | null | undefined,
	fallback: string = DEFAULT_RETURN_TO,
): string {
	if (!raw) return fallback;

	// Must be a root-relative path. Reject anything that doesn't start
	// with a single '/', and explicitly reject the off-origin forms
	// that still start with '/': '//host' (protocol-relative) and
	// '/\\host' / '/\/host' (backslash treated as '/' by browsers).
	if (raw[0] !== '/') return fallback;
	if (raw[1] === '/' || raw[1] === '\\') return fallback;

	// Resolve against a throwaway origin and confirm the result stays
	// on it. This catches anything the cheap prefix checks miss (e.g.
	// control chars, embedded credentials) without hand-rolling a URL
	// parser.
	let resolved: URL;
	try {
		resolved = new URL(raw, 'https://internal.invalid');
	} catch {
		return fallback;
	}
	if (resolved.origin !== 'https://internal.invalid') return fallback;

	// Re-serialise from the parsed URL so only the path/query/hash
	// survive — never the host, even if a parser quirk let one through.
	return `${resolved.pathname}${resolved.search}${resolved.hash}`;
}
