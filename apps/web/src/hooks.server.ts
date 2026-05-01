import * as Sentry from "@sentry/sveltekit";
import { sequence } from "@sveltejs/kit/hooks";
import { dev } from "$app/environment";
import { env } from "$env/dynamic/private";

if (!dev && env.SENTRY_DSN) {
	Sentry.init({
		dsn: env.SENTRY_DSN,
		release: env.APP_RELEASE || "dev",
		environment: env.APP_RELEASE && env.APP_RELEASE !== "dev" ? "production" : "development",
		tracesSampleRate: 0.1,
	});
}

export const handle = sequence(Sentry.sentryHandle());
export const handleError = Sentry.handleErrorWithSentry();
