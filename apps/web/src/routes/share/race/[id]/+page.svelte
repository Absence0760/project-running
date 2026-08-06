<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import SharePageShell from '$lib/components/SharePageShell.svelte';
	import { safeHref } from '$lib/util/html_escape';
	import { formatKmStable, formatDateStable } from '$lib/share/share_meta';
	import {
		buildRaceJsonLd,
		buildRaceShareCanonical,
		buildRaceShareDescription,
		buildRaceShareTitle,
	} from '$lib/share/share_race_meta';

	let { data } = $props();

	let title = $derived(buildRaceShareTitle(data.race));
	let description = $derived(buildRaceShareDescription(data.race));
	let canonicalUrl = $derived(buildRaceShareCanonical(data.siteUrl, data.id));
	let jsonLd = $derived(buildRaceJsonLd(data.race, { id: data.id, base: data.siteUrl }));

	let hasRace = $derived(!!data.race);
	let heroDate = $derived(formatDateStable(data.race?.race_date));
	let heroDistance = $derived(formatKmStable(data.race?.distance_m));
	// entry_url is DB-constrained to http(s), but pass it through safeHref
	// defence-in-depth before it reaches the anchor.
	let entryHref = $derived(data.race?.entry_url ? safeHref(data.race.entry_url) : null);
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

<SharePageShell>
	{#if hasRace}
		<!-- The landmark rides the hero rather than a wrapper: .hero is a flex
		     child of SharePageShell's .share-page, so wrapping it would move
		     the flex child and reflow the page. -->
		<main class="hero" id="main-content">
			<p class="kicker">{m('shareRace.subtitle')}</p>
			<h1>{data.race?.name}</h1>
			<p class="subtitle">
				{#if heroDate}{heroDate}{/if}
				{#if heroDate && heroDistance}<span class="dot">&middot;</span>{/if}
				{#if heroDistance}{heroDistance}{/if}
			</p>
			{#if data.race?.location_label}
				<p class="host">{data.race.location_label}</p>
			{/if}
			<div class="hero-actions">
				{#if entryHref && entryHref !== '#'}
					<a class="btn btn-primary" href={entryHref} rel="nofollow noopener" target="_blank"
						>{m('shareRace.register')}</a
					>
				{/if}
				<a class="btn btn-outline" href="/races">{m('shareRace.calendar')}</a>
			</div>
		</main>
	{:else}
		<main class="content" id="main-content">
			<div class="notfound-card">
				<p class="kicker">{m('shareRun.notFoundKicker')}</p>
				<h1>{m('shareRace.notFoundTitle')}</h1>
				<p class="notfound-sub">{m('shareRace.notFoundSub')}</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/login">{m('shareRun.signIn')}</a>
					<a class="btn btn-outline" href="/">{m('shareRun.goToThrekir')}</a>
				</div>
			</div>
		</main>
	{/if}

	{#if !auth.loggedIn && hasRace}
		<section class="signup-cta" aria-labelledby="signup-cta-heading">
			<p class="kicker">{m('shareRun.ctaKicker')}</p>
			<h2 id="signup-cta-heading">{m('shareRun.ctaHeading')}</h2>
			<p class="signup-sub">{m('shareRun.ctaSub')}</p>
			<a class="btn btn-primary" href="/login?signup=1">{m('shareRun.ctaButton')}</a>
		</section>
	{/if}
</SharePageShell>

<style>
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
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
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
	@media (min-width: 48rem) {
		.hero {
			padding: var(--space-2xl) var(--space-xl) var(--space-lg);
		}
		.hero h1 {
			font-size: 2.5rem;
		}
	}
</style>
