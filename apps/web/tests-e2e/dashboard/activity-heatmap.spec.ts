import { expect, test } from '@playwright/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Activity heatmap card on /dashboard — 20 weeks of per-day volume.
 *
 * Mobile's dashboard has carried this grid for a while; the web component
 * existed since the i18n sweep but was never mounted on any route, so the
 * canonical surface was the one missing the feature. This e2e pins the SURFACE:
 * the card renders, the grid has a cell for a day the runner actually ran, and
 * that cell is filled from the shared `--heat-*` ramp rather than from the
 * hardcoded indigo the component used to carry. Bucketing + the intensity
 * scale are unit-tested in `calendar_heatmap.test.ts`; the ramp's contrast and
 * its lockstep with mobile's `ChartPalette.ramp` are pinned in
 * `contrast_guard.test.ts`.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

/// Local yyyy-mm-dd, matching the component's cell key (`formatISO`). A UTC
/// slice would name the wrong day for any runner east of Greenwich.
function localDay(d: Date): string {
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

test.describe('dashboard activity heatmap', () => {
	let runner: SagaUser;
	// Two days back, at local midday, so the cell is inside the 20-week window
	// and cannot drift across a day boundary while the spec runs.
	const runDay = new Date();
	runDay.setDate(runDay.getDate() - 2);
	runDay.setHours(12, 0, 0, 0);

	test.beforeAll(async () => {
		[runner] = await createSagaUsers(1, { displayNames: ['Heatmap Runner'] });
		await insertRun({
			user_id: runner.id,
			started_at: runDay.toISOString(),
			distance_m: 12_000,
			duration_s: 3_600,
			source: 'app',
		});
	});

	test.afterAll(async () => {
		await deleteSagaUsers([runner].filter(Boolean));
	});

	test('renders the grid and fills the run day from the shared heat ramp', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');

			const card = page.getByTestId('activity-heatmap');
			await expect(card).toBeVisible({ timeout: 15_000 });

			// The runner's only run is the window max, so its cell takes the
			// ramp's top step. Assert the token, not a hex — the whole point of
			// the change is that this cell no longer names a colour.
			const cell = card.locator(`rect[data-day="${localDay(runDay)}"]`);
			await expect(cell).toHaveAttribute('fill', 'var(--heat-3)');

			// A day with no run keeps the tonal fill plus the frame hairline,
			// which is what makes the grid readable in dark (where the fill
			// token is byte-identical to the card).
			const empty = card.locator('rect[stroke="var(--heat-0)"]');
			await expect(empty.first()).toBeVisible();
		} finally {
			await ctx.close();
		}
	});
});
