import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * The class -> gym seam (club_events.md). A class host attaches an optional
 * gym_template (discipline + default duration); a signed-in attendee on the
 * event detail one-tap-logs the class as their OWN gym workout, pre-filled in
 * the canonical GymEditor. Inform-tier: nothing writes until the user confirms
 * inside the composer.
 *
 * (a) Host creates a Class with discipline + a default workout length via the
 *     editor; gym_template persists with the typed {discipline, duration_min}.
 * (b) On the detail page the attendee sees "Log this as a workout", opens the
 *     GymEditor pre-filled with the discipline as the title, fills a set,
 *     confirms, and a gym_workout lands in their own log.
 * Negative: a run event detail offers NO log-as-workout button (the two-sided
 * gate — athletic branch + non-class/null-template).
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — class -> gym seam', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const created: string[] = [];
	const createdWorkouts: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of createdWorkouts.splice(0)) {
			try {
				await admin.from('gym_workouts').delete().eq('id', id);
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of created.splice(0)) {
			try {
				await deleteEvent(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('Host templates a class; attendee logs it as a pre-filled workout', async ({ page }) => {
		const title = `e2e-seam-class ${Date.now()}`;
		const discipline = 'Vinyasa yoga';
		const dayIso = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString().slice(0, 10);

		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: /New event/ }).click();
		const modal = page.locator('.modal', { hasText: 'New event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		// Switch to Class — the discipline + default-duration seam fields appear.
		await modal.getByRole('radio', { name: 'Class', exact: true }).click();
		const disciplineInput = modal.getByPlaceholder(/Vinyasa yoga/);
		const durationInput = modal.getByTestId('gym-template-duration');
		await expect(disciplineInput).toBeVisible();
		await expect(durationInput).toBeVisible();

		await modal.getByPlaceholder('Sunday long run').fill(title);
		await disciplineInput.fill(discipline);
		await durationInput.fill('60');
		await modal.locator('input[type="date"]').first().fill(dayIso);
		await modal.locator('input[type="time"]').first().fill('07:30');
		await modal.getByRole('button', { name: /Create event/ }).click();
		await expect(modal).toHaveCount(0, { timeout: 10_000 });

		await page.getByRole('tab', { name: /^Events/ }).click();
		const eventRow = page.locator('a[href*="/events/"]', { hasText: title });
		await expect(eventRow).toBeVisible({ timeout: 10_000 });
		const href = (await eventRow.getAttribute('href')) ?? '';
		const id = href.match(/\/events\/([0-9a-f-]+)$/)![1];
		created.push(id);

		// gym_template persisted with the typed {discipline, duration_min} shape.
		const admin = getAdminClient();
		const { data: row } = await admin
			.from('events')
			.select('category, gym_template')
			.eq('id', id)
			.single();
		expect(row?.category).toBe('class');
		expect(row?.gym_template).toEqual({ discipline, duration_min: 60 });

		// Detail page: the inform-tier action is offered.
		await page.goto(`/clubs/richmond-run-club/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		const logBtn = page.getByTestId('log-as-workout');
		await expect(logBtn).toBeVisible();

		// Open the composer; it pre-fills the title from the class discipline.
		await logBtn.click();
		const gymModal = page.locator('.modal', { hasText: 'Log this as a workout' });
		await expect(gymModal).toBeVisible({ timeout: 5_000 });
		await expect(gymModal.getByPlaceholder('e.g. Push day')).toHaveValue(discipline);

		// Fill an exercise + a set, then confirm (inform-tier write happens here).
		await gymModal.getByPlaceholder('Exercise name').fill('Sun salutation');
		await gymModal.getByLabel('Reps', { exact: true }).first().fill('10');
		await gymModal.getByRole('button', { name: 'Save workout' }).click();
		await expect(gymModal).toHaveCount(0, { timeout: 10_000 });

		// A gym_workout titled from the class discipline lands in the user's log.
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gym_workouts')
						.select('id, title')
						.eq('user_id', USER_A.id)
						.eq('title', discipline);
					for (const w of data ?? []) createdWorkouts.push(w.id as string);
					return (data ?? []).length;
				},
				{ timeout: 10_000 }
			)
			.toBeGreaterThan(0);
	});

	test('Run event detail offers NO log-as-workout button', async ({ page }) => {
		const title = `e2e-seam-run ${Date.now()}`;
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'run',
			distance_m: 5000,
			pace_target_sec: 300
		});
		created.push(id);

		await page.goto(`/clubs/richmond-run-club/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('log-as-workout')).toHaveCount(0);
	});

	test('Social event with no template offers NO log-as-workout button', async ({ page }) => {
		const title = `e2e-seam-social ${Date.now()}`;
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'social'
		});
		created.push(id);

		await page.goto(`/clubs/richmond-run-club/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('log-as-workout')).toHaveCount(0);
	});
});
