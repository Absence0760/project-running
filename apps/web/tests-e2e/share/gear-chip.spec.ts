import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /share/run/[id] — read-only gear chip on the public share page.
 *
 * The `run_gear` RLS policy (migration 20260827_001) makes a run's gear
 * visible to anyone who can see the run, explicitly so the gear chip can
 * render on the public share surface. `RunShareView` mounts `RunGearChips`,
 * which degrades to read-only (chips, no edit button) for non-owners — so an
 * anonymous viewer should see WHICH shoe a public run was logged with, but
 * never the owner-only inventory fields (notes / target / retired_at, which
 * `fetchRunGear` doesn't even select).
 *
 * Set-up plants a public run owned by USER_A tagged with the seed Pegasus 40
 * shoe; the anon context then reads it. Cleanup drops the planted run
 * (cascades the run_gear link).
 */

const PEGASUS_GEAR_ID = '11111111-aaaa-bbbb-cccc-222222222201';

test.describe('/share/run/[id] — gear chip (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	let plantedRunId: string | null = null;

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});

		const admin = getAdminClient();
		const inserted = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date('2026-04-30T07:00:00Z').toISOString(),
				duration_s: 1800,
				distance_m: 6000,
				source: 'app' as const,
				is_public: true,
				metadata: { activity_type: 'run' },
			})
			.select('id')
			.single();
		expect(inserted.error).toBeNull();
		plantedRunId = inserted.data!.id as string;

		// auto_tag_default_gear may have already tagged the seed default
		// (Pegasus) onto the run; upsert is idempotent against the
		// unique(segment-less) run_gear pair so this is safe either way.
		const link = await admin
			.from('run_gear')
			.upsert(
				{ run_id: plantedRunId, gear_id: PEGASUS_GEAR_ID },
				{ onConflict: 'run_id,gear_id', ignoreDuplicates: true },
			);
		expect(link.error).toBeNull();
	});

	test.afterEach(async () => {
		if (plantedRunId) {
			await getAdminClient().from('runs').delete().eq('id', plantedRunId);
			plantedRunId = null;
		}
	});

	test('anon viewer sees the gear chip but no edit affordance', async ({ page }) => {
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] }),
			}),
		);

		await page.goto(`/share/run/${plantedRunId}`);

		// Anon read path works.
		await expect(page.locator('.run-meta')).toBeVisible({ timeout: 10_000 });

		// Positive: the Pegasus chip renders.
		await expect(page.locator('.gear-chip', { hasText: 'Pegasus 40' })).toBeVisible({
			timeout: 5_000,
		});

		// Negative: no owner-only edit button for an anon viewer (read-only).
		await expect(page.locator('.gear-strip .edit-btn')).toHaveCount(0);
	});
});
