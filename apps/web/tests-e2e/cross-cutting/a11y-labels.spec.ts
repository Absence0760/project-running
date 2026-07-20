import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { deleteRun, insertComment, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Accessible-name pins for icon-only controls surfaced by a UX-hunt round:
 *   - the shared Modal close button (was a hardcoded English aria-label)
 *   - the RouteExplorer clear-search button (was unlabelled)
 * Both must expose a localized accessible name so screen-reader users can
 * find them.
 */
test.describe('icon-only control accessible names', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the shared Modal close button has an accessible name', async ({ page }) => {
		await page.goto('/plans');
		await page.getByRole('button', { name: /New plan/ }).first().click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		// The close button is reachable by its accessible name ("Close").
		await expect(modal.getByRole('button', { name: 'Close' })).toBeVisible();
	});

	test('the RouteExplorer clear-search button has an accessible name', async ({ page }) => {
		await page.goto('/routes?tab=explore');
		const search = page.getByPlaceholder(/Search routes by name/);
		await expect(search).toBeVisible({ timeout: 10_000 });
		await search.fill('park');
		const clear = page.getByRole('button', { name: 'Clear search' });
		await expect(clear).toBeVisible();
		await clear.click();
		await expect(search).toHaveValue('');
	});
});

// 1×1 transparent PNG — smallest valid image the RunPhotos / RoutePhotos /
// ClubPhotos file inputs accept, so the pending caption input mounts.
const ONE_PIXEL_PNG = Buffer.from([
	0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
	0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
	0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
	0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
	0x42, 0x60, 0x82
]);

/**
 * Accessible-name pins for the reply / caption / search TEXT inputs that
 * had only a placeholder — WCAG 1.3.1 / 3.3.2 (F68), issue #386. A
 * placeholder is not a programmatic label: it is read as an ad-hoc name
 * that vanishes the instant the user types. Each input now carries a
 * localized aria-label, so getByRole('textbox', { name }) resolves it.
 */
test.describe('placeholder-only text inputs now expose accessible names', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('RouteExplorer search input has an accessible name', async ({ page }) => {
		await page.goto('/routes?tab=explore');
		const search = page.getByRole('textbox', { name: 'Search routes', exact: true });
		await expect(search).toBeVisible({ timeout: 10_000 });
		await expect(search).toHaveAttribute('placeholder', /Search routes by name/);
	});

	test('RouteBuilder place-search input has an accessible name', async ({ page }) => {
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('textbox', { name: 'Search for a place', exact: true })).toBeVisible({
			timeout: 10_000
		});
	});

	test('RunPhotos caption inputs (new + edit) have accessible names', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('button', { name: /Add photo/ })).toBeVisible({
				timeout: 10_000
			});

			// New-photo caption: revealed once a file is picked.
			await page.locator('input[type="file"]').setInputFiles({
				name: 'a11y.png',
				mimeType: 'image/png',
				buffer: ONE_PIXEL_PNG
			});
			await expect(page.getByRole('textbox', { name: 'Photo caption', exact: true })).toBeVisible({
				timeout: 10_000
			});

			// Edit caption: upload, then open the per-tile pencil.
			await page.getByRole('textbox', { name: 'Photo caption', exact: true }).fill('a11y caption');
			await page.getByRole('button', { name: 'Upload' }).click();
			const tile = page.locator('.tile').first();
			await expect(tile).toBeVisible({ timeout: 15_000 });
			await tile.getByRole('button', { name: 'Edit caption' }).click({ force: true });
			await expect(tile.getByRole('textbox', { name: 'Edit photo caption', exact: true })).toBeVisible({
				timeout: 5_000
			});
		} finally {
			await deleteRun(runId);
		}
	});

	test('RoutePhotos new-caption input has an accessible name', async ({ page }) => {
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await expect(page.getByRole('button', { name: /Add photo/ })).toBeVisible({
			timeout: 10_000
		});
		// Picking a file reveals the pending caption input (no row is written).
		await page.locator('input[type="file"]').setInputFiles({
			name: 'a11y-route.png',
			mimeType: 'image/png',
			buffer: ONE_PIXEL_PNG
		});
		await expect(page.getByRole('textbox', { name: 'Photo caption', exact: true })).toBeVisible({
			timeout: 10_000
		});
	});

	test('ClubPhotos new-caption input has an accessible name', async ({ page }) => {
		// USER_A (runner) owns Richmond Run Club → isMember → canUpload.
		await page.goto('/clubs/richmond-run-club?tab=photos');
		await expect(page.getByRole('button', { name: /Add photo/ })).toBeVisible({
			timeout: 10_000
		});
		await page.locator('input[type="file"]').setInputFiles({
			name: 'a11y-club.png',
			mimeType: 'image/png',
			buffer: ONE_PIXEL_PNG
		});
		await expect(page.getByRole('textbox', { name: 'Photo caption', exact: true })).toBeVisible({
			timeout: 10_000
		});
	});

	test('RunSocial reply input has an accessible name', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 4_000,
			duration_s: 1_200,
			is_public: true
		});
		try {
			await insertComment({
				run_id: runId,
				author_id: USER_A.id,
				body: `a11y-comment ${Date.now()}`
			});
			await page.goto(`/runs/${runId}`);
			const comment = page.locator('.comment').first();
			await expect(comment).toBeVisible({ timeout: 10_000 });
			await comment.getByRole('button', { name: 'Reply' }).click();
			await expect(comment.getByRole('textbox', { name: 'Reply to comment', exact: true })).toBeVisible({
				timeout: 5_000
			});
		} finally {
			await deleteRun(runId);
		}
	});

	test('club post reply input has an accessible name', async ({ page }) => {
		await page.goto('/clubs/richmond-run-club');
		const post = page.locator('article.post').filter({ hasText: /Big field expected/ }).first();
		await expect(post).toBeVisible({ timeout: 10_000 });
		await post.getByRole('button', { name: 'Reply' }).click();
		await expect(post.getByRole('textbox', { name: 'Reply to post', exact: true })).toBeVisible({
			timeout: 5_000
		});
	});
});
