import { expect, test } from '@playwright/test';

import {
	RUNNER_PUBLIC_ROUTE_ID,
	RUNNER_PUBLIC_RUN_ID
} from './fixtures/seeded-data';
import { USER_A, USER_B } from './fixtures/users';

/**
 * Flows spec — third-batch e2e: cross-cutting flows whose regressions
 * span more than one component.
 *
 * Smoke covers "the page loads", security covers "you can't see what
 * you shouldn't", data-flow covers "writes round-trip", happy-paths
 * covers "the user accomplishes a thing", interactions covers UI
 * plumbing that survives reload. This spec catches regressions that
 * span MULTIPLE pages or sessions:
 *
 *   - Sidebar collapse — layout-level state, persists in localStorage,
 *     applied across every authenticated route.
 *   - Notifications fan-out — USER_B kudoses → USER_A's bell badge
 *     updates on next refresh. Cross-user real-world flow.
 *   - Comment reply — nested write on the engagement chain (kudos
 *     and top-level comments are already covered).
 *   - Star a route — owner-only write that round-trips through RLS
 *     and surfaces in the starred-only filter on /routes.
 *   - Inline-edit cancel — abandons the edit cleanly without a save.
 *
 * Note: a logout-via-popover test was considered but dropped — the
 * smoke spec already exercises the same `.profile-btn → Sign out`
 * popover via `helpers.signOut`, AND signing out within a test
 * revokes the refresh token in the shared storage-state file (yes,
 * even with `scope: 'local'`), which breaks every later USER_A
 * test. Anything that signs USER_A out has to run last.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('Sidebar collapse persists across reload', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('toggle collapses sidebar, reload preserves it, toggle again expands', async ({
		page
	}) => {
		// Layout writes the boolean to localStorage as `sidebar_collapsed`
		// = '1' / '0'. Mounts read it on first paint; the class
		// .sidebar.collapsed drives the visual narrow state. The
		// regression risk: the writer happens-before the reader on
		// first render OR the localStorage key drifts between writer
		// and reader (e.g. someone renames it on one side only).
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const sidebar = page.locator('nav.sidebar');
		await expect(sidebar).not.toHaveClass(/collapsed/);

		// The toggle button has aria-label "Collapse sidebar" / "Expand
		// sidebar" depending on state. Use the role+name pair so the
		// test reads as the user does.
		await page.getByRole('button', { name: 'Collapse sidebar' }).click();
		await expect(sidebar).toHaveClass(/collapsed/);

		// Reload — collapsed state must hold.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('nav.sidebar')).toHaveClass(/collapsed/);

		// Restore so subsequent tests don't render against a collapsed
		// sidebar (selectors that assume the expanded layout would
		// silently break).
		await page.getByRole('button', { name: 'Expand sidebar' }).click();
		await expect(page.locator('nav.sidebar')).not.toHaveClass(/collapsed/);
	});
});

test.describe('Cross-user kudos triggers a notification on the recipient', () => {
	test('alex kudos runner → runner sees bell badge increment + popover entry', async ({
		browser
	}) => {
		// Two browser contexts in one test — one as USER_B (alex),
		// one as USER_A (runner). The kudos write fires the
		// `notify_run_kudos` SECURITY DEFINER trigger from
		// migration 20260528_001 which inserts into `notifications`
		// with kind='kudos'. The layout's $effect on auth-ready
		// refreshes the notification store on next page-load, so
		// the runner reload picks it up. The bell badge text is the
		// unread count.
		//
		// USER_A's seed already carries the cross-user kudos +
		// comment from alex (on a NON-pinned public run), so the
		// starting unread count is non-zero. The test asserts a
		// delta of +1 rather than an absolute 1.
		const ctxAlex = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		const alex = await ctxAlex.newPage();
		const runner = await ctxRunner.newPage();

		try {
			// ── Snapshot runner's starting unread count ──
			await runner.goto('/dashboard');
			await runner.waitForLoadState('networkidle');
			// The badge only renders when unreadCount > 0; if zero,
			// .badge is absent. Safe-read via count() then text.
			const badgeBefore = runner.locator('.bell-wrap .badge');
			const beforeText = (await badgeBefore.count()) > 0
				? (await badgeBefore.textContent())?.trim() ?? '0'
				: '0';
			const before = parseInt(beforeText, 10);

			// ── Alex kudos runner via /share/run/ ──
			await alex.route('**/functions/v1/clip-public-track', (route) =>
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ points: [] })
				})
			);
			await alex.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			await alex.waitForLoadState('networkidle');
			const kudosBtn = alex.locator('.kudos-btn');
			await expect(kudosBtn).toBeVisible({ timeout: 10_000 });
			// If the run already had alex's kudos given (left over from
			// a prior failed run), rescind first to start clean.
			if (await kudosBtn.evaluate((el) => el.classList.contains('given'))) {
				await kudosBtn.click();
				await expect(kudosBtn).not.toHaveClass(/given/);
			}
			await kudosBtn.click();
			await expect(kudosBtn).toHaveClass(/given/);

			// ── Runner reloads /dashboard — bell should reflect +1 ──
			await runner.reload();
			await runner.waitForLoadState('networkidle');
			const badgeAfter = runner.locator('.bell-wrap .badge');
			await expect(badgeAfter).toBeVisible({ timeout: 10_000 });
			await expect(badgeAfter).toHaveText(String(before + 1), {
				timeout: 10_000
			});

			// ── Open popover; assert the kudos entry actually rendered
			//    with alex's identity in the verb. The popover is a
			//    role=dialog with the items list inside; verbFor
			//    composes "<display_name> gave kudos to your <km> km".
			//    Pinned public run is 9000m → "9.0 km".
			await runner.locator('.bell-wrap .bell-btn').click();
			const popover = runner.locator('.bell-wrap [role="dialog"]');
			await expect(popover).toBeVisible({ timeout: 5_000 });
			await expect(popover).toContainText('Alex Chen gave kudos to your 9.0 km');

			// "Mark all read" clears the badge.
			await runner.getByRole('button', { name: /Mark all read/ }).click();
			// After clear: badge element disappears (unreadCount === 0).
			await expect(runner.locator('.bell-wrap .badge')).toHaveCount(0, {
				timeout: 5_000
			});

			// ── Cleanup: alex rescinds the kudos so the seeded
			// "alex kudosed runner" relationship is back to whatever
			// state we found it in (here: not-kudosed on the pinned
			// public run, since the seed exempts that run from cross-
			// user engagement). ──
			await alex.locator('.kudos-btn').click();
			await expect(alex.locator('.kudos-btn')).not.toHaveClass(/given/);
		} finally {
			await ctxAlex.close();
			await ctxRunner.close();
		}
	});
});

test.describe('Comment reply (nested write)', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('alex posts comment, replies to it, both delete via parent cascade', async ({
		page
	}) => {
		// `parent_comment_id` references run_comments(id) ON DELETE
		// CASCADE (migration 20260522_001), so deleting the parent
		// removes the reply too. Nested write goes through the same
		// `postRunComment` helper with `parent_comment_id` set —
		// regression risk is a UI form binding that drops the parent
		// id, leaving the reply orphaned at the top level.
		const parentBody = uniqueText('e2e-parent');
		const replyBody = uniqueText('e2e-reply');

		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);

		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// Post the parent comment.
		const composer = page.locator('form.composer textarea');
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await composer.fill(parentBody);
		await page.locator('form.composer button[type="submit"]').click();
		await expect(composer).toHaveValue('', { timeout: 10_000 });

		// Locate the new comment by its body — `.comment` article with
		// the matching <p>. The Reply trigger is a `.link-btn` inside
		// the same article.
		const parentArticle = page
			.locator('article.comment')
			.filter({ has: page.locator('p', { hasText: parentBody }) });
		await expect(parentArticle).toBeVisible();

		// Click "Reply" inside that article to open the inline form.
		await parentArticle.getByRole('button', { name: 'Reply', exact: true }).click();
		const replyInput = parentArticle.locator('form.reply-form input');
		await expect(replyInput).toBeVisible();
		await replyInput.fill(replyBody);
		await parentArticle
			.locator('form.reply-form button[type="submit"]')
			.click();

		// After submit: reply appears under .replies inside the parent
		// article, and the form closes.
		await expect(replyInput).toHaveCount(0, { timeout: 10_000 });
		const replyP = parentArticle.locator('.replies .reply p', {
			hasText: replyBody
		});
		await expect(replyP).toBeVisible();

		// Cleanup: deleting the parent cascades the reply.
		await parentArticle
			.getByRole('button', { name: 'Delete comment' })
			.click();
		await expect(
			page.locator('article.comment', {
				has: page.locator('p', { hasText: parentBody })
			})
		).toHaveCount(0, { timeout: 5_000 });
	});
});

test.describe('Star a route persists across reload + filter', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('star on route detail, reload persists, starred-only filter shows it, unstar restores', async ({
		page
	}) => {
		// Star toggles `routes.is_starred` via setRouteStar; the route
		// detail page renders a .star-btn button (owner-only, gated on
		// isOwner). Pinned RUNNER_PUBLIC_ROUTE_ID seeds with no star.
		// The starred-only filter on /routes hides everything that
		// isn't starred — so a successful round-trip + reload puts the
		// route in that view. Catches regressions in either the write
		// (RLS dropping the update) or the list re-fetch (filter
		// reading a stale cache).
		//
		// Cleanup unstars at the end so the seed state is preserved.
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		const starBtn = page.locator('button.star-btn');
		await expect(starBtn).toBeVisible({ timeout: 10_000 });
		await expect(starBtn).not.toHaveClass(/starred/);

		await starBtn.click();
		await expect(starBtn).toHaveClass(/starred/);

		// Reload — server-side state must agree.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('button.star-btn')).toHaveClass(/starred/, {
			timeout: 10_000
		});

		// Visit /routes; flip the starred-only filter; the pinned
		// route should appear in the narrowed list.
		await page.goto('/routes');
		await page.waitForLoadState('networkidle');
		await page.getByRole('button', { name: /Show starred only/ }).click();
		await expect(
			page.locator(`.route-card[href$="${RUNNER_PUBLIC_ROUTE_ID}"]`)
		).toBeVisible({ timeout: 10_000 });

		// Cleanup: clear the filter + unstar so the next test sees a
		// clean slate. (filteredRoutes is in localStorage as
		// `routes_filters_v1`; the filter test in interactions.spec.ts
		// would otherwise inherit starredOnly=true.)
		await page.getByRole('button', { name: /Show starred only/ }).click();
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');
		await page.locator('button.star-btn').click();
		await expect(page.locator('button.star-btn')).not.toHaveClass(/starred/);
	});
});

test.describe('Inline edit on /runs/[id] — Cancel reverts unsaved changes', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('typing into title then clicking Cancel restores the original heading', async ({
		page
	}) => {
		// The data-flow spec covers Save → reload → restore. This test
		// covers the Cancel branch: the in-flight $state never round-
		// trips to Supabase; the heading still reads the persisted
		// metadata.title after Cancel. Catches a regression where
		// Cancel accidentally writes (e.g. a refactor wiring Save +
		// Cancel to the same handler).
		const originalTitle = 'E2E demo public run';
		const draft = uniqueText('e2e-cancel-draft');

		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// Confirm starting state.
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible({ timeout: 10_000 });

		await page.locator('button[title="Edit"]').first().click();
		await page.locator('input.edit-input').fill(draft);
		await page.getByRole('button', { name: 'Cancel', exact: true }).click();

		// Editor closes immediately and the heading reads the original
		// title — no save fired.
		await expect(page.locator('input.edit-input')).toHaveCount(0);
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible();

		// Reload to confirm nothing landed on the row server-side.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible();
	});
});
