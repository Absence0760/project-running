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

function redactBreadcrumb<T extends { category?: string; message?: string; data?: Record<string, unknown> }>(b: T): T {
	const u = b.data?.url;
	if (typeof u === 'string') {
		b.data!.url = redactSignedUrl(u);
	}
	// `console` breadcrumbs carry the log message in `message` and
	// `data.arguments`. apps/web/src/lib/data.ts:369,384 log Storage
	// paths via console.warn on delete-failure paths; redact any
	// occurrence of a signed-URL substring.
	if (b.category === 'console' && typeof b.message === 'string') {
		b.message = redactSignedUrl(b.message);
	}
	return b;
}

interface SentrySpanLike {
	data?: Record<string, unknown>;
}
interface SentryEventWithSpans {
	transaction?: string;
	spans?: SentrySpanLike[];
	request?: { url?: string };
}

function redactEventSignedUrls(event: SentryEventWithSpans): SentryEventWithSpans {
	if (typeof event.transaction === 'string') {
		event.transaction = redactSignedUrl(event.transaction);
	}
	if (event.request?.url) {
		event.request.url = redactSignedUrl(event.request.url);
	}
	if (Array.isArray(event.spans)) {
		for (const s of event.spans) {
			const u = s.data?.url;
			if (typeof u === 'string') {
				s.data!.url = redactSignedUrl(u);
			}
		}
	}
	return event;
}

if (!dev && dsn) {
	Sentry.init({
		dsn,
		release,
		environment: release !== "dev" ? "production" : "development",
		tracesSampleRate: 0.1,
		replaysSessionSampleRate: 0,
		replaysOnErrorSampleRate: 0,
		beforeBreadcrumb: (breadcrumb) => {
			if (
				breadcrumb.category === 'fetch' ||
				breadcrumb.category === 'xhr' ||
				breadcrumb.category === 'console'
			) {
				return redactBreadcrumb(breadcrumb);
			}
			return breadcrumb;
		},
		beforeSend: (event) => redactEventSignedUrls(event as SentryEventWithSpans) as typeof event,
		beforeSendTransaction: (event) => redactEventSignedUrls(event as SentryEventWithSpans) as typeof event,
	});
}

export const handleError = Sentry.handleErrorWithSentry();
