<script lang="ts">
	import { browser } from '$app/environment';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/supabase';

	let error = $state('');
	let loading = $state(false);
	let email = $state('');
	let password = $state('');
	let isSignUp = $state(false);

	$effect(() => {
		if (browser && !auth.loading && auth.loggedIn) {
			goto('/dashboard', { replaceState: true });
		}
	});

	async function handleGoogleSignIn() {
		error = '';
		loading = true;
		try {
			await auth.signInWithGoogle();
			// OAuth redirects to /auth/callback
		} catch (err) {
			error = err instanceof Error ? err.message : 'Sign in failed';
			loading = false;
		}
	}

	async function handleAppleSignIn() {
		error = '';
		loading = true;
		try {
			await auth.signInWithApple();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Sign in failed';
			loading = false;
		}
	}

	async function handleEmailSubmit(e: Event) {
		e.preventDefault();
		error = '';
		loading = true;
		try {
			if (isSignUp) {
				const { error: signUpError } = await supabase.auth.signUp({ email, password });
				if (signUpError) throw signUpError;
			} else {
				const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
				if (signInError) throw signInError;
			}
			// Wait for onAuthStateChange to set loggedIn, then navigate
			await auth.refreshSession();
			goto('/dashboard');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Authentication failed';
			loading = false;
		}
	}
</script>

<div class="login-page">
	<div class="login-card">
		<a href="/" class="logo">
			<span class="logo-icon">&#9654;</span> Run
		</a>

		<h1>{isSignUp ? 'Create an account' : 'Sign in to your account'}</h1>
		<p class="subtitle">Track your runs across all your devices.</p>

		{#if error}
			<div class="error">{error}</div>
		{/if}

		<div class="login-buttons">
			<button class="btn btn-google" onclick={handleGoogleSignIn} disabled={loading}>
				<svg class="oauth-icon" viewBox="0 0 24 24" width="20" height="20">
					<path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/>
					<path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
					<path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
					<path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
				</svg>
				Continue with Google
			</button>

			<button class="btn btn-apple" onclick={handleAppleSignIn} disabled={loading}>
				<svg class="oauth-icon" viewBox="0 0 24 24" width="20" height="20" fill="white">
					<path d="M17.05 20.28c-.98.95-2.05.88-3.08.4-1.09-.5-2.08-.48-3.24 0-1.44.62-2.2.44-3.06-.4C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
				</svg>
				Continue with Apple
			</button>
		</div>

		<div class="divider">
			<span>or continue with email</span>
		</div>

		<form class="email-form" onsubmit={handleEmailSubmit}>
			<input
				type="email"
				bind:value={email}
				placeholder="Email address"
				required
				autocomplete="email"
			/>
			<input
				type="password"
				bind:value={password}
				placeholder="Password"
				required
				minlength="6"
				autocomplete={isSignUp ? 'new-password' : 'current-password'}
			/>
			<button type="submit" class="btn btn-email" disabled={loading}>
				{#if loading}
					Signing {isSignUp ? 'up' : 'in'}...
				{:else}
					{isSignUp ? 'Sign Up' : 'Sign In'}
				{/if}
			</button>
		</form>

		<p class="toggle-mode">
			{isSignUp ? 'Already have an account?' : "Don't have an account?"}
			<button class="link-btn" onclick={() => { isSignUp = !isSignUp; error = ''; }}>
				{isSignUp ? 'Sign in' : 'Sign up'}
			</button>
		</p>

		<p class="terms">
			By signing in, you agree to our Terms of Service and Privacy Policy.
		</p>
	</div>
</div>

<style>
	.login-page {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		background: linear-gradient(150deg, #0F172A 0%, #1E1B4B 40%, #312E81 100%);
		position: relative;
		overflow: hidden;
	}

	.login-page::before {
		content: '';
		position: absolute;
		top: -30%;
		right: -20%;
		width: 60%;
		height: 160%;
		background: radial-gradient(ellipse, rgba(79, 70, 229, 0.2) 0%, transparent 70%);
		pointer-events: none;
	}

	.login-page::after {
		content: '';
		position: absolute;
		bottom: -20%;
		left: -10%;
		width: 50%;
		height: 120%;
		background: radial-gradient(ellipse, rgba(236, 72, 153, 0.1) 0%, transparent 70%);
		pointer-events: none;
	}

	.login-card {
		width: 100%;
		max-width: 24rem;
		padding: var(--space-2xl);
		text-align: center;
		background: rgba(255, 255, 255, 0.95);
		backdrop-filter: blur(20px);
		border-radius: var(--radius-xl);
		box-shadow: 0 24px 48px rgba(0, 0, 0, 0.2);
		position: relative;
		z-index: 1;
		color: #0F172A;
	}

	@media (prefers-color-scheme: dark) {
		.login-card {
			background: rgba(30, 41, 59, 0.85);
			border: 1px solid rgba(255, 255, 255, 0.08);
			box-shadow: 0 24px 48px rgba(0, 0, 0, 0.4);
			color: #F1F5F9;
		}
	}

	.logo {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		font-weight: 700;
		font-size: 1.5rem;
		background: var(--gradient-primary);
		-webkit-background-clip: text;
		-webkit-text-fill-color: transparent;
		background-clip: text;
		margin-bottom: var(--space-2xl);
	}

	h1 {
		font-size: 1.25rem;
		font-weight: 700;
		margin-bottom: var(--space-sm);
	}

	.subtitle {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-xl);
	}

	.error {
		background: var(--color-danger-light);
		border: 1px solid rgba(229, 57, 53, 0.3);
		color: var(--color-danger);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		margin-bottom: var(--space-md);
		text-align: left;
	}

	.login-buttons {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.btn {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-sm);
		width: 100%;
		padding: 0.875rem var(--space-lg);
		border-radius: var(--radius-md);
		font-size: 0.95rem;
		font-weight: 500;
		transition: all var(--transition-fast);
		cursor: pointer;
	}

	.btn:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.btn-google {
		background: var(--color-surface);
		border: 1.5px solid var(--color-border);
		color: var(--color-text);
	}

	.btn-google:hover:not(:disabled) {
		border-color: var(--color-text-secondary);
		box-shadow: var(--shadow-sm);
	}

	.btn-apple {
		background: #000;
		border: 1.5px solid #000;
		color: white;
	}

	.btn-apple:hover:not(:disabled) {
		background: #1a1a1a;
	}

	@media (prefers-color-scheme: dark) {
		.btn-apple {
			border-color: #334155;
		}
	}

	.oauth-icon {
		flex-shrink: 0;
	}

	.divider {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		margin: var(--space-xl) 0;
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}

	.divider::before,
	.divider::after {
		content: '';
		flex: 1;
		border-top: 1px solid var(--color-border);
	}

	.email-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		text-align: left;
	}

	input {
		width: 100%;
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		font-family: inherit;
		/* `input` doesn't inherit color from the parent in most user-agent
		   stylesheets — set both background and text colour explicitly so
		   the field is legible against the white login card in light mode
		   and the dark card in dark mode. */
		background: white;
		color: #0F172A;
	}

	@media (prefers-color-scheme: dark) {
		input {
			background: #1E293B;
			color: #F1F5F9;
		}
	}

	input:focus {
		outline: none;
		border-color: var(--color-primary);
	}

	.btn-email {
		background: var(--gradient-primary);
		color: white;
		border: none;
		font-weight: 600;
	}

	.btn-email:hover:not(:disabled) {
		opacity: 0.9;
		box-shadow: 0 4px 12px rgba(79, 70, 229, 0.3);
	}

	.toggle-mode {
		margin-top: var(--space-lg);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.link-btn {
		background: none;
		border: none;
		color: var(--color-primary);
		font-weight: 600;
		cursor: pointer;
		font-size: inherit;
		padding: 0;
	}

	.link-btn:hover {
		text-decoration: underline;
	}

	.terms {
		margin-top: var(--space-xl);
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
	}
</style>
