import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

async function deleteAuthorReviews() {
	await getAdminClient()
		.from('route_reviews')
		.delete()
		.eq('route_id', RUNNER_PUBLIC_ROUTE_ID)
		.eq('user_id', USER_A.id);
}

/**
 * /routes/[id] — full route-review lifecycle on the canonical UI:
 * submit → render → edit → delete, every leg through the real UI.
 *
 * Companion to routes/detail.spec.ts:171 (single-shot submit only).
 * The cookie-consent banner is fixed-position and intercepts clicks on
 * the Submit button, so we pre-accept via addInitScript — same pattern
 * as cross-user/sagas/kudos-notification.spec.ts.
 */

test.describe('/routes/[id] reviews — submit, edit, delete', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(setConsentAccepted);
		await deleteAuthorReviews();
	});

	test.afterEach(async () => {
		await deleteAuthorReviews();
	});

	test('submit → render in list, edit → rating persists, delete → row gone', async ({
		page
	}) => {
		const admin = getAdminClient();
		const comment = `e2e route review ${Date.now()}`;

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);

		await page.getByRole('button', { name: 'Rate', exact: true }).click();

		const formStars = page.locator('.review-form .star-row .star-btn');
		await expect(formStars).toHaveCount(5);
		// Each star button exposes an accessible name for screen readers.
		await expect(
			page.locator('.review-form').getByRole('button', { name: 'Set rating to 4 of 5' })
		).toBeVisible();
		await formStars.nth(3).click();
		await page.locator('.review-textarea').fill(comment);
		await page
			.locator('.review-form')
			.getByRole('button', { name: 'Submit' })
			.click();

		const card = page.locator('.review-card', { hasText: comment });
		await expect(card).toBeVisible({ timeout: 10_000 });
		const filled = card.locator('.star-display.filled');
		await expect(filled).toHaveCount(4);

		const inserted = await admin
			.from('route_reviews')
			.select('rating, comment')
			.eq('route_id', RUNNER_PUBLIC_ROUTE_ID)
			.eq('user_id', USER_A.id)
			.single();
		expect((inserted.data as { rating: number }).rating).toBe(4);
		expect((inserted.data as { comment: string }).comment).toBe(comment);

		await page.getByRole('button', { name: 'Rate', exact: true }).click();
		const editStars = page.locator('.review-form .star-row .star-btn');
		await editStars.nth(4).click();
		await page.locator('.review-textarea').fill(comment);
		await page
			.locator('.review-form')
			.getByRole('button', { name: 'Submit' })
			.click();

		const editedCard = page.locator('.review-card', { hasText: comment });
		await expect(editedCard).toBeVisible({ timeout: 10_000 });
		await expect(editedCard.locator('.star-display.filled')).toHaveCount(5);

		const edited = await admin
			.from('route_reviews')
			.select('rating')
			.eq('route_id', RUNNER_PUBLIC_ROUTE_ID)
			.eq('user_id', USER_A.id)
			.single();
		expect((edited.data as { rating: number }).rating).toBe(5);

		// Delete through the UI: the author's own card carries a delete
		// button, gated behind the shared ConfirmDialog.
		await editedCard.locator('.review-delete-btn').click();
		const dialog = page.getByTestId('review-delete-confirm-dialog');
		await expect(dialog).toBeVisible();
		await dialog.getByRole('button', { name: 'Delete review' }).click();

		await expect(
			page.locator('.review-card', { hasText: comment })
		).toHaveCount(0, { timeout: 10_000 });
		await expect(page.locator('.no-reviews')).toBeVisible();

		// The row is actually gone, not just hidden client-side.
		const remaining = await admin
			.from('route_reviews')
			.select('id')
			.eq('route_id', RUNNER_PUBLIC_ROUTE_ID)
			.eq('user_id', USER_A.id);
		expect(remaining.data).toEqual([]);
	});

	test('cancelling the delete confirm keeps the review', async ({ page }) => {
		const comment = `e2e keep review ${Date.now()}`;

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByRole('button', { name: 'Rate', exact: true }).click();
		await page.locator('.review-textarea').fill(comment);
		await page.locator('.review-form').getByRole('button', { name: 'Submit' }).click();

		const card = page.locator('.review-card', { hasText: comment });
		await expect(card).toBeVisible({ timeout: 10_000 });

		await card.locator('.review-delete-btn').click();
		const dialog = page.getByTestId('review-delete-confirm-dialog');
		await expect(dialog).toBeVisible();
		await dialog.getByRole('button', { name: 'Cancel' }).click();

		await expect(dialog).toBeHidden();
		await expect(card).toBeVisible();
	});

	test('Submit disables while the upsert is in flight (no double-submit)', async ({ page }) => {
		const comment = `e2e double-submit ${Date.now()}`;

		// Hold the upsert response open so the in-flight window stays
		// observable, and count how many POSTs actually reach the server.
		let postCount = 0;
		let release: () => void = () => {};
		const gate = new Promise<void>((r) => (release = r));
		await page.route('**/rest/v1/route_reviews*', async (route) => {
			if (route.request().method() === 'POST') {
				postCount += 1;
				await gate;
			}
			await route.continue();
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByRole('button', { name: 'Rate', exact: true }).click();
		await page.locator('.review-textarea').fill(comment);

		const submit = page.locator('.review-form').getByRole('button', { name: 'Submit' });
		await submit.click();

		// The guard flips the button disabled the moment the upsert starts,
		// so a second tap can't fire a duplicate write.
		await expect(submit).toBeDisabled();
		expect(postCount).toBe(1);

		release();
		await expect(page.locator('.review-card', { hasText: comment })).toBeVisible({
			timeout: 10_000
		});
		// Exactly one write reached the server across the whole flow.
		expect(postCount).toBe(1);
	});
});
