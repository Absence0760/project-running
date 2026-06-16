import { expect, test } from '@playwright/test';

import { createClient } from '@supabase/supabase-js';

import { getAdminClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import {
	insertRun,
	deleteRun,
	setUserSetting,
	clearUserSettingKey,
} from '../fixtures/simulate';

/**
 * Run-LEVEL visibility (public / private) propagation across surfaces.
 *
 * This is the whole-run on/off gate — DISTINCT from the round-3
 * privacy-ZONE track clipping (which redacts coordinates on an
 * otherwise-public run). Here a private run is INVISIBLE to a
 * non-owner everywhere; a public run is visible. The boundary is the
 * `public_runs` view (`where is_public = true`, decisions §33,
 * migration 20260626_001) — the base `runs` SELECT has been owner-only
 * since 20260701_001, so non-owners reach a run only through that view.
 *
 * The journey walks the real arc across owner + non-owner surfaces:
 *
 *   A. DEFAULT-VISIBILITY pref governs NEW runs. The universal
 *      `privacy_default` pref (`public` | `followers` | `private`) maps
 *      to `runs.is_public` via `privacyDefaultToIsPublic` (only
 *      `public` → public). The owner's Add-run editor (RunEditor) seeds
 *      its "Make this run public" checkbox from that pref — assert
 *      checked when `public`, unchecked when `private`.
 *
 *   B. A PRIVATE run is invisible to the follower everywhere:
 *        - the follower's /social feed (fetchFollowingFeed → public_runs)
 *        - the owner's public /u/[id] profile (fetchPublicRunsByUser)
 *        - /share/run/[id] (anon lookupSharedRun → public_runs → not found)
 *        - the follower's /runs/[id] (fetchRunById is owner-scoped
 *          `.eq('user_id', uid)` — a non-owner ALWAYS sees not-found
 *          there regardless of is_public, so this surface is NOT the
 *          public-visibility gate; the share/profile/feed surfaces are.
 *          Asserted as the not-found state, grounded in rule 5).
 *
 *   C. Flip PUBLIC through the REAL owner UI (the /runs/[id] share
 *      button → makeRunPublic). The same run now APPEARS on the
 *      follower's feed, the owner's /u/[id] profile, and /share/run/[id].
 *
 *   D. Flip back PRIVATE (admin — there is no make-private UI toggle on
 *      /runs/[id], only makeRunPublic; rule 3 permits admin for setup /
 *      teardown of state the UI can't reach). The run DISAPPEARS from
 *      every non-owner surface again.
 *
 * Two saga users: owner (authors the run) + follower (follows owner so
 * the feed surface is testable). All planted state is cleaned in
 * try/finally.
 */

// A saga user must pre-accept the cookie banner: it's a role="dialog"
// that floats over the page (and over modals), and an un-dismissed
// banner intercepts pointer events on the Add-run modal / feed cards.
function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
	);
}

// A distinctive title so feed + profile assertions scope to EXACTLY the
// planted run (the feed card renders metadata.title in h3.entry-title;
// the run-detail header chip reads run.is_public).
const RUN_TITLE = `VisProp ${Date.now()}`;

test.describe('run visibility (public/private) propagation across surfaces', () => {
	let owner: SagaUser;
	let follower: SagaUser;
	let runId: string | null = null;

	test.beforeAll(async () => {
		[owner, follower] = await createSagaUsers(2, {
			displayNames: [`VisOwner ${Date.now()}`, `VisFollower ${Date.now()}`],
		});
		// follower → owner, so the owner's public runs land on the
		// follower's /social feed (fetchFollowingFeed reads user_follows).
		const admin = getAdminClient();
		const { error } = await admin
			.from('user_follows')
			.upsert(
				{ follower_id: follower.id, followee_id: owner.id },
				{ onConflict: 'follower_id,followee_id' },
			);
		if (error) throw new Error(`follow setup failed: ${error.message}`);
	});

	test.afterAll(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch {
				/* best-effort */
			}
			runId = null;
		}
		// deleteSagaUsers cascades user_follows + any orphan runs.
		await deleteSagaUsers([owner, follower]);
	});

	test('default-visibility → private-hidden → flip-public-visible → flip-private-hidden', async ({
		browser,
	}) => {
		const { url, anonKey } = loadSupabaseEnv();
		const admin = getAdminClient();

		// ── A. Default-visibility pref governs new runs (owner UI) ──
		await test.step('privacy_default=public seeds the Add-run editor checkbox CHECKED', async () => {
			await setUserSetting(owner.id, 'privacy_default', 'public');
			const ctx = await browser.newContext({ storageState: owner.storageStatePath });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto('/runs');
				// Open the Add-run modal — RunEditor seeds isPublic from the
				// freshly-read privacy_default pref in onMount.
				await page.getByRole('button', { name: '+ Add run' }).click();
				const publicToggle = page.getByLabel('Make this run public');
				await expect(publicToggle).toBeVisible({ timeout: 10_000 });
				await expect(publicToggle).toBeChecked();
			} finally {
				await ctx.close();
			}
		});

		await test.step('privacy_default=private seeds the Add-run editor checkbox UNCHECKED', async () => {
			await setUserSetting(owner.id, 'privacy_default', 'private');
			const ctx = await browser.newContext({ storageState: owner.storageStatePath });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto('/runs');
				await page.getByRole('button', { name: '+ Add run' }).click();
				const publicToggle = page.getByLabel('Make this run public');
				await expect(publicToggle).toBeVisible({ timeout: 10_000 });
				await expect(publicToggle).not.toBeChecked();
			} finally {
				await ctx.close();
			}
		});

		// Plant the journey's run as PRIVATE (matching the runner's now-
		// default-private pref). started_at within the 14-day feed window
		// so the feed query would surface it once it goes public.
		runId = await insertRun({
			user_id: owner.id,
			started_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
			duration_s: 1_800,
			distance_m: 7_000,
			is_public: false,
			activity_type: 'run',
			metadata: { title: RUN_TITLE },
		});

		// ── B. PRIVATE run is invisible to the non-owner everywhere ──
		await test.step('anon public_runs read returns nothing for the private run', async () => {
			// The wire-level gate every non-owner surface sits on top of.
			const anon = createClient(url, anonKey, { auth: { persistSession: false } });
			const { data } = await anon
				.from('public_runs')
				.select('id')
				.eq('id', runId!)
				.maybeSingle();
			expect(data).toBeNull();
		});

		await test.step('private run is absent from the follower /social feed', async () => {
			const ctx = await browser.newContext({ storageState: follower.storageStatePath });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto('/social?tab=feed');
				// The owner author chip appears only when one of their runs
				// is in the feed; the planted private run must not show.
				await expect(page.getByRole('heading', { name: RUN_TITLE })).toHaveCount(0, {
					timeout: 10_000,
				});
			} finally {
				await ctx.close();
			}
		});

		await test.step('private run is absent from the owner public /u/[id] profile (non-owner viewer)', async () => {
			const ctx = await browser.newContext({ storageState: follower.storageStatePath });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto(`/u/${owner.id}`);
				// Runs tab is the default. fetchPublicRunsByUser reads
				// public_runs, so a private run never reaches the run grid.
				await expect(page.locator('.run-grid .run-card')).toHaveCount(0, {
					timeout: 10_000,
				});
			} finally {
				await ctx.close();
			}
		});

		await test.step('/share/run/[id] (anon) shows the not-found state for the private run', async () => {
			const ctx = await browser.newContext({ storageState: { cookies: [], origins: [] } });
			const page = await ctx.newPage();
			try {
				await page.goto(`/share/run/${runId}`);
				// lookupSharedRun reads public_runs anon → null → not-found card.
				await expect(page.getByRole('heading', { name: 'Run not found.' })).toBeVisible({
					timeout: 10_000,
				});
				await expect(page.getByText('A run on Threkir')).toHaveCount(0);
			} finally {
				await ctx.close();
			}
		});

		await test.step('follower /runs/[id] is not-found (owner-scoped fetchRunById, rule 5)', async () => {
			// fetchRunById filters `.eq('user_id', uid)` — a non-owner sees
			// not-found here regardless of is_public, so this surface is NOT
			// the public-visibility gate; the share/profile/feed surfaces are.
			const ctx = await browser.newContext({ storageState: follower.storageStatePath });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto(`/runs/${runId}`);
				await expect(page.getByRole('heading', { name: 'Run not found' })).toBeVisible({
					timeout: 10_000,
				});
			} finally {
				await ctx.close();
			}
		});

		// ── C. Flip PUBLIC through the real owner UI (makeRunPublic) ──
		await test.step('owner flips the run public via the /runs/[id] share button', async () => {
			const ctx = await browser.newContext({ storageState: owner.storageStatePath });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto(`/runs/${runId}`);
				// Owner sees the run + the Private visibility chip.
				const chip = page.locator('.visibility-chip');
				await expect(chip).toBeVisible({ timeout: 10_000 });
				await expect(chip).toContainText('Private');
				// Share button on a private run opens the make-public confirm.
				await page
					.getByRole('button', { name: 'Make public and copy share link' })
					.click();
				const dialog = page.getByTestId('share-confirm-dialog');
				await expect(dialog).toBeVisible({ timeout: 10_000 });
				await dialog.getByRole('button', { name: 'Make public & copy link' }).click();
				// makeRunPublic committed → chip flips to Public in-page.
				await expect(chip).toContainText('Public', { timeout: 10_000 });
			} finally {
				await ctx.close();
			}
		});

		await test.step('public_runs now returns the run (wire-level confirmation of the flip)', async () => {
			const anon = createClient(url, anonKey, { auth: { persistSession: false } });
			const { data } = await anon
				.from('public_runs')
				.select('id, is_public')
				.eq('id', runId!)
				.maybeSingle();
			expect(data?.id).toBe(runId);
		});

		await test.step('public run now appears on the follower /social feed', async () => {
			const ctx = await browser.newContext({ storageState: follower.storageStatePath });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto('/social?tab=feed');
				await expect(page.getByRole('heading', { name: RUN_TITLE })).toBeVisible({
					timeout: 10_000,
				});
			} finally {
				await ctx.close();
			}
		});

		await test.step('public run now appears on the owner /u/[id] profile (non-owner viewer)', async () => {
			const ctx = await browser.newContext({ storageState: follower.storageStatePath });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto(`/u/${owner.id}`);
				await expect(page.locator('.run-grid .run-card')).toHaveCount(1, {
					timeout: 10_000,
				});
			} finally {
				await ctx.close();
			}
		});

		await test.step('/share/run/[id] (anon) now renders the public run', async () => {
			const ctx = await browser.newContext({ storageState: { cookies: [], origins: [] } });
			const page = await ctx.newPage();
			try {
				await page.goto(`/share/run/${runId}`);
				await expect(page.getByText('A run on Threkir')).toBeVisible({ timeout: 10_000 });
				await expect(page.getByRole('heading', { name: 'Run not found.' })).toHaveCount(0);
			} finally {
				await ctx.close();
			}
		});

		// ── D. Flip back PRIVATE (admin — no make-private UI) ──
		await test.step('owner flips the run back to private', async () => {
			const { error } = await admin
				.from('runs')
				.update({ is_public: false })
				.eq('id', runId!);
			expect(error).toBeNull();
			// Confirm the gate closed at the wire.
			const anon = createClient(url, anonKey, { auth: { persistSession: false } });
			const { data } = await anon
				.from('public_runs')
				.select('id')
				.eq('id', runId!)
				.maybeSingle();
			expect(data).toBeNull();
		});

		await test.step('re-privatised run disappears from the follower feed again', async () => {
			const ctx = await browser.newContext({ storageState: follower.storageStatePath });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto('/social?tab=feed');
				await expect(page.getByRole('heading', { name: RUN_TITLE })).toHaveCount(0, {
					timeout: 10_000,
				});
			} finally {
				await ctx.close();
			}
		});

		await test.step('re-privatised run disappears from the owner /u/[id] profile again', async () => {
			const ctx = await browser.newContext({ storageState: follower.storageStatePath });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto(`/u/${owner.id}`);
				await expect(page.locator('.run-grid .run-card')).toHaveCount(0, {
					timeout: 10_000,
				});
			} finally {
				await ctx.close();
			}
		});

		await test.step('re-privatised run shows not-found on /share/run/[id] again', async () => {
			const ctx = await browser.newContext({ storageState: { cookies: [], origins: [] } });
			const page = await ctx.newPage();
			try {
				await page.goto(`/share/run/${runId}`);
				await expect(page.getByRole('heading', { name: 'Run not found.' })).toBeVisible({
					timeout: 10_000,
				});
			} finally {
				await ctx.close();
			}
		});

		// Clear the pref we planted so a re-run of beforeAll-minted users
		// can't be affected (the saga user is deleted in afterAll anyway).
		await clearUserSettingKey(owner.id, 'privacy_default');
	});
});
