<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';
	import { auth } from '$lib/stores/auth.svelte';

	let password = $state('');
	let confirmPassword = $state('');
	let error = $state('');
	let busy = $state(false);
	// Recovery token arrives in the URL hash; supabase-js consumes it
	// automatically (detectSessionInUrl=true) on this navigation, then
	// fires onAuthStateChange with a PASSWORD_RECOVERY-tagged session.
	// Until the auth store settles we show a brief "Verifying..." state.
	let ready = $state(false);

	onMount(async () => {
		// Wait briefly for supabase-js to parse the hash and mint the
		// recovery session. The auth store's onAuthStateChange handler
		// flips auth.loading -> false once the session is detected;
		// auth.user is then populated.
		for (let i = 0; i < 30 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 100));
		}
		ready = true;
	});

	async function handleSubmit(e: Event) {
		e.preventDefault();
		error = '';
		if (password.length < 6) {
			error = 'Password must be at least 6 characters.';
			return;
		}
		if (password !== confirmPassword) {
			error = "Passwords don't match.";
			return;
		}
		busy = true;
		try {
			const { error: updateError } = await supabase.auth.updateUser({ password });
			if (updateError) throw updateError;
			await auth.refreshSession();
			goto('/dashboard');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Failed to update password.';
			busy = false;
		}
	}
</script>

<div class="reset-page">
	<div class="reset-card">
		<a href="/" class="logo">
			<img src="/icon-192.png" alt="" class="logo-mark" />
			<span>Run Onward</span>
		</a>
		<h1>Set a new password</h1>

		{#if !ready}
			<p class="muted">Verifying your reset link…</p>
		{:else if !auth.user}
			<p class="error">
				This reset link is invalid or has expired. Request a fresh one
				from the <a href="/login?reset=1">forgot-password</a> page.
			</p>
		{:else}
			<p class="subtitle">Choose a new password for {auth.user.email}.</p>

			{#if error}
				<div class="error">{error}</div>
			{/if}

			<form class="reset-form" onsubmit={handleSubmit}>
				<input
					type="password"
					bind:value={password}
					placeholder="New password"
					required
					minlength="6"
					autocomplete="new-password"
				/>
				<input
					type="password"
					bind:value={confirmPassword}
					placeholder="Confirm new password"
					required
					minlength="6"
					autocomplete="new-password"
				/>
				<button type="submit" class="btn btn-primary" disabled={busy}>
					{busy ? 'Updating…' : 'Update password'}
				</button>
			</form>
		{/if}
	</div>
</div>

<style>
	.reset-page {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		padding: var(--space-xl);
		background: var(--color-bg);
	}
	.reset-card {
		width: 100%;
		max-width: 24rem;
		padding: var(--space-2xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg, 12px);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		text-align: center;
	}
	.logo {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		font-weight: 700;
		font-size: 1.25rem;
		color: var(--color-primary);
		text-decoration: none;
	}
	.logo .logo-mark {
		width: 2rem;
		height: 2rem;
		border-radius: var(--radius-md);
		display: block;
		box-shadow: var(--shadow-sm);
		object-fit: cover;
	}
	h1 {
		margin: 0;
		font-size: 1.4rem;
	}
	.subtitle {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0;
	}
	.muted {
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.reset-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.reset-form input {
		padding: 0.6rem 0.8rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.95rem;
	}
	.error {
		background: var(--color-danger-light);
		border: 1px solid rgba(229, 57, 53, 0.3);
		color: var(--color-danger);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		text-align: left;
	}
</style>
