/**
 * The one place a dev-server origin is written down.
 *
 * `playwright.config.ts` advertises `PLAYWRIGHT_BASE_URL`, and Playwright
 * resolves a relative `page.goto` / `request.get` against the resolved
 * `use.baseURL` — so a spec should never need an origin at all. A handful
 * genuinely do (`context.grantPermissions` takes an exact origin string, a
 * bare Node `fetch` has no `baseURL` notion), and those resolve it from the
 * lane they are running in rather than restating a literal.
 *
 * Three lanes besides the sharded suite run on their own ports (livehub
 * :7778, exporthub :7779, sso :7780), so a spec that re-derives
 * `process.env.PLAYWRIGHT_BASE_URL` is wrong in three of the four lanes even
 * when it is right in the fourth. `fixtures/base-url.test.ts` fails the build
 * on any literal dev-server origin outside this module and the lane configs.
 */

/** The port `apps/web`'s `dev` script binds, and the sharded suite's default. */
export const DEFAULT_E2E_PORT = 7777;

export const DEFAULT_BASE_URL = `http://localhost:${DEFAULT_E2E_PORT}`;

/**
 * The base URL of the sharded lane. Only for callers with no `baseURL`
 * fixture in scope — `globalSetup` (which reads it off the resolved config
 * instead) and the saga-user fixture, which signs users in from a plain
 * `chromium.launch()`. Everything inside a test takes the `baseURL` fixture,
 * which is the lane's own value.
 *
 * An empty or whitespace-only override falls back rather than yielding a
 * `new URL('')` throw three frames away from the mistake.
 */
export function resolveBaseUrl(): string {
	const override = process.env.PLAYWRIGHT_BASE_URL?.trim();
	return override ? override : DEFAULT_BASE_URL;
}

/**
 * The scheme-host-port of a lane's base URL, for the two APIs that take an
 * origin rather than resolving a relative path: `context.grantPermissions`
 * and a bare Node `fetch`.
 *
 * `baseURL` is typed optional on the Playwright fixture but is always set by
 * every lane config; the fallback covers the type, not a real state.
 */
export function originOf(baseURL: string | undefined): string {
	return new URL(baseURL ?? resolveBaseUrl()).origin;
}
