import { expect, test } from '@playwright/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Multi-distance race-time predictor card on /dashboard (backlog #11).
 *
 * The card projects the 5K / 10K / Half / Marathon ladder from the runner's
 * recency-weighted qualifying efforts (pure logic in
 * lib/training/race_predictor.ts, unit-tested separately). This e2e pins the
 * SURFACE: a runner with a recent qualifying 10K sees a four-row ladder, the
 * 10K rung's predicted time matches the planted effort, and the marathon rung
 * is flagged Low confidence (a 4.2x Riegel extrapolation past the far-factor
 * cap). It also pins the self-hide contract: a runner with no qualifying run
 * never sees the card.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('dashboard race-time predictor', () => {
	let runner: SagaUser;
	let empty: SagaUser;

	test.beforeAll(async () => {
		[runner, empty] = await createSagaUsers(2, {
			displayNames: ['Predictor Runner', 'No-Qualifying Runner'],
		});

		// A clean recent 10K in 40:00 (4:00/km) — squarely qualifying
		// (>= 1.5 km, app source, not indoor), two days old so it's recent.
		await insertRun({
			user_id: runner.id,
			started_at: new Date(Date.now() - 2 * 86_400_000).toISOString(),
			distance_m: 10_000,
			duration_s: 2_400,
			source: 'app',
		});
		// A second qualifying effort so the pool size is plausible.
		await insertRun({
			user_id: runner.id,
			started_at: new Date(Date.now() - 5 * 86_400_000).toISOString(),
			distance_m: 6_000,
			duration_s: 1_500,
			source: 'app',
		});

		// The "empty" runner only logs a sub-1.5 km treadmill shuffle —
		// never a qualifying effort, so the card must stay hidden.
		await insertRun({
			user_id: empty.id,
			started_at: new Date(Date.now() - 1 * 86_400_000).toISOString(),
			distance_m: 800,
			duration_s: 300,
			source: 'app',
			metadata: { indoor: true },
		});
	});

	test.afterAll(async () => {
		await deleteSagaUsers([runner, empty].filter(Boolean));
	});

	test('renders the four-rung ladder with a matching 10K time and a low-confidence marathon', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');

			const card = page.getByTestId('race-predictor');
			await expect(card).toBeVisible({ timeout: 15_000 });

			// Four rungs: 5K, 10K, Half, Marathon.
			const rows = card.locator('table.ladder tbody tr');
			await expect(rows).toHaveCount(4);

			// The 10K rung is anchored on the planted 40:00 10K — Riegel
			// at the same distance is the time itself, so it reads 40:00.
			const tenKRow = rows.filter({ has: page.locator('td.dist', { hasText: '10' }) });
			await expect(tenKRow.locator('td.time')).toHaveText('40:00');

			// The marathon rung is a 4.2x extrapolation past the far-factor
			// cap → Low confidence chip.
			const marathonRow = rows.last();
			await expect(marathonRow.locator('.confidence-chip')).toHaveClass(/conf-low/);
		} finally {
			await ctx.close();
		}
	});

	test('hides the card for a runner with no qualifying effort', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: empty.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			// Wait for the dashboard body to settle, then assert the card is absent.
			await page.waitForLoadState('networkidle');
			await expect(page.getByTestId('race-predictor')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
