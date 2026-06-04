<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';

	// The run-history list moved to /history (F14 cosmetic rename, decision
	// D3). Kept as a thin client-side redirect so bookmarks, the old nav
	// destination, and external deep links keep resolving. A server
	// `redirect()` would emit an un-hashed inline-script stub that breaks
	// the hash-based CSP on this fully-prerendered site — see /settings for
	// the same pattern (audit-xss M2 / decisions §70). The <meta refresh>
	// is the no-JS fallback.
	onMount(() => {
		goto('/history', { replaceState: true });
	});
</script>

<svelte:head>
	<title>Redirecting…</title>
	<meta http-equiv="refresh" content="0;url=/history" />
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
