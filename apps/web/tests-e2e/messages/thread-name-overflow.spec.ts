import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /messages — a long partner name must not push the unread count out of
 * the thread list.
 *
 * `.thread-top` is a flex row holding the display name and the unread
 * badge, and the name's `<strong>` kept the default `min-width: auto`, so
 * it refused to shrink below its own text. `.threads` clips its overflow,
 * so a long name pushed the badge past the pane edge — losing the one
 * thing on the row you cannot afford to lose, on the surface whose whole
 * job is telling you there is something new.
 *
 * The name is stretched in the DOM rather than in `profiles`: the fix is
 * layout, the shards share one database, and renaming a seed user would
 * reach every spec that asserts on it.
 */
test.describe('/messages — long display name', () => {
	test.use({ storageState: USER_B.storageStatePath });

	const bodies: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const body of bodies.splice(0)) {
			await admin.from('direct_messages').delete().eq('body', body);
		}
	});

	test('the name truncates and the unread badge stays inside the pane', async ({ page }) => {
		const body = `e2e-name-overflow ${Date.now()}`;
		bodies.push(body);
		await getAdminClient()
			.from('direct_messages')
			.insert({ sender_id: USER_A.id, recipient_id: USER_B.id, body });

		await page.goto('/messages');
		const thread = page.locator('.thread', { hasText: body });
		await expect(thread).toBeVisible({ timeout: 10_000 });
		const badge = thread.locator('.badge');
		await expect(badge).toBeVisible();

		await thread.locator('.thread-top strong').evaluate((el) => {
			el.textContent = 'Bartholomew Fitzgerald-Montgomery '.repeat(6).trim();
		});

		const aside = page.locator('aside.threads');
		const asideBox = await aside.boundingBox();
		const badgeBox = await badge.boundingBox();
		const nameBox = await thread.locator('.thread-top strong').boundingBox();
		expect(asideBox).not.toBeNull();
		expect(badgeBox).not.toBeNull();
		expect(nameBox).not.toBeNull();

		// The badge is still fully within the pane that clips its overflow.
		expect(badgeBox!.x).toBeGreaterThanOrEqual(asideBox!.x);
		expect(badgeBox!.x + badgeBox!.width).toBeLessThanOrEqual(asideBox!.x + asideBox!.width + 1);
		// Which it can only be because the name gave way.
		expect(nameBox!.width).toBeLessThan(asideBox!.width);

		const overflows = await thread.locator('.thread-top strong').evaluate((el) => ({
			clipped: el.scrollWidth > el.clientWidth,
			whiteSpace: getComputedStyle(el).whiteSpace,
			textOverflow: getComputedStyle(el).textOverflow,
		}));
		expect(overflows.clipped).toBe(true);
		expect(overflows.whiteSpace).toBe('nowrap');
		expect(overflows.textOverflow).toBe('ellipsis');
	});
});
