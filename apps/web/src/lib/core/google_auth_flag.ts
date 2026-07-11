/**
 * Fail-closed feature gate for Google sign-in.
 *
 * The Google OAuth button on /login only works once the `google` provider is
 * configured on the Supabase side; until then `signInWithOAuth({provider:
 * 'google'})` just surfaces an opaque provider error. This flag is the
 * client-visible signal for "Google auth is live": when `PUBLIC_GOOGLE_AUTH_ENABLED`
 * is not explicitly truthy the button renders a "coming soon" pill and its click
 * shows a friendly notice instead of starting a redirect. Unset / empty / "false"
 * / "0" → off, matching a fresh deploy where the provider isn't wired yet.
 *
 * Mirrors the coach_flag.ts fail-closed pattern; local dev + e2e turn it on via
 * `PUBLIC_GOOGLE_AUTH_ENABLED=true` in .env.development.
 */
import { env } from '$env/dynamic/public';

export function googleAuthEnabled(): boolean {
	const raw = (env.PUBLIC_GOOGLE_AUTH_ENABLED ?? '').trim().toLowerCase();
	return raw === '1' || raw === 'true' || raw === 'yes' || raw === 'on';
}
