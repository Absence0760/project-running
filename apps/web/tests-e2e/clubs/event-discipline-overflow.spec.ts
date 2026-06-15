import { expect, test } from '@playwright/test';

import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — the class-event discipline label is
 * user-controlled free text. Without `overflow-wrap` a long single token
 * punches out of the hero. This pins the wrap fix on `.discipline-value`.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — discipline overflow', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* best-effort */
			}
			eventId = null;
		}
	});

	test('a long unbreakable discipline wraps instead of overflowing the hero', async ({ page }) => {
		const title = `e2e-class-overflow ${Date.now()}`;
		// A long single token with no spaces is the worst case.
		const discipline =
			'ReformerPilatesWithBreathworkAndProgressiveMyofascialReleaseForDeepRecoverySessions';
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		const value = page.locator('.discipline-value');
		await expect(value).toHaveText(discipline);
		await expect(value).toHaveCSS('overflow-wrap', 'anywhere');
		// The token breaks across lines, so the element doesn't overflow itself.
		const overflows = await value.evaluate((el) => el.scrollWidth > el.clientWidth + 1);
		expect(overflows).toBe(false);
	});
});
