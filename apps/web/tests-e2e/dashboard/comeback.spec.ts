import { expect, test } from '@playwright/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Comeback-load card on /dashboard.
 *
 * The acute:chronic ratio behind LoadRampCard refuses to grade a runner whose
 * recent month is nearly empty — correctly, but that leaves the runner coming
 * back from a layoff, the one this signal most concerns, with no card at all.
 * Pure logic in lib/training/comeback.ts is unit-tested separately; this pins
 * the SURFACE: a big first week back is called out, a gentle one is confirmed,
 * a comeback with no real pre-break base shows nothing rather than a number,
 * and the ratio card never appears alongside this one.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
	);
}

const DAY_MS = 86_400_000;

async function seedRun(userId: string, daysAgo: number, distanceM: number) {
	await insertRun({
		user_id: userId,
		started_at: new Date(Date.now() - daysAgo * DAY_MS).toISOString(),
		distance_m: distanceM,
		duration_s: Math.round((distanceM / 1000) * 300),
		source: 'app',
	});
}

test.describe('dashboard comeback-load card', () => {
	let steep: SagaUser;
	let easing: SagaUser;
	let baseless: SagaUser;

	test.beforeAll(async () => {
		[steep, easing, baseless] = await createSagaUsers(3, {
			displayNames: ['Steep Comeback Runner', 'Easing Comeback Runner', 'Baseless Comeback Runner'],
		});

		// Four 40 km weeks, then a 70-day break. The pre-break average is
		// 160/4 = 40 km, so this week's share is the only thing that differs.
		const preBreak = [71, 78, 85, 92];
		for (const daysAgo of preBreak) {
			await seedRun(steep.id, daysAgo, 40_000);
			await seedRun(easing.id, daysAgo, 40_000);
		}
		await seedRun(steep.id, 1, 36_000);
		await seedRun(easing.id, 1, 12_000);

		// The same break, but one run before it: nothing to call a base, so the
		// card must stay away rather than divide into a single session.
		await seedRun(baseless.id, 71, 40_000);
		await seedRun(baseless.id, 1, 36_000);
	});

	test.afterAll(async () => {
		await deleteSagaUsers([steep, easing, baseless].filter(Boolean));
	});

	test('a big first week back is called out, and the ratio card stays away', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: steep.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			await expect(page.getByTestId('comeback')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('comeback-verdict')).toHaveText(/first week/i);
			// 36 / 40 = 90 %.
			await expect(page.getByTestId('comeback-share')).toContainText('90');
			await expect(page.getByTestId('comeback-layoff')).toContainText('10');
			await expect(page.getByTestId('comeback-meaning')).not.toBeEmpty();
			await expect(page.getByTestId('load-ramp')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});

	test('a gentle first week back is confirmed as easing in', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: easing.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			await expect(page.getByTestId('comeback')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('comeback-verdict')).toHaveText(/easing/i);
			// 12 / 40 = 30 %.
			await expect(page.getByTestId('comeback-share')).toContainText('30');
		} finally {
			await ctx.close();
		}
	});

	test('a comeback with no real pre-break base shows no card', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: baseless.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			await page.waitForLoadState('networkidle');
			await expect(page.getByTestId('comeback')).toHaveCount(0);
			await expect(page.getByTestId('load-ramp')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
