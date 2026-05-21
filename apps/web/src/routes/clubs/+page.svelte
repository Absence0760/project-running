<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';

	// /clubs is now hosted under /social as the third tab. Kept as a
	// redirect so existing bookmarks, search results, mobile deep links,
	// and email links keep resolving. Sub-routes (/clubs/[slug],
	// /clubs/new, /clubs/[slug]/events/...) are unchanged.
	onMount(async () => {
		const subtab = $page.url.searchParams.get('tab');
		const target = subtab === 'browse'
			? '/social?tab=clubs&clubs-sub=browse'
			: '/social?tab=clubs';
		await goto(target, { replaceState: true });
	});
</script>

<svelte:head>
	<title>Clubs — Threkir</title>
</svelte:head>

<div class="page">
	<p class="muted">Loading…</p>
</div>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); }
	.muted { color: var(--color-text-tertiary); }
</style>
