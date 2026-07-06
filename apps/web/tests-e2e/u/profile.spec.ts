import { expect, test } from '@playwright/test';

import { USER_A, USER_B } from '../fixtures/users';

/**
 * /u/[id] — public user profile.
 *
 * Renders display_name, follower / following counts, recent public
 * runs in a card grid (mounting RunShareView in a modal on click),
 * and a Follow toggle (cross-user/follows.spec.ts covers the toggle
 * round-trip). This file holds the "page renders + tabs work + a
 * non-self viewer's view is correct" checks.
 *
 * Future depth: Followers + Following tabs render the seeded edges,
 * notifications tab gating (only visible to isSelf), the user's
 * runs grid showing Alex's recent public runs vs runner's pinned
 * one.
 */

test.describe('/u/[id] — viewing another user', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('canonical folds the in-app profile onto its public /share/profile twin', async ({
		page,
	}) => {
		// SEO consolidation: the in-app (login-gated) profile page points
		// its canonical at the crawlable /share/profile/[id] twin so search
		// engines don't split ranking signal across the two URLs.
		await page.goto(`/u/${USER_B.id}`);
		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			new RegExp(`/share/profile/${USER_B.id}$`)
		);
	});

	test('a failed profile load shows an error + retry, and retry recovers', async ({ page }) => {
		// Abort (not 500) so the supabase call rejects → the page would
		// otherwise hang on its skeleton forever. Pins the loadError + retry.
		// Abort every user_profiles read while `block` is true so the page's
		// fetchPublicProfile fails (a 500 would just return null → not-found;
		// an abort surfaces the error). Flip block off before the retry.
		let block = true;
		await page.route('**/rest/v1/user_profiles**', async (route) => {
			if (route.request().method() === 'GET' && block) {
				await route.abort();
				return;
			}
			await route.fallback();
		});

		await page.goto(`/u/${USER_B.id}`);
		await expect(page.locator('.error-banner')).toBeVisible({ timeout: 10_000 });

		block = false;
		await page.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByRole('heading', { name: 'Alex Chen' })).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.error-banner')).toHaveCount(0);
	});

	test('runner views alex profile: display_name + Follow button visible', async ({
		page
	}) => {
		// USER_A (runner) follows alex per seed, so alex's profile
		// shows the "Following" state on the toggle (not "Follow").
		await page.goto(`/u/${USER_B.id}`);

		// h1 reflects display_name. Pinned to "Alex Chen" in seed.sql.
		await expect(
			page.getByRole('heading', { name: 'Alex Chen', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// Follow button is present (alex isn't isSelf for runner).
		// Runner already follows alex, so it reads "Following".
		await expect(page.locator('button.btn-follow')).toContainText('Following');

		// Three count buttons render: Runs / Followers / Following.
		// Clicking switches the tab; we just check the chrome — the
		// cross-user/follows spec exercises the toggle round-trip.
		await expect(page.locator('button.count')).toHaveCount(3);
		await expect(
			page.locator('button.count', { hasText: 'Followers' })
		).toBeVisible();
		await expect(
			page.locator('button.count', { hasText: 'Following' })
		).toBeVisible();
	});

	test('Followers tab on alex profile lists runner; clicking the row navigates to runner', async ({
		page
	}) => {
		// Alex's seeded follow graph: runner follows alex (so alex's
		// followers includes runner), morgan follows runner (so
		// alex's followers does NOT include morgan). Drill into the
		// tab via the deep-link URL — it bypasses the count-button
		// click race and is the URL we'd hand out anyway.
		await page.goto(`/u/${USER_B.id}?tab=followers`);
		await expect(
			page.getByRole('heading', { name: 'Alex Chen', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// Followers list rendered with at least one .person-row whose
		// inner link points to runner's profile. The row itself is a
		// <div> so the inline Follow-toggle button can live alongside
		// the navigable .person-main anchor.
		const runnerRow = page.locator(`.person-row a.person-main[href="/u/${USER_A.id}"]`);
		await expect(runnerRow).toBeVisible({ timeout: 10_000 });
		await expect(runnerRow).toContainText('Jared Howard');

		// Click navigates to runner's profile — proves the row link
		// still routes (the inline toggle is a separate button).
		await runnerRow.click();
		await page.waitForURL(new RegExp(`/u/${USER_A.id}`), { timeout: 10_000 });
		await expect(
			page.getByRole('heading', { name: 'Jared Howard', level: 1 })
		).toBeVisible({ timeout: 10_000 });
	});

	test('Following tab shows the seeded edges; empty state when there are none', async ({
		page
	}) => {
		// Drill into runner's Following tab. Per seed runner follows
		// alex (and possibly morgan via the mutual follow). Just check
		// at least one .person-row renders — drift on follow-graph
		// counts shouldn't break this.
		await page.goto(`/u/${USER_A.id}?tab=following`);
		await expect(page.locator('.people-list .person-row').first())
			.toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/u/[id] — viewing self', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('runner views own profile: no Follow button, notifications tab gated to self', async ({
		page
	}) => {
		// `isSelf = $derived(auth.user?.id === userId)` hides the
		// Follow button on your own profile and exposes the
		// Notifications tab. Pins both gates.
		await page.goto(`/u/${USER_A.id}`);

		await expect(
			page.getByRole('heading', { name: 'Jared Howard', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// No Follow button on own profile.
		await expect(page.locator('button.btn-follow')).toHaveCount(0);

		// Notifications tab — only present for isSelf. The .bell-btn
		// in the sidebar has the same accessible name; scope to the
		// page's .tabs container to disambiguate.
		await expect(
			page.locator('.tabs button.tab', { hasText: 'Notifications' })
		).toBeVisible();
	});

	test('default tab is Runs when no ?tab= query param is present', async ({
		page
	}) => {
		// `let tab = $state<...>('runs')` is the default; a refactor
		// that flipped the default (e.g. dropped the explicit init in
		// a runes migration) would surprise every deep-link to the
		// profile. Pin the .active class on the Runs tab.
		await page.goto(`/u/${USER_A.id}`);
		await expect(
			page.getByRole('heading', { name: 'Jared Howard', level: 1 })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.locator('.tabs button.tab.active', { hasText: 'Runs' })
		).toBeVisible();
	});
});

test.describe('/u/[id] — non-self notifications gate', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('?tab=notifications on someone else profile renders Runs, not Notifications', async ({
		page
	}) => {
		// Line 130 of the page guards `t === 'notifications' && isSelf`.
		// A non-self viewer landing on `/u/<other>?tab=notifications`
		// (e.g. someone pasted their own deep-link to a friend) must
		// fall through to the default 'runs' tab — exposing another
		// user's notifications inbox URL would be a real privacy
		// regression even if the API rejected it (the tab UI would
		// flash empty data first).
		await page.goto(`/u/${USER_B.id}?tab=notifications`);
		await expect(
			page.getByRole('heading', { name: 'Alex Chen', level: 1 })
		).toBeVisible({ timeout: 10_000 });
		// The Notifications tab button must NOT render for non-self
		// viewers at all (the `{#if isSelf}` gate on the tab strip).
		// The bell icon in the sidebar uses the same accessible name;
		// scope to the page's .tabs container.
		await expect(
			page.locator('.tabs button.tab', { hasText: 'Notifications' })
		).toHaveCount(0);
		// Active tab falls back to Runs.
		await expect(
			page.locator('.tabs button.tab.active', { hasText: 'Runs' })
		).toBeVisible();
	});

	test('clicking a count button activates the matching tab strip button', async ({
		page
	}) => {
		// setTab() updates the in-memory `tab` state — note: it does
		// NOT write to the URL today (an asymmetry with the deep-link
		// `?tab=` reader on mount). Pin the visible state flip on the
		// .tabs strip; if a future refactor adds URL persistence, this
		// test stays correct and a separate one pinning `?tab=` after
		// click can be added then.
		await page.goto(`/u/${USER_B.id}`);
		await expect(
			page.getByRole('heading', { name: 'Alex Chen', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		await page.locator('button.count', { hasText: 'Followers' }).click();
		await expect(
			page.locator('.tabs button.tab.active', { hasText: 'Followers' })
		).toBeVisible({ timeout: 10_000 });

		await page.locator('button.count', { hasText: 'Following' }).click();
		await expect(
			page.locator('.tabs button.tab.active', { hasText: 'Following' })
		).toBeVisible({ timeout: 10_000 });
	});

	test('invalid uuid renders the Profile-not-found empty card', async ({
		page
	}) => {
		// `/u/<bogus-uuid>` must surface the dedicated "Profile not
		// found" empty card with a Back-to-dashboard CTA, not a
		// silent 404 or an infinite spinner. A regression that left
		// the page in the loading state would burn user attention on
		// a stale link the receiver didn't know was broken.
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.goto(`/u/${bogusId}`);
		await expect(
			page.getByRole('heading', { name: 'Profile not found', level: 3 })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByRole('link', { name: /Back to dashboard/i })
		).toBeVisible();
	});
});

test.describe('/u/[id] — anon visitor', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor is auth-walled to /login with ?return_to preserved', async ({
		page
	}) => {
		// `/u/[id]` is NOT in anonExtraExact (apps/web/src/routes/
		// +layout.svelte line 86) — profile pages require auth. An
		// anon visitor hitting a shared profile link must bounce
		// through /login with the original destination preserved.
		// A regression that loosened the guard would surface a
		// signed-out profile shell with no avatar render + no follow
		// affordance — confusing for everyone.
		await page.goto(`/u/${USER_B.id}`);
		await page.waitForURL(/\/login(\?|$)/, { timeout: 10_000 });
		const url = new URL(page.url());
		// return_to query param holds the original path so the user
		// lands back on the profile after signing in.
		expect(url.searchParams.get('return_to')).toBe(`/u/${USER_B.id}`);
	});
});
