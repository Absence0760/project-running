import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRoute } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /routes/[id] — community condition reports via the RouteConditions
 * component (migration 20270212_001).
 *
 * Distinct from course markers: any viewer of a visible route — not just the
 * owner — can file a report. Reads go through route_conditions_for_viewer
 * (fails closed to []). The composer self-hides when the viewer can't see /
 * report the route.
 */

async function insertRoute(isPublic: boolean): Promise<string> {
	const admin = getAdminClient();
	const id = crypto.randomUUID();
	const { error } = await admin.from('routes').insert({
		id,
		user_id: USER_A.id,
		name: 'E2E conditions route',
		waypoints: [
			{ lat: 51.5, lng: -0.12 },
			{ lat: 51.51, lng: -0.13 }
		],
		distance_m: 5_000,
		is_public: isPublic
	});
	if (error) throw new Error(`insertRoute failed: ${error.message}`);
	return id;
}

async function insertCondition(
	routeId: string,
	userId: string,
	condition: string,
	severity: string,
	note: string | null
): Promise<void> {
	const { error } = await getAdminClient().from('route_conditions').insert({
		route_id: routeId,
		user_id: userId,
		condition,
		severity,
		note
	});
	if (error) throw new Error(`insertCondition failed: ${error.message}`);
}

function acceptCookies(): void {
	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});
}

test.describe('/routes/[id] — condition reports (owner)', () => {
	test.use({ storageState: USER_A.storageStatePath });
	acceptCookies();

	let routeId: string | null = null;

	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId); // cascade clears route_conditions
			} catch (_) {
				/* best-effort */
			}
			routeId = null;
		}
	});

	test('owner reports a condition and sees it in the panel', async ({ page }) => {
		routeId = await insertRoute(false);
		await page.goto(`/routes/${routeId}`);

		// Empty state until a report exists.
		await expect(page.getByText('No condition reports yet.', { exact: false })).toBeVisible();

		await page.getByRole('button', { name: 'Report condition' }).click();
		await page.getByLabel('Condition').selectOption('flooded');
		await page.getByLabel('Severity').selectOption('impassable');
		await page.getByLabel('Note').fill('Creek over the bridge');
		await page
			.locator('.condition-composer')
			.getByRole('button', { name: 'Report condition' })
			.click();

		const list = page.locator('.conditions-list');
		await expect(list).toBeVisible();
		const rows = list.locator('.condition');
		await expect(rows).toHaveCount(1);
		await expect(rows.first().locator('.chip')).toHaveText('Flooded');
		await expect(rows.first().locator('.sev-tag')).toHaveText('Impassable');
		await expect(rows.first().locator('.condition-note')).toHaveText('Creek over the bridge');
	});

	test('a seeded report renders chip, severity and note', async ({ page }) => {
		routeId = await insertRoute(false);
		await insertCondition(routeId, USER_A.id, 'muddy', 'caution', 'Boggy in the dip');
		await page.goto(`/routes/${routeId}`);

		const row = page.locator('.conditions-list .condition').first();
		await expect(row.locator('.chip')).toHaveText('Muddy');
		await expect(row.locator('.sev-tag')).toHaveText('Caution');
		await expect(row.locator('.condition-note')).toHaveText('Boggy in the dip');
	});

	test('owner deletes their own report', async ({ page }) => {
		routeId = await insertRoute(false);
		await insertCondition(routeId, USER_A.id, 'closed', 'impassable', 'Logging closure');
		await page.goto(`/routes/${routeId}`);

		const rows = page.locator('.conditions-list .condition');
		await expect(rows).toHaveCount(1);
		await rows.first().getByRole('button', { name: 'Delete' }).click();
		// ConfirmDialog → confirm.
		await page.getByRole('button', { name: 'Delete', exact: true }).click();

		await expect(page.getByText('No condition reports yet.', { exact: false })).toBeVisible();
	});
});

test.describe('/routes/[id] — condition reports (non-owner viewer)', () => {
	test.use({ storageState: USER_B.storageStatePath });
	acceptCookies();

	let routeId: string | null = null;

	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId);
			} catch (_) {
				/* best-effort */
			}
			routeId = null;
		}
	});

	test('a non-owner viewer can report on a public route', async ({ page }) => {
		routeId = await insertRoute(true);
		await page.goto(`/routes/${routeId}`);

		await expect(page.getByRole('button', { name: 'Report condition' })).toBeVisible();
		await page.getByRole('button', { name: 'Report condition' }).click();
		await page.getByLabel('Condition').selectOption('overgrown');
		await page
			.locator('.condition-composer')
			.getByRole('button', { name: 'Report condition' })
			.click();

		await expect(page.locator('.conditions-list .condition')).toHaveCount(1);
		await expect(page.locator('.conditions-list .condition .chip').first()).toHaveText('Overgrown');
	});
});
