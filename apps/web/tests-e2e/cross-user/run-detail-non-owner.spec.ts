import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';
import { readMaybeRow } from '../fixtures/db-read';

/**
 * /runs[id] — the NON-OWNER branch (issue #666).
 *
 * `fetchRunById` is owner-scoped (`.eq('user_id', userId)`) because it is
 * the only read path that downloads the UNCLIPPED GPS track. For a long
 * time that meant the canonical signed-in run surface rendered "Run not
 * found" for every run the viewer didn't own — including a PUBLIC run by
 * a runner they follow, which RLS would have let them read. Commenting on
 * someone else's run had no reachable surface but /share/run/[id], which
 * is why the cross-user comment + kudos specs all navigate there.
 *
 * The page now resolves entitlement through the `public_runs` view
 * (is_public = true) and mounts RunShareView for a non-owner, so the
 * signed-in path works and carries kudos + comments. What this spec pins:
 *
 *   1. alex opens runner's PUBLIC run at /runs/[id] → the run renders with
 *      attribution, and the comment composer is there (the capability the
 *      finding said had no surface).
 *   2. the comment alex posts through that composer lands in the DB with
 *      author = alex — the real path, not a /share/run detour.
 *   3. NO owner chrome renders: no visibility chip, no Edit, no Delete run.
 *      Those all live inside the owner branch of the template.
 *   4. a PRIVATE run by runner still lands on the not-found state for
 *      alex. Entitlement is the public_runs row, not merely "not mine".
 *
 * The clipped-track half of the contract (a non-owner track on THIS
 * surface must come through the clip-public-track Edge Function) is pinned
 * as SURFACE 5 of cross-cutting/privacy-zone-clipping-journey.spec.ts,
 * where the privacy-zone fixture already lives.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('/runs/[id] — non-owner branch', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let publicRunId: string | null = null;
	let privateRunId: string | null = null;

	test.beforeEach(async ({ page }) => {
		// The non-owner branch fetches its track through the EF; stub it so
		// the spec doesn't depend on a planted Storage blob (the clip itself
		// is pinned by the privacy-zone journey).
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);
	});

	test.afterEach(async () => {
		for (const id of [publicRunId, privateRunId]) {
			if (!id) continue;
			try {
				// run_comments → runs cascades on delete, so this sweeps the
				// comment the spec posted too.
				await deleteRun(id);
			} catch (_) {
				/* best-effort */
			}
		}
		publicRunId = null;
		privateRunId = null;
	});

	test('alex opens runners public run, sees attribution + no owner chrome, and comments', async ({
		page
	}) => {
		const title = uniqueText('E2E non-owner run');
		publicRunId = await insertRun({
			user_id: USER_A.id,
			distance_m: 8_000,
			duration_s: 2_400,
			is_public: true,
			metadata: { activity_type: 'run', title }
		});

		// The privacy invariant, asserted here as well as in the
		// privacy-zone journey: the non-owner branch must ask the
		// clip-public-track Edge Function for the track, never take the
		// owner's direct Storage download (decisions §33). The EF response
		// is stubbed above, but the REQUEST is the observable that proves
		// which path ran.
		const clipRequest = page.waitForRequest(
			(r) =>
				r.url().includes('/functions/v1/clip-public-track') && r.method() === 'POST',
			{ timeout: 15_000 }
		);

		await page.goto(`/runs/${publicRunId}`);
		expect(JSON.parse((await clipRequest).postData() ?? '{}')).toEqual({
			run_id: publicRunId
		});

		// The run renders — this is the assertion that used to fail.
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 15_000 });
		await expect(page.getByRole('heading', { name: 'Run not found' })).toHaveCount(0);

		// Attribution names the owner and links to their profile, so the
		// viewer knows whose run they are about to comment on.
		await expect(page.locator('.other-run-owner')).toBeVisible();
		await expect(page.locator(`.other-run a[href="/u/${USER_A.id}"]`)).toHaveCount(1);

		// Owner-only chrome must be absent. Each of these is rendered from
		// inside the `run` (owner) branch of the template.
		await expect(page.locator('.visibility-chip')).toHaveCount(0);
		await expect(page.getByRole('button', { name: 'Edit title and notes' })).toHaveCount(0);
		await expect(page.getByRole('button', { name: 'Delete run' })).toHaveCount(0);

		// The capability the finding was about: a comment composer on the
		// canonical surface for a run the viewer does not own.
		const composer = page.locator('form.composer textarea');
		await expect(composer).toBeVisible({ timeout: 15_000 });

		const body = uniqueText('e2e-non-owner-comment');
		await composer.fill(body);
		await page.locator('form.composer button[type="submit"]').click();
		await expect(composer).toHaveValue('', { timeout: 15_000 });
		await expect(page.locator('.comment p').first()).toHaveText(body);

		// Wire-level: the row exists with alex as author. Rules out a purely
		// optimistic render.
		const data = await readMaybeRow(
			'run_comments by run_id+body',
			getAdminClient()
				.from('run_comments')
				.select('author_id, body')
				.eq('run_id', publicRunId)
				.eq('body', body)
				.maybeSingle()
		);
		expect(data?.author_id).toBe(USER_B.id);
	});

	test('alex gives kudos to runners public run from /runs/[id]', async ({ page }) => {
		const title = uniqueText('E2E non-owner kudos run');
		publicRunId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true,
			metadata: { activity_type: 'run', title }
		});

		await page.goto(`/runs/${publicRunId}`);

		const kudosBtn = page.locator('.kudos-btn');
		await expect(kudosBtn).toBeVisible({ timeout: 15_000 });
		await expect(kudosBtn).not.toHaveClass(/given/);
		await kudosBtn.click();
		await expect(kudosBtn).toHaveClass(/given/);

		const data = await readMaybeRow(
			'run_kudos by run_id+user_id',
			getAdminClient()
				.from('run_kudos')
				.select('user_id')
				.eq('run_id', publicRunId)
				.eq('user_id', USER_B.id)
				.maybeSingle()
		);
		expect(data?.user_id).toBe(USER_B.id);
	});

	test('a PRIVATE run by runner still lands on the not-found state', async ({ page }) => {
		// Entitlement is the public_runs row, not "the viewer isn't the
		// owner". A regression that dropped the is_public gate — or that
		// widened the non-owner fetch to the base table — would render the
		// run here instead.
		privateRunId = await insertRun({
			user_id: USER_A.id,
			distance_m: 6_000,
			duration_s: 1_800,
			is_public: false,
			metadata: { activity_type: 'run', title: uniqueText('E2E private run') }
		});

		await page.goto(`/runs/${privateRunId}`);
		await expect(page.getByRole('heading', { name: 'Run not found' })).toBeVisible({
			timeout: 15_000
		});
		await expect(page.locator('.other-run-owner')).toHaveCount(0);
		await expect(page.locator('form.composer textarea')).toHaveCount(0);
	});
});
