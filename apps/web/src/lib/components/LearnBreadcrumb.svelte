<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';

	type Crumb = { href: string; label: string };

	// Ancestors only — the page's own <h1> is the current step, so a
	// trailing self-link would repeat it.
	let { crumbs }: { crumbs: Crumb[] } = $props();
</script>

<nav class="breadcrumb" aria-label={m('learn.breadcrumbNav')}>
	{#each crumbs as crumb, i (crumb.href)}
		{#if i > 0}<span class="sep">/</span>{/if}
		<a href={crumb.href}>{crumb.label}</a>
	{/each}
</nav>

<style>
	.breadcrumb {
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		margin-bottom: var(--space-sm);
		display: flex;
		flex-wrap: wrap;
		gap: 0.3rem;
		align-items: center;
	}

	.breadcrumb a {
		color: var(--color-text-secondary);
		text-decoration: none;
	}

	.breadcrumb a:hover {
		color: var(--color-primary);
	}

	.breadcrumb .sep {
		color: var(--color-text-tertiary);
	}
</style>
