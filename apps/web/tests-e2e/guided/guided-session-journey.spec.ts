import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Guided-session discovery → preview → compare journey.
 *
 * "Guided runs" are scripted coach-voice workouts: each is a sequence of
 * timed cues that the *mobile* recorder fires via TTS as the runner
 * crosses each second mark (src/lib/training/guided_runs.ts). The WEB
 * surface is preview-only — it does NOT record or persist anything; the
 * library is built client-side from the i18n catalogue via
 * guidedRunLibrary(m). So this journey writes NO data: it walks the
 * full *discovery* arc a user actually takes, which the two existing
 * specs leave uncovered as an end-to-end flow.
 *
 * page.spec.ts pins index cards + detail render + back-to-coach links in
 * isolation; page-depth.spec.ts pins the index↔detail cue-count parity +
 * ascending-timeline data contracts. Neither walks the real multi-step
 * arc, and neither touches:
 *
 *   - the /coach guided RAIL as the discovery entry point, including its
 *     per-run INTENSITY badge (intensityFor in coach/+page.svelte) — a
 *     discovery dimension that exists ONLY on the rail, on no other
 *     surface, and is pinned by no other spec;
 *   - a signed-in user threading /coach → rail card → detail → Back to
 *     Coach (history pop) → "See the full library" → /guided → detail →
 *     Library → back to the *full library*, i.e. both entry doors plus
 *     a cross-run COMPARE (open one run, return, open a different run);
 *   - the whole library re-localizing end-to-end (coach rail heading +
 *     /guided hero + a detail script) when the active locale is German,
 *     proving the catalogue-driven library tracks the locale on every
 *     surface, not just the index.
 *
 * Grounding (assertion → source):
 *   - rail heading "Guided runs"            → en.ts:189 coachPage.guidedHeading
 *   - rail "See the full library"           → en.ts:193 coachPage.seeFullLibrary
 *   - rail intensity Easy/Tempo/Run-walk    → coach/+page.svelte:153-156 intensityFor
 *                                             + en.ts:169-171
 *   - rail cue count "8 cues"               → en.ts:192 coachPage.cueCount (plural)
 *   - /guided hero h1 "coach in your ear"   → en.ts:2978 guidedList.heroHeading
 *   - /guided card .duration "30 min"       → guided/+page.svelte:63 fmtMinutes
 *   - detail h1 = run.title                 → guided/[id]/+page.svelte:66
 *   - detail timeline rows / stamps         → guided/[id]/+page.svelte:80-88 fmtMmSs
 *   - "Back to Coach" / "Library" links     → guidedList.backToCoach en.ts:2976,
 *                                             guidedDetail.library en.ts:1882
 *   - German rail heading "Geführte Läufe"  → de.ts:180
 *   - German hero / script copy             → de.ts:2969 / de.ts:1878
 *
 * No DB cleanup: nothing is written. The only teardown is closing the
 * isolated context. Anon steps use a fresh anon context; the signed-in
 * step reuses USER_A's storage state (read-only).
 */

// The three runs in guidedRunLibrary(m), in catalogue order. titles +
// cue counts + the rail's id→intensity mapping are all from source.
const RUNS = [
	{
		id: 'easy-30',
		title: '30-Minute Easy Run',
		minutes: 30,
		cueCount: 8,
		lastStamp: '30:00',
		intensity: 'Easy'
	},
	{
		id: 'tempo-builder-25',
		title: '25-Minute Tempo Builder',
		minutes: 25,
		cueCount: 9,
		lastStamp: '25:00',
		intensity: 'Tempo'
	},
	{
		id: 'first-timer-15',
		title: 'First-Timer 15-Minute Run/Walk',
		minutes: 15,
		cueCount: 11,
		lastStamp: '15:00',
		intensity: 'Run/walk'
	}
] as const;

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

// initLocale() in i18n/store.svelte.ts reads localStorage['locale'] on
// first client mount and swaps the catalogue. Seeding it before the SPA
// boots drives the whole library into German on every surface.
function setLocaleGerman() {
	localStorage.setItem('locale', 'de');
}

test.describe('Guided session — discovery → preview → compare journey', () => {
	test.describe('anon visitor: full library → detail → compare a second run', () => {
		test.use({ storageState: { cookies: [], origins: [] } });

		test.beforeEach(async ({ context }) => {
			// Pre-accept the cookie banner: it is a role="dialog" that
			// floats over the page and would otherwise intercept the
			// card clicks we drive below.
			await context.addInitScript(setConsentAccepted);
		});

		test('browse the library, drill into one run end-to-end, then compare a different run', async ({
			page
		}) => {
			await test.step('land on the full /guided library', async () => {
				await page.goto('/guided');
				await expect(
					page.getByRole('heading', { level: 1, name: /coach in your ear/i })
				).toBeVisible();
				// Every catalogue run is a clickable card with its duration pill.
				const cards = page.locator('a.card');
				await expect(cards).toHaveCount(RUNS.length);
				for (const r of RUNS) {
					const card = page.locator(`a.card[href="/guided/${r.id}"]`);
					await expect(card.locator('.duration')).toHaveText(`${r.minutes} min`);
					await expect(card.getByRole('heading', { name: r.title })).toBeVisible();
				}
			});

			const first = RUNS[0]; // easy-30
			await test.step(`open "${first.title}" and read its full cue script`, async () => {
				await page.locator(`a.card[href="/guided/${first.id}"]`).click();
				await expect(page).toHaveURL(new RegExp(`/guided/${first.id}$`));
				await expect(
					page.getByRole('heading', { level: 1, name: first.title, exact: true })
				).toBeVisible();
				// Preview-only callout — web doesn't record; mobile runs it.
				await expect(page.getByText(/Open the mobile app to run this/)).toBeVisible();
				// The full script: exactly cueCount rows, opening at 0:00 and
				// closing at the run's full duration.
				const rows = page.locator('ol.timeline li.cue');
				await expect(rows).toHaveCount(first.cueCount);
				const stamps = page.locator('ol.timeline .at');
				await expect(stamps.first()).toHaveText('0:00');
				await expect(stamps.last()).toHaveText(first.lastStamp);
				// The detail's own cue-count chip agrees with the row count.
				await expect(page.locator('.script-head .cue-count')).toContainText(
					String(first.cueCount)
				);
			});

			await test.step('Library back link returns to the full library', async () => {
				await page.getByRole('link', { name: 'Library', exact: true }).click();
				await expect(page).toHaveURL(/\/guided$/);
				await expect(
					page.getByRole('heading', { level: 1, name: /coach in your ear/i })
				).toBeVisible();
			});

			const second = RUNS[2]; // first-timer-15 — a different duration + cue count
			await test.step(`compare a different run, "${second.title}"`, async () => {
				await page.locator(`a.card[href="/guided/${second.id}"]`).click();
				await expect(page).toHaveURL(new RegExp(`/guided/${second.id}$`));
				await expect(
					page.getByRole('heading', { level: 1, name: second.title, exact: true })
				).toBeVisible();
				// Distinct script length from the first run — proves the
				// detail page re-derives from the right library entry, not a
				// stale render of the previously-opened run.
				await expect(page.locator('ol.timeline li.cue')).toHaveCount(second.cueCount);
				await expect(page.locator('ol.timeline .at').last()).toHaveText(second.lastStamp);
				// The closing line of the first-timer script is the catalogue's
				// last cue — pin the actual spoken copy renders (en.ts:1928).
				await expect(page.getByText(/That was a real run/)).toBeVisible();
			});
		});

		test('the localized library renders in German across coach rail, /guided, and a detail', async ({
			context,
			page
		}) => {
			// Seed the locale before any navigation so initLocale() boots German.
			await context.addInitScript(setLocaleGerman);

			await test.step('/guided hero + cards localize', async () => {
				await page.goto('/guided');
				// German hero heading (de.ts:2969).
				await expect(
					page.getByRole('heading', { level: 1, name: /Ein Coach in deinem Ohr/i })
				).toBeVisible();
				// All three cards still render — the localized catalogue is
				// the same shape, only the strings differ.
				await expect(page.locator('a.card')).toHaveCount(RUNS.length);
				// German run title on the easy-30 card (de.ts:1883).
				await expect(
					page.locator('a.card[href="/guided/easy-30"]').getByRole('heading', {
						name: /lockerer Lauf/i
					})
				).toBeVisible();
			});

			await test.step('a German detail page renders the localized script header', async () => {
				await page.goto('/guided/easy-30');
				// German "The full script" (de.ts:1878).
				await expect(
					page.getByRole('heading', { name: /Das vollständige Skript/i })
				).toBeVisible();
				// Timing is locale-INDEPENDENT — the stamps stay mm:ss and the
				// row count is unchanged in German.
				await expect(page.locator('ol.timeline li.cue')).toHaveCount(8);
				await expect(page.locator('ol.timeline .at').last()).toHaveText('30:00');
			});
		});
	});

	test.describe('signed-in user: /coach rail → detail → back-to-coach → full library', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('discover from the coach guided rail, drill in, and round-trip both entry doors', async ({
			page
		}) => {
			await test.step('the coach rail surfaces the guided library with intensity badges', async () => {
				await page.goto('/coach');
				await expect(page).toHaveURL(/\/coach/);
				const rail = page.locator('aside.guided');
				await expect(
					rail.getByRole('heading', { name: 'Guided runs', exact: true })
				).toBeVisible({ timeout: 10_000 });
				// Each rail card carries an intensity badge — a discovery
				// dimension that lives ONLY on this rail (intensityFor maps
				// run id → label/tone). Pin the id→label mapping per run.
				for (const r of RUNS) {
					const card = rail.locator(`a.guided-card[href="/guided/${r.id}"]`);
					await expect(card).toBeVisible();
					await expect(card.locator('.duration')).toHaveText(`${r.minutes} min`);
					await expect(card.locator('.intensity')).toContainText(r.intensity);
					// The rail's own cue-count line (coachPage.cueCount plural).
					await expect(card.locator('.guided-card-meta')).toContainText(
						`${r.cueCount} cues`
					);
				}
			});

			await test.step('open a rail card → guided detail', async () => {
				await page.locator('aside.guided a.guided-card[href="/guided/easy-30"]').click();
				await expect(page).toHaveURL(/\/guided\/easy-30$/);
				await expect(
					page.getByRole('heading', { level: 1, name: '30-Minute Easy Run' })
				).toBeVisible();
			});

			await test.step('the detail back-link pops history to /coach (cameFromCoach)', async () => {
				// Arrived at the detail straight from /coach, so the detail's
				// afterNavigate latched cameFromCoach. Its back-link is labelled
				// "Library" (guidedDetail.library), but handleBack preventDefaults
				// and calls history.back(), returning to /coach rather than the
				// /guided list — the coach state survives.
				const backLink = page.locator('a.back-link');
				await expect(backLink).toBeVisible({ timeout: 10_000 });
				await expect(backLink).toHaveText(/Library/);
				await backLink.click();
				await expect(page).toHaveURL(/\/coach/);
			});

			await test.step('"See the full library" → /guided full library', async () => {
				await page.getByRole('link', { name: /See the full library/ }).click();
				await expect(page).toHaveURL(/\/guided$/);
				await expect(
					page.getByRole('heading', { level: 1, name: /coach in your ear/i })
				).toBeVisible();
				// All three runs present on the full library too.
				await expect(page.locator('a.card')).toHaveCount(RUNS.length);
			});

			await test.step('open a SECOND run from the full library and confirm its script', async () => {
				await page.locator('a.card[href="/guided/tempo-builder-25"]').click();
				await expect(page).toHaveURL(/\/guided\/tempo-builder-25$/);
				await expect(
					page.getByRole('heading', { level: 1, name: '25-Minute Tempo Builder' })
				).toBeVisible();
				await expect(page.locator('ol.timeline li.cue')).toHaveCount(9);
				await expect(page.locator('ol.timeline .at').last()).toHaveText('25:00');
				// Library link round-trips back to the full library.
				await page.getByRole('link', { name: 'Library', exact: true }).click();
				await expect(page).toHaveURL(/\/guided$/);
			});
		});
	});
});
