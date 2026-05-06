import * as Sentry from "@sentry/sveltekit";
import { dev } from "$app/environment";
import { env } from "$env/dynamic/public";
import {
	redactBreadcrumb,
	redactEventSignedUrls,
	type SentryEventWithSpans,
} from "$lib/sentry/redact";

const dsn = env.PUBLIC_SENTRY_DSN ?? "";
const release = env.PUBLIC_APP_RELEASE || "dev";

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
