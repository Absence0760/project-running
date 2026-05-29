import { expect, test } from '@playwright/test';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_B, USER_C_PRO } from '../fixtures/users';

// USER_B (alex) plays the coach; USER_C_PRO (morgan) plays the athlete.
const INVITE_TOKEN = 'e2ecoachinvitetoken000000000001';

test.describe('/coaching/accept/[token] — athlete redeems a coach invite', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('coach_athletes').insert({
			coach_id: USER_B.id,
			status: 'pending',
			invite_token: INVITE_TOKEN
		});
	});

	test.afterEach(async () => {
		try {
			await getAdminClient().from('coach_athletes').delete().eq('coach_id', USER_B.id);
		} catch (_) {
			/* best-effort */
		}
	});

	test('morgan redeems the invite link and lands on /coaching with alex as a coach', async ({
		page
	}) => {
		await page.goto(`/coaching/accept/${INVITE_TOKEN}`);
		await page.waitForURL(/\/coaching$/, { timeout: 15_000 });
		await expect(page.getByRole('heading', { level: 1, name: 'Coaching' })).toBeVisible({
			timeout: 10_000
		});
		// The coach renders as a link to their profile in the "My coaches" list.
		await expect(page.locator(`a[href="/u/${USER_B.id}"]`)).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/coaching — coach sees the athlete on their roster', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('coach_athletes').insert({
			coach_id: USER_B.id,
			athlete_id: USER_C_PRO.id,
			status: 'active',
			invite_token: INVITE_TOKEN,
			accepted_at: new Date().toISOString()
		});
	});

	test.afterEach(async () => {
		try {
			await getAdminClient().from('coach_athletes').delete().eq('coach_id', USER_B.id);
		} catch (_) {
			/* best-effort */
		}
	});

	test('alex sees morgan in the My athletes list', async ({ page }) => {
		await page.goto('/coaching');
		await expect(page.getByRole('heading', { level: 1, name: 'Coaching' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.locator(`a[href="/u/${USER_C_PRO.id}"]`)).toBeVisible({ timeout: 10_000 });
	});
});
