<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/core/supabase';
	import { auth } from '$lib/stores/auth.svelte';
	import { checkPasswordPair } from '$lib/core/auth_gates';
	import { m } from '$lib/i18n/store.svelte';

	let password = $state('');
	let confirmPassword = $state('');
	let error = $state('');
	let busy = $state(false);
	// Recovery token arrives in the URL hash; supabase-js consumes it
	// automatically (detectSessionInUrl=true) on this navigation, then
	// fires onAuthStateChange with a PASSWORD_RECOVERY-tagged session.
	let ready = $state(false);
	// True once updateUser succeeds. When the page unmounts WITHOUT
	// the password having been changed, we sign the recovery session
	// out — see Persona-hunt Round 2 finding Casual #1 below.
	let passwordChanged = $state(false);

	onMount(async () => {
		await auth.ready();
		ready = true;
	});

	// Persona-hunt Round 2 finding Casual #1: supabase-js consumed
	// the #access_token from the recovery URL on page load and minted
	// a live session BEFORE the new password was set. A user on a
	// shared / library / family laptop who opened the reset link
	// then closed the tab without typing left the session live —
	// anyone on that browser hitting /dashboard was signed in as the
	// victim. Fix: sign out on unmount / beforeunload IF the
	// password wasn't actually changed. This explicitly invalidates
	// the recovery session server-side so a stolen-laptop attack
	// can't navigate forward from a stale localStorage entry.
	function cleanupRecoverySession() {
		if (!passwordChanged) {
			// Fire-and-forget — we're unmounting, no await possible.
			supabase.auth.signOut({ scope: 'local' }).catch(() => {});
		}
	}

	onMount(() => {
		const handler = () => cleanupRecoverySession();
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	onDestroy(() => {
		cleanupRecoverySession();
	});

	async function handleSubmit(e: Event) {
		e.preventDefault();
		error = '';
		const pair = checkPasswordPair(password, confirmPassword);
		if (!pair.ok) {
			error = pair.reason === 'too_short'
				? m('authReset.errorTooShort')
				: m('authReset.errorMismatch');
			return;
		}
		busy = true;
		try {
			const { error: updateError } = await supabase.auth.updateUser({ password });
			if (updateError) throw updateError;
			// Flip BEFORE refreshSession so unmount triggered by goto
			// doesn't sign out the freshly-set session.
			passwordChanged = true;
			await auth.refreshSession();
			goto('/dashboard');
		} catch (err) {
			error = err instanceof Error ? err.message : m('authReset.errorGeneric');
			busy = false;
		}
	}
</script>

<div class="reset-page">
	<header class="reset-header">
		<a href="/" class="logo">
			<img src="/logo-mark.svg" alt="" class="logo-mark" />
			<span>Threkir</span>
		</a>
	</header>

	<main class="reset-main">
		<div class="reset-card">
			<p class="kicker">{m('authReset.kicker')}</p>
			<h1>{m('authReset.heading')}</h1>

			{#if !ready}
				<p class="muted">{m('authReset.verifying')}</p>
			{:else if !auth.user}
				<p class="muted">{m('authReset.invalidLink')}</p>
				<div class="error-block">
					<p>
						{m('authReset.invalidLinkBody')}
					</p>
				</div>
				<a class="btn btn-primary reset-cta" href="/login?reset=1">{m('authReset.requestNewLink')}</a>
			{:else}
				<p class="subtitle">{m('authReset.subtitlePrefix')} <strong>{auth.user.email}</strong>{m('authReset.subtitleSuffix')}</p>

				{#if error}
					<div class="error" role="alert">{error}</div>
				{/if}

				<form class="reset-form" onsubmit={handleSubmit}>
					<input
						type="password"
						bind:value={password}
						placeholder={m('authReset.newPasswordPlaceholder')}
						required
						minlength="6"
						autocomplete="new-password"
					/>
					<input
						type="password"
						bind:value={confirmPassword}
						placeholder={m('authReset.confirmPasswordPlaceholder')}
						required
						minlength="6"
						autocomplete="new-password"
					/>
					<button type="submit" class="btn btn-primary reset-cta" disabled={busy}>
						{busy ? m('authReset.updating') : m('authReset.updateButton')}
					</button>
				</form>
				<p class="reset-hint">{m('authReset.hint')}</p>
			{/if}
		</div>
	</main>

	<footer class="reset-footer">
		<a href="/login">{m('authReset.backToSignIn')}</a>
	</footer>
</div>

<style>
	.reset-page {
		min-height: 100vh;
		display: flex;
		flex-direction: column;
		background: var(--color-bg);
	}

	.reset-header {
		padding: var(--space-md) var(--space-xl);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}

	.logo {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--color-text);
		text-decoration: none;
	}
	.logo-mark {
		width: 1.85rem;
		height: 1.85rem;
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

	.reset-main {
		flex: 1;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: var(--space-xl) var(--space-md);
	}

	.reset-card {
		width: 100%;
		max-width: 28rem;
		padding: var(--space-2xl) var(--space-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-lg);
		text-align: center;
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
		margin: 0 0 var(--space-sm);
		font-size: 1.6rem;
		font-weight: 800;
		letter-spacing: -0.01em;
		color: var(--color-text);
	}

	.subtitle {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		margin: 0 0 var(--space-xl);
		line-height: 1.5;
	}
	.subtitle strong {
		color: var(--color-text);
		font-weight: 600;
	}

	.muted {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		margin: 0 0 var(--space-md);
	}

	.reset-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		text-align: start;
	}
	.reset-form input {
		padding: 0.7rem var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.95rem;
		font-family: inherit;
		background: var(--color-surface);
		color: var(--color-text);
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}
	.reset-form input:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-primary) 18%, transparent);
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	.reset-form input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}


	.reset-cta {
		width: 100%;
		padding: 0.85rem var(--space-lg);
		font-size: 0.95rem;
		margin-top: var(--space-xs);
	}

	.reset-hint {
		margin: var(--space-md) 0 0;
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}

	.error {
		background: var(--color-danger-light);
		border: 1px solid color-mix(in srgb, var(--color-danger) 30%, transparent);
		color: var(--color-danger);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		text-align: start;
		margin-bottom: var(--space-md);
	}

	.error-block {
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		padding: var(--space-md);
		border-radius: var(--radius-md);
		text-align: start;
		margin-bottom: var(--space-md);
	}
	.error-block p {
		margin: 0;
		font-size: 0.88rem;
		line-height: 1.5;
		color: var(--color-text-secondary);
	}

	.reset-footer {
		padding: var(--space-lg) var(--space-md);
		border-top: 1px solid var(--color-border);
		text-align: center;
		font-size: 0.85rem;
		background: var(--color-surface);
	}
	.reset-footer a {
		color: var(--color-text-secondary);
		text-decoration: none;
	}
	.reset-footer a:hover {
		color: var(--color-primary);
	}
</style>
