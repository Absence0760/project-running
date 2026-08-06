<script lang="ts">
	import { browser } from '$app/environment';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import SeoHead from '$lib/components/SeoHead.svelte';
	import PublicHeader from '$lib/components/PublicHeader.svelte';
	import PublicFooter from '$lib/components/PublicFooter.svelte';
	import { buildOrganizationJsonLd, buildWebSiteJsonLd } from '$lib/share/site_meta';
	import { normaliseSiteUrl } from '$lib/share/share_meta';

	let { data } = $props();

	// The apex root is the single canonical home for the brand — set it
	// so the www/apex duplicate (both served by CloudFront) can't split
	// ranking signal, and so localized client-side variants of the
	// landing copy all fold onto one URL.
	const canonical = $derived(`${normaliseSiteUrl(data.siteUrl)}/`);
	const jsonLd = $derived([
		buildOrganizationJsonLd(data.siteUrl),
		buildWebSiteJsonLd(data.siteUrl),
	]);

	$effect(() => {
		if (browser && !auth.loading && auth.loggedIn) {
			goto('/dashboard', { replaceState: true });
		}
	});

	const showLanding = $derived(!browser || (!auth.loading && !auth.loggedIn));

	const apps = $derived([
		{
			icon: 'android',
			name: 'Android',
			tagline: 'Flutter · Material 3',
			body: m('landing.appAndroidBody'),
			comingSoon: true
		},
		{
			icon: 'phone_iphone',
			name: 'iOS',
			tagline: 'Flutter · Cupertino',
			body: m('landing.appIosBody'),
			comingSoon: true
		},
		{
			icon: 'watch',
			name: 'Apple Watch',
			tagline: 'Native SwiftUI',
			body: m('landing.appAppleWatchBody'),
			comingSoon: true
		},
		{
			icon: 'watch',
			name: 'Wear OS',
			tagline: 'Kotlin · Compose',
			body: m('landing.appWearOsBody'),
			comingSoon: true
		},
		{
			icon: 'desktop_windows',
			name: 'Web',
			tagline: 'SvelteKit',
			body: m('landing.appWebBody')
		}
	]);
</script>

<SeoHead
	title={m('landing.pageTitle')}
	description={m('landing.pageDescription')}
	{canonical}
	{jsonLd}
/>

{#if !showLanding}
	<div class="landing-loading">
		<span>{m('landing.loading')}</span>
	</div>
{:else}
<PublicHeader overlay />

<main class="hero">
	<h1>{m('landing.heroLine1')}<br />{m('landing.heroLine2')}<br />{m('landing.heroLine3')}</h1>
	<p class="hero-sub">
		{m('landing.heroSub')}
	</p>
	<div class="hero-actions">
		<a href="/login" class="btn btn-primary btn-lg">{m('landing.getStarted')}</a>
		<a href="#apps" class="btn btn-outline btn-lg">{m('landing.seeTheApps')}</a>
	</div>
</main>

<section id="features" class="features">
	<div class="feature">
		<span class="feature-icon material-symbols">route</span>
		<h3>{m('landing.featureRouteBuilderTitle')}</h3>
		<p>{m('landing.featureRouteBuilderBody')}</p>
	</div>
	<div class="feature">
		<span class="feature-icon material-symbols">watch</span>
		<h3>{m('landing.featureWatchParityTitle')}</h3>
		<p>{m('landing.featureWatchParityBody')}</p>
	</div>
	<div class="feature">
		<span class="feature-icon material-symbols">sync</span>
		<h3>{m('landing.featureSyncTitle')}</h3>
		<p>{m('landing.featureSyncBody')}</p>
	</div>
	<div class="feature">
		<span class="feature-icon material-symbols">analytics</span>
		<h3>{m('landing.featureAnalysisTitle')}</h3>
		<p>{m('landing.featureAnalysisBody')}</p>
	</div>
</section>

<section id="apps" class="apps-section">
	<div class="section-head">
		<h2>{m('landing.appsSectionTitle')}</h2>
		<p>{m('landing.appsSectionSub')}</p>
	</div>
	<div class="apps-grid">
		{#each apps as app}
			<article class="app-card" class:coming-soon={app.comingSoon}>
				<span class="app-icon material-symbols">{app.icon}</span>
				<h3>
					{app.name}
					{#if app.comingSoon}
						<span class="coming-soon-pill">{m('landing.comingSoon')}</span>
					{/if}
				</h3>
				<span class="app-tagline">{app.tagline}</span>
				<p>{app.body}</p>
			</article>
		{/each}
	</div>
</section>

<section class="closing-cta">
	<h2>{m('landing.closingTitle')}</h2>
	<p>{m('landing.closingBody')}</p>
	<a href="/login" class="btn btn-primary btn-lg">{m('landing.signInToContinue')}</a>
</section>

<PublicFooter />
{/if}

<style>
	.landing-loading {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		color: var(--color-text-tertiary);
		background: var(--color-bg);
	}

	.hero {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		min-height: 85vh;
		padding: var(--space-2xl);
		text-align: center;
		background: linear-gradient(150deg, #0F172A 0%, #1E1B4B 35%, #4F46E5 70%, #7C3AED 100%);
		position: relative;
		overflow: hidden;
	}

	.hero::before {
		content: '';
		position: absolute;
		top: -50%;
		right: -20%;
		width: 60%;
		height: 200%;
		background: radial-gradient(ellipse, rgba(236, 72, 153, 0.15) 0%, transparent 70%);
		pointer-events: none;
	}

	.hero::after {
		content: '';
		position: absolute;
		bottom: -30%;
		left: -10%;
		width: 50%;
		height: 150%;
		background: radial-gradient(ellipse, rgba(6, 182, 212, 0.1) 0%, transparent 70%);
		pointer-events: none;
	}

	h1 {
		font-size: 4rem;
		font-weight: 800;
		line-height: 1.08;
		letter-spacing: -0.03em;
		margin-bottom: var(--space-lg);
		color: #ffffff;
		position: relative;
		z-index: 1;
	}

	.hero-sub {
		font-size: 1.25rem;
		/* 20px normal weight is not WCAG large text, so this owes 4.5:1. At
		   0.65 it read 3.284:1 against the hero's palest stop (#7C3AED) and
		   3.582 against #4F46E5; 0.85 reads 4.534 and 5.004. */
		color: rgba(255, 255, 255, 0.85);
		max-width: 34rem;
		margin-bottom: var(--space-2xl);
		position: relative;
		z-index: 1;
		line-height: 1.55;
	}

	.hero-actions {
		display: flex;
		gap: var(--space-md);
		position: relative;
		z-index: 1;
	}

	.btn {
		padding: 0.75rem 1.75rem;
		border-radius: var(--radius-lg);
		font-weight: 600;
		font-size: 1rem;
		transition: all var(--transition-base);
		display: inline-block;
	}

	.btn-lg {
		padding: 0.875rem 2.25rem;
		font-size: 1.05rem;
	}

	.btn-primary {
		background: #ffffff;
		color: #4F46E5;
		border: none;
		box-shadow: 0 4px 14px rgba(0, 0, 0, 0.15);
	}

	.btn-primary:hover {
		background: #F0EFFF;
		transform: translateY(-1px);
		box-shadow: 0 6px 20px rgba(0, 0, 0, 0.2);
	}

	.btn-outline {
		border: 1.5px solid rgba(255, 255, 255, 0.35);
		color: #ffffff;
		background: rgba(255, 255, 255, 0.08);
		backdrop-filter: blur(8px);
	}

	.btn-outline:hover {
		border-color: rgba(255, 255, 255, 0.6);
		background: rgba(255, 255, 255, 0.15);
		transform: translateY(-1px);
	}

	.features {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--space-lg);
		padding: 4rem var(--space-2xl) 5rem;
		max-width: 72rem;
		margin: 0 auto;
	}

	.feature {
		text-align: center;
		padding: var(--space-xl);
		border-radius: var(--radius-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		box-shadow: var(--shadow-sm);
		transition: all var(--transition-base);
	}

	.feature:hover {
		transform: translateY(-4px);
		box-shadow: var(--shadow-lg);
		border-color: transparent;
	}

	.feature-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 2rem;
		margin-bottom: var(--space-md);
		display: flex;
		align-items: center;
		justify-content: center;
		width: 3.5rem;
		height: 3.5rem;
		border-radius: var(--radius-lg);
		margin-inline-start: auto;
		margin-inline-end: auto;
	}

	/* Four decorative accents, one per card. The frozen indigo / pink / emerald
	   / orange they replace each failed WCAG 1.4.11 in ONE theme on the tint it
	   painted over the card — 5.414 / 3.120 / 2.309 / 2.533:1 light and 2.386 /
	   4.069 / 5.543 / 5.045:1 dark — because a fixed hue cannot suit both a
	   near-white and a dark-violet card. Each is now a base token's 12% tint
	   under its own theme-aware -text ink, the pairing the status chips already
	   use, so both halves flip with the theme: 5.914 / 5.244 / 5.649 / 4.838
	   light and 6.205 / 5.971 / 6.565 / 6.054 dark. Colour carries nothing here
	   — the icon, heading and body each say what the card is — so the four are
	   picked for spread, not for meaning. */
	.feature:nth-child(1) .feature-icon {
		background: color-mix(in srgb, var(--color-primary) 12%, var(--color-surface));
		color: var(--color-primary);
	}
	.feature:nth-child(2) .feature-icon {
		background: color-mix(in srgb, var(--color-secondary) 12%, var(--color-surface));
		color: var(--color-secondary-text);
	}
	.feature:nth-child(3) .feature-icon {
		background: color-mix(in srgb, var(--color-success) 12%, var(--color-surface));
		color: var(--color-success-text);
	}
	.feature:nth-child(4) .feature-icon {
		background: color-mix(in srgb, var(--color-accent-cyan) 12%, var(--color-surface));
		color: var(--color-accent-cyan-text);
	}

	.feature h3 {
		font-size: 1.05rem;
		font-weight: 700;
		margin-bottom: var(--space-sm);
	}

	.feature p {
		font-size: 0.875rem;
		color: var(--color-text-secondary);
		line-height: 1.6;
	}

	.apps-section {
		padding: 5rem var(--space-2xl) 6rem;
		background: var(--color-bg-secondary);
		border-top: 1px solid var(--color-border);
		border-bottom: 1px solid var(--color-border);
	}

	.section-head {
		max-width: 44rem;
		margin: 0 auto var(--space-2xl);
		text-align: center;
	}

	.section-head h2 {
		font-size: 2.25rem;
		font-weight: 800;
		letter-spacing: -0.02em;
		margin-bottom: var(--space-md);
	}

	.section-head p {
		color: var(--color-text-secondary);
		font-size: 1.05rem;
	}

	.apps-grid {
		display: grid;
		grid-template-columns: repeat(5, 1fr);
		gap: var(--space-lg);
		max-width: 80rem;
		margin: 0 auto;
	}

	.app-card {
		padding: var(--space-xl);
		border-radius: var(--radius-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		box-shadow: var(--shadow-sm);
		transition: all var(--transition-base);
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}

	.app-card:hover {
		transform: translateY(-4px);
		box-shadow: var(--shadow-lg);
	}

	.app-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 1.75rem;
		width: 3rem;
		height: 3rem;
		border-radius: var(--radius-md);
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-primary-light);
		color: var(--color-primary);
		margin-bottom: var(--space-sm);
	}

	.app-card h3 {
		font-size: 1.05rem;
		font-weight: 700;
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}

	.coming-soon-pill {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		padding: 0.15rem 0.5rem;
		border-radius: 999px;
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		border: 1px solid var(--color-border);
		white-space: nowrap;
	}

	/* Tone down the card to read "planned, not shipping" — same layout,
	   muted icon + slightly lower contrast on body copy. Suppress the
	   hover lift too: nothing to click into, so the affordance would
	   over-promise. */
	.app-card.coming-soon .app-icon {
		background: var(--color-bg-secondary);
		color: var(--color-text-tertiary);
	}
	.app-card.coming-soon p {
		color: var(--color-text-tertiary);
	}
	.app-card.coming-soon:hover {
		transform: none;
		box-shadow: var(--shadow-sm);
	}

	.app-tagline {
		font-size: 0.75rem;
		font-weight: 600;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--color-text-tertiary);
	}

	.app-card p {
		margin-top: var(--space-sm);
		font-size: 0.88rem;
		line-height: 1.55;
		color: var(--color-text-secondary);
	}

	.closing-cta {
		padding: 5rem var(--space-2xl);
		text-align: center;
		background: linear-gradient(135deg, #1E1B4B 0%, #4F46E5 100%);
		color: #ffffff;
	}

	.closing-cta h2 {
		font-size: 2rem;
		font-weight: 800;
		letter-spacing: -0.02em;
		margin-bottom: var(--space-sm);
	}

	.closing-cta p {
		color: rgba(255, 255, 255, 0.75);
		margin-bottom: var(--space-xl);
		font-size: 1.05rem;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}

	@media (max-width: 960px) {
		.features { grid-template-columns: repeat(2, 1fr); }
		.apps-grid { grid-template-columns: repeat(2, 1fr); }
	}

	@media (max-width: 768px) {
		h1 { font-size: 2.5rem; }
		.section-head h2 { font-size: 1.75rem; }
		.apps-grid { grid-template-columns: 1fr; }
	}
</style>
