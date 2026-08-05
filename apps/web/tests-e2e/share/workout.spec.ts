import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /share/workout/[id] — public gym-workout share page (anon + authed).
 *
 * A public workout is readable logged-out (the "gym_workouts owner or
 * public read" RLS gates the anon read on is_public), so this page works
 * for a signed-out viewer. A private workout 404s. No notes / RPE are
 * fetched, so nothing private leaks past what the owner made public.
 */

test.describe('/share/workout/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	let publicWorkoutId: string | null = null;
	let privateWorkoutId: string | null = null;
	const stamp = Date.now();
	const title = `E2E Share lift ${stamp}`;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data: pub, error } = await admin
			.from('gym_workouts')
			.insert({
				user_id: USER_A.id,
				title,
				started_at: new Date().toISOString(),
				is_public: true
			})
			.select('id')
			.single();
		if (error) throw error;
		publicWorkoutId = (pub as { id: string }).id;
		await admin.from('gym_sets').insert([
			{ workout_id: publicWorkoutId, set_index: 0, exercise_name: 'Squat', reps: 5, weight_kg: 100 }
		]);

		const { data: priv } = await admin
			.from('gym_workouts')
			.insert({
				user_id: USER_A.id,
				title: `${title} (private)`,
				started_at: new Date().toISOString(),
				is_public: false
			})
			.select('id')
			.single();
		privateWorkoutId = (priv as { id: string }).id;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		for (const id of [publicWorkoutId, privateWorkoutId]) {
			if (id) await admin.from('gym_workouts').delete().eq('id', id);
		}
	});

	test('anon viewer sees the public workout + sign-up CTA', async ({ page }) => {
		await page.goto(`/share/workout/${publicWorkoutId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		// The logged set surfaces (Squat block + the 100 kg / 5 reps set).
		await expect(page.getByRole('heading', { name: 'Squat' })).toBeVisible();
		await expect(page.locator('.set-val').first()).toContainText('100');
		// Anon visitors get the sign-up CTA.
		await expect(
			page.locator('a[href="/login?signup=1"]')
		).toBeVisible({ timeout: 5_000 });
	});

	test('private workout 404s to the not-found state', async ({ page }) => {
		await page.goto(`/share/workout/${privateWorkoutId}`);
		await expect(page.getByText('Workout not found.')).toBeVisible({ timeout: 10_000 });
		// No exercise blocks for a hidden workout.
		await expect(page.locator('.exercise-block')).toHaveCount(0);
	});

	test('the public workout head carries the canonical, OG tags, and JSON-LD', async ({
		page
	}) => {
		await page.goto(`/share/workout/${publicWorkoutId}`);
		await expect(page).toHaveTitle(`${title} — Threkir`);
		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			new RegExp(`/share/workout/${publicWorkoutId}$`)
		);
		await expect(page.locator('meta[property="og:title"]')).toHaveAttribute(
			'content',
			`${title} — Threkir`
		);
		// Counts only, in canonical kg — never the owner's notes or per-set RPE,
		// and never the viewer's preferred weight unit.
		const desc = await page
			.locator('meta[property="og:description"]')
			.getAttribute('content');
		expect(desc).toContain('1 exercise');
		expect(desc).toContain('1 set');
		// volume_kg is the trigger-maintained reps × load total: 5 × 100.
		expect(desc).toContain('500 kg lifted');
		expect(desc).not.toMatch(/\blb\b/);

		const ld = await page.locator('script[type="application/ld+json"]').first().textContent();
		const obj = JSON.parse(ld as string);
		expect(obj['@type']).toBe('WebPage');
		expect(obj.name).toBe(title);
		expect(obj.breadcrumb['@type']).toBe('BreadcrumbList');
	});

	// Deterministic without a seeded workout: a crawler on a stale link must
	// still get a valid head, never the app shell's generic one.
	test('unknown id still renders a valid SEO head', async ({ page }) => {
		await page.goto('/share/workout/00000000-0000-0000-0000-000000000000');
		await expect(page).toHaveTitle('Workout — Threkir');
		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			/\/share\/workout\/00000000-0000-0000-0000-000000000000$/
		);
		const ld = await page.locator('script[type="application/ld+json"]').first().textContent();
		expect(JSON.parse(ld as string)['@type']).toBe('WebPage');
	});
});
