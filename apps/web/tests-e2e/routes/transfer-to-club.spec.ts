import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

const SYDNEY_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const SYDNEY_SLUG = 'sydney-run-club';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

async function restoreRouteToPersonal() {
	await getAdminClient()
		.from('routes')
		.update({ club_id: null })
		.eq('id', RUNNER_PUBLIC_ROUTE_ID);
}

/**
 * Owner-initiated route transfer to a club. The UI affordance lives
 * on /clubs/[slug] (Routes tab, admin-only) — not on /routes/[id] —
 * via the "Transfer from My routes" button which opens a modal that
 * picks a personal route the admin owns and flips routes.club_id.
 *
 * The detail.spec on the club page already pins the affordance is
 * visible for the admin (clubs/detail.spec.ts:49). This spec drives
 * the end-to-end transfer: click → select → confirm → route shows up
 * under the club Routes tab → club_id row update verified.
 *
 * Cleanup: service-role afterEach restores `routes.club_id = null` so
 * the seed state is preserved for sibling specs.
 */

test.describe('/routes — owner transfers a personal route into Sydney Run Club', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(setConsentAccepted);
		await restoreRouteToPersonal();
	});

	test.afterEach(async () => {
		await restoreRouteToPersonal();
	});

	test('Transfer modal → route lands in club Routes tab + DB row updates', async ({
		page
	}) => {
		const admin = getAdminClient();

		await page.goto(`/clubs/${SYDNEY_SLUG}`);
		await expect(
			page.getByRole('heading', { level: 1, name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('tab', { name: /^Routes/ }).click();

		await page
			.getByRole('button', { name: /Transfer from My routes/ })
			.first()
			.click();

		const modal = page.locator('.modal', { hasText: 'Transfer route to club' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.locator('select').selectOption(RUNNER_PUBLIC_ROUTE_ID);
		await modal.getByRole('button', { name: 'Transfer', exact: true }).click();

		await expect(modal).toBeHidden({ timeout: 10_000 });

		await expect(
			page.locator(`.club-route-grid a[href$="${RUNNER_PUBLIC_ROUTE_ID}"]`)
		).toBeVisible({ timeout: 10_000 });

		const after = await admin
			.from('routes')
			.select('club_id')
			.eq('id', RUNNER_PUBLIC_ROUTE_ID)
			.single();
		expect((after.data as { club_id: string | null }).club_id).toBe(
			SYDNEY_CLUB_ID
		);

		// The transfer modal's `transferableRoutes` filter excludes routes
		// already in a club — so re-opening the modal must no longer offer
		// the route we just moved. Pins the optimistic state refresh in
		// the page after the write.
		await page
			.getByRole('button', { name: /Transfer from My routes/ })
			.first()
			.click();
		const modal2 = page.locator('.modal', {
			hasText: 'Transfer route to club'
		});
		await expect(modal2).toBeVisible({ timeout: 5_000 });
		const remainingOptions = modal2.locator(
			`select option[value="${RUNNER_PUBLIC_ROUTE_ID}"]`
		);
		await expect(remainingOptions).toHaveCount(0);
	});
});
