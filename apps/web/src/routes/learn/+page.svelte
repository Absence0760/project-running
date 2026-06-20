<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { buildLearnCanonical } from '$lib/learn/learn_meta';
	import { guidesByCategory } from '$lib/learn/guides';
	import GuideCard from '$lib/components/GuideCard.svelte';

	let { data } = $props();

	const pageTitle = m('learn.hubPageTitle');
	const pageDesc = m('learn.hubPageDescription');
	const canonicalUrl = buildLearnCanonical(data.siteUrl, '/learn');
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
		<p class="kicker">{m('learn.hubKicker')}</p>
		<h1>{m('learn.hubTitle')}</h1>
		<p class="hero-sub">{m('learn.hubSub')}</p>
	</section>

	<main class="content">
		{#each data.categories as category (category.id)}
			<section class="category-section" aria-labelledby="cat-{category.id}">
				<h2 id="cat-{category.id}">{m(category.labelKey)}</h2>
				<div class="guide-grid">
					{#each guidesByCategory(category.id) as guide (guide.slug)}
						<GuideCard {guide} />
					{/each}
				</div>
			</section>
		{/each}
	</main>

	<section class="signup-cta" aria-labelledby="learn-cta-heading">
		<p class="kicker">{m('learn.ctaKicker')}</p>
		<h2 id="learn-cta-heading">{m('learn.ctaHeading')}</h2>
		<p class="signup-sub">{m('learn.ctaSub')}</p>
		<a class="btn btn-primary" href="/login?signup=1">{m('learn.ctaButton')}</a>
	</section>

	<footer class="learn-footer">
		<a href="/">{m('learn.footerHome')}</a>
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
		max-width: 56rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-xl) var(--space-md) var(--space-md);
		text-align: center;
	}

	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-sm);
	}

	.hero h1 {
		font-size: 2rem;
		font-weight: 800;
		margin: 0 0 var(--space-sm);
		line-height: 1.15;
		color: var(--color-text);
	}

	.hero-sub {
		font-size: 1rem;
		color: var(--color-text-secondary);
		max-width: 40rem;
		margin: 0 auto;
		line-height: 1.5;
	}

	.content {
		max-width: 64rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-xl);
	}

	.category-section h2 {
		font-size: 1.3rem;
		font-weight: 700;
		margin: 0 0 var(--space-md);
		color: var(--color-text);
	}

	.guide-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr));
		gap: var(--space-md);
	}

	.signup-cta {
		max-width: 56rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-xl) var(--space-md);
		text-align: center;
	}

	.signup-cta h2 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
		color: var(--color-text);
	}

	.signup-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 32rem;
		margin: 0 auto var(--space-md);
		line-height: 1.5;
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
			padding: var(--space-2xl) var(--space-xl) var(--space-lg);
		}
		.hero h1 {
			font-size: 2.5rem;
		}
		.content {
			padding: var(--space-md) var(--space-xl);
		}
	}
</style>
