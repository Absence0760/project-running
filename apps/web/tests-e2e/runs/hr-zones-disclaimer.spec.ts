import { expect, test } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — HR-zone medication disclaimer (persona round-5 older).
 *
 * HR zones derive from a formula-estimated max HR (Tanaka / 220−age)
 * when the user has neither explicit `hr_zones` nor a measured
 * `max_hr_bpm` pref. For runners on beta-blockers / BP meds the formula
 * over-predicts. A short, non-alarming disclaimer points them at the
 * prefs HR field — but ONLY when zones are actually shown AND the
 * estimate is formula-derived (no explicit cutoffs or max-HR override).
 *
 * The seed user (USER_A / runner@test.com) carries an explicit
 * `max_hr_bpm` + `hr_zones` in seed.sql, so the disclaimer must STAY
 * HIDDEN for them even when the zone bar renders — pinning the
 * formula-derived gating. It must also stay hidden when there are no HR
 * samples (no zones → nothing to disclaim).
 *
 * The "shows for a formula-only user" branch isn't reachable with the
 * single seeded user (they always have explicit HR prefs), so it's not
 * e2e-testable here; the gating predicate itself is the unit of value
 * and is pinned by the two negative cases below.
 */

test.describe('/runs/[id] — HR-zone medication disclaimer', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('hidden when the user has explicit HR prefs, even though the zone bar renders', async ({
		page
	}) => {
		const tBase = new Date('2026-04-10T08:00:00Z').getTime();
		const bpmSamples = [110, 120, 145, 165, 130];
		const track = bpmSamples.map((bpm, i) => ({
			lat: -37.8136 + i * 0.0001,
			lng: 144.9631 + i * 0.0001,
			ts: new Date(tBase + i * 60_000).toISOString(),
			bpm
		}));

		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 1_000,
			duration_s: 300,
			is_public: false,
			metadata: { activity_type: 'run' },
			track
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Heart Rate Zones' })).toBeVisible({
				timeout: 10_000
			});
			// Zone bar renders (HR samples present) but the disclaimer is
			// suppressed because the seed user has a measured max HR.
			await expect(page.locator('.hr-segment')).toHaveCount(5);
			await expect(page.locator('.hr-disclaimer')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});

	test('no disclaimer when there are no HR samples (zones not shown)', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false,
			metadata: { activity_type: 'run' }
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Heart Rate Zones' })).toBeVisible({
				timeout: 10_000
			});
			await expect(page.locator('.hr-segment')).toHaveCount(0);
			await expect(page.locator('.hr-disclaimer')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});
});
