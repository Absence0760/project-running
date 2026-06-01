import { expect, test } from '@playwright/test';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_B, USER_C_PRO } from '../fixtures/users';

// USER_B (alex) plays the coach; USER_C_PRO (morgan) plays the athlete.
const INVITE_TOKEN = 'e2ecoachinvitetoken000000000001';

async function clearLinks() {
	const admin = getAdminClient();
	await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
	await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
}

test.describe('/coaching/accept/[token] — athlete side', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.beforeEach(async () => {
		await clearLinks();
		await getAdminClient().from('coach_athletes').insert({
			coach_id: USER_B.id,
			status: 'pending',
			invite_token: INVITE_TOKEN
		});
	});

	test.afterEach(clearLinks);

	test('redeems the invite link and lands on /coaching with the coach listed', async ({ page }) => {
		await page.goto(`/coaching/accept/${INVITE_TOKEN}`);
		await page.waitForURL(/\/coaching$/, { timeout: 15_000 });
		await expect(page.getByRole('heading', { level: 1, name: 'Coaching' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.locator(`a[href="/u/${USER_B.id}"]`)).toBeVisible({ timeout: 10_000 });
	});

	test('an unknown token shows the invite-problem card, not a redirect', async ({ page }) => {
		await page.goto('/coaching/accept/deadbeefdeadbeefdeadbeefdeadbeef');
		await expect(page.getByRole('heading', { name: 'Invite problem' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page).toHaveURL(/\/coaching\/accept\//);
	});
});

test.describe('/coaching — coach side', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.afterEach(clearLinks);

	test('sees an active athlete on the roster and can remove them', async ({ page }) => {
		await clearLinks();
		await getAdminClient().from('coach_athletes').insert({
			coach_id: USER_B.id,
			athlete_id: USER_C_PRO.id,
			status: 'active',
			invite_token: INVITE_TOKEN,
			accepted_at: new Date().toISOString()
		});

		await page.goto('/coaching');
		await expect(page.getByRole('heading', { level: 1, name: 'Coaching' })).toBeVisible({
			timeout: 10_000
		});
		// The athlete row links to the coach review surface
		// (/coaching/athletes/[id]) — both the name and the Review button.
		const athleteLink = page.locator(`a[href="/coaching/athletes/${USER_C_PRO.id}"]`);
		await expect(athleteLink.first()).toBeVisible({ timeout: 10_000 });

		// removeAthlete() goes through a window.confirm() — accept it.
		page.on('dialog', (d) => d.accept());
		await page.getByRole('button', { name: 'Remove' }).first().click();
		await expect(athleteLink).toHaveCount(0, { timeout: 10_000 });
	});

	test('review surface shows an athlete private run the coach can read', async ({ page }) => {
		await clearLinks();
		await getAdminClient().from('coach_athletes').insert({
			coach_id: USER_B.id,
			athlete_id: USER_C_PRO.id,
			status: 'active',
			invite_token: INVITE_TOKEN,
			accepted_at: new Date().toISOString()
		});
		// A PRIVATE run owned by the athlete — the coach reads it via the
		// `active coach reads athlete runs` RLS policy (decisions § 98),
		// which is the whole point of this surface.
		const admin = getAdminClient();
		const runIns = await admin
			.from('runs')
			.insert({
				user_id: USER_C_PRO.id,
				started_at: new Date('2026-05-20T07:00:00Z').toISOString(),
				duration_s: 1800,
				distance_m: 6000,
				source: 'app' as const,
				is_public: false,
				metadata: { activity_type: 'run' }
			})
			.select('id')
			.single();

		try {
			await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
			await expect(
				page.getByRole('heading', { level: 2, name: 'Recent runs' })
			).toBeVisible({ timeout: 10_000 });
			await expect(
				page.getByRole('heading', { level: 2, name: 'Plan compliance' })
			).toBeVisible({ timeout: 10_000 });
			// The private run is listed, flagged as Private.
			await expect(page.getByText('Private').first()).toBeVisible({ timeout: 10_000 });
		} finally {
			if (runIns.data?.id) await admin.from('runs').delete().eq('id', runIns.data.id);
		}
	});

	test('review surface refuses an athlete who is not on the roster', async ({ page }) => {
		await clearLinks();
		await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
		await expect(
			page.getByRole('heading', { name: 'Not on your roster' })
		).toBeVisible({ timeout: 10_000 });
	});

	test('can mint a pending invite and revoke it', async ({ page, context }) => {
		await clearLinks();
		await context.grantPermissions(['clipboard-read', 'clipboard-write']);

		await page.goto('/coaching');
		await expect(page.getByRole('heading', { level: 1, name: 'Coaching' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByText('Pending invite')).toHaveCount(0);

		await page.getByRole('button', { name: 'Invite an athlete' }).click();
		await expect(page.getByText('Pending invite')).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Revoke' }).first().click();
		await expect(page.getByText('Pending invite')).toHaveCount(0, { timeout: 10_000 });
	});
});
