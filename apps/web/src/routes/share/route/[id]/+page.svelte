<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDistance } from '$lib/mock-data';
	import { fetchRouteById } from '$lib/data';
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
		// server-side privacy-zone clipping for `waypoints`. The wire
		// never carries unclipped polyline to a non-owner viewer; no
		// client-side clip pass needed here.
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
	// Head meta uses the thin projection from +page.ts (baked into
	// the prerendered HTML), with the body-fetched `route` as the
	// browser-side upgrade once the owner-aware fetch lands.
	let metaSource = $derived(route ?? data.route ?? null);
	let pageTitle = $derived(buildRouteShareTitle(metaSource));
	let pageDesc = $derived(buildRouteShareDescription(metaSource));
</script>

<svelte:head>
	<title>{pageTitle}</title>
	<meta name="description" content={pageDesc} />
	<!-- Open Graph — Facebook, LinkedIn, Slack, Discord, iMessage all
	     read the og:* tags for the unfurl preview. og:image points at
	     a generic static asset for now; a per-route track-preview PNG
	     would be a follow-up that needs a server-side image renderer. -->
	<meta property="og:title" content={pageTitle} />
	<meta property="og:description" content={pageDesc} />
	<meta property="og:type" content="website" />
	<meta property="og:site_name" content="Run Onward" />
	<meta property="og:image" content="/apple-touch-icon.png" />
	<!-- Twitter / X — `summary_large_image` so the unfurl renders the
	     full og:image rather than a tiny icon. -->
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={pageTitle} />
	<meta name="twitter:description" content={pageDesc} />
	<meta name="twitter:image" content="/apple-touch-icon.png" />
</svelte:head>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">
			Run Onward
		</a>
	</header>

	{#if loading}
		<div class="content"><p class="status">Loading...</p></div>
	{:else if notFound}
		<div class="content">
			<p class="status">Route not found or is private.</p>
			<a href="/" class="home-link">Go to home page</a>
		</div>
	{:else if route}
		<div class="content">
			<h1>{route.name}</h1>
			<div class="route-meta">
				<span>{formatDistance(route.distance_m)}</span>
				{#if route.elevation_m}
					<span class="meta-sep">&middot;</span>
					<span>{route.elevation_m} m elevation</span>
				{/if}
				<span class="meta-sep">&middot;</span>
				<span class="surface-tag">{route.surface}</span>
			</div>

			{#if waypoints.length > 0}
				<div class="map-container">
					<RunMap track={waypoints} />
				</div>

				{#if hasElevationData}
					<section class="card">
						<h2>Elevation Profile</h2>
						<ElevationProfile {elevations} totalDistance={route.distance_m} />
					</section>
				{/if}
			{/if}

			<div class="cta">
				<p>Want to run this route?</p>
				<a href="/login?signup=1" class="btn btn-primary">Sign up for Free</a>
			</div>
		</div>
	{/if}
</div>

<style>
	.share-page {
		min-height: 100vh;
		background: var(--color-bg);
	}

	.share-header {
		padding: var(--space-md) var(--space-xl);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}

	.share-logo {
		font-weight: 700;
		font-size: 1.25rem;
		color: var(--color-primary);
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}

	.content {
		max-width: 56rem;
		margin: 0 auto;
		padding: var(--space-xl) var(--space-2xl);
	}

	.status {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.home-link {
		display: block;
		text-align: center;
		color: var(--color-primary);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: var(--space-xs);
	}

	h2 {
		font-size: 0.9rem;
		font-weight: 600;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.route-meta {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-xl);
	}

	.meta-sep {
		color: var(--color-text-tertiary);
	}

	.surface-tag {
		text-transform: capitalize;
	}

	.map-container {
		height: 24rem;
		border-radius: var(--radius-lg);
		overflow: hidden;
		margin-bottom: var(--space-xl);
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-xl);
	}

	.cta {
		text-align: center;
		padding: var(--space-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}

	.cta p {
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
	}

</style>
