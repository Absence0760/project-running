import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/licenses — third-party-license attribution page. A static
 * list rendered from a hardcoded `deps` array in LicenseList.svelte;
 * this page is the project's notice of attribution for its OSS deps.
 *
 * Coverage:
 *  - every known dep renders a row + license badge,
 *  - the "View license" toggle expands a full-text block,
 *  - the page is auth-gated (settings layout is not anon-allowed).
 */

const KNOWN_DEPS: { name: string; license: string }[] = [
	{ name: 'SvelteKit', license: 'MIT' },
	{ name: 'Svelte', license: 'MIT' },
	{ name: '@supabase/supabase-js', license: 'MIT' },
	{ name: '@supabase/ssr', license: 'MIT' },
	{ name: 'MapLibre GL JS', license: 'BSD-3-Clause' },
	{ name: 'Anthropic SDK', license: 'MIT' },
	// Dual-licensed deps carry an explicit election on the public record
	// (audit/licenses 2026-07-02): JSZip is (MIT OR GPL-3.0-or-later) — MIT
	// elected; DOMPurify is (MPL-2.0 OR Apache-2.0) — Apache-2.0 elected.
	{ name: 'JSZip', license: 'MIT (elected)' },
	{ name: 'isomorphic-dompurify', license: 'MIT' },
	{ name: 'DOMPurify', license: 'Apache-2.0 (elected)' },
	{ name: '@sentry/sveltekit', license: 'MIT' },
	{ name: '@zip.js/zip.js', license: 'BSD-3-Clause' },
	{ name: 'fit-file-parser', license: 'MIT' },
	{ name: 'marked', license: 'MIT' },
	{ name: 'material-symbols', license: 'Apache-2.0' },
	// Ships no license metadata in the npm package; upstream mapbox/jsonlint
	// verified MIT — pinned so the row (and the verification note) can't drift.
	{ name: '@mapbox/jsonlint-lines-primitives', license: 'MIT (verified upstream)' },
	{ name: 'mdsvex', license: 'MIT' },
	{ name: 'normalize.css', license: 'MIT' },
	{ name: 'unplugin-icons', license: 'MIT' },
	{ name: '@iconify-json/material-symbols', license: 'Apache-2.0' },
	{ name: 'MapTiler tiles', license: 'Commercial (MapTiler Cloud)' },
	{ name: 'html-to-image', license: 'MIT' },
];

test.describe('/settings/licenses (signed-in)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('open-source license list mounts with framework + data-layer rows', async ({ page }) => {
		await page.goto('/settings/licenses');

		await expect(page.getByRole('heading', { level: 1, name: /Open-source licenses/ })).toBeVisible(
			{ timeout: 10_000 },
		);

		await expect(page.getByRole('link', { name: 'SvelteKit', exact: true })).toBeVisible();
		await expect(page.getByRole('link', { name: 'Svelte', exact: true })).toBeVisible();
		await expect(page.getByRole('link', { name: '@supabase/supabase-js' })).toBeVisible();

		await expect(page.getByRole('heading', { level: 2, name: 'Map data' })).toBeVisible();
	});

	test('every known dep renders a row with its license badge', async ({ page }) => {
		await page.goto('/settings/licenses');
		await expect(page.getByRole('heading', { level: 1, name: /Open-source licenses/ })).toBeVisible(
			{ timeout: 10_000 },
		);

		const list = page.locator('.lic-list');
		await expect(list).toBeVisible();

		for (const dep of KNOWN_DEPS) {
			const item = list.locator('li', { hasText: dep.name }).first();
			await expect(item).toBeVisible();
			await expect(item.locator('.lic-badge', { hasText: dep.license })).toBeVisible();
		}
	});

	test('clicking "View license" expands the full license text', async ({ page }) => {
		await page.goto('/settings/licenses');
		await expect(page.getByRole('heading', { level: 1, name: /Open-source licenses/ })).toBeVisible(
			{ timeout: 10_000 },
		);

		const svelteKitRow = page.locator('.lic-list li', { hasText: 'SvelteKit' }).first();
		const toggle = svelteKitRow.getByRole('button', { name: 'View license' });
		await expect(toggle).toBeVisible();

		// Pre-expand: no .lic-text rendered on the row.
		await expect(svelteKitRow.locator('.lic-text')).toHaveCount(0);

		await toggle.click();

		// Post-expand: button label flips + license text is visible.
		await expect(svelteKitRow.getByRole('button', { name: 'Hide license' })).toBeVisible();
		const text = svelteKitRow.locator('.lic-text');
		await expect(text).toBeVisible();
		await expect(text).toContainText(/MIT/i);

		// Toggle off — text disappears again.
		await svelteKitRow.getByRole('button', { name: 'Hide license' }).click();
		await expect(svelteKitRow.locator('.lic-text')).toHaveCount(0);
	});
});

test.describe('/settings/licenses (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor is redirected to /login', async ({ page }) => {
		await page.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});

		await page.goto('/settings/licenses');
		await expect(page).toHaveURL(/\/login/, { timeout: 10_000 });
	});
});
