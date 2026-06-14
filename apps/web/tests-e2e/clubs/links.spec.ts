import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteClub } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug] — admin edits the club's website + social links
 * (migration 20270131_001). The link row renders with
 * rel="noopener noreferrer", and a non-http(s) URL is rejected by
 * normaliseClubLink before it can reach the row (XSS gate).
 */

async function insertOwnedClub(): Promise<{ id: string; slug: string }> {
	const admin = getAdminClient();
	const id = crypto.randomUUID();
	const slug = `e2e-links-${id.slice(0, 8)}`;
	const { error } = await admin.from('clubs').insert({
		id,
		owner_id: USER_A.id,
		name: 'E2E Links Club',
		slug,
		is_public: true
	});
	if (error) throw new Error(`insertOwnedClub failed: ${error.message}`);
	return { id, slug };
}

test.describe('/clubs/[slug] — club links', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let clubId: string | null = null;

	test.afterEach(async () => {
		if (clubId) {
			try {
				await deleteClub(clubId);
			} catch (_) {
				/* best-effort */
			}
			clubId = null;
		}
	});

	test('admin adds links; safe links render, javascript: is dropped', async ({ page }) => {
		const club = await insertOwnedClub();
		clubId = club.id;

		await page.goto(`/clubs/${club.slug}`);
		await page.getByRole('button', { name: 'Edit club' }).click();

		await page.getByLabel('Website').fill('https://example.com');
		// A javascript: URL must be dropped, not stored.
		await page.getByLabel('Instagram').fill('javascript:alert(1)');
		await page.getByRole('button', { name: 'Save changes' }).click();

		// The website link renders with hardened rel + a new tab target.
		const website = page.getByRole('link', { name: 'Visit our website' });
		await expect(website).toBeVisible();
		await expect(website).toHaveAttribute('href', 'https://example.com');
		await expect(website).toHaveAttribute('rel', /noopener/);
		await expect(website).toHaveAttribute('target', '_blank');

		// The javascript: instagram link was rejected — no Instagram anchor.
		await expect(page.getByRole('link', { name: 'Instagram' })).toHaveCount(0);

		// And it never reached the database.
		const { data } = await getAdminClient()
			.from('clubs')
			.select('instagram_url, website_url')
			.eq('id', club.id)
			.single();
		expect(data?.website_url).toBe('https://example.com');
		expect(data?.instagram_url).toBeNull();
	});
});
