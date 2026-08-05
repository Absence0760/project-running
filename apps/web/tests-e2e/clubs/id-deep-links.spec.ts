import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Stable-id deep links. The notification worker (apps/job_worker) builds every
 * email + push CTA from one notifications row and cannot join for a club slug,
 * so it addresses an event and a club by id; web owns the id → canonical-URL
 * resolution. These paths are also baked into mail and notification trays that
 * are already delivered, so they have to keep resolving indefinitely — which is
 * exactly why they get an e2e rather than only a unit guard.
 *
 * Seed fixtures (apps/backend/supabase/seed.sql): the public
 * 'richmond-run-club' + its public 'Sunday Long Run' event.
 */

const CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const EVENT_ID = 'e1111111-0000-0000-0000-000000000001';

test.describe('id deep links resolve to canonical URLs (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('/events/[id] forwards to the nested club event page', async ({ page }) => {
		await page.goto(`/events/${EVENT_ID}`);
		await expect(page).toHaveURL(
			new RegExp(`/clubs/richmond-run-club/events/${EVENT_ID}$`),
			{ timeout: 10_000 },
		);
		await expect(page).toHaveTitle('Sunday Long Run — Threkir');
	});

	test('/clubs/[uuid] forwards to the slug URL', async ({ page }) => {
		await page.goto(`/clubs/${CLUB_ID}`);
		await expect(page).toHaveURL(/\/clubs\/richmond-run-club$/, { timeout: 10_000 });
		await expect(page).toHaveTitle('Richmond Run Club — Threkir');
	});
});

test.describe('/notifications resolves to the inbox tab', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/notifications forwards to the viewer own profile inbox tab', async ({ page }) => {
		await page.goto('/notifications');
		await expect(page).toHaveURL(
			new RegExp(`/u/${USER_A.id}\\?tab=notifications$`),
			{ timeout: 10_000 },
		);
	});
});
