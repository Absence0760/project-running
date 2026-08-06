import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * The six `em` font-sizes, resolved.
 *
 * `font_size_floor_guard.test.ts` count-pins them at six and says why: an `em`
 * compounds with whatever its ancestor resolved to, so no static scan can price
 * one, and a scan that guessed would be asserting on an ancestor chain nobody
 * measured — § 503's trap. § 525 left them there as "unmeasurable". They are not
 * unmeasurable, only un-measured-statically: `getComputedStyle` prices them
 * exactly, which is the same move § 525 already made for the media-query
 * override it could not see from source.
 *
 * Three of the six are Material Symbols glyph sizing (`ChallengeProgressBar`
 * 1.05em, `RunGearChips` 0.95em, `settings/gear` 1.1em) and are deliberately NOT
 * asserted here. An icon's `font-size` is the glyph's box — the `em` analogue of
 * the "text inside a graphic" class the floor guard already exempts — and it has
 * no reading size to protect, so holding one to a *legibility* floor would be
 * asserting the wrong thing and would teach the next reader that icons owe it.
 * They are classified in `font_size_floor_guard.test.ts` instead.
 *
 * The other three are real text and are what this spec measures: the coach
 * chat's inline `code` and its `pre code`, and the cookie notice's consent hint.
 */

const FLOOR_PX = 11;
const COACH_MESSAGE_ID = 'e1e1e1e1-0000-4000-8000-00000000f100';

async function resolved(
	page: import('@playwright/test').Page,
	selector: string
): Promise<number[]> {
	const sizes = await page
		.locator(selector)
		.evaluateAll((els) =>
			els.map((el) => parseFloat(getComputedStyle(el as HTMLElement).fontSize))
		);
	expect(sizes.length, `${selector} matched no element to measure`).toBeGreaterThan(0);
	return sizes;
}

async function expectAllAtFloor(
	page: import('@playwright/test').Page,
	selector: string
): Promise<void> {
	for (const px of await resolved(page, selector)) {
		expect(px, `${selector} resolves to ${px}px`).toBeGreaterThanOrEqual(FLOOR_PX);
	}
}

test.describe('em font-sizes resolve above the 11px micro-label floor', () => {
	test('the cookie notice consent hint (0.9em on a public page)', async ({ page }) => {
		// Logged out on purpose — the notice is a public page, which is what
		// makes this one of the cheap three to resolve.
		await page.goto('/cookie-notice');
		await expect(page.locator('.manage-consent-hint')).toBeVisible({ timeout: 10_000 });
		await expectAllAtFloor(page, '.manage-consent-hint');
	});

	test.describe('signed in', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test.beforeEach(async ({ context }) => {
			await context.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});
		});

		test('the coach chat markdown code spans (0.85em inside prose)', async ({ page }) => {
			// The chat renders whatever `coach_messages` holds for the caller's
			// no-plan thread, so an assistant message is all it takes to reach
			// both `code` rules — nothing here calls Anthropic. Seeded in the
			// test rather than the fixture so the row is torn down with it.
			const admin = getAdminClient();
			await admin.from('coach_messages').delete().eq('id', COACH_MESSAGE_ID);
			const { error } = await admin.from('coach_messages').insert({
				id: COACH_MESSAGE_ID,
				user_id: USER_A.id,
				plan_id: null,
				role: 'assistant',
				content: 'Try an `easy` effort.\n\n```\nweek 1: 5k easy\n```\n'
			});
			if (error) throw new Error(`type-floor em: could not seed a message — ${error.message}`);

			try {
				// `?plan=none` is the page's explicit no-plan sentinel. Without
				// it `resolvePlanId` defaults to the runner's ACTIVE plan, so the
				// chat opens that plan's thread and the seeded row — which lives
				// on the null-plan thread — never loads.
				await page.goto('/coach?plan=none');
				// Inline `code` and `pre code` are separate rules at the same
				// 0.85em; both must be on the page for this to mean anything.
				await expect(page.locator('.md :not(pre) > code').first()).toBeVisible({
					timeout: 15_000
				});
				await expect(page.locator('.md pre code').first()).toBeVisible();
				await expectAllAtFloor(page, '.md :not(pre) > code');
				await expectAllAtFloor(page, '.md pre code');
			} finally {
				await admin.from('coach_messages').delete().eq('id', COACH_MESSAGE_ID);
			}
		});

	});
});
