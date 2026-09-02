import { expect, test } from '@playwright/test';

import { readRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The versioned AI-processing consent record, end to end across the two
 * surfaces that write it and the two that refuse without it.
 *
 * Every other AI spec in the tree mocks the endpoint
 * (`routes/describe.spec.ts` fulfils `/api/coach/route-describe` itself) or
 * runs as a seeded user whom `seed.sql` already stamps at the current
 * version — so the gate has never been exercised against a real refusal.
 * That is the whole point of this file: a saga user starts with NO record,
 * so every request below reaches the real `gateAiDisclosure` and the real
 * `get_my_profile()` RPC.
 *
 * What it pins, in the order a person hits it:
 *
 *   1. `/coach` render-gates the chat behind the first-use disclosure —
 *      the composer is not merely disabled, it is not in the DOM, so no
 *      fetch can fan out to Anthropic before the click.
 *   2. Accepting records the CURRENT version server-side, not the minimum
 *      the Coach needs — the ladder is monotone and the widened
 *      disclosure is what was rendered.
 *   3. Withdrawing on `/settings/account` clears the whole record
 *      (Art 7(3)) and the `/coach` gate RE-ENGAGES. A consent gate that
 *      only closes on the way in is not a gate.
 *   4. The route AI refuses with its own copy after a withdrawal —
 *      pointing at Settings, not at "try again". A consent gap is not
 *      something a runner can retry away, and the L1 templated baseline
 *      still renders beside the refusal.
 *
 * Point 4 deliberately does NOT mock the endpoint: it drives the real
 * handler, whose disclosure gate sits ahead of the tier check and does not
 * honour the dev paywall bypass. No Anthropic key is needed to reach it.
 */
test.describe('AI-processing consent — gate, record, withdraw, re-engage', () => {
	test.describe.configure({ timeout: 120_000 });

	const admin = getAdminClient();

	/** Must equal AI_DISCLOSURE_CURRENT_VERSION / ai_disclosure_current_version(). */
	const CURRENT_VERSION = 2;

	let user: SagaUser;
	let routeId: string;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['AI Consent Saga'] });

		const { data, error } = await admin
			.from('routes')
			.insert({
				user_id: user.id,
				name: 'E2E consent gate loop',
				distance_m: 10_000,
				elevation_m: 120,
				surface: 'road',
				is_public: false,
				waypoints: [
					{ lat: 51.5, lng: -0.12 },
					{ lat: 51.51, lng: -0.11 },
					{ lat: 51.5, lng: -0.12 },
				],
			})
			.select('id')
			.single();
		if (error) throw error;
		routeId = (data as { id: string }).id;
	});

	test.afterAll(async () => {
		await deleteSagaUsers([user]);
	});

	/** The consent record as the database holds it, read past RLS. */
	async function consentRecord(): Promise<{
		ai_disclosure_version: number | null;
		coach_consent_at: string | null;
	}> {
		return readRow(
			'ai consent record',
			admin
				.from('user_profiles')
				.select('ai_disclosure_version, coach_consent_at')
				.eq('id', user.id)
				.single(),
		);
	}

	/**
	 * Put the record into a known state before each test, so no test depends
	 * on the one before it having run (and a `--grep` of any single one still
	 * exercises the real gate). The service role is a trusted writer for
	 * `lock_consent_columns_trg`, which is what makes a direct set possible.
	 */
	async function setConsent(version: number | null): Promise<void> {
		const { error } = await admin
			.from('user_profiles')
			.update({
				ai_disclosure_version: version,
				coach_consent_at: version == null ? null : new Date().toISOString(),
			})
			.eq('id', user.id);
		if (error) throw error;
	}

	test('the chat is render-gated until consent, and the accept records the current version', async ({
		browser,
	}) => {
		await setConsent(null);
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		try {
			// Nothing may reach the coach endpoint before the click. Counting
			// at the network layer is the only way to prove the render gate
			// actually gates rather than merely hides.
			let coachCalls = 0;
			await page.route('**/api/coach**', async (route) => {
				coachCalls++;
				await route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ error: 'e2e: should not be reached' }),
				});
			});

			await page.goto('/coach');

			const dialog = page.locator('.coach-consent');
			await expect(dialog).toBeVisible({ timeout: 15_000 });
			// Render-gated, not disabled: the composer does not exist yet.
			await expect(page.getByPlaceholder(/Ask about today/)).toHaveCount(0);
			expect(coachCalls).toBe(0);

			await page.getByRole('button', { name: /I consent/ }).click();

			await expect(page.getByPlaceholder(/Ask about today/)).toBeVisible({ timeout: 15_000 });
			await expect(dialog).toHaveCount(0);

			// The version recorded is the one that was RENDERED (the widest
			// this build knows), not the Coach's own minimum of 1 — a lower
			// stamp would silently leave the route AI refusing after an
			// acceptance the user experienced as blanket.
			const rec = await consentRecord();
			expect(rec.ai_disclosure_version).toBe(CURRENT_VERSION);
			expect(rec.coach_consent_at).not.toBeNull();
		} finally {
			await ctx.close();
		}
	});

	test('withdrawing on /settings/account clears the record and re-engages the /coach gate', async ({
		browser,
	}) => {
		await setConsent(CURRENT_VERSION);
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/account');

			// The section reads "active" off the record set above.
			const withdraw = page.getByRole('button', { name: 'Withdraw consent' });
			await expect(withdraw).toBeVisible({ timeout: 15_000 });
			await withdraw.click();

			// The section flips to its inactive copy, and the withdraw control
			// is gone with it.
			await expect(withdraw).toHaveCount(0, { timeout: 10_000 });
			await expect(page.getByText(/haven't consented to Threkir's AI features/)).toBeVisible();

			// Art 7(3): the whole server-held record goes, not just the version.
			const rec = await consentRecord();
			expect(rec.ai_disclosure_version).toBeNull();
			expect(rec.coach_consent_at).toBeNull();

			// And the gate is closed again on the next visit.
			await page.goto('/coach');
			await expect(page.locator('.coach-consent')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByPlaceholder(/Ask about today/)).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});

	test('the route AI refuses a withdrawn record with consent copy, keeping the templated baseline', async ({
		browser,
	}) => {
		await setConsent(null);
		const rec = await consentRecord();
		expect(rec.ai_disclosure_version).toBeNull();

		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		try {
			// Unmocked on purpose — this drives the real handler's
			// gateAiDisclosure. Observe the status rather than replacing it.
			let describeStatus = 0;
			page.on('response', (res) => {
				if (res.url().includes('/api/coach/route-describe')) describeStatus = res.status();
			});

			await page.goto(`/routes/${routeId}`);
			const describeBtn = page.getByRole('button', { name: /Describe this route/i });
			await expect(describeBtn).toBeVisible({ timeout: 15_000 });
			await describeBtn.click();

			// The refusal names the consent gap and points at where to act —
			// the generic "please try again" would send the runner in a loop.
			await expect(page.getByText(/AI descriptions need the updated AI disclosure/)).toBeVisible({
				timeout: 15_000,
			});
			await expect(page.getByText(/Couldn't generate a description/)).toHaveCount(0);

			// L1 survives the refusal: the locally-templated sentence is still
			// on the page.
			await expect(page.locator('.route-description')).toContainText(/road/i);

			expect(describeStatus).toBe(403);
		} finally {
			await ctx.close();
		}
	});
});
