import { expect, test } from '@playwright/test';

import { deleteRun, insertRun, setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Cross-cutting: user-setting → propagation across multiple surfaces.
 *
 * The unit-pref round-trip (`tests-e2e/settings/unit-pref-round-trip.spec.ts`)
 * covers the headline propagation path. This spec covers the OTHER
 * load-bearing settings where the failure mode is "setting flipped
 * but downstream surface kept rendering with the old value" —
 * specifically the settings that drive derived computations on the
 * run-detail page:
 *
 *   - `hr_zones` — the 5-number cutoff array. Same per-point bpm
 *     samples bucket into DIFFERENT zones depending on the cutoffs.
 *     A user who sets their max-HR-keyed zones lower (e.g. an older
 *     runner with HRmax=170) must see the run-detail zone bar
 *     re-bucket their samples into the new zones. Headline failure:
 *     the page caches the default cutoffs forever.
 *   - `body_weight_kg` — drives the calorie estimate. A 70 kg runner
 *     who updates their weight to 90 kg must see the calorie number
 *     scale up by ~28% on every run, retrospectively.
 *
 * Each test plants a known-shape run, flips the setting via service-
 * role (no UI dance — faster + more reliable than driving the
 * settings page UI), navigates to /runs/[id], and asserts the
 * downstream surface reflects the new value. Both directions are
 * walked so a half-baked propagation path (works low → high but not
 * high → low) fails loud.
 */

// ───────────────────── hr_zones → run-detail HR Zones ─────────────────────

test.describe('Settings propagation: hr_zones → /runs/[id] HR Zones', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string;

	test.beforeAll(async () => {
		// Plant a run with a track that carries per-point bpm samples
		// spanning the zone ladder. The default cutoffs are
		// [114, 133, 152, 171, 190], so samples at 100 / 125 / 145 /
		// 165 fall in Z1 / Z2 / Z3 / Z4 respectively (one sample each,
		// no Z5). With a lower hr_zones config those same samples
		// shift up the ladder; with a higher one they shift down.
		//
		// The samples carry `ts`, so the page takes its TIME-WEIGHTED
		// branch -- the one a real recorder always reaches. Each sample
		// weighs half the gap behind it plus half the gap ahead, each half
		// capped at 30 s, so four samples 60 s apart weigh 30 / 60 / 60 /
		// 30 seconds: 17 / 33 / 33 / 17 percent. The first and last carry
		// half because nothing precedes or follows them -- that is the
		// shape of the real computation, not an artefact of the fixture.
		// The field was `t` until decisions § 1404, a key the app never
		// reads, so this track reached the count fallback instead and
		// every figure below was a flat 25 %.
		const baseLat = -37.8136;
		const baseLng = 144.9631;
		const tBase = new Date('2026-04-15T08:00:00Z').getTime();
		const bpmSamples = [100, 125, 145, 165];
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-04-15T08:00:00Z',
			duration_s: 600,
			distance_m: 1_000,
			is_public: false,
			metadata: { activity_type: 'run', avg_bpm: 134 },
			track: bpmSamples.map((bpm, i) => ({
				lat: baseLat + i * 0.0001,
				lng: baseLng + i * 0.0001,
				ts: new Date(tBase + i * 60_000).toISOString(),
				bpm,
			})),
		});
	});

	test.afterAll(async () => {
		await deleteRun(runId).catch(() => {});
		// Clear the hr_zones key — leaving custom cutoffs would
		// pollute other specs.
		await setUserSetting(USER_A.id, 'hr_zones', null);
	});

	test('default hr_zones (unset): samples bucket across Z2/Z3/Z4 evenly', async ({
		page,
	}) => {
		// No hr_zones set in user_settings → page uses default
		// [114, 133, 152, 171, 190].
		// 100 → ≤114 → Z1; 125 → ≤133 → Z2; 145 → ≤152 → Z3; 165 → ≤171 → Z4,
		// one sample each, weighing 30 / 60 / 60 / 30 s → 17 / 33 / 33 / 17 / 0.
		await setUserSetting(USER_A.id, 'hr_zones', null);
		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { name: 'Heart Rate Zones' }))
			.toBeVisible({ timeout: 10_000 });

		// Pin the distribution by reading each zone's legend percentage.
		const pcts = page.locator('.hr-legend .hr-zone-pct');
		await expect(pcts).toHaveCount(5);
		// Whole strings, not `toContainText`: '30%' contains '0', so an
		// empty-zone assertion written that way is satisfied by a third of
		// the run.
		await expect(pcts.nth(0)).toHaveText('17%');
		await expect(pcts.nth(1)).toHaveText('33%');
		await expect(pcts.nth(2)).toHaveText('33%');
		await expect(pcts.nth(3)).toHaveText('17%');
		await expect(pcts.nth(4)).toHaveText('0%');
	});

	test('custom hr_zones (lower cutoffs): same samples shift to higher zones', async ({
		page,
	}) => {
		// cutoffs = [90, 110, 130, 150, 170] puts every sample one rung
		// higher: 100 > 90 → Z2; 125 > 110 → Z3; 145 > 130 → Z4;
		// 165 > 150 → Z5. The ladder shifts and the weights come with it,
		// so the distribution is 0 / 17 / 33 / 33 / 17.
		await setUserSetting(USER_A.id, 'hr_zones', {
			z1: 90,
			z2: 110,
			z3: 130,
			z4: 150,
			z5: 170,
		});
		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { name: 'Heart Rate Zones' }))
			.toBeVisible({ timeout: 10_000 });

		const pcts = page.locator('.hr-legend .hr-zone-pct');
		await expect(pcts).toHaveCount(5);
		await expect(pcts.nth(0)).toHaveText('0%');
		await expect(pcts.nth(1)).toHaveText('17%');
		await expect(pcts.nth(2)).toHaveText('33%');
		await expect(pcts.nth(3)).toHaveText('33%');
		await expect(pcts.nth(4)).toHaveText('17%');
	});

	test('custom hr_zones (higher cutoffs): same samples shift to lower zones', async ({
		page,
	}) => {
		// cutoffs = [140, 160, 180, 200, 220]
		// 100 ≤140 → Z1; 125 ≤140 → Z1; 145 >140, ≤160 → Z2;
		// 165 >160, ≤180 → Z3. Z1 now holds the first two samples, 30 + 60
		// of the 180 s total → 50 / 33 / 17 / 0 / 0.
		await setUserSetting(USER_A.id, 'hr_zones', {
			z1: 140,
			z2: 160,
			z3: 180,
			z4: 200,
			z5: 220,
		});
		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { name: 'Heart Rate Zones' }))
			.toBeVisible({ timeout: 10_000 });

		const pcts = page.locator('.hr-legend .hr-zone-pct');
		await expect(pcts).toHaveCount(5);
		await expect(pcts.nth(0)).toHaveText('50%');
		await expect(pcts.nth(1)).toHaveText('33%');
		await expect(pcts.nth(2)).toHaveText('17%');
		await expect(pcts.nth(3)).toHaveText('0%');
		await expect(pcts.nth(4)).toHaveText('0%');
	});

	test('round-trip: lower → higher → unset returns to defaults', async ({
		page,
	}) => {
		// Walk a full cycle to catch a regression that caches the
		// settings fetch and never re-reads on subsequent navigations.
		// Each navigation should re-fetch settings on mount and apply
		// the current cutoffs.

		// Phase 1: lower.
		await setUserSetting(USER_A.id, 'hr_zones', {
			z1: 90,
			z2: 110,
			z3: 130,
			z4: 150,
			z5: 170,
		});
		await page.goto(`/runs/${runId}`);
		const pcts = page.locator('.hr-legend .hr-zone-pct');
		await expect(pcts.first()).toBeVisible({ timeout: 10_000 });
		await expect(pcts.nth(0)).toHaveText('0%'); // Z1 empty

		// Phase 2: higher.
		await setUserSetting(USER_A.id, 'hr_zones', {
			z1: 140,
			z2: 160,
			z3: 180,
			z4: 200,
			z5: 220,
		});
		await page.goto(`/runs/${runId}`);
		await expect(pcts.first()).toBeVisible({ timeout: 10_000 });
		await expect(pcts.nth(0)).toHaveText('50%'); // Z1 dominates

		// Phase 3: unset → defaults.
		await setUserSetting(USER_A.id, 'hr_zones', null);
		await page.goto(`/runs/${runId}`);
		await expect(pcts.first()).toBeVisible({ timeout: 10_000 });
		await expect(pcts.nth(0)).toHaveText('17%'); // back to defaults
	});
});

// ───────────────────── body_weight_kg → run-detail Calories ─────────────────────

test.describe('Settings propagation: body_weight_kg → /runs/[id] Calories', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string;

	test.beforeAll(async () => {
		// 5 km run — easy multiplication. estimatedCalories =
		// round(bodyWeightKg × 1.0 × 5_000 / 1000) = round(weight × 5).
		// At 70 kg: 350 kcal. At 90 kg: 450. At 50 kg: 250.
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-04-16T08:00:00Z',
			duration_s: 1800,
			distance_m: 5_000,
			is_public: false,
			metadata: { activity_type: 'run' },
		});
	});

	test.afterAll(async () => {
		await deleteRun(runId).catch(() => {});
		await setUserSetting(USER_A.id, 'body_weight_kg', null);
	});

	test('body_weight_kg=70 → Calories shows 350 for a 5km run', async ({
		page,
	}) => {
		await setUserSetting(USER_A.id, 'body_weight_kg', 70);
		await page.goto(`/runs/${runId}`);
		const cal = page
			.locator('.key-stat', { hasText: 'Calories' })
			.locator('.key-stat-value');
		await expect(cal).toHaveText('350', { timeout: 10_000 });
	});

	test('body_weight_kg=90 → Calories scales up to 450 (same run)', async ({
		page,
	}) => {
		// Headline regression net: SAME run, different setting, must
		// re-render the calorie value. A cache that holds the 70-kg
		// value across page mounts would fail here.
		await setUserSetting(USER_A.id, 'body_weight_kg', 90);
		await page.goto(`/runs/${runId}`);
		const cal = page
			.locator('.key-stat', { hasText: 'Calories' })
			.locator('.key-stat-value');
		await expect(cal).toHaveText('450', { timeout: 10_000 });
	});

	test('body_weight_kg=50 → Calories scales down to 250', async ({
		page,
	}) => {
		await setUserSetting(USER_A.id, 'body_weight_kg', 50);
		await page.goto(`/runs/${runId}`);
		const cal = page
			.locator('.key-stat', { hasText: 'Calories' })
			.locator('.key-stat-value');
		await expect(cal).toHaveText('250', { timeout: 10_000 });
	});

	test('body_weight_kg unset: Calories pill renders the 70-kg fallback with an "(est)" label', async ({
		page,
	}) => {
		// Commit 9bf25fd flipped the unset behaviour from "hide the
		// pill" to "show the pill with a 70-kg fallback + an `(est)`
		// suffix on the label" so the key-stats grid never has an
		// empty cell. Pin the new contract: 70 kg × 5 km ≈ 350 kcal,
		// label reads "Calories kcal (est)".
		await setUserSetting(USER_A.id, 'body_weight_kg', null);
		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { level: 1 }))
			.toBeVisible({ timeout: 10_000 });
		const calRow = page.locator('.key-stat', { hasText: 'Calories' });
		await expect(calRow).toHaveCount(1);
		await expect(calRow.locator('.key-stat-value')).toHaveText('350');
		await expect(calRow.locator('.key-stat-label')).toContainText('(est)');
	});

	test('round-trip: 70 → 90 → unset → 70 each lands the documented value', async ({
		page,
	}) => {
		const cal = page
			.locator('.key-stat', { hasText: 'Calories' })
			.locator('.key-stat-value');
		const calRow = page.locator('.key-stat', { hasText: 'Calories' });
		const calLabel = page
			.locator('.key-stat', { hasText: 'Calories' })
			.locator('.key-stat-label');

		// 70 → 350, label is plain (no `(est)` suffix when set).
		await setUserSetting(USER_A.id, 'body_weight_kg', 70);
		await page.goto(`/runs/${runId}`);
		await expect(cal).toHaveText('350', { timeout: 10_000 });
		await expect(calLabel).not.toContainText('(est)');

		// 90 → 450 (still no `(est)` suffix — value is real).
		await setUserSetting(USER_A.id, 'body_weight_kg', 90);
		await page.goto(`/runs/${runId}`);
		await expect(cal).toHaveText('450', { timeout: 10_000 });
		await expect(calLabel).not.toContainText('(est)');

		// unset → pill keeps rendering with the 70-kg fallback + the
		// `(est)` label (post-9bf25fd contract; previously the pill
		// hid).
		await setUserSetting(USER_A.id, 'body_weight_kg', null);
		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { level: 1 }))
			.toBeVisible({ timeout: 10_000 });
		await expect(calRow).toHaveCount(1);
		await expect(cal).toHaveText('350');
		await expect(calLabel).toContainText('(est)');

		// back to 70 → 350, label drops the `(est)` suffix again.
		await setUserSetting(USER_A.id, 'body_weight_kg', 70);
		await page.goto(`/runs/${runId}`);
		await expect(cal).toHaveText('350', { timeout: 10_000 });
		await expect(calLabel).not.toContainText('(est)');
	});
});
