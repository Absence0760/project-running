// Cookie-name + cookie-parsing helper for the server-side Sentry
// gate. Lives in its own file so the test runner (tsx + node:test)
// can import it without pulling Svelte runes ($state) in via the
// neighbouring consent.svelte.ts.
//
// audit/cookie-consent + audit/third-party-data-flows (May 2026).
// See hooks.server.ts for the wiring.

export const CONSENT_COOKIE_NAME = 'cookie_consent';
export const CONSENT_COOKIE_ACCEPTED_VALUE = 'accepted';

/**
 * Returns true when the request carries an `accepted` consent cookie.
 * Stateless / pure — does not consult localStorage, browser state, or
 * SvelteKit context, so it's reachable from any request-shaped input.
 *
 * Cookie name is case-sensitive per RFC 6265 §4.2.1.
 */
export function isConsentGivenFromCookieHeader(
	cookieHeader: string | null | undefined,
): boolean {
	if (!cookieHeader) return false;
	const cookies = cookieHeader.split(/;\s*/);
	for (const c of cookies) {
		const eq = c.indexOf('=');
		if (eq === -1) continue;
		const name = c.slice(0, eq).trim();
		if (name !== CONSENT_COOKIE_NAME) continue;
		const value = decodeURIComponent(c.slice(eq + 1).trim());
		if (value === CONSENT_COOKIE_ACCEPTED_VALUE) return true;
	}
	return false;
}

export function isConsentGiven(request: Request): boolean {
	return isConsentGivenFromCookieHeader(request.headers.get('cookie'));
}
