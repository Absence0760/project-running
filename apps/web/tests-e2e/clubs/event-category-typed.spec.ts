import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Typed club events (slice E) — type-first editor + category-gated detail.
 *
 * run / cycle are distance-based athletic events: route, distance, target
 * pace, race mode, results leaderboard. class / social are attendance-only:
 * no athletic affordances, a class surfaces its free-text discipline label.
 *
 * (a) Creating a Class via the editor hides route/distance/pace and reveals
 *     the discipline field; the detail page surfaces the discipline and hides
 *     the race panel + results/leaderboard + distance/pace stats.
 * (b) A run event still shows the full athletic surface (distance, target
 *     pace, "Submit my time"), proving run/cycle behave exactly as today.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug] — typed events (slice E)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const created: string[] = [];

	test.afterEach(async () => {
		for (const id of created.splice(0)) {
			try {
				await deleteEvent(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('Class: editor hides athletic fields + shows discipline; detail hides leaderboard', async ({
		page
	}) => {
		const title = `e2e-class ${Date.now()}`;
		const discipline = 'Vinyasa yoga';
		const dayIso = new Date(Date.now() + 7 * 24 * 3600 * 1000)
			.toISOString()
			.slice(0, 10);

		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: /New event/ }).click();
		const modal = page.locator('.modal', { hasText: 'New event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		// The athletic fields are uniquely addressable: the distance input is
		// the only step="0.1" number input, the pace minutes input carries the
		// "min" placeholder, and the route picker is the only <select>. Asserting
		// on these (not the label text) avoids colliding with the category hint
		// copy, which itself mentions "distance" / "pace".
		const distanceInput = modal.locator('input[step="0.1"]');
		const paceInput = modal.getByPlaceholder('min', { exact: true });
		const routeSelect = modal.locator('select');
		const disciplineInput = modal.getByPlaceholder(/Vinyasa yoga/);

		// Default category is Group run — the athletic surface is present.
		await expect(modal.getByRole('radio', { name: 'Group run' })).toBeChecked();
		await expect(distanceInput).toBeVisible();
		await expect(paceInput).toBeVisible();
		await expect(routeSelect).toBeVisible();
		await expect(disciplineInput).toHaveCount(0);

		// Switch to Class — route / distance / pace disappear, discipline appears.
		await modal.getByRole('radio', { name: 'Class', exact: true }).click();
		await expect(distanceInput).toHaveCount(0);
		await expect(paceInput).toHaveCount(0);
		await expect(routeSelect).toHaveCount(0);
		await expect(disciplineInput).toBeVisible();

		await modal.getByPlaceholder('Sunday long run').fill(title);
		await disciplineInput.fill(discipline);
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

		// createEvent persisted both category and discipline.
		const admin = getAdminClient();
		const { data: row } = await admin
			.from('events')
			.select('category, discipline, distance_m, pace_target_sec, route_id')
			.eq('id', id)
			.single();
		expect(row?.category).toBe('class');
		expect(row?.discipline).toBe(discipline);
		expect(row?.distance_m).toBeNull();
		expect(row?.pace_target_sec).toBeNull();
		expect(row?.route_id).toBeNull();

		// Detail page: discipline surfaced, athletic affordances absent.
		await page.goto(`/clubs/richmond-run-club/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByText(discipline)).toBeVisible();
		await expect(page.getByText('Submit my time')).toHaveCount(0);
		await expect(page.getByRole('heading', { name: /^Results/ })).toHaveCount(0);
		await expect(page.getByRole('heading', { name: 'Race control' })).toHaveCount(0);
		await expect(page.getByText('Target pace')).toHaveCount(0);
		// RSVP + Going remain — attendance applies to every category.
		await expect(page.getByText('Going', { exact: false }).first()).toBeVisible();
	});

	test('Run: athletic surface (distance, target pace, Submit my time) still present', async ({
		page
	}) => {
		const title = `e2e-run ${Date.now()}`;
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'run',
			distance_m: 5000,
			pace_target_sec: 300,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});
		created.push(id);

		await page.goto(`/clubs/richmond-run-club/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		// Athletic stats + the results section render exactly as before.
		await expect(page.getByText('Target pace').first()).toBeVisible();
		await expect(page.getByRole('heading', { name: /^Results/ })).toBeVisible();
		await expect(page.getByText('Submit my time')).toBeVisible();
	});
});
