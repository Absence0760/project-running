<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/core/supabase';
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';

	let error = $state('');

	onMount(async () => {
		// Supabase PKCE flow: auth code arrives in the query string (?code=…), not the hash.
		const { error: authError } = await supabase.auth.exchangeCodeForSession(
			window.location.search.substring(1)
		);

		if (authError) {
			// The client's detectSessionInUrl bootstrap can win a race with
			// this explicit exchange — it consumes the code + PKCE verifier
			// first, leaving our call to fail with "code verifier not found"
			// even though a valid session now exists. Treat that as success:
			// only surface the error when no session was established.
			const { data: { session } } = await supabase.auth.getSession();
			if (!session) {
				error = authError.message;
				return;
			}
		}

		// OAuth-path age + terms capture (audit/gdpr Critical). The
		// pre-redirect tick on /login stashed timestamps in
		// sessionStorage; replay them via the RPC. Idempotent — a
		// returning user (already-stamped profile) is a no-op. If the
		// stash is missing (Safari private mode, returning user, or a
		// callback not initiated from /login), the /auth/confirm-age
		// fallback below re-prompts.
		try {
			const stampedAge = sessionStorage.getItem('age_confirmed_at');
			const stampedTerms = sessionStorage.getItem('terms_accepted_at');
			if (stampedAge && stampedTerms) {
				await supabase.rpc('confirm_age_and_terms');
				sessionStorage.removeItem('age_confirmed_at');
				sessionStorage.removeItem('terms_accepted_at');
			}
		} catch (_) {
			/* RPC failed — the /auth/confirm-age check below catches it. */
		}

		await auth.refreshSession();

		// Profile-level gate: if either consent timestamp is null
		// post-callback, force the confirm-age page before any feature
		// surface renders.
		try {
			const { data: prof } = await supabase.rpc('get_my_profile').maybeSingle();
			const row = prof as
				| { age_confirmed_at: string | null; terms_accepted_at: string | null }
				| null;
			if (!row?.age_confirmed_at || !row?.terms_accepted_at) {
				goto('/auth/confirm-age');
				return;
			}
		} catch (_) {
			// Profile read failed — fail closed to /auth/confirm-age
			// rather than /dashboard. The next session refresh does
			// NOT repeat the consent check, so a transient DB error
			// here would otherwise grant access to the app without
			// consent. confirm_age_and_terms() is idempotent, so an
			// already-confirmed user incurs at most one extra click.
			// /audit/owasp May 2026 Medium #5.
			goto('/auth/confirm-age');
			return;
		}

		goto('/dashboard');
	});
</script>

<div class="callback-page">
	{#if error}
		<p class="error">{m('authCallback.failed', { error })}</p>
		<a href="/login">{m('authCallback.backToLogin')}</a>
	{:else}
		<p>{m('authCallback.signingIn')}</p>
	{/if}
</div>

<style>
	.callback-page {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		gap: 1rem;
		color: var(--color-text-secondary);
	}

	.error {
		color: var(--color-danger);
	}
</style>
