import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /guided + /guided/[id] — guided audio run library.
 *
 * Library: apps/web/src/lib/training/guided_runs.ts → GUIDED_RUN_LIBRARY,
 * with three runs today: easy-30, tempo-builder-25, first-timer-15.
 * The detail page calls findGuidedRun(id) and renders the full cue
 * script. Anon-readable. The actual playback only happens on mobile —
 * the web is a preview surface.
 */

const KNOWN_RUNS = [
	{
		id: 'easy-30',
		title: '30-Minute Easy Run',
		minutes: 30,
		firstCueAt: '0:00',
		// Hand-picked cues that exercise the mm:ss formatter — the
		// 5-minute mark renders as "5:00" (single-digit m, padded s)
		// and the 29-minute mark as "29:00" (double-digit m).
		expectedCues: ['0:00', '5:00', '29:00']
	},
	{
		id: 'tempo-builder-25',
		title: '25-Minute Tempo Builder',
		minutes: 25,
		firstCueAt: '0:00',
		expectedCues: ['0:00', '4:00', '18:00']
	},
	{
		id: 'first-timer-15',
		title: 'First-Timer 15-Minute Run/Walk',
		minutes: 15,
		firstCueAt: '0:00',
		expectedCues: ['0:00', '3:00', '14:00']
	}
];

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('/guided — index page (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(setConsentAccepted);
	});

	test('renders the kicker, h1, tagline + "preview only" mobile callout', async ({ page }) => {
		await page.goto('/guided');
		await expect(page.getByText('Guided runs', { exact: true }).first()).toBeVisible();
		await expect(page.getByRole('heading', { level: 1, name: /coach in your ear/i })).toBeVisible();
		await expect(page.getByText(/Scripted coach-voice workouts/)).toBeVisible();
		await expect(page.getByText(/Open these on the mobile app/)).toBeVisible();
	});

	test('library section is labelled for assistive tech', async ({ page }) => {
		await page.goto('/guided');
		await expect(page.getByRole('region', { name: /guided run library/i })).toBeVisible();
	});

	test('icons in the hero callout are aria-hidden (no ligature leak)', async ({ page }) => {
		await page.goto('/guided');
		// The note's icon span carries `phone_iphone` as text content
		// (Material Symbols ligature). Without aria-hidden the icon
		// ligature reaches the accessibility tree as raw text.
		const iconCount = await page
			.locator('.note .material-symbols:not([aria-hidden="true"])')
			.count();
		expect(iconCount).toBe(0);
	});

	test('lists every guided run from the library as a clickable card', async ({ page }) => {
		await page.goto('/guided');
		const cards = page.locator('a.card');
		await expect(cards).toHaveCount(KNOWN_RUNS.length);
		for (const r of KNOWN_RUNS) {
			const card = page.locator(`a.card[href="/guided/${r.id}"]`);
			await expect(card).toBeVisible();
			await expect(card.locator('.duration')).toHaveText(`${r.minutes} min`);
			await expect(card.getByRole('heading', { name: r.title })).toBeVisible();
		}
	});

	test('card cue-count footer matches the library data', async ({ page }) => {
		await page.goto('/guided');
		// Each card surfaces "N cues across the run". The number is
		// the library's cue array length — pin a known one to fail
		// loudly if the formatter drifts. easy-30 has 8 cues.
		const easyCard = page.locator('a.card[href="/guided/easy-30"]');
		await expect(easyCard.locator('.cue-count')).toContainText('8 cues');
	});

	test('document title is set on the index', async ({ page }) => {
		await page.goto('/guided');
		await expect(page).toHaveTitle(/Guided runs/);
	});

	test('anon viewer does NOT see the Back-to-Coach link', async ({ page }) => {
		// /guided is anon-readable but /coach is not — gating the back
		// link on auth.loggedIn keeps anon visitors out of a route
		// they can't reach.
		await page.goto('/guided');
		await expect(page.getByRole('link', { name: /Back to Coach/ })).toHaveCount(0);
	});

	test('anon viewer loads /guided/[id] without redirect to login', async ({ page }) => {
		const res = await page.goto('/guided/easy-30');
		expect(res?.status() ?? 200).toBeLessThan(400);
		await expect(page).toHaveURL(/\/guided\/easy-30$/);
		await expect(page.getByRole('heading', { level: 1, name: '30-Minute Easy Run' })).toBeVisible();
	});
});

test.describe('/guided/[id] — detail pages (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(setConsentAccepted);
	});

	for (const r of KNOWN_RUNS) {
		test(`detail for ${r.id} renders hero, duration badge, cues, and ← Library link`, async ({
			page
		}) => {
			await page.goto(`/guided/${r.id}`);
			await expect(page.getByRole('heading', { name: r.title, exact: true })).toBeVisible();
			// Hero duration badge — the small pill next to the kicker.
			await expect(page.locator('.hero .duration')).toHaveText(`${r.minutes} min`);
			// Script section + heading.
			await expect(page.getByRole('region', { name: /cue script/i })).toBeVisible();
			await expect(page.getByRole('heading', { name: /full script/i })).toBeVisible();
			// Back link → /guided. Use exact accessible name now that
			// the arrow_back icon is aria-hidden.
			const back = page.getByRole('link', { name: 'Library', exact: true });
			await expect(back).toHaveAttribute('href', '/guided');
			// Every cue's at_sec renders inside the timeline.
			const cueEntries = page.locator('ol.timeline .at');
			await expect(cueEntries.first()).toHaveText(r.firstCueAt);
			for (const stamp of r.expectedCues) {
				await expect(cueEntries.filter({ hasText: new RegExp(`^${stamp}$`) })).toHaveCount(1);
			}
		});

		test(`document title for ${r.id} includes the run title`, async ({ page }) => {
			await page.goto(`/guided/${r.id}`);
			await expect(page).toHaveTitle(new RegExp(r.title.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')));
		});
	}

	test('cue formatter pads seconds to two digits across mm:ss boundaries', async ({ page }) => {
		// The fmtMmSs helper in /guided/[id]/+page.svelte must produce
		// `0:00`, `5:00`, `10:00`, `29:00` for the library's cues —
		// dropping the leading zero on seconds (e.g. "5:0") would
		// silently break the layout. Pin a sample from each known run
		// that exercises both single- and double-digit minutes.
		await page.goto('/guided/easy-30');
		const stamps = page.locator('ol.timeline .at');
		await expect(stamps.nth(0)).toHaveText('0:00');
		await expect(stamps.nth(1)).toHaveText('5:00');
		await expect(stamps.nth(2)).toHaveText('10:00');
		// 29:00 — double-digit minutes, seconds still zero-padded.
		await expect(stamps.filter({ hasText: /^29:00$/ })).toHaveCount(1);
	});

	test('detail-page icons are aria-hidden (no ligature leak)', async ({ page }) => {
		await page.goto('/guided/easy-30');
		const leakedIcons = await page
			.locator('.material-symbols:not([aria-hidden="true"])')
			.count();
		expect(leakedIcons).toBe(0);
	});

	test('unknown id renders the "Unknown guided run" empty state with a Back to library CTA', async ({
		page
	}) => {
		const res = await page.goto('/guided/no-such-run-id');
		expect(res?.status() ?? 200).toBeGreaterThanOrEqual(200);
		await expect(page.getByText(/Unknown guided run/)).toBeVisible();
		await expect(
			page.locator('.empty').getByRole('link', { name: /Back to library/, exact: true })
		).toHaveAttribute('href', '/guided');
	});

	test('empty-state Back to library CTA round-trips to /guided', async ({ page }) => {
		await page.goto('/guided/no-such-run-id');
		await page
			.locator('.empty')
			.getByRole('link', { name: /Back to library/, exact: true })
			.click();
		await expect(page).toHaveURL(/\/guided$/);
		await expect(page.getByRole('heading', { level: 1, name: /coach in your ear/i })).toBeVisible();
	});

	test('document title falls back to "Guided run" on unknown id', async ({ page }) => {
		await page.goto('/guided/no-such-run-id');
		await expect(page).toHaveTitle(/Guided run/);
	});
});

test.describe('/guided ↔ /guided/[id] — navigation round-trip', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(setConsentAccepted);
	});

	test('library card click → detail → Library back link → library', async ({ page }) => {
		await page.goto('/guided');
		await page.locator('a.card[href="/guided/easy-30"]').click();
		await expect(page).toHaveURL(/\/guided\/easy-30$/);
		await expect(page.getByRole('heading', { level: 1, name: '30-Minute Easy Run' })).toBeVisible();
		await page.getByRole('link', { name: 'Library', exact: true }).click();
		await expect(page).toHaveURL(/\/guided$/);
		await expect(page.getByRole('heading', { level: 1, name: /coach in your ear/i })).toBeVisible();
	});
});

test.describe('/guided — signed-in back-to-Coach round-trip', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('signed-in user sees a Back-to-Coach link with href=/coach', async ({ page }) => {
		await page.goto('/guided');
		const back = page.getByRole('link', { name: /Back to Coach/ });
		await expect(back).toBeVisible({ timeout: 10_000 });
		await expect(back).toHaveAttribute('href', '/coach');
	});

	test('/coach → "See the full library" → /guided → Back to Coach → /coach', async ({ page }) => {
		// Pins the snapshot-restoring history pop pattern: the
		// /guided afterNavigate hook flips cameFromCoach when the
		// previous route was /coach, and Back-to-Coach calls
		// history.back() so the original coach state survives.
		await page.goto('/coach');
		await expect(page).toHaveURL(/\/coach/);
		await page.getByRole('link', { name: /See the full library/ }).click();
		await expect(page).toHaveURL(/\/guided$/);
		const back = page.getByRole('link', { name: /Back to Coach/ });
		await expect(back).toBeVisible({ timeout: 10_000 });
		await back.click();
		await expect(page).toHaveURL(/\/coach/);
	});

	test('cold-load /guided (no /coach referrer) keeps the back-link as a normal nav', async ({
		page
	}) => {
		// When the user lands on /guided directly (not from /coach),
		// cameFromCoach stays false — clicking Back to Coach is a
		// plain soft-nav with no history.back() side effect.
		await page.goto('/guided');
		const back = page.getByRole('link', { name: /Back to Coach/ });
		await expect(back).toBeVisible({ timeout: 10_000 });
		await back.click();
		await expect(page).toHaveURL(/\/coach/);
	});
});
