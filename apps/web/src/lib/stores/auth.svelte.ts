import { browser } from '$app/environment';
import { supabase } from '$lib/core/supabase';
import { dropUserCache } from '$lib/settings/settings';
import { setUnit } from '$lib/format/units.svelte';
import { createReadyGate, isAuthSettled } from './auth_ready';

/// Upper bound a `ready()` waiter will block before resolving anyway,
/// matching the longest of the old per-page poll loops (~1–3 s). It is a
/// safety net for a wedged initial session check — settlement normally
/// flushes waiters far sooner.
const AUTH_READY_TIMEOUT_MS = 3000;

interface User {
	id: string;
	email: string;
	display_name: string | null;
	avatar_url: string | null;
	parkrun_number: string | null;
	preferred_unit: 'km' | 'mi';
	subscription_tier: 'free' | 'pro' | 'lifetime';
	/// Set to an ISO timestamp when RevenueCat fires `BILLING_ISSUE`
	/// (a renewal payment failed but the entitlement is still live
	/// during the store's grace period). Cleared on RENEWAL,
	/// UNCANCELLATION, EXPIRATION, or CANCELLATION. Drives the
	/// global "Update your card to keep Pro" banner so the user can
	/// fix the card before the grace period exhausts.
	billing_issue_at: string | null;
	/// ISO timestamp stamped when the post-signup onboarding wizard
	/// either completes or is dismissed. Null = user has not yet
	/// seen / dismissed the wizard. Migration 20261016_001
	/// backfilled every existing row to `now()` so the wizard never
	/// shows up retroactively — only new signups land with null.
	/// The auth-shell layout reads this to decide whether to
	/// redirect to /onboarding on login.
	onboarded_at: string | null;
}

function createAuthStore() {
	let user = $state<User | null>(null);
	let loggedIn = $state(false);
	let loading = $state(true);

	const gate = createReadyGate({
		isSettled: () => isAuthSettled({ loading, user, loggedIn }),
		timeoutMs: AUTH_READY_TIMEOUT_MS,
	});

	async function signInWithGoogle() {
		const { error } = await supabase.auth.signInWithOAuth({
			provider: 'google',
			options: { redirectTo: `${window.location.origin}/auth/callback` }
		});
		if (error) throw error;
	}

	async function signInWithApple() {
		const { error } = await supabase.auth.signInWithOAuth({
			provider: 'apple',
			options: { redirectTo: `${window.location.origin}/auth/callback` }
		});
		if (error) throw error;
	}

	async function refreshSession() {
		const { data: { session } } = await supabase.auth.getSession();
		if (session) {
			loggedIn = true;
			loading = false;
			// Awaited so callers like auth/callback can navigate after the
			// profile is hydrated. Trade-off: refreshSession resolves ~50–200 ms
			// later (one extra DB round-trip). The background fetch on
			// onAuthStateChange is intentionally not awaited (it fires on every
			// visibility change and we don't want to block there).
			await fetchUser(session.user.id, session.user.email ?? '').catch(console.error);
		} else {
			loggedIn = false;
			user = null;
			loading = false;
		}
		gate.markSettled();
	}

	async function fetchUser(userId?: string, email?: string) {
		if (!userId) {
			const { data: { session } } = await supabase.auth.getSession();
			if (!session) return;
			userId = session.user.id;
			email = session.user.email ?? '';
		}

		// Self-read goes through the `get_my_profile` SECURITY DEFINER RPC
		// because `subscription_tier`, `subscription_at`, and
		// `parkrun_number` are column-level revoked from authenticated
		// callers on `user_profiles` (migration 20260707_001).
		const { data: profile } = await supabase.rpc('get_my_profile');

		if (profile) {
			user = {
				id: userId,
				email: email ?? '',
				display_name: profile.display_name,
				avatar_url: profile.avatar_url,
				parkrun_number: profile.parkrun_number,
				preferred_unit: profile.preferred_unit ?? 'km',
				subscription_tier: profile.subscription_tier ?? 'free',
				billing_issue_at: profile.billing_issue_at ?? null,
				onboarded_at: profile.onboarded_at ?? null,
			};
			setUnit(user.preferred_unit);
		} else {
			// Profile doesn't exist yet — create it. `onboarded_at`
			// stays null so the layout's gate routes the new user to
			// /onboarding.
			await supabase.from('user_profiles').upsert({
				id: userId,
				preferred_unit: 'km',
				subscription_tier: 'free',
			});
			user = {
				id: userId,
				email: email ?? '',
				display_name: null,
				avatar_url: null,
				parkrun_number: null,
				preferred_unit: 'km',
				subscription_tier: 'free',
				billing_issue_at: null,
				onboarded_at: null,
			};
			setUnit('km');
		}
		gate.markSettled();
	}

	async function logout() {
		// `scope: 'local'` only invalidates this browser context. The
		// default ('global') would also revoke refresh tokens on the
		// user's mobile + watch sessions, which is rarely what the
		// user means when they click Sign out on the web — sign-out-
		// everywhere belongs on a separate "sign out of all devices"
		// affordance, not the default Sign out button.
		const priorUserId = user?.id;
		await supabase.auth.signOut({ scope: 'local' });
		user = null;
		loggedIn = false;
		// Drop the prior user's cached prefs so a subsequent sign-in
		// as a different user on the same browser can't read the
		// previous user's universal / device bags or replay their
		// queued offline writes against the wrong account.
		if (priorUserId) dropUserCache(priorUserId);
	}

	// Listen for auth state changes
	if (browser) {
		supabase.auth.onAuthStateChange((event, session) => {
			if (session) {
				loggedIn = true;
				fetchUser(session.user.id, session.user.email ?? '').catch(console.error);
			} else {
				loggedIn = false;
				user = null;
			}
			loading = false;
			gate.markSettled();
		});

		// Initial session check
		supabase.auth.getSession().then(({ data: { session } }) => {
			if (session) {
				loggedIn = true;
				fetchUser(session.user.id, session.user.email ?? '').catch(console.error);
			}
			loading = false;
			gate.markSettled();
		});
	}

	return {
		get user() { return user; },
		get loggedIn() { return loggedIn; },
		get loading() { return loading; },
		get isPro() { return user?.subscription_tier === 'pro' || user?.subscription_tier === 'lifetime'; },
		/// Resolves once auth has settled — a user row has hydrated, or
		/// the session is definitively anon. Replaces the open-coded
		/// `for (i<N) await sleep(50)` poll that pages used to guard their
		/// onMount fetch against the auth race. See auth_ready.ts.
		ready: gate.ready,
		signInWithGoogle,
		signInWithApple,
		fetchUser,
		refreshSession,
		logout,
	};
}

export const auth = createAuthStore();
