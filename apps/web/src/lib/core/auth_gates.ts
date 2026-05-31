/// Sign-up gating logic for the `/login` page. Shared between the
/// email/password submit handler and every OAuth provider button so
/// the same legal consent applies regardless of how the user creates
/// the account.
///
/// GDPR Article 8 requires parental consent for users under 16 in the
/// EU — we ask the user to self-declare 16+. The Terms / Privacy
/// acceptance gate covers ToS + Privacy Policy. Both apply whenever
/// the form is in sign-up mode; sign-in mode (existing account) is
/// unaffected.
///
/// Mobile mirrors this logic in
/// `apps/mobile_android/lib/screens/sign_up_screen.dart` (`_checkGates`).
/// The mobile sign-up screen is separate from the sign-in screen, so
/// the gates always apply there; on web the screen is shared and
/// the gate has to be conditional on `isSignUp`.

export type SignUpGateResult =
	| { ok: true }
	| { ok: false; error: string };

export const SIGNUP_GATE_ERROR_ADULT =
	'Please confirm you are 16 or older to continue.';
export const SIGNUP_GATE_ERROR_TERMS =
	'Please accept the Terms of Service and Privacy Policy to continue.';

/// Pure pre-flight check before any account-creation path (email +
/// password, Google OAuth, future Apple OAuth). When `isSignUp` is
/// false the gates don't apply — sign-in to an existing account
/// doesn't need fresh consent.
export function checkSignUpGates(
	isSignUp: boolean,
	confirmAdult: boolean,
	acceptTerms: boolean,
): SignUpGateResult {
	if (!isSignUp) return { ok: true };
	if (!confirmAdult) return { ok: false, error: SIGNUP_GATE_ERROR_ADULT };
	if (!acceptTerms) return { ok: false, error: SIGNUP_GATE_ERROR_TERMS };
	return { ok: true };
}
