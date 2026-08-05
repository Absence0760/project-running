<script lang="ts">
	import RunShareView from '$lib/components/RunShareView.svelte';
	import SharePageShell from '$lib/components/SharePageShell.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { isLiveBroadcast } from '$lib/runs/live_broadcast';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		buildRunJsonLd,
		buildRunShareCanonical,
		buildRunShareDescription,
		buildRunShareTitle,
		formatKmStable,
		formatDateStable,
	} from '$lib/share/share_meta';

	let { data } = $props();

	let title = $derived(buildRunShareTitle(data.run, data.displayName));
	let description = $derived(buildRunShareDescription(data.run, data.displayName));
	// Absolute canonical so search engines fold the in-app /runs/[id]
	// surface (which canonicals here) onto this single public page —
	// parity with share/route, which already does both this + JSON-LD.
	let canonicalUrl = $derived(buildRunShareCanonical(data.siteUrl, data.id));
	// JSON-LD WebPage + breadcrumb. Injected via {@html} because a
	// literal <script> in Svelte markup would be hoisted/compiled; the
	// builder pre-escapes < / > / & so a malicious caption can't
	// terminate the script element.
	let jsonLd = $derived(
		buildRunJsonLd(data.run, {
			id: data.id,
			base: data.siteUrl,
			displayName: data.displayName,
		})
	);

	let heroDistance = $derived(formatKmStable(data.run?.distance_m));
	let heroDate = $derived(formatDateStable(data.run?.started_at));
	let heroAthlete = $derived(data.displayName ?? '');
	// The runner's own caption is the headline they screenshot for social
	// (persona round-5); prefer it for the hero <h1>, falling back to the
	// "<athlete>'s run" framing when the run has no caption.
	let heroCaption = $derived(
		(((data.run?.metadata as Record<string, unknown> | null)?.title as string) ?? '').trim()
	);
	let hasRun = $derived(!!data.run);
	// A run still being broadcast is a 0 km / 0:00 stub here — without this the
	// page presented it as a finished run of nothing and gave the spectator no
	// route to the tracker they actually came for.
	let live = $derived(isLiveBroadcast(data.run));
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<link rel="canonical" href={canonicalUrl} />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="article" />
	<meta property="og:url" content={canonicalUrl} />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content="/og/run/{data.id}.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content="/og/run/{data.id}.png" />
	{@html `<script type="application/ld+json">${jsonLd}</script>`}
</svelte:head>

<SharePageShell>
	{#if hasRun}
		<section class="hero">
			<p class="kicker">{m('shareRun.heroKicker')}</p>
			<h1>
				{#if heroCaption}{heroCaption}{:else if heroAthlete}{m('shareRun.heroAthleteRun', { name: heroAthlete })}{:else}{m('shareRun.heroPublicRun')}{/if}
			</h1>
			<p class="subtitle">
				{#if heroDistance}{heroDistance}{/if}
				{#if heroDistance && heroDate}<span class="dot">&middot;</span>{/if}
				{#if heroDate}{heroDate}{/if}
			</p>
		</section>

		{#if live}
			<section class="live-cta" data-testid="share-run-live-cta">
				<p class="kicker"><span class="live-dot" aria-hidden="true"></span>{m('shareRun.liveKicker')}</p>
				<p class="live-sub">{m('shareRun.liveSub')}</p>
				<a class="btn btn-primary" href="/live/{data.id}">{m('shareRun.liveWatch')}</a>
			</section>
		{/if}

		<main class="content">
			<RunShareView runId={data.id} headerless hideAnonCta />
		</main>
	{:else}
		<main class="content">
			<div class="notfound-card">
				<p class="kicker">{m('shareRun.notFoundKicker')}</p>
				<h1>{m('shareRun.notFoundTitle')}</h1>
				<p class="notfound-sub">
					{m('shareRun.notFoundSub')}
				</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/login">{m('shareRun.signIn')}</a>
					<a class="btn btn-outline" href="/">{m('shareRun.goToThrekir')}</a>
				</div>
			</div>
		</main>
	{/if}

	{#if !auth.loggedIn && hasRun}
		<section class="signup-cta" aria-labelledby="signup-cta-heading">
			<p class="kicker">{m('shareRun.ctaKicker')}</p>
			<h2 id="signup-cta-heading">{m('shareRun.ctaHeading')}</h2>
			<p class="signup-sub">
				{m('shareRun.ctaSub')}
			</p>
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

	.dot {
		color: var(--color-text-tertiary);
		margin: 0 0.3rem;
	}

	.live-cta {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-lg) var(--space-md);
		text-align: center;
		background: var(--color-success-light);
		border-block: 1px solid var(--color-success);
	}

	.live-cta .kicker {
		color: var(--color-success-text);
	}

	.live-dot {
		display: inline-block;
		inline-size: 0.5rem;
		block-size: 0.5rem;
		border-radius: 50%;
		background: var(--color-success);
		margin-inline-end: 0.4rem;
	}

	.live-sub {
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-md);
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
		.hero .subtitle {
			font-size: 1rem;
		}
		.content {
			padding: var(--space-md) var(--space-xl);
		}
		.signup-cta {
			padding: var(--space-xl) var(--space-xl) var(--space-2xl);
		}
		.signup-cta h2 {
			font-size: 1.6rem;
		}
	}
</style>
