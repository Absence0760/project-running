import { checkPasswordPair, type PasswordPairReason } from './auth_gates';

/// The slice of `supabase.auth` this flow needs. Narrowed to an interface
/// so the orchestration is unit-testable with a fake client (the real
/// `GoTrueClient` satisfies it).
export interface ReauthPasswordClient {
	reauthenticate(): Promise<{ error: { message: string } | null }>;
	updateUser(attrs: {
		password: string;
		nonce: string;
	}): Promise<{ error: { message: string } | null }>;
}

export type PasswordChangeOutcome =
	| { ok: true }
	| { ok: false; reason: 'pair'; pairReason: PasswordPairReason }
	| { ok: false; reason: 'nonce_required' }
	| { ok: false; reason: 'update_failed'; message: string };

/// Step-up gate for changing the sign-in password.
///
/// WHY: a live access token must NOT be enough to seize an account. A
/// token copied from an unlocked device, exfiltrated by XSS, or leaked
/// from a debug session can drive `updateUser({ password })` off the
/// ambient session with zero knowledge of the current password. This
/// gates the update on a reauthentication nonce e-mailed to the
/// account's verified address (GoTrue `secure_password_change` +
/// `reauthenticate()`) — proof the caller controls the inbox, which a
/// stolen token does not confer. The nonce path (not a current-password
/// re-verify) is deliberate: it also lets an OAuth-only account that has
/// no password set one, and GoTrue verifies the nonce server-side so the
/// gate can't be skipped by calling the API directly.
///
/// Fail-closed: with no nonce the update is never attempted. GoTrue is
/// the authority on nonce validity; this only guarantees the client
/// never bypasses the step-up.
export async function changePasswordWithReauth(
	client: ReauthPasswordClient,
	input: { newPassword: string; confirmPassword: string; nonce: string },
): Promise<PasswordChangeOutcome> {
	const pair = checkPasswordPair(input.newPassword, input.confirmPassword);
	if (!pair.ok) return { ok: false, reason: 'pair', pairReason: pair.reason };

	const nonce = input.nonce.trim();
	if (nonce.length === 0) return { ok: false, reason: 'nonce_required' };

	const { error } = await client.updateUser({ password: input.newPassword, nonce });
	if (error) return { ok: false, reason: 'update_failed', message: error.message };
	return { ok: true };
}

export type ReauthRequestOutcome = { ok: true } | { ok: false; message: string };

/// Ask GoTrue to e-mail the account a reauthentication nonce. Kicks off
/// the step-up above; the user then enters the code into the same form.
export async function requestReauthNonce(
	client: Pick<ReauthPasswordClient, 'reauthenticate'>,
): Promise<ReauthRequestOutcome> {
	const { error } = await client.reauthenticate();
	if (error) return { ok: false, message: error.message };
	return { ok: true };
}
