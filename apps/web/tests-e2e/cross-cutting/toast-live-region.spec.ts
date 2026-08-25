import { expect, test } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { USER_A } from '../fixtures/users';

/**
 * WCAG 4.1.3 Status Messages, for the app-wide toast announcer.
 *
 * A live region only announces changes that happen inside it while it is
 * already in the accessibility tree. `ToastContainer` used to mount the region
 * and the toast text in the same `{#if}`, so the first toast of a burst — one
 * toast at a time, which is the ordinary case across ~400 `showToast` call
 * sites — appeared as one mutation and was announced by nothing.
 *
 * The two things worth pinning are therefore: the regions exist BEFORE any
 * toast does, and a toast's text lands in the one matching its politeness while
 * the visible stack stays out of the accessibility tree so nothing is spoken
 * twice.
 */

// The browser is pinned to UTC while the runner is not, so the recap year has
// to be read off the browser's calendar (decisions § 728).
const CURRENT_YEAR = browserDate().slice(0, 4);

test.describe('toast live regions', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('both regions are mounted and empty before any toast exists', async ({ page }) => {
		await page.goto('/dashboard');

		const polite = page.getByTestId('toast-live-polite');
		const assertive = page.getByTestId('toast-live-assertive');

		await expect(polite).toBeAttached({ timeout: 10_000 });
		await expect(assertive).toBeAttached();
		await expect(polite).toHaveAttribute('aria-live', 'polite');
		await expect(assertive).toHaveAttribute('aria-live', 'assertive');

		// No toast has fired, so there is nothing for either region to carry.
		await expect(page.locator('.toast')).toHaveCount(0);
		expect((await polite.textContent())?.trim()).toBe('');
		expect((await assertive.textContent())?.trim()).toBe('');
	});

	test('an error toast lands in the assertive region, not the polite one', async ({ page }) => {
		await page.route('**/rest/v1/public_recaps**', (route) =>
			route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated failure' })
			})
		);

		await page.goto(`/recap/${CURRENT_YEAR}`);
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		const assertive = page.getByTestId('toast-live-assertive');
		// The region was already in the tree when the failure fired — that is the
		// whole point, so read it before the toast rather than after.
		await expect(assertive).toBeAttached();

		await page.getByRole('button', { name: 'Publish & copy link' }).click();

		const visible = page.locator('.toast-error');
		await expect(visible).toBeVisible({ timeout: 5_000 });
		const message = ((await visible.first().textContent()) ?? '').trim();
		expect(message.length).toBeGreaterThan(0);

		await expect(assertive).toHaveText(message);
		await expect(page.getByTestId('toast-live-polite')).toHaveText('');

		// The visible stack must stay out of the accessibility tree, or the same
		// sentence is announced by both it and the region above it.
		await expect(page.locator('.toast-container')).toHaveAttribute('aria-hidden', 'true');
	});
});
