import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_B } from '../fixtures/users';

/**
 * VerifiedBadge accessible label is localized, not hardcoded English.
 *
 * The Flutter twin already falls back to the localized standard copy
 * ("Official verified club") when no explicit tooltip is passed; web
 * used to ship a hardcoded English string as the default `title`,
 * meaning the badge's `aria-label` could never localize. This pins the
 * fix: the badge on a verified club renders with the i18n value of
 * `verifiedBadge.tooltip` (English default catalogue).
 *
 * Richmond Run Club (seeded, Alex/USER_B is an active member) is flipped
 * to `is_verified = true` for the duration of the test and reverted in
 * afterAll so the shared seed stays clean for other shards.
 */

const RICHMOND_ID = 'c1111111-0000-0000-0000-000000000001';
const VERIFIED_LABEL = 'Official verified club';

test.describe('/clubs/[slug] — verified badge has a localized label', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { error } = await admin
			.from('clubs')
			.update({ is_verified: true })
			.eq('id', RICHMOND_ID);
		if (error) throw error;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		await admin.from('clubs').update({ is_verified: false }).eq('id', RICHMOND_ID);
	});

	test('badge renders with the i18n tooltip as its accessible name', async ({ page }) => {
		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });

		const badge = page.getByTestId('verified-badge').first();
		await expect(badge).toBeVisible({ timeout: 10_000 });
		// The localized label flows into both title + aria-label — not a
		// hardcoded literal baked into the component.
		await expect(badge).toHaveAttribute('aria-label', VERIFIED_LABEL);
		await expect(badge).toHaveAttribute('title', VERIFIED_LABEL);
	});
});
