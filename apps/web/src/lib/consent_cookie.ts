// Cookie-name + cookie-parsing helper for the server-side Sentry
// gate. Lives in its own file so the test runner (tsx + node:test)
// can import it without pulling Svelte runes ($state) in via the
// neighbouring consent.svelte.ts.
//
// audit/cookie-consent + audit/third-party-data-flows (May 2026).
// Persona-hunt Round 3 finding Privacy #4 added the Sec-GPC short-
// circuit. See hooks.server.ts for the wiring.

export const CONSENT_COOKIE_NAME = 'cookie_consent';
export const CONSENT_COOKIE_ACCEPTED_VALUE = 'accepted';

/**
 * Returns true when the request carries a `Sec-GPC: 1` Global Privacy
 * Control signal — RFC-pending but adopted by Firefox, Brave, DuckDuckGo,
 * iOS Safari (via the Privacy Protections toggle). California AG +
 * Colorado AG have ruled GPC is a binding "Do Not Sell / Share" signal
 * under CCPA/CPRA + CPA; EDPB likewise treats it as an objection signal
 * under GDPR Art 21. Stateless / pure — same shape as the cookie helper.
 *
 * Persona-hunt Round 3 finding Privacy #4. Pre-fix the server ignored
 * the header entirely, so a GPC-enabled visitor still had Sentry +
 * other consent-gated paths load until they manually rejected the
 * banner (and the banner itself loaded over their explicit opt-out).
 */
export function hasGpcSignalFromHeader(
	gpcHeader: string | null | undefined,
): boolean {
	// Only "1" is the active opt-out signal per the spec; any other
	// value (including "0" and the absent header) means "no signal".
	return gpcHeader != null && gpcHeader.trim() === '1';
}

export function hasGpcSignal(request: Request): boolean {
	return hasGpcSignalFromHeader(request.headers.get('sec-gpc'));
}

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

/**
 * Combined gate the server-side hook reads on every request: returns
 * true only when the user has accepted AND has not sent a GPC signal.
 * The GPC signal hard-overrides the cookie — a user can flip their
 * browser's GPC toggle without revisiting the site and we MUST honour
 * the change immediately, not on next visit.
 */
export function isConsentGiven(request: Request): boolean {
	if (hasGpcSignal(request)) return false;
	return isConsentGivenFromCookieHeader(request.headers.get('cookie'));
}
