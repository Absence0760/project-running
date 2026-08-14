import { expect, test } from '@playwright/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Training-load-ramp card on /dashboard.
 *
 * The acute:chronic workload ratio and its injury-risk band already drove the
 * coach roster; this card is the first time the runner it describes can see
 * it. Pure logic in lib/training/self_load.ts is unit-tested separately — this
 * pins the SURFACE: a runner whose week spikes over their own base sees the
 * high band, a runner holding steady sees the optimal one, and a runner with
 * too little history to divide by sees no card at all rather than a zeroed
 * ratio that would read as "safe".
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
	);
}

const DAY_MS = 86_400_000;

test.describe('dashboard training-load-ramp card', () => {
	let spiking: SagaUser;
	let steady: SagaUser;
	let thin: SagaUser;

	test.beforeAll(async () => {
		[spiking, steady, thin] = await createSagaUsers(3, {
			displayNames: ['Spiking Runner', 'Steady Runner', 'Thin History Runner'],
		});

		// A run in each of the four trailing 7-day windows clears the
		// active-weeks gate for both graded users; only the acute week differs.
		// 120 km against a 40 km base is a ratio of 2.0 — the chronic average
		// includes the acute week, so (120 + 3*40)/4 = 60.
		const base: [number, number][] = [
			[8, 40_000],
			[15, 40_000],
			[22, 40_000],
		];
		for (const [daysBack, distance] of [[1, 120_000] as [number, number], ...base]) {
			await insertRun({
				user_id: spiking.id,
				started_at: new Date(Date.now() - daysBack * DAY_MS).toISOString(),
				distance_m: distance,
				duration_s: Math.round((distance / 1000) * 300),
				source: 'app',
			});
		}
		for (const [daysBack, distance] of [[1, 40_000] as [number, number], ...base]) {
			await insertRun({
				user_id: steady.id,
				started_at: new Date(Date.now() - daysBack * DAY_MS).toISOString(),
				distance_m: distance,
				duration_s: Math.round((distance / 1000) * 300),
				source: 'app',
			});
		}

		// A single run in an otherwise empty month: exactly the shape that
		// would manufacture a terrifying ratio out of a runner who has barely
		// trained, so the card must stay away.
		await insertRun({
			user_id: thin.id,
			started_at: new Date(Date.now() - DAY_MS).toISOString(),
			distance_m: 30_000,
			duration_s: 9_000,
			source: 'app',
		});
	});

	test.afterAll(async () => {
		await deleteSagaUsers([spiking, steady, thin].filter(Boolean));
	});

	test('a spike week is shown as the high-risk band', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: spiking.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			const card = page.getByTestId('load-ramp');
			await expect(card).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('load-ramp-band')).toHaveText(/high/i);
			// 120 / 60 = 2.00.
			await expect(page.getByTestId('load-ramp-ratio')).toContainText('2');
			await expect(page.getByTestId('load-ramp-meaning')).not.toBeEmpty();
		} finally {
			await ctx.close();
		}
	});

	test('a steady month is shown as the optimal band', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: steady.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			await expect(page.getByTestId('load-ramp')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('load-ramp-band')).toHaveText(/optimal/i);
		} finally {
			await ctx.close();
		}
	});

	test('too little history shows no card rather than a zeroed ratio', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: thin.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			await page.waitForLoadState('networkidle');
			await expect(page.getByTestId('load-ramp')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
