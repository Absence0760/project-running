import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /coach — deleting an archived conversation is permanent, so it now
 * routes through the shared ConfirmDialog (was a one-tap "Delete forever"
 * that fired immediately). Seed a no-plan archive, open the conversation
 * sidebar, and assert: Cancel keeps it, Confirm removes it.
 */

const ARCHIVED_AT = '2026-05-01T12:00:00.000Z';

async function clearArchive() {
	await getAdminClient()
		.from('coach_messages')
		.delete()
		.eq('user_id', USER_A.id)
		.is('plan_id', null);
}

test.describe('/coach — archived-conversation delete', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		await clearArchive();
		await getAdminClient()
			.from('coach_messages')
			.insert([
				{
					user_id: USER_A.id,
					plan_id: null,
					role: 'user',
					content: 'How was my long run pace?',
					archived_at: ARCHIVED_AT,
					created_at: '2026-05-01T11:59:00.000Z'
				},
				{
					user_id: USER_A.id,
					plan_id: null,
					role: 'assistant',
					content: 'Solid — steady effort throughout.',
					archived_at: ARCHIVED_AT,
					created_at: '2026-05-01T11:59:30.000Z'
				}
			]);
	});

	test.afterEach(clearArchive);

	test('Cancel keeps the archive; Confirm deletes it', async ({ page }) => {
		// ?plan=none → planId null, matching the seeded archive's plan filter.
		await page.goto('/coach?plan=none');
		await expect(page.getByPlaceholder(/Ask about/i)).toBeVisible({ timeout: 15_000 });

		// The conversation sidebar starts collapsed — open it.
		await page.getByRole('button', { name: /Show conversations|Hide conversations/i }).click();

		const archiveRow = page.locator('.archive-row', { hasText: 'How was my long run pace?' });
		await expect(archiveRow).toBeVisible({ timeout: 10_000 });

		// Delete → ConfirmDialog. Cancel keeps the row.
		await archiveRow.getByRole('button', { name: 'Delete archive' }).click();
		const dialog = page.locator('.modal', { hasText: 'Delete this conversation?' });
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(archiveRow).toBeVisible();

		// Delete → confirm → row gone.
		await archiveRow.getByRole('button', { name: 'Delete archive' }).click();
		await dialog.getByRole('button', { name: 'Delete forever' }).click();
		await expect(archiveRow).toHaveCount(0, { timeout: 10_000 });
	});
});
