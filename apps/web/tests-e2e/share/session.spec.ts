import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /share/session/[id] — public session-plan share page (anon + authed).
 *
 * A public session plan is readable logged-out (the "public session plans are
 * readable" RLS policy gates the anon read on is_public, and the blocks/items
 * inherit-visibility policies expose the children when the parent is public),
 * so this page works for a signed-out viewer. A private plan 404s. A session
 * plan carries no author fitness data, so nothing private leaks past what the
 * author made public.
 */

test.describe('/share/session/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	let publicPlanId: string | null = null;
	let privatePlanId: string | null = null;
	const stamp = Date.now();
	const title = `E2E Share session ${stamp}`;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data: pub, error } = await admin
			.from('session_plans')
			.insert({
				author_id: USER_A.id,
				title,
				discipline: 'Vinyasa Yoga',
				equipment: 'Mat',
				is_public: true
			})
			.select('id')
			.single();
		if (error) throw error;
		publicPlanId = (pub as { id: string }).id;
		await admin.from('session_plan_items').insert([
			{
				plan_id: publicPlanId,
				position: 0,
				movement_name: 'Downward Dog',
				kind: 'hold',
				duration_s: 60
			},
			{
				plan_id: publicPlanId,
				position: 1,
				movement_name: 'Warrior II',
				kind: 'hold',
				duration_s: 45,
				per_side: true
			}
		]);

		const { data: priv } = await admin
			.from('session_plans')
			.insert({
				author_id: USER_A.id,
				title: `${title} (private)`,
				is_public: false
			})
			.select('id')
			.single();
		privatePlanId = (priv as { id: string }).id;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		for (const id of [publicPlanId, privatePlanId]) {
			if (id) await admin.from('session_plans').delete().eq('id', id);
		}
	});

	test('anon viewer sees the public session + sign-up CTA', async ({ page }) => {
		await page.goto(`/share/session/${publicPlanId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		// The expanded steps surface: Downward Dog + the per-side Warrior II split
		// into Left / Right rows.
		const steps = page.getByTestId('session-steps');
		await expect(steps).toContainText('Downward Dog');
		await expect(steps).toContainText('Warrior II (Left)');
		await expect(steps).toContainText('Warrior II (Right)');
		// Anon visitors get the sign-up CTA.
		await expect(page.locator('a[href="/login?signup=1"]')).toBeVisible({ timeout: 5_000 });
	});

	test('private session 404s to the not-found state', async ({ page }) => {
		await page.goto(`/share/session/${privatePlanId}`);
		await expect(page.getByText('Session plan not found.')).toBeVisible({ timeout: 10_000 });
		// No sequence list for a hidden plan.
		await expect(page.getByTestId('session-steps')).toHaveCount(0);
	});
});
