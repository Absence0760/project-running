<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDistance } from '$lib/mock-data';
	import { fetchPublicRoute } from '$lib/data';
	import RunMap from '$lib/components/RunMap.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import type { Route } from '$lib/types';

	let { data } = $props();

	let route = $state<Route | null>(null);
	let loading = $state(true);
	let notFound = $state(false);

	onMount(async () => {
		route = await fetchPublicRoute(data.id);
		if (!route) notFound = true;
		loading = false;
	});

	let elevations = $derived(route?.waypoints?.map((w) => w.ele ?? 0) ?? []);
</script>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">
			<span class="logo-icon">&#9654;</span> Run
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

			{#if route.waypoints.length > 0}
				<div class="map-container">
					<RunMap track={route.waypoints} />
				</div>

				<section class="card">
					<h2>Elevation Profile</h2>
					<ElevationProfile {elevations} totalDistance={route.distance_m} />
				</section>
			{/if}

			<div class="cta">
				<p>Want to run this route?</p>
				<a href="/login" class="btn btn-primary">Sign up free</a>
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

	.btn-primary {
		display: inline-block;
		padding: var(--space-sm) var(--space-xl);
		background: var(--color-primary);
		color: white;
		border-radius: var(--radius-md);
		font-weight: 600;
	}

	.btn-primary:hover {
		background: var(--color-primary-hover);
	}
</style>
