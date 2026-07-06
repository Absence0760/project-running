<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { formatKmStable, formatDateStable } from '$lib/share/share_meta';
	import {
		buildEventJsonLd,
		buildEventShareCanonical,
		buildEventShareDescription,
		buildEventShareTitle,
	} from '$lib/share/share_event_meta';

	let { data } = $props();

	let title = $derived(buildEventShareTitle(data.event));
	let description = $derived(buildEventShareDescription(data.event));
	let canonicalUrl = $derived(buildEventShareCanonical(data.siteUrl, data.id));
	let jsonLd = $derived(buildEventJsonLd(data.event, { id: data.id, base: data.siteUrl }));

	let hasEvent = $derived(!!data.event);
	let heroDate = $derived(formatDateStable(data.event?.starts_at));
	let heroDistance = $derived(formatKmStable(data.event?.distance_m));
	// The in-app event lives under its club; deep-link there when we know
	// the slug, else fall back to the home page.
	let appHref = $derived(
		data.event?.club_slug
			? `/clubs/${data.event.club_slug}/events/${data.id}`
			: '/'
	);
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<link rel="canonical" href={canonicalUrl} />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="website" />
	<meta property="og:url" content={canonicalUrl} />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content="/og-default.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content="/og-default.png" />
	{@html `<script type="application/ld+json">${jsonLd}</script>`}
</svelte:head>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">Threkir</a>
	</header>

	{#if hasEvent}
		<section class="hero">
			<p class="kicker">{m('shareEvent.heroKicker')}</p>
			<h1>{data.event?.title}</h1>
			<p class="subtitle">
				{#if heroDate}{heroDate}{/if}
				{#if heroDate && heroDistance}<span class="dot">&middot;</span>{/if}
				{#if heroDistance}{heroDistance}{/if}
			</p>
			{#if data.event?.club_name}
				<p class="host">{m('shareEvent.hostedBy', { club: data.event.club_name })}</p>
			{/if}
			<div class="hero-actions">
				<a class="btn btn-primary" href={appHref}>{m('shareRun.goToThrekir')}</a>
			</div>
		</section>
	{:else}
		<main class="content">
			<div class="notfound-card">
				<p class="kicker">{m('shareEvent.notFoundKicker')}</p>
				<h1>{m('shareEvent.notFoundTitle')}</h1>
				<p class="notfound-sub">{m('shareEvent.notFoundSub')}</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/login">{m('shareRun.signIn')}</a>
					<a class="btn btn-outline" href="/">{m('shareRun.goToThrekir')}</a>
				</div>
			</div>
		</main>
	{/if}

	{#if !auth.loggedIn && hasEvent}
		<section class="signup-cta" aria-labelledby="signup-cta-heading">
			<p class="kicker">{m('shareRun.ctaKicker')}</p>
			<h2 id="signup-cta-heading">{m('shareRun.ctaHeading')}</h2>
			<p class="signup-sub">{m('shareRun.ctaSub')}</p>
			<a class="btn btn-primary" href="/login?signup=1">{m('shareRun.ctaButton')}</a>
		</section>
	{/if}

	<footer class="share-footer">
		<a href="/">{m('shareRun.footerHome')}</a>
		<span class="dot">&middot;</span>
		<a href="/login">{m('shareRun.signIn')}</a>
	</footer>
</div>

<style>
	.share-page {
		min-height: 100vh;
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
	}
	.share-header {
		padding: var(--space-sm) var(--space-md);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}
	.share-logo {
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--color-primary);
		text-decoration: none;
	}
	.hero {
		max-width: 48rem;
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
	}
	.hero .subtitle {
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		margin: 0;
	}
	.host {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		margin: var(--space-xs) 0 0;
	}
	.hero-actions {
		margin-top: var(--space-md);
	}
	.dot {
		color: var(--color-text-tertiary);
		margin: 0 0.3rem;
	}
	.content {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-md);
	}
	.notfound-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl) var(--space-lg);
		margin-top: var(--space-xl);
		text-align: center;
	}
	.notfound-card h1 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
	}
	.notfound-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 28rem;
		margin: 0 auto var(--space-lg);
		line-height: 1.5;
	}
	.notfound-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
	}
	.signup-cta {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-lg) var(--space-md) var(--space-xl);
		text-align: center;
	}
	.signup-cta h2 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
	}
	.signup-cta .signup-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 32rem;
		margin: 0 auto var(--space-md);
		line-height: 1.5;
	}
	.share-footer {
		margin-top: auto;
		padding: var(--space-lg) var(--space-md);
		border-top: 1px solid var(--color-border);
		text-align: center;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		background: var(--color-surface);
	}
	.share-footer a {
		color: var(--color-text-secondary);
		text-decoration: none;
	}
	.share-footer a:hover {
		color: var(--color-primary);
	}
	@media (min-width: 48rem) {
		.share-header {
			padding: var(--space-md) var(--space-xl);
		}
		.hero {
			padding: var(--space-2xl) var(--space-xl) var(--space-lg);
		}
		.hero h1 {
			font-size: 2.5rem;
		}
	}
</style>
