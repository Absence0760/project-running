import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Unit-pref round-trip regression net.
 *
 * The unit preference (`user_settings.prefs.preferred_unit`) gates
 * how every stored run renders to the user. The expensive failure
 * mode is "newly-recorded runs render correctly but old ones don't"
 * — that would happen if a screen stored the distance string at
 * write-time instead of reading the live unit pref at render-time.
 * The cheaper failure mode is "switching the pref doesn't propagate
 * to already-displayed surfaces" — caught by the existing
 * preferences.spec.ts. This test covers a third axis the others
 * don't: that the SAME runs, viewed at different pref settings,
 * render in the right unit at every flip — i.e. that retrospective
 * display is unit-reactive.
 *
 * Two runs with deterministic distances are planted via service-
 * role, then the spec walks km → mi → km. At each step it verifies
 * BOTH runs (not just the most-recent) carry the expected unit
 * suffix AND the numerically-correct value. A regression that
 * converted only the newest run, OR that cached the formatted
 * string at insert time, fails here.
 */

// Two runs with round-number distances in each unit system. 5000 m
// is 5.00 km / 3.11 mi exactly; 10000 m is 10.00 km / 6.21 mi
// exactly. The /runs list renders via `formatDistance(metres)` →
// "5.00 km" / "3.11 mi" / "10.00 km" / "6.21 mi".
const RUN_A_METRES = 5000;
const RUN_B_METRES = 10000;
const RUN_A_KM_TEXT = '5.00 km';
const RUN_A_MI_TEXT = '3.11 mi';
const RUN_B_KM_TEXT = '10.00 km';
const RUN_B_MI_TEXT = '6.21 mi';

async function setPref(userId: string, value: 'km' | 'mi'): Promise<void> {
	// Stamp both surfaces the app reads: user_settings.prefs (the
	// canonical universal bag — what units.svelte.ts reads) AND
	// user_profiles.preferred_unit (legacy column the auth-store
	// also reads on sign-in to seed the signal). Keeping the two
	// in lockstep so the test isn't sensitive to which one a given
	// page checks.
	const admin = getAdminClient();
	const { data: existing } = await admin
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();
	const prefs = (existing?.prefs as Record<string, unknown> | null) ?? {};
	prefs['preferred_unit'] = value;
	if (existing) {
		await admin
			.from('user_settings')
			.update({ prefs, updated_at: new Date().toISOString() })
			.eq('user_id', userId);
	} else {
		await admin.from('user_settings').insert({ user_id: userId, prefs });
	}
	await admin
		.from('user_profiles')
		.update({ preferred_unit: value })
		.eq('id', userId);
}

test.describe('/runs — unit pref round-trip', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runIdA: string;
	let runIdB: string;

	test.beforeAll(async () => {
		// Plant two runs spanning the date window that /runs's default
		// "Date range" filter ("Today") would hide. The spec changes
		// the filter to "All time" so both surface. Distances chosen
		// so the formatted strings are deterministic (5.00 / 3.11 /
		// 10.00 / 6.21).
		runIdA = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-03-01T08:00:00.000Z',
			duration_s: 1500,
			distance_m: RUN_A_METRES,
			is_public: false,
		});
		runIdB = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-03-02T08:00:00.000Z',
			duration_s: 3000,
			distance_m: RUN_B_METRES,
			is_public: false,
		});
	});

	test.afterAll(async () => {
		await deleteRun(runIdA).catch(() => {});
		await deleteRun(runIdB).catch(() => {});
		// Reset pref so other specs see the default.
		await setPref(USER_A.id, 'km');
	});

	test('km → mi → km: both planted runs follow the pref on every flip', async ({
		page,
	}) => {
		// ── Step 1: pref = km, both runs show km ──────────────────
		await setPref(USER_A.id, 'km');
		await page.goto('/runs');
		await page.getByLabel('Date range').selectOption('all');

		const rowA = page.locator(`a[href="/runs/${runIdA}"]`);
		const rowB = page.locator(`a[href="/runs/${runIdB}"]`);
		await expect(rowA).toBeVisible({ timeout: 10_000 });
		await expect(rowB).toBeVisible({ timeout: 10_000 });

		// .run-stat-value renders formatDistance(metres). First .run-stat
		// inside each row is the Distance stat (Duration / Pace follow).
		const distA = rowA.locator('.run-stat-value').first();
		const distB = rowB.locator('.run-stat-value').first();
		await expect(distA).toHaveText(RUN_A_KM_TEXT);
		await expect(distB).toHaveText(RUN_B_KM_TEXT);
		// Negative shape — no "mi" leaks while in km mode.
		await expect(distA).not.toContainText('mi');
		await expect(distB).not.toContainText('mi');

		// ── Step 2: flip to mi, both runs re-render in mi ─────────
		// The flip happens server-side (service-role on user_settings +
		// user_profiles). A page reload re-fetches the auth store +
		// the unit-pref signal. This is the headline "retrospective
		// display" test — Run A was inserted at km-mode but viewed at
		// mi-mode must render in mi with the correct converted value.
		await setPref(USER_A.id, 'mi');
		await page.goto('/runs');
		await page.getByLabel('Date range').selectOption('all');
		await expect(rowA).toBeVisible({ timeout: 10_000 });
		await expect(rowB).toBeVisible();

		const distA_mi = rowA.locator('.run-stat-value').first();
		const distB_mi = rowB.locator('.run-stat-value').first();
		await expect(distA_mi).toHaveText(RUN_A_MI_TEXT);
		await expect(distB_mi).toHaveText(RUN_B_MI_TEXT);
		// Negative shape — no "km" remnant.
		await expect(distA_mi).not.toContainText(/\bkm\b/);
		await expect(distB_mi).not.toContainText(/\bkm\b/);

		// ── Step 3: also pin the run-DETAIL surface honours the flip
		// for an already-stored run ───────────────────────────────
		// /runs/[id] reads the same `formatDistance` so the row +
		// detail surfaces share the bug bait. Pin the .key-stat
		// distance value matches RUN_A_MI_TEXT.
		await page.goto(`/runs/${runIdA}`);
		const detailDist = page
			.locator('.key-stat', { hasText: 'Distance' })
			.locator('.key-stat-value');
		await expect(detailDist).toHaveText(RUN_A_MI_TEXT, { timeout: 10_000 });

		// ── Step 4: flip back to km, both runs revert ─────────────
		// The "revert" path is what catches a regression that cached
		// the converted string somewhere (in localStorage, in a
		// memoised derived, in a write-time format) — the runs would
		// stay stuck at mi values.
		await setPref(USER_A.id, 'km');
		await page.goto('/runs');
		await page.getByLabel('Date range').selectOption('all');
		await expect(rowA).toBeVisible({ timeout: 10_000 });

		await expect(rowA.locator('.run-stat-value').first()).toHaveText(
			RUN_A_KM_TEXT,
		);
		await expect(rowB.locator('.run-stat-value').first()).toHaveText(
			RUN_B_KM_TEXT,
		);

		// Detail page also reverts.
		await page.goto(`/runs/${runIdA}`);
		await expect(
			page
				.locator('.key-stat', { hasText: 'Distance' })
				.locator('.key-stat-value'),
		).toHaveText(RUN_A_KM_TEXT, { timeout: 10_000 });
	});
});
