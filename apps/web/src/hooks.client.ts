import * as Sentry from "@sentry/sveltekit";
import { dev } from "$app/environment";
import { env } from "$env/dynamic/public";

const dsn = env.PUBLIC_SENTRY_DSN ?? "";
const release = env.PUBLIC_APP_RELEASE || "dev";

// Strip Supabase Storage signed-URL query strings from any URL field
// before it lands in a Sentry breadcrumb / span / event. Signed URLs
// embed an HMAC token in the query that grants access to a bucket
// object — we don't want them in the error-reporting tail. Match
// is broad ("/storage/v1/object/sign/" anywhere in the URL) so it
// covers both run-photos and any future private bucket.
function redactSignedUrl(url: string): string {
	if (!url.includes('/storage/v1/object/sign/')) return url;
	const q = url.indexOf('?');
	return q === -1 ? url : url.slice(0, q) + '?<redacted>';
}

function redactBreadcrumb<T extends { data?: Record<string, unknown> }>(b: T): T {
	const u = b.data?.url;
	if (typeof u === 'string') {
		b.data!.url = redactSignedUrl(u);
	}
	return b;
}

if (!dev && dsn) {
	Sentry.init({
		dsn,
		release,
		environment: release !== "dev" ? "production" : "development",
		tracesSampleRate: 0.1,
		replaysSessionSampleRate: 0,
		replaysOnErrorSampleRate: 0,
		beforeBreadcrumb: (breadcrumb) =>
			breadcrumb.category === 'fetch' || breadcrumb.category === 'xhr'
				? redactBreadcrumb(breadcrumb)
				: breadcrumb,
		beforeSendTransaction: (event) => {
			const tx = event.transaction;
			if (typeof tx === 'string') event.transaction = redactSignedUrl(tx);
			return event;
		},
	});
}

export const handleError = Sentry.handleErrorWithSentry();
