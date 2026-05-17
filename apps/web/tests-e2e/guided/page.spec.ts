import { expect, test } from '@playwright/test';

/**
 * /guided + /guided/[id] — guided audio run library.
 *
 * Library: apps/web/src/lib/guided_runs.ts → GUIDED_RUN_LIBRARY,
 * with three runs today: easy-30, tempo-builder-25, first-timer-15.
 * The detail page calls findGuidedRun(id) and renders the full cue
 * script. Anon-readable. The actual playback only happens on mobile —
 * the web is a preview surface.
 */

const KNOWN_RUNS = [
	{ id: 'easy-30', title: '30-Minute Easy Run', minutes: 30 },
	{ id: 'tempo-builder-25', title: '25-Minute Tempo Builder', minutes: 25 },
	{ id: 'first-timer-15', title: 'First-Timer 15-Minute Run/Walk', minutes: 15 },
];

test.describe('/guided — index page', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('renders the hero + "preview only" mobile callout', async ({ page }) => {
		await page.goto('/guided');
		await expect(page.getByRole('heading', { name: /coach in your ear/i })).toBeVisible();
		await expect(page.getByText(/Open these on the mobile app/)).toBeVisible();
	});

	test('lists every guided run from the library as a clickable card', async ({ page }) => {
		await page.goto('/guided');
		// One card per library entry. Cards are <a class="card">.
		const cards = page.locator('a.card');
		await expect(cards).toHaveCount(KNOWN_RUNS.length);
		for (const r of KNOWN_RUNS) {
			const card = page.locator(`a.card[href="/guided/${r.id}"]`);
			await expect(card).toBeVisible();
			// .duration is the dedicated label slot; matching by the
			// raw "N min" string would collide with the subtitle copy
			// ("Coach voice · 30 min · easy effort") in the same card.
			await expect(card.locator('.duration')).toHaveText(`${r.minutes} min`);
			await expect(card.getByRole('heading', { name: r.title })).toBeVisible();
		}
	});

	test('document title is set on the index', async ({ page }) => {
		await page.goto('/guided');
		await expect(page).toHaveTitle(/Guided runs/);
	});
});

test.describe('/guided/[id] — detail pages', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	for (const r of KNOWN_RUNS) {
		test(`detail for ${r.id} renders the hero + script + back link`, async ({ page }) => {
			await page.goto(`/guided/${r.id}`);
			// Title is in <h1>. Use exact-match to avoid false-positives on
			// other run titles that appear in document.title.
			await expect(page.getByRole('heading', { name: r.title, exact: true })).toBeVisible();
			await expect(page.getByRole('heading', { name: /script/i })).toBeVisible();
			// "← Library" back link points at the index.
			await expect(page.getByRole('link', { name: /Library/ })).toHaveAttribute(
				'href',
				'/guided'
			);
		});
	}

	test('cue list renders at least one mm:ss entry', async ({ page }) => {
		// Detail page formats each cue's at_sec as mm:ss in <span class="at">.
		// Library data guarantees each run has at least one cue at the start
		// (00:00) or shortly after.
		await page.goto('/guided/easy-30');
		const cueEntries = page.locator('.at');
		await expect(cueEntries.first()).toBeVisible();
		// First cue is at 0 seconds → '0:00'. Pin the format to catch a
		// regression in fmtMmSs (e.g. dropping the leading zero).
		await expect(cueEntries.first()).toHaveText('0:00');
	});

	test('unknown id renders the "Unknown guided run" empty state', async ({ page }) => {
		const res = await page.goto('/guided/no-such-run-id');
		// Status may be 200 (SvelteKit static fallback) or 404; the user-
		// facing contract is "renders an empty state with a back link".
		expect(res?.status() ?? 200).toBeGreaterThanOrEqual(200);
		await expect(page.getByText(/Unknown guided run/)).toBeVisible();
		// The empty state surfaces two paths to the library: a small back-
		// link at the top and a primary CTA inside the empty card. Both
		// point at /guided. Assert the CTA (the visible, big one a user
		// would actually click) so the test fails if the empty state
		// loses its primary action.
		await expect(
			page.locator('.empty').getByRole('link', { name: /Back to library/, exact: true })
		).toHaveAttribute('href', '/guided');
	});

	test('document title falls back to "Guided run" on unknown id', async ({ page }) => {
		await page.goto('/guided/no-such-run-id');
		await expect(page).toHaveTitle(/Guided run/);
	});
});

import { USER_A } from '../fixtures/users';

test.describe('/guided — signed-in back navigation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('signed-in user sees a ← Back to Coach link at the top of the library', async ({
		page
	}) => {
		// /guided is reached from the /coach right-rail "See the full
		// library →" link. Without an in-page back affordance the user
		// has to dig through the sidebar to return. Pin the back link
		// so a regression that drops it fails here.
		await page.goto('/guided');
		const back = page.getByRole('link', { name: /Back to Coach/ });
		await expect(back).toBeVisible({ timeout: 10_000 });
		await expect(back).toHaveAttribute('href', '/coach');
	});

	test('anon viewer does NOT see the Back-to-Coach link (no /coach route for anon)', async ({
		browser
	}) => {
		// /guided is anon-readable but /coach is not — gating the back
		// link on auth.loggedIn keeps the link from leading anon
		// visitors into a route they can't reach.
		const ctx = await browser.newContext({ storageState: undefined });
		const page = await ctx.newPage();
		await page.goto('/guided');
		await expect(
			page.getByRole('link', { name: /Back to Coach/ })
		).toHaveCount(0);
		await ctx.close();
	});
});
