import { expect, test } from '@playwright/test';

/**
 * /safety/confirm — the anonymous safety-contact confirmation card must
 * follow the theme.
 *
 * The card hard-coded `background: #fff` while its text came from
 * `--color-text`, so in dark mode it painted near-white ink on a white card
 * and the whole page — the prompt, the SMS opt-in, the outcome — was
 * unreadable. The page has no navigation and no account behind it: the
 * emergency contact either reads this card or the runner has no confirmed
 * contact. It also kept a local copy of `.btn-primary` with `color: #fff`,
 * which app.css forbids for exactly this reason; in dark the primary fill
 * is a light peach, so white-on-peach failed too.
 *
 * Asserted against the resolved tokens rather than literal colours so the
 * test still means something if the palette moves.
 */
async function readCardColours(page: import('@playwright/test').Page) {
	return page.evaluate(() => {
		const card = document.querySelector('[data-testid="safety-confirm-card"]') as HTMLElement;
		const probe = document.createElement('div');
		probe.style.backgroundColor = 'var(--color-surface)';
		probe.style.color = 'var(--color-on-primary)';
		document.body.appendChild(probe);
		const probeStyle = getComputedStyle(probe);
		const surface = probeStyle.backgroundColor;
		const onPrimary = probeStyle.color;
		probe.remove();
		const cardStyle = getComputedStyle(card);
		const cta = card.querySelector('.btn-primary') as HTMLElement | null;
		return {
			cardBackground: cardStyle.backgroundColor,
			surface,
			onPrimary,
			ctaColour: cta ? getComputedStyle(cta).color : null,
		};
	});
}

test.describe('/safety/confirm — themed surface', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('dark: the card paints on the surface token, not white', async ({ page }) => {
		await page.emulateMedia({ colorScheme: 'dark' });
		await page.goto('/safety/confirm');
		await expect(page.getByTestId('safety-confirm-card')).toBeVisible({ timeout: 10_000 });

		const c = await readCardColours(page);
		expect(c.cardBackground).toBe(c.surface);
		expect(c.cardBackground).not.toBe('rgb(255, 255, 255)');
		// The CTA takes the shared button's on-primary ink, so it can't be
		// white text on the dark theme's light primary fill.
		expect(c.ctaColour).toBe(c.onPrimary);
	});

	test('light: the same token still resolves to the light surface', async ({ page }) => {
		await page.emulateMedia({ colorScheme: 'light' });
		await page.goto('/safety/confirm');
		await expect(page.getByTestId('safety-confirm-card')).toBeVisible({ timeout: 10_000 });

		const c = await readCardColours(page);
		expect(c.cardBackground).toBe(c.surface);
		expect(c.ctaColour).toBe(c.onPrimary);
	});
});
