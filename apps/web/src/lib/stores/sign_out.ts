export type SignOutScope = 'local' | 'global';

export interface SignOutError {
	message?: string;
}

export interface AuthSignOutClient {
	signOut(options: { scope: SignOutScope }): Promise<{ error: SignOutError | null }>;
}

/// Single seam the local "Sign out" and the "Sign out everywhere" affordances
/// both route through, so the only thing that differs between them is `scope`.
/// `local` invalidates just this browser context; `global` also revokes every
/// refresh token server-side (mobile + watch + other browsers) — the action a
/// user reaches for when they suspect a token was exfiltrated. Returns the
/// provider error (or null) rather than throwing so each caller can decide
/// whether to swallow it (local Sign out) or fail closed (global).
export async function signOutWithScope(
	client: AuthSignOutClient,
	scope: SignOutScope,
): Promise<SignOutError | null> {
	const { error } = await client.signOut({ scope });
	return error;
}
