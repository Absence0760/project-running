import * as Sentry from "@sentry/sveltekit";
import { dev } from "$app/environment";
import { env } from "$env/dynamic/public";

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
	});
}

export const handleError = Sentry.handleErrorWithSentry();
