<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';

	// `/settings` has no content of its own — it just bounces to the first
	// tab. A client-side redirect (mirroring /clubs, /feed, /explore) keeps
	// this a normal prerendered page whose only inline script is the
	// hash-covered SvelteKit hydration block. The previous server `redirect()`
	// (+page.ts, prerender=true) emitted a redirect STUB with an un-hashed
	// inline `location.href` script that rode the CloudFront header's
	// `unsafe-inline` — the one page the hash-based CSP couldn't cover
	// (audit-xss M2 / decisions §70). The <meta refresh> is the no-JS fallback.
	onMount(() => {
		goto('/settings/account', { replaceState: true });
	});
</script>

<svelte:head>
	<title>Redirecting…</title>
	<meta http-equiv="refresh" content="0;url=/settings/account" />
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
