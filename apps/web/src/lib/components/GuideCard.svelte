<script lang="ts">
	import { m, currentLocale } from '$lib/i18n/store.svelte';
	import { getCategory } from '$lib/learn/categories';
	import { localizedGuideMeta, type GuideIndexEntry } from '$lib/learn/guides';

	let { guide }: { guide: GuideIndexEntry } = $props();

	const category = $derived(getCategory(guide.category));
	// Re-resolve the card's title + description for the active locale so the
	// listing matches the localized article body a click away; falls back to
	// the English frontmatter field-by-field when no localized file exists.
	const meta = $derived(localizedGuideMeta(guide.slug, currentLocale()) ?? guide);
</script>

<a class="card-elevated guide-card" href="/learn/{guide.slug}">
	{#if category}
		<span class="category-pill">{m(category.labelKey)}</span>
	{/if}
	<h3>{meta.title}</h3>
	<p class="guide-desc">{meta.description}</p>
	<span class="read-more">{m('learn.readGuide')}</span>
</a>

<style>
	.guide-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-lg);
		text-decoration: none;
		color: inherit;
		height: 100%;
	}

	.category-pill {
		align-self: flex-start;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: 0.7rem;
		font-weight: 700;
		color: var(--color-primary);
		background: var(--color-primary-subtle, var(--color-bg));
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		padding: 0.15rem 0.5rem;
	}

	.guide-card h3 {
		font-size: 1.1rem;
		font-weight: 700;
		margin: 0;
		line-height: 1.25;
		color: var(--color-text);
	}

	.guide-desc {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		margin: 0;
		line-height: 1.5;
		flex: 1;
	}

	.read-more {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-primary);
	}
</style>
