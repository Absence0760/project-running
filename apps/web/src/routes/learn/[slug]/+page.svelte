<script lang="ts">
	import { m, currentLocale } from '$lib/i18n/store.svelte';
	import { formatDate } from '$lib/format/time';
	import {
		buildGuideDescription,
		buildGuideJsonLd,
		buildGuideTitle,
		buildLearnCanonical,
	} from '$lib/learn/learn_meta';
	import { getGuide, isEnglishFallback } from '$lib/learn/guides';
	import { getCategory } from '$lib/learn/categories';
	import LearnCta from '$lib/components/LearnCta.svelte';

	let { data } = $props();

	// Resolve the category in-component (its labelKey is a typed
	// MessageKey) rather than threading the key through load, where
	// SvelteKit's serialised PageData widens it back to string.
	const category = $derived(getCategory(data.categoryId));

	// Re-resolve client-side for the active locale so a non-English
	// visitor gets the localized guide when one exists (and the
	// "in English" notice when it falls back). The build-time prerender
	// bakes the English guide; the head meta is stable across locales.
	const guide = $derived(getGuide(data.guide.slug, currentLocale()) ?? data.guide);
	const showFallbackNotice = $derived(isEnglishFallback(data.guide.slug, currentLocale()));

	const pageTitle = $derived(buildGuideTitle(data.guide.title));
	const pageDesc = $derived(buildGuideDescription(data.guide.description));
	const canonicalUrl = $derived(buildLearnCanonical(data.siteUrl, `/learn/${data.guide.slug}`));
	const ogImage = $derived(data.guide.heroImage || '/og-default.png');
	const jsonLd = $derived(
		buildGuideJsonLd({
			title: data.guide.title,
			description: data.guide.description,
			slug: data.guide.slug,
			updated: data.guide.updated,
			categoryId: data.categoryId,
			categoryLabel: category ? m(category.labelKey) : '',
			base: data.siteUrl,
		}),
	);

	const GuideBody = $derived(guide.component);
</script>

<svelte:head>
	<title>{pageTitle}</title>
	<meta name="description" content={pageDesc} />
	<link rel="canonical" href={canonicalUrl} />
	<meta property="og:title" content={pageTitle} />
	<meta property="og:description" content={pageDesc} />
	<meta property="og:type" content="article" />
	<meta property="og:url" content={canonicalUrl} />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content={ogImage} />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={pageTitle} />
	<meta name="twitter:description" content={pageDesc} />
	<meta name="twitter:image" content={ogImage} />
	{@html `<script type="application/ld+json">${jsonLd}</script>`}
</svelte:head>

<div class="learn-page">
	<header class="learn-header">
		<a href="/" class="learn-logo">Threkir</a>
		<nav class="learn-nav">
			<a href="/login">{m('learn.signIn')}</a>
		</nav>
	</header>

	<article class="learn-article">
		<nav class="breadcrumb" aria-label="Breadcrumb">
			<a href="/">{m('learn.breadcrumbHome')}</a>
			<span class="sep">/</span>
			<a href="/learn">{m('learn.breadcrumbLearn')}</a>
			{#if category}
				<span class="sep">/</span>
				<a href="/learn/category/{category.id}">{m(category.labelKey)}</a>
			{/if}
		</nav>

		<h1>{guide.title}</h1>
		<p class="updated">{m('learn.lastUpdated', { date: formatDate(data.guide.updated) })}</p>

		{#if showFallbackNotice}
			<p class="fallback-notice">{m('learn.englishFallbackNotice')}</p>
		{/if}

		<div class="prose">
			<GuideBody />
		</div>

		<LearnCta feature={data.guide.cta?.feature} />
	</article>

	<footer class="learn-footer">
		<a href="/learn">{m('learn.breadcrumbLearn')}</a>
		<span class="dot">&middot;</span>
		<a href="/login">{m('learn.signIn')}</a>
	</footer>
</div>

<style>
	.learn-page {
		min-height: 100vh;
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
	}

	.learn-header {
		padding: var(--space-sm) var(--space-md);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
		display: flex;
		align-items: center;
		justify-content: space-between;
	}

	.learn-logo {
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--color-primary);
		text-decoration: none;
	}

	.learn-nav a {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		text-decoration: none;
	}

	.learn-nav a:hover {
		color: var(--color-primary);
	}

	.learn-article {
		max-width: 44rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-xl) var(--space-md);
	}

	.breadcrumb {
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		margin-bottom: var(--space-md);
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

	.learn-article h1 {
		font-size: 2rem;
		font-weight: 800;
		line-height: 1.15;
		margin: 0 0 var(--space-sm);
		color: var(--color-text);
	}

	.updated {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-md);
	}

	.fallback-notice {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-sm) var(--space-md);
		margin: 0 0 var(--space-lg);
	}

	.prose {
		font-size: 1.02rem;
		line-height: 1.7;
		color: var(--color-text);
	}

	.prose :global(h2) {
		font-size: 1.4rem;
		font-weight: 700;
		margin: var(--space-xl) 0 var(--space-sm);
		color: var(--color-text);
	}

	.prose :global(h3) {
		font-size: 1.15rem;
		font-weight: 700;
		margin: var(--space-lg) 0 var(--space-xs);
		color: var(--color-text);
	}

	.prose :global(p) {
		margin: 0 0 var(--space-md);
	}

	.prose :global(ul),
	.prose :global(ol) {
		margin: 0 0 var(--space-md);
		padding-left: 1.4rem;
	}

	.prose :global(li) {
		margin-bottom: var(--space-xs);
	}

	.prose :global(a) {
		color: var(--color-primary);
	}

	.prose :global(strong) {
		font-weight: 700;
	}

	.dot {
		color: var(--color-text-tertiary);
		margin: 0 0.3rem;
	}

	.learn-footer {
		margin-top: auto;
		padding: var(--space-lg) var(--space-md);
		border-top: 1px solid var(--color-border);
		text-align: center;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		background: var(--color-surface);
	}

	.learn-footer a {
		color: var(--color-text-secondary);
		text-decoration: none;
	}

	.learn-footer a:hover {
		color: var(--color-primary);
	}

	@media (min-width: 48rem) {
		.learn-header {
			padding: var(--space-md) var(--space-xl);
		}
		.learn-article {
			padding: var(--space-2xl) var(--space-md);
		}
		.learn-article h1 {
			font-size: 2.4rem;
		}
	}
</style>
