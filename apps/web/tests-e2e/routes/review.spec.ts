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
 * submit → render → edit → row removed after a service-role delete.
 *
 * Companion to routes/detail.spec.ts:171 (single-shot submit only).
 * The cookie-consent banner is fixed-position and intercepts clicks on
 * the Submit button, so we pre-accept via addInitScript — same pattern
 * as cross-user/sagas/kudos-notification.spec.ts.
 *
 * There is no UI delete affordance on the review card today
 * (apps/web/src/routes/routes/[id]/+page.svelte renders rating + date
 * + comment with no row-level delete button), so the "delete" leg of
 * the saga goes through service-role + reload. The TODO below tracks
 * that gap.
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

	test('submit → render in list, edit → rating persists, service-role delete → row gone', async ({
		page
	}) => {
		const admin = getAdminClient();
		const comment = `e2e route review ${Date.now()}`;

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		await page.getByRole('button', { name: 'Rate', exact: true }).click();

		const formStars = page.locator('.review-form .star-row .star-btn');
		await expect(formStars).toHaveCount(5);
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

		// TODO: there is no UI delete affordance for route reviews — when
		// a per-row delete button lands on .review-card, swap this for a
		// click + assertion. For now, the closest behavioural pin is
		// service-role delete + reload → row disappears.
		await deleteAuthorReviews();
		await page.reload();
		await expect(
			page.locator('.review-card', { hasText: comment })
		).toHaveCount(0);
		await expect(page.locator('.no-reviews')).toBeVisible();
	});
});
