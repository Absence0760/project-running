import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Gym programming — create a club-owned gym-routine template from the club
 * Templates tab in one step (gym_programming.md). The single admin "Add
 * template" button links to the unified create hub (/plans/new?club=<id>);
 * choosing "Gym routine" mounts the RoutineEditor, and on save the new routine
 * is published to the club via publish_gym_routine_as_template (the
 * admin-checked RPC — gym_routines has no club-admin INSERT policy, unlike
 * session_plans) and the user is returned to the Templates tab.
 *
 * Mirrors sessions/club-template-create.spec.ts; the difference is gym leaves a
 * personal source routine behind (build-then-publish), so two rows share the
 * title — the personal one (club_id null) and the published club copy.
 *
 * USER_A owns Richmond Run Club (admin), so the admin-only button is visible.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs — create gym-routine template via the hub', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdTitles: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const title of createdTitles.splice(0)) {
			try {
				// The personal source + the published club copy share the title;
				// exercises + sets cascade.
				await admin.from('gym_routines').delete().eq('title', title);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('admin creates a club gym-routine template; it lands club_id-set and lists', async ({
		page
	}) => {
		const title = `e2e-club-gym-create ${Date.now()}`;
		createdTitles.push(title);

		await page.goto('/clubs/richmond-run-club?tab=templates');

		// One admin "Add template" front door → the create hub, scoped to this club.
		const newBtn = page.getByTestId('new-template');
		await expect(newBtn).toBeVisible({ timeout: 10_000 });
		await newBtn.click();
		await page.waitForURL(new RegExp(`/plans/new\\?.*club=${RICHMOND_CLUB_ID}`), {
			timeout: 10_000
		});

		// Pick the Gym-routine kind from the hub chooser.
		await page.getByTestId('kind-gym').click();
		const editor = page.locator('.routine-editor');
		await expect(editor).toBeVisible({ timeout: 5_000 });
		await page.getByTestId('routine-title').fill(title);
		await page.getByTestId('routine-exercise-name').first().fill('Back Squat');

		await page.getByTestId('routine-save').click();

		// A club-owned create returns to the Templates tab it came from, with the
		// new template listed.
		await page.waitForURL(/\/clubs\/richmond-run-club/, { timeout: 10_000 });
		await expect(page.getByRole('link', { name: title })).toBeVisible({ timeout: 10_000 });

		// The published club copy persisted (club_id set, author = the admin).
		const admin = getAdminClient();
		const { data: clubRows } = await admin
			.from('gym_routines')
			.select('id, club_id, author_id')
			.eq('club_id', RICHMOND_CLUB_ID)
			.eq('title', title);
		expect(clubRows?.length).toBe(1);
		expect(clubRows?.[0].author_id).toBe(USER_A.id);
	});
});
