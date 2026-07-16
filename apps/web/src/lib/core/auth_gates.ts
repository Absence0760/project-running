/// Sign-up gating logic for the `/login` page, plus the password-pair
/// check shared by every surface that mints a password. Shared between
/// the email/password submit handler and every OAuth provider button so
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

/// A stable, locale-independent reason a sign-up gate failed. The
/// caller resolves it to a localized message via `m('login.gateAdult')`
/// / `m('login.gateTerms')` so the error isn't hard-coded English.
export type SignUpGateReason = 'adult' | 'terms';

export type SignUpGateResult =
	| { ok: true }
	| { ok: false; reason: SignUpGateReason };

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
	if (!confirmAdult) return { ok: false, reason: 'adult' };
	if (!acceptTerms) return { ok: false, reason: 'terms' };
	return { ok: true };
}

/// GoTrue's default minimum. `config.toml` sets no
/// `minimum_password_length`, so a shorter password is rejected by the
/// auth server anyway — checking here turns an opaque API error into a
/// field-level message.
export const MIN_PASSWORD_LENGTH = 6;

/// A stable, locale-independent reason a password pair was rejected.
/// The caller resolves it to a localized message — the keys differ per
/// surface (`login.*` on sign-up, `authReset.*` on reset), so the
/// mapping stays at the call site rather than in here.
export type PasswordPairReason = 'too_short' | 'mismatch';

export type PasswordPairResult =
	| { ok: true }
	| { ok: false; reason: PasswordPairReason };

/// Pure check for the two password inputs on any surface that MINTS a
/// password — sign-up and password reset both do, and both must ask
/// twice. A typo in a single-field sign-up is silently baked into the
/// account: the user confirms their email, then can never sign in,
/// because the stored hash is of a string they never meant to type.
/// That failure is invisible to us and indistinguishable from a
/// forgotten password to them.
///
/// Neither side is trimmed. Leading / trailing whitespace is a real
/// part of a password, and it is exactly the typo class this catches —
/// trimming would let `secret ` and `secret` through as equal and store
/// whichever the caller happened to pass first.
///
/// Length is checked before equality so two matching-but-too-short
/// entries report the fixable problem rather than a mismatch the user
/// can't see.
export function checkPasswordPair(
	password: string,
	confirmPassword: string,
): PasswordPairResult {
	if (password.length < MIN_PASSWORD_LENGTH) return { ok: false, reason: 'too_short' };
	if (password !== confirmPassword) return { ok: false, reason: 'mismatch' };
	return { ok: true };
}
