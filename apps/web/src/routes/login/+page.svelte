<script lang="ts">
	import { browser } from '$app/environment';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import { checkSignUpGates } from '$lib/core/auth_gates';

	let error = $state('');
	let info = $state('');
	let loading = $state(false);
	let email = $state('');
	let password = $state('');
	let isSignUp = $state($page.url.searchParams.get('signup') === '1');
	let isReset = $state($page.url.searchParams.get('reset') === '1');
	let confirmAdult = $state(false);
	let acceptTerms = $state(false);
	let hydrated = $state(false);
	// Snapshot return_to at mount, BEFORE either the post-sign-in $effect
	// or the explicit handler goto can fire. The previous version re-read
	// $page.url.searchParams every call, but the $effect's goto mutates
	// the URL to the return_to target on the same tick — caching once
	// removes the race.
	let returnToOnMount = $state<string>('/dashboard');
	onMount(() => {
		hydrated = true;
		const raw = $page.url.searchParams.get('return_to');
		returnToOnMount = raw && raw.startsWith('/') ? raw : '/dashboard';
	});

	function safeReturnTo(): string {
		return returnToOnMount;
	}

	$effect(() => {
		if (browser && !auth.loading && auth.loggedIn) {
			goto(safeReturnTo(), { replaceState: true });
		}
	});

	async function handleGoogleSignIn() {
		error = '';
		// Google OAuth creates an account on first sign-in, so the
		// sign-up gates (16+ + ToS / Privacy acceptance) have to apply
		// the same way as the email/password sign-up path. Mobile's
		// `sign_up_screen._signInWithGoogle` mirrors this via
		// `_checkGates()`. Sign-in to an existing account skips the
		// gates — `checkSignUpGates` returns ok when `isSignUp` is
		// false.
		const gate = checkSignUpGates(isSignUp, confirmAdult, acceptTerms);
		if (!gate.ok) {
			error = gate.error;
			return;
		}
		// Stash the consent timestamps so /auth/callback can stamp
		// them server-side after the OAuth redirect — OAuth's first-
		// sign-in flow can't pass options.data into raw_user_meta_data,
		// so the post-callback RPC is the canonical capture point.
		// See migration 20260929_001 + audit/gdpr (2026-05-25) Critical.
		if (isSignUp) {
			const stamp = new Date().toISOString();
			try {
				sessionStorage.setItem('age_confirmed_at', stamp);
				sessionStorage.setItem('terms_accepted_at', stamp);
			} catch (_) {
				/* Safari private-mode disables sessionStorage — the
				   /auth/callback fallback redirects to /auth/confirm-age
				   when the stash is missing. */
			}
		}
		loading = true;
		try {
			await auth.signInWithGoogle();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Sign in failed';
			loading = false;
		}
	}

	function handleAppleSignIn() {
		// Apple OAuth isn't wired up on the Supabase side yet — calling
		// signInWithApple just surfaces an opaque provider error. Tell
		// the user clearly and point them at the working options. When
		// Apple OAuth ships, copy the `handleGoogleSignIn` gate
		// pattern so the sign-up checkboxes apply to Apple too.
		error = 'Sign in with Apple is coming soon. For now, please use Google or email.';
	}

	async function handleEmailSubmit(e: Event) {
		e.preventDefault();
		error = '';
		info = '';
		loading = true;
		try {
			if (isReset) {
				// Supabase tacks the recovery token on the hash; the wording
				// is intentionally non-committal so this isn't a user-
				// enumeration oracle.
				const redirectTo = `${window.location.origin}/auth/reset`;
				const { error: resetError } = await supabase.auth.resetPasswordForEmail(email, {
					redirectTo
				});
				if (resetError) throw resetError;
				info = "If that email is registered, we've sent a password reset link.";
				email = '';
			} else if (isSignUp) {
				const gate = checkSignUpGates(isSignUp, confirmAdult, acceptTerms);
				if (!gate.ok) throw new Error(gate.error);
				const stamp = new Date().toISOString();
				const { error: signUpError } = await supabase.auth.signUp({
					email,
					password,
					options: {
						// raw_user_meta_data carries the consent
						// timestamps at the auth layer; the server-side
						// stamp on user_profiles happens via the RPC
						// below. See migration 20260929_001 + audit/gdpr.
						data: { age_confirmed_at: stamp, terms_accepted_at: stamp },
					},
				});
				if (signUpError) throw signUpError;
				// Server-side consent stamp on user_profiles. Fire-
				// and-forget — if email confirmation is pending and no
				// JWT exists yet, the /auth/callback fallback retries.
				try {
					await supabase.rpc('confirm_age_and_terms');
				} catch (_) {
					/* Retry path covers the failure. */
				}
				await auth.refreshSession();
				goto(safeReturnTo());
			} else {
				const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
				if (signInError) throw signInError;
				await auth.refreshSession();
				goto(safeReturnTo());
			}
		} catch (err) {
			error = err instanceof Error ? err.message : 'Authentication failed';
		} finally {
			loading = false;
		}
	}

	let kicker = $derived(isReset ? 'Forgot your password?' : isSignUp ? 'Join Threkir' : 'Welcome back');
	let headline = $derived(
		isReset ? 'Reset your password' : isSignUp ? 'Create an account' : 'Sign in to your account'
	);
	let subtitle = $derived(
		isReset
			? "Enter your email and we'll send you a reset link."
			: isSignUp
				? 'Track your runs across every device. Free forever.'
				: 'Pick up where you left off — your runs are waiting.'
	);
</script>

<div class="login-page">
	<aside class="brand-pane" aria-hidden="true">
		<a href="/" class="brand-logo">
			<img src="/icon-192.png" alt="" class="brand-mark" />
			<span class="brand-name">Threkir</span>
		</a>
		<div class="brand-copy">
			<p class="brand-kicker">{kicker}</p>
			<h2 class="brand-headline">Track every run. Plan every race. Bring your club along.</h2>
			<ul class="brand-bullets">
				<li>
					<span class="bullet-dot" aria-hidden="true"></span>
					<span>Map, splits, elevation, HR zones — the basics, polished.</span>
				</li>
				<li>
					<span class="bullet-dot" aria-hidden="true"></span>
					<span>Plans that adapt: VDOT, Riegel, week-by-week editable preview.</span>
				</li>
				<li>
					<span class="bullet-dot" aria-hidden="true"></span>
					<span>Clubs, kudos, comments. Private by default; share what you choose.</span>
				</li>
			</ul>
		</div>
		<p class="brand-foot">Free forever. Add Pro to unlock club perks, the coach, and bulk imports.</p>
	</aside>

	<main class="form-pane">
		<div class="login-card">
			<a href="/" class="logo logo-mobile">
				<img src="/icon-192.png" alt="" class="logo-mark" />
				<span>Threkir</span>
			</a>

			<p class="kicker">{kicker}</p>
			<h1>{headline}</h1>
			<p class="subtitle">{subtitle}</p>

			{#if error}
				<div class="error" role="alert">{error}</div>
			{/if}
			{#if info}
				<div class="info" role="status" aria-live="polite">{info}</div>
			{/if}

			{#if !isReset}
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
						<span class="soon-pill">Soon</span>
					</button>
				</div>

				<div class="divider">
					<span>or continue with email</span>
				</div>
			{/if}

			<form class="email-form" onsubmit={handleEmailSubmit}>
				<!--
					audit/accessibility High (May 2026): inputs used
					placeholder-only — disappears as the user types and
					screen readers announce just "edit text" without a
					persistent name. Add a visually-hidden <label> via
					.visually-hidden (defined in app.css). aria-label
					alone is also valid per WCAG 3.3.2 but explicit
					<label for> is the most compatible form.
				-->
				<label for="login-email" class="visually-hidden">Email address</label>
				<input
					id="login-email"
					type="email"
					bind:value={email}
					placeholder="Email address"
					required
					autocomplete="email"
				/>
				{#if !isReset}
					<label for="login-password" class="visually-hidden">Password</label>
					<input
						id="login-password"
						type="password"
						bind:value={password}
						placeholder="Password"
						required
						minlength="6"
						autocomplete={isSignUp ? 'new-password' : 'current-password'}
					/>
				{/if}
				{#if isSignUp}
					<label class="signup-check">
						<input type="checkbox" bind:checked={confirmAdult} required />
						<span>I confirm I am 16 years of age or older.</span>
					</label>
					<label class="signup-check">
						<input type="checkbox" bind:checked={acceptTerms} required />
						<span>
							I have read and agree to the
							<a href="/terms" target="_blank" rel="noopener noreferrer">Terms of Service</a>
							and
							<a href="/privacy" target="_blank" rel="noopener noreferrer">Privacy Policy</a>.
						</span>
					</label>
				{/if}
				<button
					type="submit"
					class="btn btn-email"
					disabled={!hydrated || loading || (isSignUp && (!confirmAdult || !acceptTerms))}
				>
					{#if loading}
						{#if isReset}Sending...{:else}Signing {isSignUp ? 'up' : 'in'}...{/if}
					{:else if isReset}
						Send reset link
					{:else}
						{isSignUp ? 'Sign Up' : 'Sign In'}
					{/if}
				</button>
			</form>

			{#if isReset}
				<p class="toggle-mode">
					<button type="button" class="link-btn" onclick={() => { isReset = false; error = ''; info = ''; }}>
						Back to sign in
					</button>
				</p>
			{:else}
				<p class="toggle-mode">
					{isSignUp ? 'Already have an account?' : "Don't have an account?"}
					<button type="button" class="link-btn" onclick={() => { isSignUp = !isSignUp; error = ''; }}>
						{isSignUp ? 'Sign in' : 'Sign up'}
					</button>
				</p>
				{#if !isSignUp}
					<p class="toggle-mode">
						<button type="button" class="link-btn" onclick={() => { isReset = true; error = ''; password = ''; }}>
							Forgot your password?
						</button>
					</p>
				{/if}
			{/if}

			{#if !isSignUp}
				<p class="terms">
					By signing in, you agree to our
					<a href="/terms" target="_blank" rel="noopener noreferrer">Terms of Service</a>
					and
					<a href="/privacy" target="_blank" rel="noopener noreferrer">Privacy Policy</a>.
				</p>
			{/if}
		</div>

		{#if !isReset}
			<p class="form-pane-foot">
				Free forever &middot; Add Pro to unlock club perks, the coach, and bulk imports.
			</p>
		{/if}
	</main>
</div>

<style>
	.login-page {
		min-height: 100vh;
		display: grid;
		grid-template-columns: 1fr;
		background: var(--color-bg);
	}

	.brand-pane {
		display: none;
	}

	@media (min-width: 56rem) {
		.login-page {
			grid-template-columns: minmax(28rem, 0.95fr) minmax(0, 1.05fr);
		}
		.form-pane {
			order: 0;
		}
		.brand-pane {
			order: 1;
			display: flex;
			flex-direction: column;
			justify-content: space-between;
			padding: var(--space-2xl);
			background: linear-gradient(150deg, #2C5F6E 0%, #4F8090 45%, #F2A07B 100%);
			color: #FFFFFF;
			position: relative;
			overflow: hidden;
		}
		.brand-pane::before {
			content: '';
			position: absolute;
			inset: -20% -10% -10% -20%;
			background: radial-gradient(ellipse at 30% 20%, rgba(255, 255, 255, 0.18) 0%, transparent 55%);
			pointer-events: none;
		}
		.brand-pane::after {
			content: '';
			position: absolute;
			inset: -20% -20% -30% -10%;
			background: radial-gradient(ellipse at 80% 90%, rgba(185, 167, 232, 0.35) 0%, transparent 55%);
			pointer-events: none;
		}
	}

	.brand-logo,
	.brand-copy,
	.brand-foot {
		position: relative;
		z-index: 1;
	}

	.brand-logo {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		text-decoration: none;
		color: inherit;
	}
	.brand-mark {
		width: 2.5rem;
		height: 2.5rem;
		border-radius: var(--radius-md);
		object-fit: cover;
		box-shadow: 0 4px 12px rgba(0, 0, 0, 0.18);
	}
	.brand-name {
		font-weight: 700;
		font-size: 1.4rem;
		letter-spacing: -0.01em;
	}

	.brand-copy {
		max-width: 32rem;
	}

	.brand-kicker {
		text-transform: uppercase;
		letter-spacing: 0.12em;
		font-size: 0.78rem;
		font-weight: 700;
		opacity: 0.85;
		margin: 0 0 var(--space-sm);
	}

	.brand-headline {
		font-size: 2.25rem;
		line-height: 1.15;
		font-weight: 800;
		margin: 0 0 var(--space-lg);
		letter-spacing: -0.02em;
	}

	@media (min-width: 72rem) {
		.brand-headline {
			font-size: 2.75rem;
		}
	}

	.brand-bullets {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.brand-bullets li {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		font-size: 0.98rem;
		line-height: 1.5;
		opacity: 0.95;
	}
	.bullet-dot {
		flex-shrink: 0;
		width: 0.55rem;
		height: 0.55rem;
		border-radius: 50%;
		background: #FFFFFF;
		margin-top: 0.45rem;
		box-shadow: 0 0 0 4px rgba(255, 255, 255, 0.15);
	}

	.brand-foot {
		font-size: 0.85rem;
		opacity: 0.8;
		max-width: 32rem;
		line-height: 1.5;
		margin: 0;
	}

	.form-pane {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: var(--space-xl) var(--space-md);
		gap: var(--space-md);
	}

	@media (min-width: 56rem) {
		.form-pane {
			padding: var(--space-2xl);
			justify-content: center;
		}
	}

	.login-card {
		width: 100%;
		max-width: 26rem;
		padding: var(--space-xl);
		text-align: center;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-lg);
	}

	@media (min-width: 56rem) {
		.login-card {
			border: none;
			box-shadow: none;
			background: transparent;
			padding: 0;
		}
	}

	.logo {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		font-weight: 700;
		font-size: 1.25rem;
		color: var(--color-text);
		text-decoration: none;
		margin-bottom: var(--space-xl);
	}
	.logo-mobile {
		display: inline-flex;
	}
	@media (min-width: 56rem) {
		.logo-mobile {
			display: none;
		}
	}
	.logo .logo-mark {
		width: 2rem;
		height: 2rem;
		border-radius: var(--radius-md);
		display: block;
		box-shadow: var(--shadow-sm);
		object-fit: cover;
	}
	.logo span {
		background: var(--gradient-primary);
		-webkit-background-clip: text;
		-webkit-text-fill-color: transparent;
		background-clip: text;
	}

	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.72rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-xs);
	}

	h1 {
		font-size: 1.6rem;
		font-weight: 800;
		margin: 0 0 var(--space-xs);
		letter-spacing: -0.01em;
		color: var(--color-text);
	}

	.subtitle {
		font-size: 0.92rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-xl);
		line-height: 1.5;
	}

	.error {
		background: var(--color-danger-light);
		border: 1px solid color-mix(in srgb, var(--color-danger) 30%, transparent);
		color: var(--color-danger);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		margin-bottom: var(--space-md);
		text-align: start;
	}
	.info {
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		color: var(--color-text);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		margin-bottom: var(--space-md);
		text-align: start;
	}

	.login-buttons {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.btn-google,
	.btn-apple,
	.btn-email {
		width: 100%;
		padding: 0.85rem var(--space-lg);
		font-size: 0.95rem;
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
		position: relative;
	}

	.btn-apple:hover:not(:disabled) {
		background: #1a1a1a;
	}

	.soon-pill {
		font-size: 0.65rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		padding: 0.1rem 0.45rem;
		border-radius: 9999px;
		background: rgba(255, 255, 255, 0.18);
		color: rgba(255, 255, 255, 0.9);
		margin-inline-start: 0.4rem;
	}

	:global(html[data-theme='dark']) .btn-apple {
		border-color: #334155;
	}

	.oauth-icon {
		flex-shrink: 0;
	}

	.divider {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		margin: var(--space-lg) 0;
		color: var(--color-text-tertiary);
		font-size: 0.78rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
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
		gap: var(--space-sm);
		text-align: start;
	}

	input[type='email'],
	input[type='password'] {
		width: 100%;
		padding: 0.7rem var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.95rem;
		font-family: inherit;
		background: var(--color-surface);
		color: var(--color-text);
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}

	input[type='email']:focus,
	input[type='password']:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-primary) 18%, transparent);
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	input[type='email']:focus-visible, input[type='password']:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}


	.btn-email {
		background: var(--gradient-primary);
		color: #FFFFFF;
		border: none;
		font-weight: 600;
		margin-top: var(--space-xs);
	}

	.btn-email:hover:not(:disabled) {
		filter: brightness(1.05);
		box-shadow: 0 4px 14px color-mix(in srgb, var(--color-primary) 30%, transparent);
	}

	.toggle-mode {
		margin-top: var(--space-md);
		font-size: 0.88rem;
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
		margin-top: var(--space-lg);
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
	}
	.terms a,
	.signup-check a {
		color: inherit;
		text-decoration: underline;
	}
	.signup-check {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.4;
		text-align: start;
		margin-top: var(--space-2xs);
	}
	.signup-check input[type='checkbox'] {
		margin-top: 0.2rem;
		flex-shrink: 0;
	}

	.form-pane-foot {
		max-width: 26rem;
		text-align: center;
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
		margin: 0;
	}
	@media (min-width: 56rem) {
		.form-pane-foot {
			display: none;
		}
	}
</style>
