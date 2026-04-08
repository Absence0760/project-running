import { browser } from '$app/environment';
import { supabase } from '$lib/supabase';

interface User {
	id: string;
	email: string;
	display_name: string | null;
	avatar_url: string | null;
	parkrun_number: string | null;
	preferred_unit: 'km' | 'mi';
	subscription_tier: 'free' | 'premium';
}

function createAuthStore() {
	let user = $state<User | null>(null);
	let loggedIn = $state(false);
	let loading = $state(true);

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

	/**
	 * Email/password login for local development.
	 */
	async function demoLogin(email: string) {
		loading = true;
		try {
			// Try sign in first, fall back to sign up
			const password = 'testtest';
			let { error } = await supabase.auth.signInWithPassword({ email, password });
			if (error?.message?.includes('Invalid login') || error?.message?.includes('invalid_credentials')) {
				// User might not exist — try sign up
				const signup = await supabase.auth.signUp({ email, password });
				if (signup.error) {
					// If already registered, the password was wrong
					if (signup.error.message?.includes('already registered')) {
						throw new Error('Incorrect password. If you created this user via CLI with a different password, recreate it or use that password.');
					}
					throw signup.error;
				}
			} else if (error) {
				throw error;
			}
			await refreshSession();
		} finally {
			loading = false;
		}
	}

	async function refreshSession() {
		const { data: { session } } = await supabase.auth.getSession();
		if (session) {
			loggedIn = true;
			await fetchUser(session.user.id, session.user.email ?? '');
		} else {
			loggedIn = false;
			user = null;
		}
	}

	async function fetchUser(userId?: string, email?: string) {
		if (!userId) {
			const { data: { session } } = await supabase.auth.getSession();
			if (!session) return;
			userId = session.user.id;
			email = session.user.email ?? '';
		}

		// Try to fetch profile, create if missing
		const { data: profile } = await supabase
			.from('user_profiles')
			.select('*')
			.eq('id', userId)
			.single();

		if (profile) {
			user = {
				id: userId,
				email: email ?? '',
				display_name: profile.display_name,
				avatar_url: profile.avatar_url,
				parkrun_number: profile.parkrun_number,
				preferred_unit: profile.preferred_unit ?? 'km',
				subscription_tier: profile.subscription_tier ?? 'free',
			};
		} else {
			// Profile doesn't exist yet — create it
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
			};
		}
	}

	async function logout() {
		await supabase.auth.signOut();
		user = null;
		loggedIn = false;
	}

	// Listen for auth state changes
	if (browser) {
		supabase.auth.onAuthStateChange(async (event, session) => {
			if (session) {
				loggedIn = true;
				await fetchUser(session.user.id, session.user.email ?? '');
			} else {
				loggedIn = false;
				user = null;
			}
			loading = false;
		});

		// Initial session check
		supabase.auth.getSession().then(({ data: { session } }) => {
			if (session) {
				loggedIn = true;
				fetchUser(session.user.id, session.user.email ?? '');
			}
			loading = false;
		});
	}

	return {
		get user() { return user; },
		get loggedIn() { return loggedIn; },
		get loading() { return loading; },
		get isPremium() { return user?.subscription_tier === 'premium'; },
		signInWithGoogle,
		signInWithApple,
		demoLogin,
		fetchUser,
		refreshSession,
		logout,
	};
}

export const auth = createAuthStore();
