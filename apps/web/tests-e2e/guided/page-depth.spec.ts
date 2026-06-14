import { expect, test } from '@playwright/test';

/**
 * /guided depth coverage — gaps the page.spec.ts smoke suite leaves
 * open. That suite checks the index cards exist, each detail renders
 * its hero + a few cue stamps, and the navigation round-trips. This
 * file pins the data-integrity contracts between the index and the
 * detail timeline that a library edit could silently break:
 *
 *   - index card cue-count footer === detail timeline row count, per
 *     run (the count the user sees on the card must equal the actual
 *     number of cues they get on the detail page).
 *   - the timeline is strictly ascending in time + the LAST stamp is
 *     the run's full duration (the closing cue), which no existing
 *     test asserts — they only check hand-picked interior stamps.
 *   - the hero subtitle + description render (the "coach voice" copy).
 *   - the empty/unknown state and the valid state share the same back
 *     link target, and the unknown detail page returns a 200 SPA shell
 *     (a missing run is an in-page empty state, never a 404 / redirect).
 */

const KNOWN = [
	{ id: 'easy-30', minutes: 30, cueCount: 8, lastStamp: '30:00' },
	{ id: 'tempo-builder-25', minutes: 25, cueCount: 9, lastStamp: '25:00' },
	{ id: 'first-timer-15', minutes: 15, cueCount: 11, lastStamp: '15:00' }
];

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('/guided — index↔detail cue-count parity (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(setConsentAccepted);
	});

	for (const r of KNOWN) {
		test(`${r.id}: card cue-count footer matches the detail timeline length`, async ({
			page
		}) => {
			// Read the count the card advertises.
			await page.goto('/guided');
			const card = page.locator(`a.card[href="/guided/${r.id}"]`);
			await expect(card.locator('.cue-count')).toContainText(`${r.cueCount} cues`);

			// Now the detail page must render exactly that many timeline
			// rows — the contract a library edit (adding a cue without
			// re-counting) would break.
			await page.goto(`/guided/${r.id}`);
			const rows = page.locator('ol.timeline li.cue');
			await expect(rows).toHaveCount(r.cueCount);
			// The detail's own cue-count chip agrees too.
			await expect(page.locator('.script-head .cue-count')).toContainText(
				`${r.cueCount}`
			);
		});

		test(`${r.id}: timeline is strictly ascending and closes at the full duration`, async ({
			page
		}) => {
			await page.goto(`/guided/${r.id}`);
			const stamps = page.locator('ol.timeline .at');
			const labels = await stamps.allInnerTexts();
			// First cue is always 0:00, last cue is the run's full
			// length — pins the script's open + close markers.
			expect(labels[0].trim()).toBe('0:00');
			expect(labels[labels.length - 1].trim()).toBe(r.lastStamp);
			// Strictly ascending in seconds (mm:ss → seconds).
			const secs = labels.map((l) => {
				const [mm, ss] = l.trim().split(':').map(Number);
				return mm * 60 + ss;
			});
			for (let i = 1; i < secs.length; i++) {
				expect(secs[i]).toBeGreaterThan(secs[i - 1]);
			}
			// Every cue is within the run duration.
			const max = r.minutes * 60;
			for (const s of secs) expect(s).toBeLessThanOrEqual(max);
		});
	}

	test('each detail hero renders a subtitle + a description blurb', async ({ page }) => {
		// The "coach voice" subtitle + the one-paragraph description are
		// the preview copy; pin they aren't blank (a library edit that
		// dropped the message key would render an empty node).
		for (const r of KNOWN) {
			await page.goto(`/guided/${r.id}`);
			const subtitle = page.locator('.hero .subtitle');
			const desc = page.locator('.hero .desc');
			await expect(subtitle).toBeVisible();
			await expect(desc).toBeVisible();
			expect((await subtitle.innerText()).trim().length).toBeGreaterThan(0);
			expect((await desc.innerText()).trim().length).toBeGreaterThan(0);
		}
	});
});

test.describe('/guided/[id] — unknown id is an in-page empty state, not a 404', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(setConsentAccepted);
	});

	test('an unknown id serves a 200 SPA shell + the empty state, no redirect', async ({
		page
	}) => {
		const res = await page.goto('/guided/totally-made-up-id');
		// Static SPA shell — not a hard 404 / 3xx.
		expect(res?.status() ?? 200).toBeLessThan(400);
		await expect(page).toHaveURL(/\/guided\/totally-made-up-id$/);
		await expect(page.getByText(/Unknown guided run/)).toBeVisible();
		// No timeline rows on the empty state.
		await expect(page.locator('ol.timeline li.cue')).toHaveCount(0);
		// Both the top back-link and the empty CTA point at /guided.
		await expect(
			page.locator('.back-link').first()
		).toHaveAttribute('href', '/guided');
		await expect(
			page.locator('.empty').getByRole('link', { name: /Back to library/i })
		).toHaveAttribute('href', '/guided');
	});

	test('a numeric-looking id (no run) still falls into the empty state without crashing', async ({
		page
	}) => {
		// Different id shape from the alpha one above — a regression in
		// findGuidedRun param handling could throw on an odd id. Pin it
		// renders the empty state, not a blank page.
		await page.goto('/guided/12345');
		await expect(page.getByText(/Unknown guided run/)).toBeVisible();
		await expect(page).toHaveTitle(/Guided run/);
	});
});
