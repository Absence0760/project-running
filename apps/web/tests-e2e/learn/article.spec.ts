import { expect, test } from '@playwright/test';

/**
 * `/learn/<slug>` — a single prerendered guide article.
 */

test.describe('/learn/road-running-101 (article)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('renders the article body, breadcrumb, and CTA block', async ({ page }) => {
		await page.goto('/learn/road-running-101');

		await expect(page.getByRole('heading', { name: 'Road running 101', level: 1 })).toBeVisible();
		// A known prose marker from the body.
		await expect(page.getByText('What road running actually is')).toBeVisible();

		// Breadcrumb up to the hub.
		const breadcrumb = page.getByRole('navigation', { name: 'Breadcrumb' });
		await expect(breadcrumb.getByRole('link', { name: 'Learn' })).toBeVisible();

		// The end-of-article CTA card.
		await expect(
			page.getByRole('heading', { name: 'Ready to do this in the app?' })
		).toBeVisible();
	});

	test('feature CTA points at its app route and the sign-up link is the signup variant', async ({
		page,
	}) => {
		await page.goto('/learn/road-running-101');

		// road-running-101's cta.feature is training-plans → /plans/new.
		await expect(page.getByRole('link', { name: 'Build a training plan' })).toHaveAttribute(
			'href',
			'/plans/new'
		);
		await expect(
			page.getByRole('link', { name: 'Create a free account' })
		).toHaveAttribute('href', '/login?signup=1');
	});
});
