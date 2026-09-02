import { expect, test } from '@playwright/test';

import { noonOnBrowserDay } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Art 7(3) withdrawal of the health-data consent, driven through the real
 * Save on `/settings/account`.
 *
 * Every existing spec that touches this checkbox deliberately stops short of
 * saving — `settings/account.spec.ts` and `settings/preferences.spec.ts` both
 * restore the box and leave the write unmade, because a real withdrawal
 * against the shared seed user would erase USER_A's demographics for every
 * other spec in the shard. So the withdrawal itself, which is the destructive
 * half, has never been executed end to end. A saga user makes it safe.
 *
 * The two claims that matter, and they pull in opposite directions:
 *
 *   - Everything Art 9 goes. `withdraw_health_data_consent()` nulls the
 *     stamp, the gender and the height and erases the whole weight series;
 *     the page additionally nulls the `user_settings.prefs.date_of_birth`
 *     MIRROR, which is what the run-detail age grade and the training-pace
 *     surfaces read. A mirror left behind is a health inference still running
 *     off a consent that was withdrawn.
 *   - The age record STAYS. `user_profiles.date_of_birth` is the
 *     under-18 discoverability floor's record (§ 718 / § 721) — a child
 *     protection purpose that carries no consent term and must not be
 *     defeated by declining the Art 9 one. Erasing it here would be a
 *     regression that no "did the erasure work" assertion catches.
 *
 * The second test then reads the withheld state back out of a real page: with
 * a date on record and consent withdrawn, `/nutrition/targets` must say so
 * rather than either printing the age (spending the ungated record on a
 * health purpose) or claiming "Not set" about a date the runner did set.
 */
test.describe('health-data consent — withdrawal erases Art 9, keeps the age record', () => {
	test.describe.configure({ timeout: 120_000 });

	const admin = getAdminClient();

	const DOB = '1978-04-09';
	const HEIGHT_CM = 181;
	const WEIGHT_KG = 74.5;

	let user: SagaUser;

	test.beforeEach(async () => {
		// A fresh user per test: the withdrawal is destructive and the second
		// test needs the pre-withdrawal shape too.
		[user] = await createSagaUsers(1, { displayNames: ['Health Consent Saga'] });

		// The service role is a trusted writer for `lock_consent_columns_trg`,
		// so the granted state can be planted without driving the grant UI.
		const { error: profErr } = await admin
			.from('user_profiles')
			.update({
				date_of_birth: DOB,
				gender: 'male',
				height_cm: HEIGHT_CM,
				health_data_consent_at: new Date().toISOString(),
			})
			.eq('id', user.id);
		if (profErr) throw profErr;

		const { error: bmErr } = await admin
			.from('body_metrics')
			.insert({ user_id: user.id, weight_kg: WEIGHT_KG, recorded_at: noonOnBrowserDay() });
		if (bmErr) throw bmErr;

		// The Art 9 mirror the health-use surfaces actually read.
		const { error: setErr } = await admin
			.from('user_settings')
			.upsert({ user_id: user.id, prefs: { date_of_birth: DOB } });
		if (setErr) throw setErr;
	});

	test.afterEach(async () => {
		await deleteSagaUsers([user]);
	});

	test('unticking consent and saving erases the Art 9 set, the weight series and the prefs mirror', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/account');

			const consent = page
				.locator('label.consent-checkbox')
				.locator('input[type="checkbox"]')
				.first();
			await expect(consent).toBeChecked({ timeout: 15_000 });
			await consent.uncheck();

			await page.getByRole('button', { name: /Save Profile/ }).click();
			await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
				timeout: 15_000,
			});

			const prof = await readRow<{
				data: {
					health_data_consent_at: string | null;
					gender: string | null;
					height_cm: number | null;
					date_of_birth: string | null;
				} | null;
				error: { message: string } | null;
			}>(
				'profile after withdrawal',
				admin
					.from('user_profiles')
					.select('health_data_consent_at, gender, height_cm, date_of_birth')
					.eq('id', user.id)
					.single(),
			);

			expect(prof.health_data_consent_at).toBeNull();
			expect(prof.gender).toBeNull();
			expect(prof.height_cm).toBeNull();
			// § 721: the age record is not the withdrawal's to touch.
			expect(prof.date_of_birth).toBe(DOB);

			const weights = await readRows(
				'body_metrics after withdrawal',
				admin.from('body_metrics').select('id').eq('user_id', user.id),
			);
			expect(weights).toHaveLength(0);

			const settings = await readRow<{
				data: { prefs: Record<string, unknown> | null } | null;
				error: { message: string } | null;
			}>(
				'settings after withdrawal',
				admin.from('user_settings').select('prefs').eq('user_id', user.id).single(),
			);
			// The mirror is the value every health-use surface reads. Left
			// behind, the age grade keeps running off a withdrawn consent.
			expect(settings.prefs?.date_of_birth ?? null).toBeNull();
		} finally {
			await ctx.close();
		}
	});

	test('/nutrition/targets reports the age as consent-withheld, never as the number or as unset', async ({
		browser,
	}) => {
		// Withdraw the stamp only — the age record stays, which is exactly
		// the state that separates "withheld" from "absent".
		const { error } = await admin
			.from('user_profiles')
			.update({ health_data_consent_at: null })
			.eq('id', user.id);
		if (error) throw error;

		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto('/nutrition/targets');

			const ageRow = page.locator('.metric-list li').filter({ hasText: 'Age' }).first();
			await expect(ageRow).toBeVisible({ timeout: 15_000 });
			await expect(ageRow).toContainText('Needs health-data consent');
			// Not the age, and not "Not set" — the runner did set a date.
			await expect(ageRow).not.toContainText(/\d+\s*(years|yrs)/i);
			await expect(ageRow).not.toContainText('Not set');
		} finally {
			await ctx.close();
		}
	});
});
