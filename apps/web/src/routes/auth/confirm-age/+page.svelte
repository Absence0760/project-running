<script lang="ts">
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';
	import {
		SIGNUP_GATE_ERROR_ADULT,
		SIGNUP_GATE_ERROR_TERMS,
		checkSignUpGates,
	} from '$lib/auth_gates';

	// Post-OAuth fallback gate. Reached from /auth/callback when the
	// user's user_profiles row is missing `age_confirmed_at` or
	// `terms_accepted_at`. Re-asks for the same affirmation the
	// /login sign-up flow captures, then stamps via the SECURITY
	// DEFINER `confirm_age_and_terms()` RPC.
	//
	// Server-side enforcement story: a user who skips this page (closes
	// the tab, or hits /dashboard directly via a stale URL) keeps a
	// profile with null consent timestamps. Future RPC guards can
	// reject privileged operations against such accounts. See migration
	// 20260929_001 + audit/gdpr (2026-05-25) Critical.

	let confirmAdult = $state(false);
	let acceptTerms = $state(false);
	let loading = $state(false);
	let error = $state('');

	async function handleSubmit(e: Event) {
		e.preventDefault();
		error = '';
		const gate = checkSignUpGates(true, confirmAdult, acceptTerms);
		if (!gate.ok) {
			error = gate.error;
			return;
		}
		loading = true;
		try {
			const { error: rpcError } = await supabase.rpc('confirm_age_and_terms');
			if (rpcError) throw rpcError;
			goto('/dashboard');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not record consent.';
		} finally {
			loading = false;
		}
	}
</script>

<svelte:head>
	<title>Confirm your age — Threkir</title>
</svelte:head>

<div class="confirm-page">
	<main class="card">
		<h1>One more step</h1>
		<p class="lede">
			Before you start, please confirm a couple of things. We do this
			once per account — it won't show again.
		</p>

		<form onsubmit={handleSubmit}>
			<label class="check">
				<input type="checkbox" bind:checked={confirmAdult} />
				<span>I confirm I am 16 years of age or older.</span>
			</label>

			<label class="check">
				<input type="checkbox" bind:checked={acceptTerms} />
				<span>
					I have read and accept the
					<a href="/terms" target="_blank" rel="noopener noreferrer">Terms of Service</a> and the
					<a href="/privacy" target="_blank" rel="noopener noreferrer">Privacy Policy</a>.
				</span>
			</label>

			{#if error}
				<p class="error" role="alert">{error}</p>
			{/if}

			<button
				type="submit"
				class="btn btn-primary"
				disabled={loading || !confirmAdult || !acceptTerms}
			>
				{loading ? 'Saving…' : 'Continue'}
			</button>
		</form>

		<p class="fine">
			These two confirmations stamp your account once and are
			recorded on the server. Required values: {SIGNUP_GATE_ERROR_ADULT
				.replace('Please confirm you are ', '')
				.replace(' to continue.', '')} and
			{SIGNUP_GATE_ERROR_TERMS
				.replace('Please accept the ', '')
				.replace(' to continue.', '')}.
		</p>
	</main>
</div>

<style>
	.confirm-page {
		min-height: 100vh;
		display: grid;
		place-items: center;
		padding: 2rem 1rem;
		background: var(--color-bg);
	}
	.card {
		max-width: 32rem;
		width: 100%;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: 1rem;
		padding: 2rem;
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
	h1 {
		margin: 0;
		font-size: 1.75rem;
	}
	.lede {
		color: var(--color-text-secondary);
		margin: 0;
	}
	form {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		margin-top: 0.5rem;
	}
	.check {
		display: flex;
		gap: 0.75rem;
		align-items: flex-start;
		line-height: 1.4;
	}
	.check input {
		margin-top: 0.2rem;
	}
	.error {
		color: var(--color-danger);
		margin: 0;
	}
	.fine {
		font-size: 0.875rem;
		color: var(--color-text-secondary);
		margin: 0;
	}
</style>
