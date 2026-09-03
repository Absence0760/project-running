import { expect, test, type Page } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * The race calendar's import modal is provider-driven, not RunSignUp-only
 * (race_calendar.md). Every leg the `race-results-import` Edge Function ships —
 * RunSignUp, UltraSignup, ChronoTrack — is reachable from a listing of that
 * provider once its credentials are configured, and each asks for the field its
 * own leg is scoped by: a bib for the two whose scope gate demands one, an
 * athlete id for UltraSignup, which reads one athlete's history.
 *
 * Dev and CI ship no provider credentials, so the configured branch is reached
 * by stubbing the two availability probes. Only the probes are stubbed —
 * everything from the listing row to the request the modal builds is real, and
 * the assertions are on the request body the page actually sends.
 */

const stamp = Date.now();

const LEGS = [
	{
		provider: 'runsignup',
		label: 'RunSignUp',
		input: 'runsignup-bib',
		submit: 'race-import-runsignup',
		value: '1471',
		body: { bib: '1471' }
	},
	{
		provider: 'ultrasignup',
		label: 'UltraSignup',
		input: 'ultrasignup-athlete',
		submit: 'race-import-ultrasignup',
		value: 'athlete-902',
		body: { ultraSignUpAthleteId: 'athlete-902' }
	},
	{
		provider: 'chronotrack',
		label: 'ChronoTrack',
		input: 'chronotrack-bib',
		submit: 'race-import-chronotrack',
		value: '55',
		body: { bib: '55' }
	}
] as const;

const raceNameFor = (provider: string) => `E2E ${provider} Configured ${stamp}`;

/// Report every leg as provisioned, and record the import the modal builds.
async function stubProviders(page: Page, imports: Record<string, unknown>[]) {
	await page.route('**/functions/v1/race-results-import', (route) => {
		const body = (route.request().postDataJSON() ?? {}) as Record<string, unknown>;
		if (body.probe === true) {
			return route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ configured: true })
			});
		}
		imports.push(body);
		return route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({ imported: 1, skipped: 0, enriched: 0 })
		});
	});
}

test.describe('/races import modal — every configured leg is reachable', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const listingIds: string[] = [];

	test.beforeAll(async () => {
		for (const leg of LEGS) {
			listingIds.push(
				await insertRaceListing({
					provider: leg.provider,
					name: raceNameFor(leg.provider),
					race_date: browserDate(45),
					provider_race_id: `e2e-${leg.provider}-configured`
				})
			);
		}
	});

	test.afterAll(async () => {
		for (const id of listingIds) await deleteRaceListing(id);
	});

	for (const leg of LEGS) {
		test(`${leg.label} offers its own scoped import`, async ({ page }) => {
			const imports: Record<string, unknown>[] = [];
			await stubProviders(page, imports);

			const raceName = raceNameFor(leg.provider);
			await page.goto('/races');
			await page.getByTestId('races-search').fill(raceName);

			const card = page.getByTestId('race-card').filter({ hasText: raceName });
			await expect(card).toBeVisible({ timeout: 15_000 });
			await card.getByTestId('race-import').click();

			const submit = page.getByTestId(leg.submit);
			await expect(submit).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId(`race-${leg.provider}-unavailable`)).toHaveCount(0);

			await page.getByTestId(leg.input).fill(leg.value);
			await submit.click();

			await expect
				.poll(() => imports.length, { timeout: 15_000 })
				.toBeGreaterThan(0);
			// The right leg, scoped by the field that leg's own gate reads — a
			// ChronoTrack race must not be imported as somebody's RunSignUp result.
			expect(imports[0].provider).toBe(leg.provider);
			expect(imports[0].listingId).toBe(listingIds[LEGS.indexOf(leg)]);
			expect(imports[0]).toMatchObject(leg.body);
		});
	}

	test('a bib-scoped leg will not submit unscoped', async ({ page }) => {
		// `runSignUpScopeGate` / `chronoTrackScopeGate` reject an unscoped call
		// before any upstream fetch, so the modal must not offer to make it —
		// an unscoped pull imports the whole finisher field (issue #360).
		const imports: Record<string, unknown>[] = [];
		await stubProviders(page, imports);

		const raceName = raceNameFor('chronotrack');
		await page.goto('/races');
		await page.getByTestId('races-search').fill(raceName);
		await page
			.getByTestId('race-card')
			.filter({ hasText: raceName })
			.getByTestId('race-import')
			.click();

		await expect(page.getByTestId('race-import-chronotrack')).toBeDisabled({
			timeout: 15_000
		});
	});
});
