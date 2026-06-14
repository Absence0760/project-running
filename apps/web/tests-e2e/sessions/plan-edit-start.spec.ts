import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Two session-plan lifecycle steps the instructor relies on that the build /
 * attach happy-path (session-plan.spec.ts) doesn't cover:
 *
 * (a) EDIT an existing plan — reopen a saved sequence, add a movement, save,
 *     and confirm the extra step round-trips. session-plan.spec only ever
 *     builds a fresh plan; the editor's `existing` (update) path is untested.
 * (b) START the runner FROM a class event — a member on the class detail page
 *     follows the attached-sequence link through to /sessions/[id] and can
 *     start the follow-along player. session-plan.spec attaches the plan and
 *     asserts the read-only sequence, but never follows the link to the runner.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/sessions/[id] — edit + start-from-event', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdPlanIds: string[] = [];
	const createdEventIds: string[] = [];

	async function seedPlan(items: { position: number; movement_name: string; reps: number }[]): Promise<{
		id: string;
		title: string;
	}> {
		const admin = getAdminClient();
		const title = `e2e-edit-plan ${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
		const { data, error } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title, discipline: 'Pilates' })
			.select('id')
			.single();
		if (error) throw error;
		const planId = data!.id as string;
		createdPlanIds.push(planId);
		await admin.from('session_plan_items').insert(
			items.map((it) => ({
				plan_id: planId,
				position: it.position,
				movement_name: it.movement_name,
				kind: 'reps' as const,
				reps: it.reps,
				per_side: false
			}))
		);
		return { id: planId, title };
	}

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of createdEventIds.splice(0)) {
			try {
				await deleteEvent(id);
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of createdPlanIds.splice(0)) {
			try {
				await admin.from('session_plans').delete().eq('id', id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('editing a saved plan to add a movement round-trips the new step', async ({ page }) => {
		const { id: planId, title } = await seedPlan([
			{ position: 0, movement_name: 'The Hundred', reps: 100 },
			{ position: 1, movement_name: 'Roll Up', reps: 8 }
		]);

		await page.goto(`/sessions/${planId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('session-steps').locator('li')).toHaveCount(2);

		// Open the editor on the existing plan (header action shares the
		// "Save" label with the editor's primary button — scope each click).
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		await expect(modal.locator('.item-card')).toHaveCount(2);

		// Append a third movement and save the update.
		await modal.getByRole('button', { name: 'Add movement' }).click();
		const newCard = modal.locator('.item-card').nth(2);
		await newCard.getByLabel('Type').selectOption('reps');
		await newCard.getByLabel('Movement', { exact: true }).fill('Teaser');
		await newCard.getByLabel('Reps', { exact: true }).fill('6');
		await modal.getByRole('button', { name: 'Save', exact: true }).click();

		await expect(modal).toHaveCount(0, { timeout: 10_000 });

		// The detail view reflects the updated three-step sequence.
		const steps = page.getByTestId('session-steps').locator('li');
		await expect(steps).toHaveCount(3, { timeout: 10_000 });
		await expect(steps.nth(2)).toContainText('Teaser');

		// And the new item persisted on the plan.
		const admin = getAdminClient();
		const { data: itemRows } = await admin
			.from('session_plan_items')
			.select('movement_name')
			.eq('plan_id', planId);
		expect((itemRows ?? []).map((r) => r.movement_name)).toContain('Teaser');
	});

	test('a class event links through to its attached session, where the runner starts', async ({
		page
	}) => {
		const { id: planId } = await seedPlan([{ position: 0, movement_name: 'Cat Cow', reps: 10 }]);

		const eventTitle = `e2e-class-start ${Date.now()}`;
		const eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: eventTitle,
			category: 'class',
			discipline: 'Pilates',
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});
		createdEventIds.push(eventId);
		await getAdminClient().from('events').update({ session_plan_id: planId }).eq('id', eventId);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: eventTitle })).toBeVisible({ timeout: 10_000 });

		// The attached sequence links to the session page.
		const sequence = page.getByTestId('session-sequence');
		const planLink = sequence.locator('a.session-plan-name');
		await expect(planLink).toHaveAttribute('href', `/sessions/${planId}`);
		await planLink.click();

		await page.waitForURL(new RegExp(`/sessions/${planId}$`), { timeout: 10_000 });

		// The follow-along player is reachable from there.
		await page.getByTestId('session-start').click();
		await expect(page.getByTestId('session-runner')).toBeVisible({ timeout: 10_000 });
	});
});
