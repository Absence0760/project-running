<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { joinClubByToken } from '$lib/data';
	import { supabase } from '$lib/supabase';
	import { auth } from '$lib/stores/auth.svelte';

	let token = $derived($page.params.token as string);
	let status = $state<'joining' | 'error' | 'not-authed'>('joining');
	let errorMsg = $state<string | null>(null);

	onMount(async () => {
		if (!auth.loggedIn) {
			status = 'not-authed';
			return;
		}
		try {
			const clubId = await joinClubByToken(token);
			const { data } = await supabase.from('clubs').select('slug').eq('id', clubId).single();
			goto(data?.slug ? `/clubs/${data.slug}` : '/clubs');
		} catch (e: unknown) {
			status = 'error';
			errorMsg = e instanceof Error ? e.message : 'This invite is invalid or expired.';
		}
	});
</script>

<div class="page">
	{#if status === 'joining'}
		<p>Joining the club…</p>
	{:else if status === 'not-authed'}
		<h1>Sign in to accept this invite</h1>
		<p class="muted">You need an account to join a private club.</p>
		<a
			href="/login?return_to={encodeURIComponent($page.url.pathname)}"
			class="btn-primary"
		>Sign in</a>
	{:else}
		<h1>Invite problem</h1>
		<p class="error">{errorMsg}</p>
		<a href="/clubs" class="btn-secondary">Back to clubs</a>
	{/if}
</div>

<style>
	.page {
		max-width: 28rem;
		margin: 0 auto;
		padding: var(--space-2xl);
		text-align: center;
	}

	h1 {
		font-size: 1.4rem;
		margin: 0 0 0.5rem;
	}

	.muted {
		color: var(--color-text-secondary);
		margin-bottom: var(--space-md);
	}

	.error {
		color: var(--color-danger);
		background: var(--color-danger-light);
		padding: 0.6rem 0.9rem;
		border-radius: var(--radius-md);
		margin-bottom: var(--space-md);
	}

	.btn-primary,
	.btn-secondary {
		display: inline-block;
		padding: 0.55rem 1rem;
		border-radius: var(--radius-md);
		font-weight: 600;
	}

	.btn-primary {
		background: var(--color-primary);
		color: var(--color-bg);
	}

	.btn-secondary {
		background: transparent;
		color: var(--color-text);
		border: 1px solid var(--color-border);
	}
</style>
