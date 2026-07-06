<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import Avatar from '$lib/components/Avatar.svelte';
	import {
		buildClubJsonLd,
		buildClubShareCanonical,
		buildClubShareDescription,
		buildClubShareTitle,
	} from '$lib/share/share_club_meta';

	let { data } = $props();

	let title = $derived(buildClubShareTitle(data.club));
	let description = $derived(buildClubShareDescription(data.club));
	let canonicalUrl = $derived(buildClubShareCanonical(data.siteUrl, data.slug));
	let jsonLd = $derived(buildClubJsonLd(data.club, { slug: data.slug, base: data.siteUrl }));
	let ogImage = $derived(data.club?.avatar_url || '/og-default.png');

	let hasClub = $derived(!!data.club);
	let appHref = $derived(`/clubs/${data.slug}`);
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
	<meta property="og:image" content={ogImage} />
	<meta name="twitter:card" content="summary" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content={ogImage} />
	{@html `<script type="application/ld+json">${jsonLd}</script>`}
</svelte:head>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">Threkir</a>
	</header>

	{#if hasClub}
		<section class="hero">
			<div class="avatar-wrap">
				<Avatar name={data.club?.name ?? null} url={data.club?.avatar_url ?? null} size="96px" font="2.2rem" bg="seed" />
			</div>
			<p class="kicker">{m('shareClub.subtitle')}</p>
			<h1>{data.club?.name}</h1>
			{#if data.club?.location_label}
				<p class="host">{data.club.location_label}</p>
			{/if}
			{#if data.club?.description}
				<p class="desc">{data.club.description}</p>
			{/if}
			<div class="hero-actions">
				<a class="btn btn-primary" href={appHref}>{m('shareRun.goToThrekir')}</a>
			</div>
		</section>
	{:else}
		<main class="content">
			<div class="notfound-card">
				<p class="kicker">{m('shareRun.notFoundKicker')}</p>
				<h1>{m('shareClub.notFoundTitle')}</h1>
				<p class="notfound-sub">{m('shareClub.notFoundSub')}</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/login">{m('shareRun.signIn')}</a>
					<a class="btn btn-outline" href="/">{m('shareRun.goToThrekir')}</a>
				</div>
			</div>
		</main>
	{/if}

	{#if !auth.loggedIn && hasClub}
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
	.avatar-wrap {
		display: flex;
		justify-content: center;
		margin-bottom: var(--space-md);
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
	.host {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm);
	}
	.desc {
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		max-width: 34rem;
		margin: 0 auto;
		line-height: 1.5;
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
