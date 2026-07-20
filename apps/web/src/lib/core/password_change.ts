/// Step-up rule for changing an existing account's password
/// (`/settings/account`). A live access token alone must never be enough
/// to rotate the password: a token copied off an unlocked device, taken
/// by an XSS elsewhere in the authenticated app, or leaked from a debug
/// tool would otherwise let the holder lock the owner out permanently
/// (OWASP ASVS V2.1.14 / CWE-620). The caller proves possession of the
/// CURRENT password before the new one is written.
///
/// `/auth/reset` deliberately does NOT come through here — that flow is
/// already gated by a single-use recovery token mailed to the address on
/// file, which is the proof this function is asking for by another route.
///
/// Web-only for now. Mobile's `settings_account_screen.dart` dialog has
/// the same hole and wants the same rule ported, tracked in
/// `docs/product/followups.md § Mobile`; until then this is not a parity
/// pair (`auth_gates` remains the shared half).

import { checkPasswordPair, type PasswordPairReason } from './auth_gates';

export type PasswordChangeReason =
	| PasswordPairReason
	| 'current_missing'
	| 'current_invalid'
	| 'update_failed';

export type PasswordChangeResult =
	| { ok: true }
	| { ok: false; reason: PasswordChangeReason; detail?: string };

export interface PasswordChangeInput {
	currentPassword: string;
	newPassword: string;
	confirmPassword: string;
}

export interface PasswordChangeDeps {
	/// Resolves true only on a positive proof that `currentPassword` is
	/// the account's password today. Anything else — a rejected
	/// credential, a network failure, a missing email on the session —
	/// is false, and a throw is treated the same way.
	verifyCurrentPassword(currentPassword: string): Promise<boolean>;
	updatePassword(newPassword: string): Promise<{ error: string | null }>;
}

export async function changePassword(
	input: PasswordChangeInput,
	deps: PasswordChangeDeps,
): Promise<PasswordChangeResult> {
	const pair = checkPasswordPair(input.newPassword, input.confirmPassword);
	if (!pair.ok) return { ok: false, reason: pair.reason };

	if (input.currentPassword.length === 0) {
		return { ok: false, reason: 'current_missing' };
	}

	let verified = false;
	try {
		verified = await deps.verifyCurrentPassword(input.currentPassword);
	} catch {
		verified = false;
	}
	if (!verified) return { ok: false, reason: 'current_invalid' };

	const { error } = await deps.updatePassword(input.newPassword);
	if (error) return { ok: false, reason: 'update_failed', detail: error };
	return { ok: true };
}
