import { browser } from '$app/environment';
import { supabase } from '$lib/supabase';
import { setUnit } from '$lib/units.svelte';

interface User {
	id: string;
	email: string;
	display_name: string | null;
	avatar_url: string | null;
	parkrun_number: string | null;
	preferred_unit: 'km' | 'mi';
	subscription_tier: 'free' | 'pro' | 'lifetime';
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

	async function refreshSession() {
		const { data: { session } } = await supabase.auth.getSession();
		if (session) {
			loggedIn = true;
			loading = false;
			// Don't await — fetch profile in background so navigation isn't blocked
			fetchUser(session.user.id, session.user.email ?? '').catch(console.error);
		} else {
			loggedIn = false;
			user = null;
			loading = false;
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
			setUnit(user.preferred_unit);
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
			setUnit('km');
		}
	}

	async function logout() {
		await supabase.auth.signOut();
		user = null;
		loggedIn = false;
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
		get isPro() { return user?.subscription_tier === 'pro' || user?.subscription_tier === 'lifetime'; },
		signInWithGoogle,
		signInWithApple,
		fetchUser,
		refreshSession,
		logout,
	};
}

export const auth = createAuthStore();
