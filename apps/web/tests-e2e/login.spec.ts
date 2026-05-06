import { expect, test } from '@playwright/test';

import { signIn } from './fixtures/helpers';
import { USER_A } from './fixtures/users';

/**
 * /login — auth surface for the email-form path.
 *
 * The successful-sign-in flow is in cross-cutting/sign-in-out.spec.ts
 * because it spans /login → /dashboard and is the seam between
 * unauthenticated and authenticated app states. This file holds the
 * /login-only behaviours: failed sign-ins that stay on /login, the
 * page rendering for an anon visitor, and (in future rounds) the
 * OAuth-button affordances + reset-password flow.
 */

test.describe('/login', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('rejects an unknown email/password combo and stays on /login', async ({
		page
	}) => {
		await signIn(page, {
			...USER_A,
			email: 'noone@nowhere.test',
			password: 'wrong-password'
		});

		// Stay on /login (the form re-renders with an error banner).
		// We don't assert the error copy — it may shift; the URL
		// behaviour is the security contract.
		await expect(page).toHaveURL(/\/login/);
	});
});
