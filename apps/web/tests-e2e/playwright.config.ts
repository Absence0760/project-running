import { resolve } from 'node:path';

import { defineConfig, devices } from '@playwright/test';

import { resolveBaseUrl } from './fixtures/base-url';

/**
 * Playwright e2e config for apps/web.
 *
 * Prereq: local Supabase up via `cd apps/backend && supabase start`.
 * The dev server is auto-started by the webServer block below.
 *
 * Why `vite dev` instead of `vite build && vite preview`:
 *   the app's eleven `+server.ts` endpoints are not in an
 *   adapter-static build. `/api/coach` and the `/api/routes/osrm`
 *   proxy declare `prerender = false`, so nothing is emitted for them
 *   and `vite preview` would answer a POST to `/api/coach` with the
 *   SPA fallback — a 200 of HTML. `cross-cutting/paywall-wire.spec.ts`
 *   posts there directly to pin the SERVER-side tier gate (429 at the
 *   cap, 401 anonymous) and `cross-cutting/tier-cache-resilience.spec.ts`
 *   fetches it to prove the handler re-reads the tier per call; both
 *   would stop testing anything without failing. Production serves
 *   those endpoints as Lambdas (decisions §53), which `vite preview`
 *   has no equivalent of either. Second reason: a static build bakes
 *   `PUBLIC_*` at BUILD time, so the `webServer.env` overrides below —
 *   which force the localhost tile + OSRM services empty — would have
 *   to move into the build command to have any effect at all.
 *
 *   Not the reason, though it stood here until round 41: an asset-base
 *   break on deep links. SvelteKit computes the relative
 *   `new URL("..", location)` base only when the page is NOT the
 *   fallback (`!state.prerendering?.fallback` in kit's
 *   `runtime/server/page/render.js`); the fallback carries the literal
 *   `paths.base` and absolute `_app/` URLs, so `/runs/<id>` cannot
 *   break them. The claim also named `fallback: "index.html"`, which
 *   the build has not produced since the shell was renamed to
 *   `200.html` (svelte.config.js, decisions § 1268).
 *
 * Local dev: `cd apps/web && pnpm test:e2e` (auto-boots dev server).
 * Or `pnpm test:e2e:ui` for the UI picker.
 *
 * PLAYWRIGHT_BASE_URL moves the whole lane to another port — the dev
 * server this config boots, the readiness probe, and `use.baseURL` all
 * come off the one resolved value, so a second checkout can run the
 * suite beside a first without the two fighting over :7777.
 *
 * The fixtures/auth.ts globalSetup signs each seeded user in once via
 * the UI and saves their storage state to .auth/<user>.json. Spec
 * files attach the storage state via test.use({ storageState: ... }).
 * .auth/ is gitignored.
 */
const WEB_DIR = resolve(import.meta.dirname, '..');

const BASE_URL = resolveBaseUrl();
const DEV_PORT = new URL(BASE_URL).port;
if (!DEV_PORT) {
	throw new Error(
		`PLAYWRIGHT_BASE_URL must name a port — this config boots the dev server on it. Got ${BASE_URL}.`
	);
}

export default defineConfig({
	testDir: '.',
	// Don't recurse into node_modules / .auth / fixtures from the testDir glob.
	// spectator_websocket.spec.ts needs the Go live-hub + a hub-pointed dev
	// server, which only playwright.livehub.config.ts boots — exclude it here
	// so the sharded suite never runs it without the hub (it'd hit the
	// Realtime/demo fallback and fail).
	testIgnore: [
		'**/node_modules/**',
		'**/.auth/**',
		'**/fixtures/**',
		'**/live/spectator_websocket.spec.ts',
		// The queued-export lane needs the Go worker + a dev server with
		// PUBLIC_EXPORT_HUB_URL set, which only
		// playwright.exporthub.config.ts boots. Without it the page takes
		// the Edge Function fallback and the job card never appears.
		'**/settings/export_job.spec.ts',
		// The SSO/OAuth lane (tests-e2e/sso) needs the mock OIDC provider +
		// GoTrue wired to it, which only playwright.sso.config.ts boots.
		'**/sso/**'
	],

	// Stable on CI even with the dev server taking a beat to warm up.
	timeout: 30_000,
	expect: { timeout: 10_000 },

	// One retry on CI absorbs incidental flake (Supabase realtime warmup,
	// dev-server transient HMR errors); no retries locally so flakes are
	// visible during development.
	retries: process.env.CI ? 1 : 0,

	// Fail fast in CI — a failure usually means the seed is mis-stated and
	// every dependent test will fail the same way. Locally, run them all.
	forbidOnly: !!process.env.CI,
	// Single worker — the dev server doesn't isolate per-page state and
	// concurrent tests against shared Supabase data can race. Set higher
	// after the suite is stable.
	workers: 1,
	fullyParallel: false,

	reporter: process.env.CI ? [['github'], ['list']] : 'list',

	// Auto-start the dev server. `reuseExistingServer` lets a manually
	// started server (e.g. for `playwright test --ui`) take precedence.
	webServer: {
		// `pnpm exec` (not `pnpm run dev`, which pins --port 7777) so the
		// port follows PLAYWRIGHT_BASE_URL. `pnpm exec` does not move cwd
		// the way `pnpm run` does, hence the explicit WEB_DIR — same shape
		// as the livehub / exporthub / sso configs.
		command: `pnpm exec vite dev --port ${DEV_PORT}`,
		cwd: WEB_DIR,
		url: BASE_URL,
		reuseExistingServer: !process.env.CI,
		timeout: 60_000,
		// Force the localhost dev services empty for e2e. `.env.development`
		// ships a localhost:8080 tileserver + localhost:5000 OSRM the runner
		// doesn't boot; process.env wins over the .env files, so this makes the
		// suite fall through (tiles → MapTiler/OSM raster; routing → the dev
		// /api/routes/osrm proxy's demo fallback, though the specs mock the
		// proxy path in-browser) deterministically, local and CI alike, instead
		// of chasing services that aren't there. See decisions.md § 137.
		env: { PUBLIC_TILE_STYLE_URL: '', OSRM_URL: '' },
		// Vite logs are noisy; only surface them on failure.
		stdout: 'ignore',
		stderr: 'pipe'
	},

	use: {
		baseURL: BASE_URL,
		trace: 'on-first-retry',
		screenshot: 'only-on-failure',
		video: 'retain-on-failure',
		// The seed data assumes km units (user_profiles.preferred_unit = 'km').
		locale: 'en-GB',
		timezoneId: 'UTC'
	},

	globalSetup: './fixtures/auth.ts',

	// Chromium-only on purpose. Webkit + Firefox would 3× the runtime;
	// the cross-browser bug yield on a SvelteKit static site is low.
	// Add projects later if a bug ever shows up that's browser-specific.
	projects: [
		{
			name: 'chromium',
			use: { ...devices['Desktop Chrome'] }
		}
	]
});
