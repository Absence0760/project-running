import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * The sidebar account popover declares role="menu" (its trigger declares
 * aria-haspopup="menu"). Under ARIA that promises two things this test pins:
 *
 *   1. The menu OWNS role="menuitem" children — the exact condition axe's
 *      `aria-required-children` enforces. Before the fix the items were bare
 *      <a>/<button> with no menuitem role, so a screen reader announced a
 *      menu with zero operable items (issue #387, WCAG 4.1.2). We assert the
 *      menuitem semantics directly rather than pulling in @axe-core/playwright
 *      (not a project dependency); getByRole('menuitem') is empty before the
 *      fix and returns the four items after it.
 *
 *   2. The keyboard behaviour role="menu" implies — arrow-key / Home / End
 *      roving focus + Escape — matching the /history "Log" menu reference
 *      implementation (onLogMenuKeydown). The old popover only did Tab.
 *
 * Uses USER_A's saved storage state and never signs out, so the refresh
 * token in the saved file stays valid for the rest of the suite.
 */
test.describe('sidebar account popover — ARIA menu semantics', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('role="menu" owns the four menuitems (aria-required-children)', async ({ page }) => {
		await page.goto('/dashboard');
		await page.locator('.profile-btn').click();

		const menu = page.getByRole('menu', { name: 'Account menu' });
		await expect(menu).toBeVisible();

		// The menu must own operable menuitem children — the property
		// aria-required-children checks. Fails before the fix (0 menuitems).
		await expect(menu.getByRole('menuitem')).toHaveCount(4);
		await expect(menu.getByRole('menuitem', { name: 'View profile' })).toBeVisible();
		await expect(menu.getByRole('menuitem', { name: 'Athletes & coaches' })).toBeVisible();
		await expect(menu.getByRole('menuitem', { name: 'Settings' })).toBeVisible();
		await expect(menu.getByRole('menuitem', { name: 'Sign out' })).toBeVisible();
	});

	test('arrow keys / Home / End rove focus across the menuitems', async ({ page }) => {
		await page.goto('/dashboard');
		await page.locator('.profile-btn').click();

		const viewProfile = page.getByRole('menuitem', { name: 'View profile' });
		const coaching = page.getByRole('menuitem', { name: 'Athletes & coaches' });
		const settings = page.getByRole('menuitem', { name: 'Settings' });
		const signOut = page.getByRole('menuitem', { name: 'Sign out' });

		// Opening the popover moves focus to the first item.
		await expect(viewProfile).toBeFocused();

		await page.keyboard.press('ArrowDown');
		await expect(coaching).toBeFocused();

		await page.keyboard.press('ArrowDown');
		await expect(settings).toBeFocused();

		await page.keyboard.press('End');
		await expect(signOut).toBeFocused();

		// Wraps forward from the last item back to the first.
		await page.keyboard.press('ArrowDown');
		await expect(viewProfile).toBeFocused();

		// Wraps backward from the first item to the last.
		await page.keyboard.press('ArrowUp');
		await expect(signOut).toBeFocused();

		await page.keyboard.press('Home');
		await expect(viewProfile).toBeFocused();
	});

	test('Escape closes the menu and returns focus to the trigger', async ({ page }) => {
		await page.goto('/dashboard');
		await page.locator('.profile-btn').click();

		const menu = page.getByRole('menu', { name: 'Account menu' });
		await expect(menu).toBeVisible();

		await page.keyboard.press('Escape');
		await expect(menu).toBeHidden();
		await expect(page.locator('.profile-btn')).toBeFocused();
	});
});
