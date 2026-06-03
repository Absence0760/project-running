import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright e2e config for apps/web.
 *
 * Prereq: local Supabase up via `cd apps/backend && supabase start`.
 * The dev server is auto-started by the webServer block below.
 *
 * Why `vite dev` instead of `vite build && vite preview`:
 *   adapter-static + `fallback: "index.html"` returns the SPA shell
 *   for any unmatched route (e.g. /runs/<id>). The fallback HTML
 *   computes its asset base via `new URL("..", location).pathname` —
 *   for /runs/<id> that resolves to /runs, breaking _app/ asset URLs.
 *   Production fixes this with a CloudFront viewer-request rewrite;
 *   `vite preview` doesn't have that, so dev mode is the right
 *   server for e2e. The trade-off (HMR + slower first-paint) doesn't
 *   matter for headless tests.
 *
 * Local dev: `cd apps/web && pnpm test:e2e` (auto-boots dev server).
 * Or `pnpm test:e2e:ui` for the UI picker.
 *
 * The fixtures/auth.ts globalSetup signs each seeded user in once via
 * the UI and saves their storage state to .auth/<user>.json. Spec
 * files attach the storage state via test.use({ storageState: ... }).
 * .auth/ is gitignored.
 */
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
		'**/live/spectator_websocket.spec.ts'
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
		command: 'pnpm run dev',
		url: 'http://localhost:7777',
		reuseExistingServer: !process.env.CI,
		timeout: 60_000,
		// Vite logs are noisy; only surface them on failure.
		stdout: 'ignore',
		stderr: 'pipe'
	},

	use: {
		baseURL: process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:7777',
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
