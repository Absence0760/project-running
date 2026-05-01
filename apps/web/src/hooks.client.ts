import * as Sentry from "@sentry/sveltekit";
import { dev } from "$app/environment";
import { PUBLIC_SENTRY_DSN, PUBLIC_APP_RELEASE } from "$env/static/public";

if (!dev && PUBLIC_SENTRY_DSN) {
	Sentry.init({
		dsn: PUBLIC_SENTRY_DSN,
		release: PUBLIC_APP_RELEASE || "dev",
		environment: PUBLIC_APP_RELEASE && PUBLIC_APP_RELEASE !== "dev" ? "production" : "development",
		tracesSampleRate: 0.1,
		replaysSessionSampleRate: 0,
		replaysOnErrorSampleRate: 0,
	});
}

export const handleError = Sentry.handleErrorWithSentry();
