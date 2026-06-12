import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Session planner P1 (session_planner.md) — build + save + reuse a session
 * plan, then attach it to a class event and confirm the event surfaces the
 * expanded sequence read-only.
 *
 * USER_A owns Richmond Run Club (admin) so they're the event organiser the
 * attach trigger requires. Unique titles per run so assertions + cleanup never
 * collide in the shared seed DB.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/sessions — session plan build, read, attach', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdEvents: string[] = [];
	const createdPlanTitles: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of createdEvents.splice(0)) {
			try {
				await deleteEvent(id);
			} catch (_) {
				/* best-effort */
			}
		}
		for (const title of createdPlanTitles.splice(0)) {
			try {
				await admin.from('session_plans').delete().eq('title', title);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('build a 3-item plan with a per-side hold, reopen, attach to a class event', async ({
		page
	}) => {
		const stamp = Date.now();
		const planTitle = `e2e-session ${stamp}`;
		createdPlanTitles.push(planTitle);

		await page.goto('/sessions');
		await page.getByRole('button', { name: 'New session' }).click();
		const modal = page.locator('.modal', { hasText: 'New session' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByLabel('Title').fill(planTitle);

		// Three movements: a hold, a per-side hold, and a reps item.
		// Movement 0 (default row): Downward Dog, hold 30s.
		const cards = modal.locator('.item-card');
		await cards.nth(0).getByLabel('Movement').fill('Downward Dog');
		await cards.nth(0).getByLabel('Seconds').fill('30');

		// Movement 1: Low Lunge, hold 45s, per side.
		await modal.getByRole('button', { name: 'Add movement' }).click();
		await cards.nth(1).getByLabel('Movement').fill('Low Lunge');
		await cards.nth(1).getByLabel('Seconds').fill('45');
		await cards.nth(1).getByLabel('Per side (left & right)').check();

		// Movement 2: The Hundred, reps.
		await modal.getByRole('button', { name: 'Add movement' }).click();
		await cards.nth(2).getByLabel('Type').selectOption('reps');
		await cards.nth(2).getByLabel('Movement').fill('The Hundred');
		await cards.nth(2).getByLabel('Reps').fill('100');

		await modal.getByRole('button', { name: 'Save', exact: true }).click();

		// Navigated to the detail/read view; the per-side hold expanded to L/R.
		await expect(page.getByRole('heading', { name: planTitle })).toBeVisible({
			timeout: 10_000
		});
		const steps = page.getByTestId('session-steps').locator('li');
		// 1 (Downward Dog) + 2 (Low Lunge L/R) + 1 (The Hundred) = 4 steps.
		await expect(steps).toHaveCount(4);
		await expect(steps.nth(1)).toContainText('Low Lunge (Left)');
		await expect(steps.nth(2)).toContainText('Low Lunge (Right)');
		await expect(steps.nth(3)).toContainText('100 reps');

		// The plan persisted with three items, one per_side.
		const admin = getAdminClient();
		const { data: planRow } = await admin
			.from('session_plans')
			.select('id')
			.eq('title', planTitle)
			.single();
		const planId = planRow!.id as string;
		const { data: itemRows } = await admin
			.from('session_plan_items')
			.select('per_side')
			.eq('plan_id', planId);
		expect(itemRows).toHaveLength(3);
		expect((itemRows ?? []).filter((r) => r.per_side)).toHaveLength(1);

		// Reopen from the list to confirm reuse (read round-trips).
		await page.goto('/sessions');
		await page.getByRole('link', { name: planTitle }).click();
		await expect(page.getByTestId('session-steps').locator('li')).toHaveCount(4);

		// Create a class event USER_A organises, then attach the plan.
		const eventTitle = `e2e-class ${stamp}`;
		const eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: eventTitle,
			category: 'class',
			discipline: 'Vinyasa yoga',
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});
		createdEvents.push(eventId);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: eventTitle })).toBeVisible({
			timeout: 10_000
		});

		const sequence = page.getByTestId('session-sequence');
		await expect(sequence).toBeVisible();
		await sequence.getByRole('button', { name: 'Attach to a class event' }).click();
		await page.getByTestId('attach-plan-select').selectOption(planId);
		await page.getByTestId('attach-plan-save').click();

		// The event now surfaces the attached sequence read-only.
		await expect(sequence.getByText('Low Lunge (Left)')).toBeVisible({ timeout: 10_000 });
		await expect(sequence.getByText('Low Lunge (Right)')).toBeVisible();

		// And the attachment persisted on the event row.
		const { data: evRow } = await admin
			.from('events')
			.select('session_plan_id')
			.eq('id', eventId)
			.single();
		expect(evRow?.session_plan_id).toBe(planId);
	});
});
