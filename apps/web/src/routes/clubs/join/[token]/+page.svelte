<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { joinClubByToken } from '$lib/core/data';
	import { supabase } from '$lib/core/supabase';
	import { auth } from '$lib/stores/auth.svelte';

	let token = $derived($page.params.token as string);
	let status = $state<'joining' | 'error' | 'not-authed'>('joining');
	let errorMsg = $state<string | null>(null);

	onMount(async () => {
		// Auth-race shape: a hard reload onto the invite URL races
		// auth.loading → false vs auth.user populating. Same poll
		// pattern as settings / dashboard / clubs.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
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

	let returnTo = $derived(encodeURIComponent($page.url.pathname));
</script>

<div class="invite-page">
	<header class="invite-header">
		<a href="/" class="logo">
			<img src="/icon-192.png" alt="" class="logo-mark" />
			<span>Threkir</span>
		</a>
	</header>

	<main class="invite-main">
		{#if status === 'joining'}
			<section class="invite-card joining-card" aria-live="polite">
				<p class="kicker">Almost there</p>
				<h1>Joining the club…</h1>
				<p class="muted">Hang tight — we're redeeming your invite.</p>
				<div class="spinner-dots" aria-hidden="true">
					<span></span><span></span><span></span>
				</div>
			</section>
		{:else if status === 'not-authed'}
			<section class="invite-card">
				<p class="kicker">You've been invited</p>
				<h1>Sign in to accept this invite</h1>
				<p class="muted">
					You need a Threkir account to join. Sign in to an existing account or
					create a new one — both are free.
				</p>
				<div class="invite-actions">
					<a class="btn btn-primary" href="/login?return_to={returnTo}">Sign in</a>
					<a class="btn btn-outline" href="/login?signup=1&return_to={returnTo}">
						Create a free account
					</a>
				</div>
				<p class="footnote">
					Private clubs only show their members and posts after you've joined.
				</p>
			</section>
		{:else}
			<section class="invite-card">
				<p class="kicker">Hmm</p>
				<h1>Invite problem</h1>
				<p class="error">{errorMsg}</p>
				<p class="muted">
					This invite link may have been rotated, the club may have changed its join policy,
					or the link could simply be expired. Ask whoever sent it to share a fresh one.
				</p>
				<div class="invite-actions">
					<a class="btn btn-primary" href="/clubs">Browse clubs</a>
					<a class="btn btn-outline" href="/dashboard">Go to dashboard</a>
				</div>
			</section>
		{/if}
	</main>
</div>

<style>
	.invite-page {
		min-height: 100vh;
		display: flex;
		flex-direction: column;
		background: var(--color-bg);
	}

	.invite-header {
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

	.invite-main {
		flex: 1;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: var(--space-xl) var(--space-md);
	}

	.invite-card {
		width: 100%;
		max-width: 32rem;
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
		font-size: 1.7rem;
		font-weight: 800;
		letter-spacing: -0.01em;
		color: var(--color-text);
		line-height: 1.2;
	}

	.muted {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		margin: 0 0 var(--space-lg);
		line-height: 1.5;
	}

	.error {
		color: var(--color-danger);
		background: var(--color-danger-light);
		border: 1px solid color-mix(in srgb, var(--color-danger) 30%, transparent);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		margin: 0 0 var(--space-md);
		font-size: 0.88rem;
		text-align: left;
	}

	.invite-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
	}
	.invite-actions :global(.btn),
	.invite-actions :global(.btn-primary),
	.invite-actions :global(.btn-outline) {
		min-width: 12rem;
	}

	.footnote {
		margin: var(--space-lg) 0 0;
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
	}

	.joining-card .spinner-dots {
		display: inline-flex;
		gap: 0.4rem;
		margin-top: var(--space-md);
	}
	.spinner-dots span {
		width: 0.55rem;
		height: 0.55rem;
		border-radius: 50%;
		background: var(--color-primary);
		opacity: 0.4;
		animation: dot-pulse 1.2s ease-in-out infinite;
	}
	.spinner-dots span:nth-child(2) {
		animation-delay: 0.18s;
	}
	.spinner-dots span:nth-child(3) {
		animation-delay: 0.36s;
	}
	@keyframes dot-pulse {
		0%, 80%, 100% { opacity: 0.4; transform: scale(0.85); }
		40% { opacity: 1; transform: scale(1); }
	}
	@media (prefers-reduced-motion: reduce) {
		.spinner-dots span {
			animation: none;
			opacity: 0.6;
		}
	}
</style>
