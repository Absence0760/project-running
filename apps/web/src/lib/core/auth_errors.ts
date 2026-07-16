import type { MessageKey } from '$lib/i18n/messages';

/// Friendly, actionable categories an auth failure maps to. Supabase's
/// raw `err.message` ("AuthApiException…", "Failed to fetch") is
/// developer jargon no end user should read — and it's unlocalized.
/// Classify into one of these and render the matching i18n message so
/// the banner can tell "wrong password" from "offline" from "that
/// email already has an account". Mobile mirrors the classification in
/// `apps/mobile_android/lib/auth_error.dart` — keep the branches in sync.
export type AuthErrorKind =
	| 'offline'
	| 'invalidCredentials'
	| 'rateLimited'
	| 'emailExists'
	| 'emailNotConfirmed'
	| 'weakPassword'
	| 'generic';

/// Classify an arbitrary auth error. Structural / duck-typed: reads the
/// error's `code` + `status` when present (supabase-js `AuthApiError`
/// carries both) and falls back to matching the message, so plain
/// `TypeError: Failed to fetch` network failures classify too.
export function classifyAuthError(error: unknown): AuthErrorKind {
	const shaped = error as { code?: unknown; status?: unknown; message?: unknown } | null;
	const code = typeof shaped?.code === 'string' ? shaped.code.toLowerCase() : null;
	const status = typeof shaped?.status === 'number' ? shaped.status : null;
	const msg = (
		typeof shaped?.message === 'string' ? shaped.message : String(error ?? '')
	).toLowerCase();

	if (msg.includes('failed to fetch') || msg.includes('networkerror') || msg.includes('load failed')) {
		return 'offline';
	}

	if (
		status === 429 ||
		(code !== null && code.includes('rate')) ||
		msg.includes('rate limit') ||
		msg.includes('too many requests')
	) {
		return 'rateLimited';
	}

	if (
		code === 'invalid_credentials' ||
		code === 'invalid_grant' ||
		msg.includes('invalid login credentials') ||
		msg.includes('invalid credentials')
	) {
		return 'invalidCredentials';
	}

	if (code === 'user_already_exists' || code === 'email_exists' || msg.includes('already registered')) {
		return 'emailExists';
	}

	if (code === 'email_not_confirmed' || msg.includes('email not confirmed')) {
		return 'emailNotConfirmed';
	}

	if (
		code === 'weak_password' ||
		msg.includes('weak password') ||
		msg.includes('password should be at least') ||
		msg.includes('password should contain at least')
	) {
		return 'weakPassword';
	}

	return 'generic';
}

const MESSAGE_KEYS: Record<AuthErrorKind, MessageKey> = {
	offline: 'login.errorOffline',
	invalidCredentials: 'login.errorInvalidCredentials',
	rateLimited: 'login.errorRateLimited',
	emailExists: 'login.errorEmailExists',
	emailNotConfirmed: 'login.errorEmailNotConfirmed',
	weakPassword: 'login.errorWeakPassword',
	generic: 'login.errorGeneric',
};

/// The i18n key for a classified kind. `login.errorWeakPassword` takes
/// a `{min}` param — pass `{ min: PASSWORD_MIN_LENGTH }` to `m()`.
export function authErrorMessageKey(kind: AuthErrorKind): MessageKey {
	return MESSAGE_KEYS[kind];
}
