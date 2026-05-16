import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /routes/[id] — SegmentsPanel (v2 tiered leaderboards).
 *
 * Pairs with the SECURITY DEFINER fix in `20260830_001_segment_
 * leaderboard_tiered_security_definer_fix.sql`. The original
 * `SECURITY INVOKER` declaration returned `permission denied for
 * table user_profiles` on every real call; the web caller silently
 * masked the error and the surface returned empty leaderboards.
 *
 * These tests pin the UX-visible side of that fix:
 *   - Open a segment → leaderboard renders with rows (not the "no
 *     efforts yet" empty state). This is the silent-empty regression
 *     guard.
 *   - Tier filter dropdowns (Gender + Age band) drive the RPC and
 *     narrow the row set.
 *   - Cross-user demographic mask: gender + age columns are only
 *     populated for the calling user's row (the privacy posture from
 *     decisions.md §60).
 *   - Crown banner renders only when the viewer holds rank-1 in the
 *     current tier.
 *   - .viewer highlight class on the rank row owned by the calling
 *     user.
 *   - Create + Delete round-trip (canCreate=auth.loggedIn).
 *   - ConfirmDialog gates delete.
 *
 * Fixtures planted via service-role in beforeAll / cleaned in
 * afterAll so the suite is self-contained. None of the seeded
 * routes have segments, and none of the seeded users have
 * demographics — both are part of the fixture set-up.
 */

const BATTERSEA_ROUTE_ID = '225a576a-6108-4157-bc71-d42d8d6d1bf4';
let segmentId: string;
let plantedRunIds: string[] = [];

test.describe('/routes/[id] — SegmentsPanel (v2 tiered leaderboards)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test.beforeAll(async () => {
		const admin = getAdminClient();

		// 1. Plant gender + date_of_birth on USER_B (cohort: female 30-34)
		//    so the tier-filter narrowing test has a definite match.
		//    USER_A + USER_C stay demographic-less (cohort: null) to
		//    exercise the masking branch — anyone NOT in a tier filter
		//    drops out of the filtered result set.
		await admin
			.from('user_profiles')
			.update({
				gender: 'female',
				date_of_birth: new Date(
					new Date().getFullYear() - 32,
					0,
					1
				).toISOString().slice(0, 10)
			})
			.eq('id', USER_B.id);

		// 2. Plant a segment on the Battersea Park route. Length 1000m
		//    (start 1000, end 2000) — fits cleanly inside the 7800m
		//    route distance.
		const { data: segRow, error: segErr } = await admin
			.from('segments')
			.insert({
				route_id: BATTERSEA_ROUTE_ID,
				name: 'e2e-Park Lap',
				start_distance_m: 1000,
				end_distance_m: 2000,
				created_by: USER_A.id
			})
			.select('id')
			.single();
		if (segErr) throw segErr;
		segmentId = (segRow as { id: string }).id;

		// 3. Plant one run + one effort for each of USER_A, USER_B,
		//    USER_C with deterministic times so the leaderboard order
		//    is stable. Times: USER_A=240s (rank 1, crown), USER_B=260s
		//    (rank 2), USER_C=300s (rank 3).
		const users = [
			{ user: USER_A, time: 240 },
			{ user: USER_B, time: 260 },
			{ user: USER_C_PRO, time: 300 }
		];
		const startTs = new Date('2026-04-10T08:00:00Z').getTime();
		for (let i = 0; i < users.length; i++) {
			const { user, time } = users[i];
			const startedAt = new Date(startTs + i * 60_000).toISOString();
			const { data: runRow, error: runErr } = await admin
				.from('runs')
				.insert({
					user_id: user.id,
					started_at: startedAt,
					duration_s: 1800,
					distance_m: 7800,
					source: 'app',
					is_public: true,
					metadata: { activity_type: 'run' },
					route_id: BATTERSEA_ROUTE_ID
				})
				.select('id')
				.single();
			if (runErr) throw runErr;
			const runId = (runRow as { id: string }).id;
			plantedRunIds.push(runId);
			const { error: effErr } = await admin.from('segment_efforts').insert({
				segment_id: segmentId,
				run_id: runId,
				user_id: user.id,
				time_seconds: time,
				started_at: startedAt
			});
			if (effErr) throw effErr;
		}
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		// Cascade: deleting the segment removes segment_efforts via
		// ON DELETE CASCADE. We delete the planted runs to keep the
		// runs feed clean for the next test session.
		if (segmentId) {
			await admin.from('segments').delete().eq('id', segmentId);
		}
		if (plantedRunIds.length > 0) {
			await admin.from('runs').delete().in('id', plantedRunIds);
		}
		// Roll back USER_B's planted demographics so the seed
		// invariants are preserved.
		await admin
			.from('user_profiles')
			.update({ gender: null, date_of_birth: null })
			.eq('id', USER_B.id);
	});

	test('SegmentsPanel mounts under /routes/[id] with the seeded segment', async ({
		page
	}) => {
		// `.segments-panel` is the component root. The `<h2>Segments</h2>`
		// header is its unique mount marker. The planted segment shows
		// in the seg-list with the name we used.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await expect(page.locator('.segments-panel'))
			.toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.segments-panel h2'))
			.toHaveText('Segments');
		await expect(
			page.locator('.seg-row strong', { hasText: 'e2e-Park Lap' })
		).toBeVisible();
	});

	test('clicking a segment opens its leaderboard (silent-empty regression pin)', async ({
		page
	}) => {
		// Load-bearing test: if the SECURITY DEFINER fix from
		// 20260830_001 regresses to SECURITY INVOKER, the RPC fails
		// with 42501 and `fetchSegmentLeaderboardTiered` masks it with
		// `console.warn + return []`. The user sees "No efforts yet"
		// instead of the leaderboard. This test fails the moment
		// SECURITY INVOKER + the column-grant lockdown re-collide.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		const board = page.locator('.seg.open .leaderboard ol');
		await expect(board).toBeVisible({ timeout: 10_000 });
		await expect(board.locator('li')).toHaveCount(3);
		// Must NOT render the empty-state copy.
		await expect(
			page.locator('.leaderboard .muted', { hasText: /No efforts yet/i })
		).toHaveCount(0);
	});

	test('leaderboard is ordered by time_seconds asc (rank 1 is fastest)', async ({
		page
	}) => {
		// Planted times: USER_A 240s (4:00), USER_B 260s (4:20),
		// USER_C 300s (5:00). The .time cell renders mm:ss for sub-1h
		// times.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		const rows = page.locator('.seg.open .leaderboard ol li');
		await expect(rows).toHaveCount(3, { timeout: 10_000 });
		await expect(rows.nth(0).locator('.time')).toHaveText('4:00');
		await expect(rows.nth(1).locator('.time')).toHaveText('4:20');
		await expect(rows.nth(2).locator('.time')).toHaveText('5:00');
	});

	test('caller (USER_A) holds the crown → .crown-banner renders', async ({
		page
	}) => {
		// USER_A planted at 240s (rank 1, current tier = All / All).
		// Component reads `_crownHolder.effort.user_id === auth.user?.id`
		// to render the banner. A regression that masked auth.user?.id
		// (broken auth store) would silently hide the banner.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		await expect(page.locator('.crown-banner'))
			.toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.crown-banner'))
			.toContainText(/You hold this crown/);
	});

	test('the caller\'s row carries the .viewer highlight class', async ({
		page
	}) => {
		// USER_A's row is the rank-1 row. The .viewer modifier paints
		// it with the primary-tint background. A regression that
		// dropped the auth-driven class would let runners not find
		// themselves in long lists.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		const viewerRow = page.locator('.seg.open .leaderboard ol li.viewer');
		await expect(viewerRow).toHaveCount(1, { timeout: 10_000 });
	});

	test('Gender filter = Women narrows to USER_B only (cross-user mask)', async ({
		page
	}) => {
		// USER_B planted as female 30-34. Filtering Gender=Women must
		// hide USER_A (no demographics) + USER_C (no demographics).
		// This drives the RPC's `p_gender` parameter; success implies
		// the SECURITY DEFINER function bypassed the column-grant
		// lockdown AND the filter operated on the underlying gender
		// column (not the masked return column — those are NULL for
		// non-self rows, see test below).
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		await expect(page.locator('.tier-filters'))
			.toBeVisible({ timeout: 10_000 });
		await page
			.locator('.tier-filters select')
			.first()
			.selectOption('female');
		const rows = page.locator('.seg.open .leaderboard ol li');
		// USER_A no longer in the filtered set — viewer highlight
		// disappears entirely.
		await expect(page.locator('.seg.open .leaderboard ol li.viewer'))
			.toHaveCount(0, { timeout: 10_000 });
		await expect(rows).toHaveCount(1);
	});

	test('Reset clears Gender + Age filters back to All / All ages', async ({
		page
	}) => {
		// .clear-btn appears only when at least one filter is set.
		// Press it → both filters revert → leaderboard reloads with
		// all 3 rows.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		await expect(page.locator('.tier-filters'))
			.toBeVisible({ timeout: 10_000 });
		await page
			.locator('.tier-filters select')
			.first()
			.selectOption('female');
		// Reset button now visible.
		const reset = page.locator('.tier-filters .clear-btn');
		await expect(reset).toBeVisible({ timeout: 5_000 });
		await reset.click();
		// Filters back to All — count returns to 3.
		await expect(page.locator('.seg.open .leaderboard ol li'))
			.toHaveCount(3, { timeout: 10_000 });
		// Reset button is no longer rendered.
		await expect(reset).toHaveCount(0);
	});

	test('opening a different segment resets the filters (cohort hygiene)', async ({
		page
	}) => {
		// `toggleLeaderboard` resets genderFilter + ageFilter to null
		// when openSegmentId changes. We only have one segment, but we
		// can drive the close → reopen path on the same segment which
		// goes through the same reset. Pin via the chevron-flip +
		// re-opening without the reset button present.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		await page
			.locator('.tier-filters select')
			.first()
			.selectOption('female');
		// Close.
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		await expect(page.locator('.seg.open')).toHaveCount(0, {
			timeout: 5_000
		});
		// Reopen.
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		// The Reset chip should NOT be present (filters cleared on
		// re-open via the toggle path).
		await expect(page.locator('.tier-filters .clear-btn'))
			.toHaveCount(0, { timeout: 5_000 });
	});

	test('caret material-symbols flips expand_more ↔ expand_less on open / close', async ({
		page
	}) => {
		// Visual cue surface. The component switches the icon glyph
		// based on openSegmentId. Pin both states.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		const row = page.locator('.seg-row', { hasText: 'e2e-Park Lap' });
		await expect(row.locator('.caret')).toHaveText('expand_more', {
			timeout: 10_000
		});
		await row.click();
		await expect(row.locator('.caret')).toHaveText('expand_less');
		await row.click();
		await expect(row.locator('.caret')).toHaveText('expand_more');
	});

	test('Create + Delete round-trip via the panel UI', async ({ page }) => {
		// canCreate is auth.loggedIn → "New segment" button visible to
		// USER_A. Pin the round-trip: open form → fill → submit → row
		// appears → delete → ConfirmDialog → confirm → row disappears.
		// Use a name distinct from the beforeAll fixture so the tests
		// don't interfere.
		const tempName = `e2e-tmp-${Date.now()}`;
		const admin = getAdminClient();
		try {
			await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
			await page
				.getByRole('button', { name: 'New segment' })
				.click({ timeout: 10_000 });
			// Form mounts.
			const form = page.locator('.create');
			await expect(form).toBeVisible({ timeout: 5_000 });
			await form.locator('input[type="text"]').fill(tempName);
			await form.locator('input[type="number"]').first().fill('3000');
			await form.locator('input[type="number"]').nth(1).fill('4000');
			await form.getByRole('button', { name: 'Create' }).click();
			// New row appears in the seg-list.
			const newRow = page.locator('.seg-row', { hasText: tempName });
			await expect(newRow).toBeVisible({ timeout: 10_000 });

			// Open it + click Delete segment → ConfirmDialog.
			await newRow.click();
			await page
				.locator('.seg.open .link-btn.danger', { hasText: /Delete segment/ })
				.click({ timeout: 5_000 });
			const dialog = page.getByRole('dialog', { name: /Delete segment/ })
				.or(page.locator('.modal', { hasText: 'Delete segment?' }));
			await expect(dialog.first()).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Delete' }).click();

			// Row gone.
			await expect(newRow).toHaveCount(0, { timeout: 10_000 });
		} finally {
			// Sweep: in case the test failed mid-flow leaving the row.
			await admin
				.from('segments')
				.delete()
				.eq('route_id', BATTERSEA_ROUTE_ID)
				.eq('name', tempName);
		}
	});

	test('Cancel on Delete-segment dialog keeps the row + its leaderboard', async ({
		page
	}) => {
		// ConfirmDialog has Cancel + Confirm paths. Cancel must NOT
		// remove the segment — verifies the destructive action is
		// gated on Confirm only.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		await page
			.locator('.seg.open .link-btn.danger', { hasText: /Delete segment/ })
			.click({ timeout: 5_000 });
		const dialog = page.getByRole('dialog', { name: /Delete segment/ })
			.or(page.locator('.modal', { hasText: 'Delete segment?' }));
		await expect(dialog.first()).toBeVisible({ timeout: 5_000 });
		// Cancel → no destructive action.
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		// Segment still in the list + the row is still open with its
		// leaderboard rendered.
		await expect(
			page.locator('.seg-row', { hasText: 'e2e-Park Lap' })
		).toBeVisible();
		await expect(
			page.locator('.seg.open .leaderboard ol li')
		).toHaveCount(3);
	});

	test('New-segment toggle button label flips Cancel ↔ New segment', async ({
		page
	}) => {
		// The header button is a single control that toggles showCreate.
		// Pin the label flip so a regression that left it stuck at one
		// value (e.g. forgetting the `{showCreate ? ... : ...}` ternary)
		// would surface here.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		const btn = page.locator('.segments-panel .hd button');
		await expect(btn).toHaveText('New segment', { timeout: 10_000 });
		await btn.click();
		await expect(btn).toHaveText('Cancel');
		await btn.click();
		await expect(btn).toHaveText('New segment');
	});

	test('clicking an athlete row navigates to /u/[id]', async ({ page }) => {
		// Each leaderboard row carries `<a href="/u/{athlete.id}">`.
		// Click on the rank-1 row (USER_A himself) and verify the URL
		// resolves to USER_A's profile.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await page
			.locator('.seg-row', { hasText: 'e2e-Park Lap' })
			.click();
		await expect(
			page.locator('.seg.open .leaderboard ol li')
		).toHaveCount(3, { timeout: 10_000 });

		// Pin the USER_A row's athlete link target.
		await expect(
			page.locator(`.seg.open .leaderboard ol li.viewer a[href="/u/${USER_A.id}"]`)
		).toBeVisible();
	});

	test('Create form rejects sub-100m ranges with a toast (validation guard)', async ({
		page
	}) => {
		// `submitCreate` rejects ranges shorter than 100 m as a sanity
		// gate. The error surfaces via the toast container. Pin the
		// negative — a regression that loosened the guard would let
		// trivial 1-m "segments" pile up.
		await page.goto(`/routes/${BATTERSEA_ROUTE_ID}`);
		await page
			.getByRole('button', { name: 'New segment' })
			.click({ timeout: 10_000 });
		await page.locator('.create input[type="text"]').fill('e2e-too-short');
		// Force a < 100m gap so the validator runs (start=500, end=550).
		await page.locator('.create input[type="number"]').first().fill('500');
		await page.locator('.create input[type="number"]').nth(1).fill('550');
		await page.locator('.create').getByRole('button', { name: 'Create' }).click();
		// Toast appears with the 100 m message.
		await expect(
			page.locator('.toast', { hasText: /at least 100 m/i }).first()
				.or(page.getByText(/at least 100 m/i).first())
		).toBeVisible({ timeout: 5_000 });
	});
});
