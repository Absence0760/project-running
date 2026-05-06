import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright e2e config for apps/web.
 *
 * Boot order (the suite assumes both are already running):
 *   1. cd apps/backend && supabase start          (PostgREST on :54321)
 *   2. apps/web preview server on :8888           (npm run build && npm run preview)
 *
 * Local dev: `cd apps/web && pnpm exec playwright test` (or `--ui` for the picker).
 *
 * The fixtures/auth.ts globalSetup signs each seeded user in once via the
 * UI and saves their storage state to .auth/<user>.json. Spec files attach
 * the storage state via test.use({ storageState: '.auth/<user>.json' }) so
 * later tests skip the form submit. .auth/ is gitignored.
 */
export default defineConfig({
	testDir: '.',
	// Don't recurse into node_modules / .auth / fixtures from the testDir glob.
	testIgnore: ['**/node_modules/**', '**/.auth/**', '**/fixtures/**'],

	// Stable on CI even with the dev server taking a beat to warm up.
	timeout: 30_000,
	expect: { timeout: 10_000 },

	// One retry on CI absorbs incidental flake (Supabase realtime warmup,
	// CloudFront-style caching from Vite preview); no retries locally so
	// flakes are visible during development.
	retries: process.env.CI ? 1 : 0,

	// Fail fast in CI — a failure usually means the seed is mis-stated and
	// every dependent test will fail the same way. Locally, run them all.
	forbidOnly: !!process.env.CI,
	workers: process.env.CI ? 2 : undefined,
	fullyParallel: true,

	reporter: process.env.CI ? [['github'], ['list']] : 'list',

	use: {
		baseURL: process.env.PLAYWRIGHT_BASE_URL ?? 'http://127.0.0.1:8888',
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
