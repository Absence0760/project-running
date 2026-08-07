/**
 * The public site origin, and the one place its default is spelled.
 *
 * `PUBLIC_SITE_URL` is what a preview or a self-hosted deploy sets so the
 * canonical / `og:url` / sitemap entries point at that host. Every consumer
 * folded it against the same literal fallback, and there were 28 copies of that
 * fold: 15 as a named `DEFAULT_SITE_URL` per module and 13 spelled inline as
 * `env.PUBLIC_SITE_URL || '…'` inside a component or a Lambda.
 *
 * A default that lives in 28 places is a default nobody can change: a deploy
 * that renamed the host would have to find all of them, and the ones it missed
 * would emit a canonical pointing at the old domain — which is § 546's lesson
 * about a `<loc>` disagreeing with the page it names, one layer up.
 *
 * NOT for the `privacy@…` contact addresses or the iCal `uid` domain. Those
 * share a string with the origin and are a different concept: a mailbox and an
 * RFC 5545 identity domain do not move when the site is served from another
 * host.
 */
export const DEFAULT_SITE_URL = 'https://threkir.com';

/**
 * The origin to build absolute URLs against, given whatever env the caller can
 * see (`$env/dynamic/public` in a route, `process.env` in a Lambda).
 *
 * Takes the value rather than reading the env itself, because the two runtimes
 * expose it differently and a module that reached for one would not load in the
 * other. A blank or whitespace-only value folds to the default — an env var set
 * to the empty string is a deploy that failed to configure it, not a request to
 * serve canonicals from nowhere.
 */
export function siteOrigin(configured: string | undefined | null): string {
	const trimmed = configured?.trim();
	return trimmed ? trimmed.replace(/\/+$/, '') : DEFAULT_SITE_URL;
}
