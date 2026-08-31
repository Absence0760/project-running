import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /runs/[id] — the guided-run attribution chip.
 *
 * The recorder stamps `runs.metadata.guided_run_id` with the library slug of
 * the scripted coach workout a run was recorded under (decisions § 802). The
 * chip is the read surface: it resolves the slug against `guidedRunLibrary`
 * and links to the preview page the library already has at `/guided/[id]`.
 *
 * Three things are pinned here that a unit test cannot see:
 *   1. absence self-hides — the overwhelmingly common case;
 *   2. a slug the shipped library no longer carries still claims the run was
 *      guided, without naming it, without linking, and without ever putting
 *      the raw slug in front of a reader;
 *   3. a non-owner reading the same public run sees no chip. The key is
 *      owner-only (`20270627000001` strips it from `public_runs`) and the
 *      chip lives in the owner branch of the template, which a non-owner
 *      never enters.
 */

const DISTANCE_M = 5200;
const DURATION_S = 1800;

async function stampGuidedRun(runId: string, value: unknown): Promise<void> {
	const admin = getAdminClient();
	const { error } = await admin
		.from('runs')
		.update({ metadata: { activity_type: 'run', guided_run_id: value } })
		.eq('id', runId);
	if (error) throw new Error(`stamp failed: ${error.message}`);
}

test.describe('/runs/[id] — guided-run attribution', () => {
	let runId: string | null = null;

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
	});

	test.describe('owner', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('chip is hidden when the run carries no guided_run_id', async ({ page }) => {
			runId = await insertRun({
				user_id: USER_A.id,
				distance_m: DISTANCE_M,
				duration_s: DURATION_S,
				is_public: false
			});
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('guided-run-chip')).toHaveCount(0);
		});

		test('a known slug names the guided run and links to its preview page', async ({ page }) => {
			runId = await insertRun({
				user_id: USER_A.id,
				distance_m: DISTANCE_M,
				duration_s: DURATION_S,
				is_public: false
			});
			await stampGuidedRun(runId, 'easy-30');

			await page.goto(`/runs/${runId}`);
			const chip = page.getByTestId('guided-run-chip');
			await expect(chip).toBeVisible({ timeout: 15_000 });
			// The library title, not the slug.
			await expect(chip).toContainText('30-Minute Easy Run');
			await expect(chip).not.toContainText('easy-30');
			await expect(chip).toHaveAttribute('href', '/guided/easy-30');

			await chip.click();
			await expect(page).toHaveURL(/\/guided\/easy-30$/);
			await expect(page.getByRole('heading', { level: 1 })).toHaveText('30-Minute Easy Run');
		});

		test('an unknown slug degrades to an unnamed, unlinked chip', async ({ page }) => {
			// The library is versioned in code, so a run recorded under a
			// workout a later build dropped resolves to null. Hiding the chip
			// would present that run as a silent one.
			runId = await insertRun({
				user_id: USER_A.id,
				distance_m: DISTANCE_M,
				duration_s: DURATION_S,
				is_public: false
			});
			await stampGuidedRun(runId, 'retired-workout-99');

			await page.goto(`/runs/${runId}`);
			const chip = page.getByTestId('guided-run-chip');
			await expect(chip).toBeVisible({ timeout: 15_000 });
			// `toContainText` rather than `toHaveText`: the chip's leading
			// <span class="material-symbols"> carries the ligature name as text.
			await expect(chip).toContainText('Guided run');
			await expect(chip).not.toContainText('retired-workout-99');
			// Not a link — /guided/retired-workout-99 is the library's own
			// "unknown guided run" dead end.
			await expect(page.locator('a[data-testid="guided-run-chip"]')).toHaveCount(0);
		});

		test('a non-string guided_run_id self-hides rather than rendering', async ({ page }) => {
			// `runs.metadata` is a schemaless jsonb bag: nothing at the database
			// level stops a number landing on the key.
			runId = await insertRun({
				user_id: USER_A.id,
				distance_m: DISTANCE_M,
				duration_s: DURATION_S,
				is_public: false
			});
			await stampGuidedRun(runId, 3);

			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('guided-run-chip')).toHaveCount(0);
		});
	});

	test.describe('non-owner', () => {
		test.use({ storageState: USER_B.storageStatePath });

		test('a public run carrying the key shows no chip to another runner', async ({ page }) => {
			// The non-owner branch mounts RunShareView, whose track comes
			// through the clip-public-track Edge Function; stub it so the spec
			// doesn't depend on a planted Storage blob.
			await page.route('**/functions/v1/clip-public-track', (route) =>
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ points: [] })
				})
			);
			runId = await insertRun({
				user_id: USER_A.id,
				distance_m: DISTANCE_M,
				duration_s: DURATION_S,
				is_public: true
			});
			await stampGuidedRun(runId, 'easy-30');

			await page.goto(`/runs/${runId}`);
			await expect(page.locator('.other-run')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('guided-run-chip')).toHaveCount(0);
			await expect(page.getByText('30-Minute Easy Run')).toHaveCount(0);
		});
	});
});
