<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';
	import { auth } from '$lib/stores/auth.svelte';

	let error = $state('');

	onMount(async () => {
		// Supabase PKCE flow: auth code arrives in the query string (?code=…), not the hash.
		const { error: authError } = await supabase.auth.exchangeCodeForSession(
			window.location.search.substring(1)
		);

		if (authError) {
			error = authError.message;
			return;
		}

		await auth.refreshSession();
		goto('/dashboard');
	});
</script>

<div class="callback-page">
	{#if error}
		<p class="error">Authentication failed: {error}</p>
		<a href="/login">Back to login</a>
	{:else}
		<p>Signing you in...</p>
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
