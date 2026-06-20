<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { buildGuideTitle, buildLearnCanonical } from '$lib/learn/learn_meta';
	import GuideCard from '$lib/components/GuideCard.svelte';

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
	<header class="learn-header">
		<a href="/" class="learn-logo">Threkir</a>
		<nav class="learn-nav">
			<a href="/login">{m('learn.signIn')}</a>
		</nav>
	</header>

	<section class="hero">
		<nav class="breadcrumb" aria-label="Breadcrumb">
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
