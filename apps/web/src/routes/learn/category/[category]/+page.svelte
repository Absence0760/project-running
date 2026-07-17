<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { buildGuideTitle, buildLearnCanonical } from '$lib/learn/learn_meta';
	import GuideCard from '$lib/components/GuideCard.svelte';
	import PublicHeader from '$lib/components/PublicHeader.svelte';
	import PublicFooter from '$lib/components/PublicFooter.svelte';

	let { data } = $props();

	const categoryLabel = $derived(m(data.category.labelKey));
	const pageTitle = $derived(buildGuideTitle(categoryLabel));
	const pageDesc = $derived(m('learn.hubPageDescription'));
	const canonicalUrl = $derived(
		buildLearnCanonical(data.siteUrl, `/learn/category/${data.category.id}`),
	);
</script>

<svelte:head>
	<title>{pageTitle}</title>
	<meta name="description" content={pageDesc} />
	<link rel="canonical" href={canonicalUrl} />
	<meta property="og:title" content={pageTitle} />
	<meta property="og:description" content={pageDesc} />
	<meta property="og:type" content="website" />
	<meta property="og:url" content={canonicalUrl} />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content="/og-default.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={pageTitle} />
	<meta name="twitter:description" content={pageDesc} />
	<meta name="twitter:image" content="/og-default.png" />
</svelte:head>

<div class="learn-page">
	<PublicHeader />

	<section class="hero">
		<nav class="breadcrumb" aria-label={m('learn.breadcrumbNav')}>
			<a href="/">{m('learn.breadcrumbHome')}</a>
			<span class="sep">/</span>
			<a href="/learn">{m('learn.breadcrumbLearn')}</a>
		</nav>
		<h1>{categoryLabel}</h1>
	</section>

	<main class="content">
		<div class="guide-grid">
			{#each data.guides as guide (guide.slug)}
				<GuideCard {guide} />
			{/each}
		</div>
	</main>

	<PublicFooter />
</div>

<style>
	.learn-page {
		min-height: 100vh;
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
	}

	.hero {
		max-width: 64rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-xl) var(--space-md) var(--space-sm);
	}

	.breadcrumb {
		font-size: 0.85rem;
		margin-bottom: var(--space-sm);
		display: flex;
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

	.hero h1 {
		font-size: 2rem;
		font-weight: 800;
		margin: 0;
		color: var(--color-text);
	}

	.content {
		max-width: 64rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-md);
	}

	.guide-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr));
		gap: var(--space-md);
	}

	@media (min-width: 48rem) {
		.hero {
			padding: var(--space-2xl) var(--space-xl) var(--space-md);
		}
		.hero h1 {
			font-size: 2.5rem;
		}
		.content {
			padding: var(--space-md) var(--space-xl);
		}
	}
</style>
