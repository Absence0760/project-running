<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';

	// /feed is no longer a top-level tab — the activity feed lives as a
	// self-only "Feed" tab on the runner's own profile (/u/[me]?tab=feed).
	// The route stays alive as a thin redirect so the sitemap entry, the
	// "Browse the feed" CTA in NotificationsList, and any external deep
	// links keep resolving. The auth guard in +layout.svelte sends anon
	// visitors to /login first; we only run once the user is known.
	onMount(async () => {
		// Wait for the auth store to hydrate. The layout's auth guard
		// already gates anon visitors, so by the time we get here a
		// signed-in user should resolve quickly.
		for (let i = 0; i < 40 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		const uid = auth.user?.id;
		if (uid) {
			await goto(`/u/${uid}?tab=feed`, { replaceState: true });
		}
	});
</script>

<svelte:head>
	<title>Feed — Run Onward</title>
</svelte:head>

<div class="page">
	<p class="muted">Loading…</p>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
	.muted {
		color: var(--color-text-tertiary);
	}
</style>
