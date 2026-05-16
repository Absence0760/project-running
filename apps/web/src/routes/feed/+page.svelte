<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';

	// /feed is now the Feed tab under /social. Kept as a thin redirect
	// so the sitemap entry, the bell-popover "Browse the feed" CTA, and
	// external deep links keep resolving. The auth guard in +layout.svelte
	// sends anon visitors to /login first.
	onMount(async () => {
		await goto('/social?tab=feed', { replaceState: true });
	});
</script>

<svelte:head>
	<title>Feed — Run Onward</title>
</svelte:head>

<div class="page">
	<p class="muted">Loading…</p>
</div>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); }
	.muted { color: var(--color-text-tertiary); }
</style>
