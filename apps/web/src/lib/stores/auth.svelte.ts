import { browser } from '$app/environment';

interface User {
	id: string;
	email: string;
	display_name: string | null;
	avatar_url: string | null;
	parkrun_number: string | null;
	preferred_unit: 'km' | 'mi';
	subscription_tier: 'free' | 'premium';
}

interface Session {
	access_token: string;
	user: { id: string; email: string };
}

function getStoredToken(): string | null {
	if (!browser) return null;
	return localStorage.getItem('auth_token');
}

function createAuthStore() {
	let user = $state<User | null>(null);
	let session = $state<Session | null>(null);
	let loggedIn = $state(!!getStoredToken());
	let loading = $state(false);

	async function signInWithGoogle() {
		// TODO: Wire to Supabase OAuth
		// const { error } = await supabase.auth.signInWithOAuth({ provider: 'google' });
		throw new Error('Google sign-in not yet configured — use demo login for local testing');
	}

	async function signInWithApple() {
		// TODO: Wire to Supabase OAuth
		// const { error } = await supabase.auth.signInWithOAuth({ provider: 'apple' });
		throw new Error('Apple sign-in not yet configured — use demo login for local testing');
	}

	/**
	 * Demo login for local testing — bypasses OAuth.
	 * In production this would be removed.
	 */
	async function demoLogin(email: string) {
		loading = true;
		try {
			// Simulate a session with mock data
			const mockSession: Session = {
				access_token: 'demo-token',
				user: { id: 'demo-user-id', email },
			};
			session = mockSession;
			localStorage.setItem('auth_token', mockSession.access_token);
			loggedIn = true;
			await fetchUser();
		} finally {
			loading = false;
		}
	}

	async function fetchUser() {
		if (!loggedIn) return;
		// TODO: Fetch from Supabase user_profiles table
		// const { data } = await supabase.from('user_profiles').select('*').eq('id', session.user.id).single();
		user = {
			id: session?.user.id ?? 'demo-user-id',
			email: session?.user.email ?? 'demo@runapp.com',
			display_name: 'Jared Howard',
			avatar_url: null,
			parkrun_number: 'A123456',
			preferred_unit: 'km',
			subscription_tier: 'free',
		};
	}

	async function logout() {
		// TODO: await supabase.auth.signOut();
		localStorage.removeItem('auth_token');
		user = null;
		session = null;
		loggedIn = false;
	}

	// Restore session on load
	if (browser && getStoredToken()) {
		fetchUser();
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
		logout,
	};
}

export const auth = createAuthStore();
