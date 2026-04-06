<script lang="ts">
	function handleGoogleSignIn() {
		// TODO: supabase.auth.signInWithOAuth({ provider: 'google' })
	}

	function handleAppleSignIn() {
		// TODO: supabase.auth.signInWithOAuth({ provider: 'apple' })
	}
</script>

<div class="login-page">
	<div class="login-card">
		<a href="/" class="logo">
			<span class="logo-icon">&#9654;</span> Run
		</a>

		<h1>Sign in to your account</h1>
		<p class="subtitle">Track your runs across all your devices.</p>

		<div class="login-buttons">
			<button class="btn btn-google" onclick={handleGoogleSignIn}>
				<svg class="oauth-icon" viewBox="0 0 24 24" width="20" height="20">
					<path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/>
					<path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
					<path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
					<path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
				</svg>
				Continue with Google
			</button>

			<button class="btn btn-apple" onclick={handleAppleSignIn}>
				<svg class="oauth-icon" viewBox="0 0 24 24" width="20" height="20" fill="white">
					<path d="M17.05 20.28c-.98.95-2.05.88-3.08.4-1.09-.5-2.08-.48-3.24 0-1.44.62-2.2.44-3.06-.4C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
				</svg>
				Continue with Apple
			</button>
		</div>

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
		background: var(--color-bg);
	}

	.login-card {
		width: 100%;
		max-width: 24rem;
		padding: var(--space-2xl);
		text-align: center;
	}

	.logo {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		font-weight: 700;
		font-size: 1.5rem;
		color: var(--color-primary);
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
	}

	.btn-google {
		background: var(--color-surface);
		border: 1.5px solid var(--color-border);
		color: var(--color-text);
	}

	.btn-google:hover {
		border-color: var(--color-text-secondary);
		box-shadow: var(--shadow-sm);
	}

	.btn-apple {
		background: #000;
		border: 1.5px solid #000;
		color: white;
	}

	.btn-apple:hover {
		background: #1a1a1a;
	}

	.oauth-icon {
		flex-shrink: 0;
	}

	.terms {
		margin-top: var(--space-xl);
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
	}
</style>
