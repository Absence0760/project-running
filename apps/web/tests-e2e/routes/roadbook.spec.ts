import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRoute } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /routes/[id]/roadbook — the race crew sheet built from a route's course
 * markers + a goal time (migration 20270129_001 markers + roadbook.ts engine).
 * Asserts projected arrival, a red cutoff chip when the goal is too slow, the
 * URL carrying the goal (shareable), and that the effort/even toggle re-paces.
 */

async function seedRoute(): Promise<string> {
	const admin = getAdminClient();
	const id = crypto.randomUUID();
	// A climbing course: flat first half, steep second half, so the effort
	// model has terrain to bite on. ~0.001° lat ≈ 111 m.
	const waypoints = [];
	for (let i = 0; i <= 18; i++) {
		waypoints.push({ lat: 51.5 + i * 0.001, lng: -0.12, ele: i > 9 ? (i - 9) * 30 : 0 });
	}
	const { error } = await admin.from('routes').insert({
		id,
		user_id: USER_A.id,
		name: 'E2E Roadbook Course',
		waypoints,
		distance_m: 2000,
		is_public: false
	});
	if (error) throw new Error(`seedRoute failed: ${error.message}`);

	// Aid station near the start, a cutoff near the middle (30-min limit).
	const mk = async (kind: string, label: string, lat: number, meta: object) => {
		const { error: e } = await admin.from('route_markers').insert({
			route_id: id,
			user_id: USER_A.id,
			kind,
			label,
			lat,
			lng: -0.12,
			meta
		});
		if (e) throw new Error(`marker ${label} failed: ${e.message}`);
	};
	await mk('aid_station', 'Aid 1', 51.5 + 4 * 0.001, { services: ['water', 'food'] });
	await mk('cutoff', 'Gate', 51.5 + 9 * 0.001, { cutoff_elapsed_s: 1800 });
	return id;
}

test.describe('/routes/[id]/roadbook', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let routeId: string | null = null;

	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId);
			} catch (_) {
				/* cascade clears markers */
			}
			routeId = null;
		}
	});

	test('renders the schedule, flags a missed cutoff, and is URL-shareable', async ({ page }) => {
		routeId = await seedRoute();

		// A deliberately slow goal (2h) → the 30-min cutoff at mid-course is a miss.
		await page.goto(`/routes/${routeId}/roadbook?goal=7200&start=06:00&model=even`);

		const rows = page.locator('.rb-table tbody tr');
		await expect(rows).toHaveCount(4); // start, Aid 1, Gate, finish
		await expect(rows.nth(1)).toContainText('Aid 1');
		await expect(rows.nth(1)).toContainText('Water');
		await expect(rows.nth(2)).toContainText('Gate');

		// The cutoff at the slow goal is red (miss).
		await expect(rows.nth(2).locator('.cut-miss')).toBeVisible();

		// Tighten the goal to 30 min → the cutoff is no longer a miss.
		await page.getByLabel('Goal time').fill('0:30:00');
		await page.getByLabel('Goal time').blur();
		await expect(page).toHaveURL(/goal=1800/);
		await expect(rows.nth(2).locator('.cut-miss')).toHaveCount(0);
	});

	test('effort model re-paces vs even and updates the URL', async ({ page }) => {
		routeId = await seedRoute();
		await page.goto(`/routes/${routeId}/roadbook?goal=3600&model=even`);

		// Read the Gate arrival under even pacing.
		const gateArrival = page.locator('.rb-table tbody tr').nth(2).locator('td.num').nth(2);
		const evenText = (await gateArrival.textContent())?.trim();

		// Switch to effort — the flat first half is reached sooner, so the
		// mid-course Gate arrival should change.
		await page.getByRole('button', { name: 'Effort' }).click();
		await expect(page).toHaveURL(/model=effort/);
		await expect(async () => {
			const effortText = (await gateArrival.textContent())?.trim();
			expect(effortText).not.toBe(evenText);
		}).toPass();
	});
});
