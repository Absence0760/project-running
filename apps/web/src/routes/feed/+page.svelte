<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { m } from '$lib/i18n/store.svelte';

	// /feed is now the Feed tab under /social. Kept as a thin redirect
	// so the sitemap entry, the bell-popover "Browse the feed" CTA, and
	// external deep links keep resolving. The auth guard in +layout.svelte
	// sends anon visitors to /login first.
	onMount(async () => {
		await goto('/social?tab=feed', { replaceState: true });
	});
</script>

<svelte:head>
	<title>{m('shell.redirecting')}</title>
</svelte:head>

<div class="page">
	<p class="muted">{m('shell.loading')}</p>
</div>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); }
	.muted { color: var(--color-text-tertiary); }
</style>
