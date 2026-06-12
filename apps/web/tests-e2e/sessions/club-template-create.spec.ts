import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Session planner P3 (session_planner.md) — create a club-owned session template
 * from the club Templates tab. The "New session template" affordance links to
 * the unified create hub (/plans/new?type=session&club=<id>), which mounts the
 * SessionPlanEditor in club-owned mode; on save it returns to the Templates tab
 * with the new template listed and the row carries club_id.
 *
 * USER_A owns Richmond Run Club (admin), so the admin-only link is visible.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs — create session template via the hub', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdTitles: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const title of createdTitles.splice(0)) {
			try {
				await admin.from('session_plans').delete().eq('title', title);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('admin creates a club-owned session template; it lands club_id-set and lists', async ({
		page
	}) => {
		const title = `e2e-club-session-create ${Date.now()}`;
		createdTitles.push(title);

		await page.goto('/clubs/richmond-run-club?tab=templates');

		// The admin-only front door links to the unified create hub, pre-scoped
		// to session + this club.
		const newLink = page.getByTestId('new-session-template');
		await expect(newLink).toBeVisible({ timeout: 10_000 });
		await newLink.click();
		await page.waitForURL(/\/plans\/new\?.*type=session/, { timeout: 10_000 });
		await page.waitForURL(new RegExp(`club=${RICHMOND_CLUB_ID}`), { timeout: 10_000 });

		// The session branch is active — the editor is mounted.
		const editor = page.locator('.session-editor');
		await expect(editor).toBeVisible({ timeout: 5_000 });
		await editor.getByLabel('Title', { exact: true }).fill(title);
		const card = editor.locator('.item-card').first();
		await card.getByRole('combobox', { name: 'Movement' }).fill('Sun Salutation');
		await card.getByLabel('Seconds', { exact: true }).fill('60');

		await editor.getByRole('button', { name: 'Save', exact: true }).click();

		// A club-owned create returns to the Templates tab it came from, with the
		// new template listed.
		await page.waitForURL(/\/clubs\/richmond-run-club/, { timeout: 10_000 });
		await expect(page.getByRole('link', { name: title })).toBeVisible({ timeout: 10_000 });

		// It persisted as a club-owned plan (club_id set, author = the admin).
		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('session_plans')
			.select('id, club_id, author_id')
			.eq('title', title);
		expect(rows?.length).toBe(1);
		expect(rows?.[0].club_id).toBe(RICHMOND_CLUB_ID);
		expect(rows?.[0].author_id).toBe(USER_A.id);
	});
});
