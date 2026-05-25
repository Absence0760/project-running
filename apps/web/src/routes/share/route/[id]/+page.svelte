<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDistance } from '$lib/mock-data';
	import { fetchRouteById } from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
	import RunMap from '$lib/components/RunMap.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import { buildRouteShareDescription, buildRouteShareTitle } from '$lib/share_meta';
	import type { Route, TrackPoint } from '$lib/types';

	let { data } = $props();

	let route = $state<Route | null>(null);
	let waypoints = $state<TrackPoint[]>([]);
	let loading = $state(true);
	let notFound = $state(false);

	onMount(async () => {
		// `fetchRouteById` is the owner-aware reader: owner / club member
		// gets the full route via RLS; anon / non-owner gets the
		// `public_routes` view (no `geom` / `start_point`) plus
		// server-side privacy-zone clipping for `waypoints`.
		const r = await fetchRouteById(data.id);
		if (!r) {
			notFound = true;
		} else {
			route = r;
			waypoints = (r.waypoints ?? []) as TrackPoint[];
		}
		loading = false;
	});

	let elevations = $derived(waypoints.map((w) => w.ele ?? 0));
	let hasElevationData = $derived(
		elevations.length > 1 && Math.max(...elevations) > Math.min(...elevations)
	);
	let metaSource = $derived(route ?? data.route ?? null);
	let pageTitle = $derived(buildRouteShareTitle(metaSource));
	let pageDesc = $derived(buildRouteShareDescription(metaSource));
</script>

<svelte:head>
	<title>{pageTitle}</title>
	<meta name="description" content={pageDesc} />
	<meta property="og:title" content={pageTitle} />
	<meta property="og:description" content={pageDesc} />
	<meta property="og:type" content="website" />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content="/og/route/{data.id}.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={pageTitle} />
	<meta name="twitter:description" content={pageDesc} />
	<meta name="twitter:image" content="/og/route/{data.id}.png" />
</svelte:head>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">Threkir</a>
	</header>

	{#if loading}
		<div class="content"><p class="status">Loading…</p></div>
	{:else if notFound}
		<div class="content">
			<div class="notfound-card">
				<p class="kicker">Nothing to see here</p>
				<h1>Route not found or is private.</h1>
				<p class="notfound-sub">
					This link may have expired, the route may have been deleted, or its owner may have made it
					private.
				</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/login">Sign in</a>
					<a class="btn btn-outline" href="/">Go to Threkir</a>
				</div>
			</div>
		</div>
	{:else if route}
		<section class="hero">
			<p class="kicker">A public route</p>
			<h1>{route.name}</h1>
			<p class="route-meta">
				<span>{formatDistance(route.distance_m)}</span>
				{#if route.elevation_m}
					<span class="meta-sep">&middot;</span>
					<span>{route.elevation_m} m elevation</span>
				{/if}
				<span class="meta-sep">&middot;</span>
				<span class="surface-tag">{route.surface}</span>
			</p>
		</section>

		<main class="content">
			{#if waypoints.length > 0}
				<div class="map-container">
					<RunMap track={waypoints} requireExplicitConsent />
				</div>

				{#if hasElevationData}
					<section class="card">
						<h2>Elevation Profile</h2>
						<ElevationProfile {elevations} totalDistance={route.distance_m} />
					</section>
				{/if}
			{/if}
		</main>

		{#if !auth.loggedIn}
			<section class="signup-cta" aria-labelledby="signup-cta-heading">
				<p class="kicker">Make it yours</p>
				<h2 id="signup-cta-heading">Sign up to run this route</h2>
				<p class="signup-sub">
					Free. Save routes, record runs, view splits and elevation, follow friends.
				</p>
				<a class="btn btn-primary" href="/login?signup=1">Sign up for Free</a>
			</section>
		{/if}
	{/if}

	<footer class="share-footer">
		<a href="/">Threkir home</a>
		<span class="dot">&middot;</span>
		<a href="/login">Sign in</a>
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
		color: var(--color-text);
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

	.status {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl) 0;
	}

	h2 {
		font-size: 0.9rem;
		font-weight: 600;
		margin: 0 0 var(--space-md);
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.route-meta {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-xs);
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		margin: 0;
		flex-wrap: wrap;
	}

	.meta-sep {
		color: var(--color-text-tertiary);
	}

	.surface-tag {
		text-transform: capitalize;
	}

	.map-container {
		height: 22rem;
		border-radius: var(--radius-lg);
		overflow: hidden;
		margin-bottom: var(--space-md);
		border: 1px solid var(--color-border);
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-md);
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
		text-transform: none;
		letter-spacing: 0;
		color: var(--color-text);
	}

	.signup-cta .signup-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 32rem;
		margin: 0 auto var(--space-md);
		line-height: 1.5;
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
		.hero .route-meta {
			font-size: 1rem;
		}
		.content {
			padding: var(--space-md) var(--space-xl);
		}
		.map-container {
			height: 26rem;
		}
		.signup-cta {
			padding: var(--space-xl) var(--space-xl) var(--space-2xl);
		}
		.signup-cta h2 {
			font-size: 1.6rem;
		}
	}
</style>
