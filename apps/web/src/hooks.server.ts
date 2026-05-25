import * as Sentry from "@sentry/sveltekit";
import type { Handle, HandleServerError } from "@sveltejs/kit";
import { dev } from "$app/environment";
import { env } from "$env/dynamic/private";
import { isConsentGiven } from "$lib/consent_cookie";

// audit/cookie-consent + audit/third-party-data-flows (May 2026)
// flagged that server-side Sentry initialised + intercepted every
// request before the user had seen the consent banner. EU IPs were
// forwarded to a US sub-processor (Sentry) under no lawful basis.
//
// Three-layer gate (self-audit caught that the original two-layer
// version still leaked 5xx errors via handleErrorWithSentry):
//   1. Sentry.init() runs once at module load — keep the dev/dsn
//      condition; the client never gets a chance to consent if the
//      server isn't even configured for tracing.
//   2. The handle middleware that wires sentryHandle() into the
//      request flow now reads the consent cookie per-request (via
//      isConsentGiven, which is a pure cookie-parsing helper so
//      the gate stays unit-testable without Svelte runtime).
//      Requests without an "accepted" cookie skip Sentry entirely —
//      no IP capture, no traces sent.
//   3. handleError is wrapped to do the same consent check before
//      capturing. Sentry's handleErrorWithSentry calls
//      captureException unconditionally for 5xx errors; a server
//      error from an unconsented user would otherwise still ship
//      the stack + URL + IP to Sentry. The wrapped version logs
//      the error to stderr (so it still surfaces in CloudWatch /
//      Lambda logs) and skips the Sentry call.
//
// The cookie is written by the client-side consent module
// ($lib/consent.svelte). When the user accepts, the cookie ships
// on the next request; when they reset, it's cleared. Requests
// before the banner is interacted with have no cookie and are
// excluded.

if (!dev && env.SENTRY_DSN) {
	Sentry.init({
		dsn: env.SENTRY_DSN,
		release: env.APP_RELEASE || "dev",
		environment: env.APP_RELEASE && env.APP_RELEASE !== "dev" ? "production" : "development",
		tracesSampleRate: 0.1,
	});
}

const sentryHandle = Sentry.sentryHandle();
const sentryHandleError = Sentry.handleErrorWithSentry();

export const handle: Handle = async ({ event, resolve }) => {
	if (isConsentGiven(event.request)) {
		return sentryHandle({ event, resolve });
	}
	return resolve(event);
};

export const handleError: HandleServerError = (input) => {
	// Consent-gated error capture. When the cookie is missing or
	// "rejected", log to stderr (CloudWatch / Lambda still pick it
	// up) but don't ship the error + request context to Sentry.
	if (isConsentGiven(input.event.request)) {
		return sentryHandleError(input);
	}
	console.error(
		"[hooks.server] uncaught error (consent missing, not sent to Sentry):",
		input.error instanceof Error ? input.error.stack : String(input.error),
	);
};
