<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDistance } from '$lib/mock-data';
	import { toGpx, toKml, downloadFile } from '$lib/gpx';
	import { fetchRouteById } from '$lib/data';
	import { supabase } from '$lib/supabase';
	import RunMap from '$lib/components/RunMap.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import type { Route } from '$lib/types';

	let { data } = $props();

	let route = $state<Route | null>(null);
	let loading = $state(true);

	onMount(async () => {
		route = await fetchRouteById(data.id);
		loading = false;
	});

	let shareLink = $state('');
	let shareCopied = $state(false);

	function handleExportGpx() {
		if (!route || !route.waypoints.length) return;
		const coords: [number, number][] = route.waypoints.map((w) => [w.lng, w.lat]);
		const eles = route.waypoints.map((w) => w.ele ?? 0);
		const gpx = toGpx(route.name, coords, eles);
		const filename = route.name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_') + '.gpx';
		downloadFile(gpx, filename, 'application/gpx+xml');
	}

	function handleExportKml() {
		if (!route || !route.waypoints.length) return;
		const coords: [number, number][] = route.waypoints.map((w) => [w.lng, w.lat]);
		const eles = route.waypoints.map((w) => w.ele ?? 0);
		const kml = toKml(route.name, coords, eles);
		const filename = route.name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_') + '.kml';
		downloadFile(kml, filename, 'application/vnd.google-earth.kml+xml');
	}

	async function handleShare() {
		if (!route) return;
		// Make route public if it isn't already
		if (!route.is_public) {
			await supabase.from('routes').update({ is_public: true }).eq('id', route.id);
			route.is_public = true;
		}
		shareLink = `${window.location.origin}/share/route/${route.id}`;
		shareCopied = false;
	}

	async function copyShareLink() {
		await navigator.clipboard.writeText(shareLink);
		shareCopied = true;
		setTimeout(() => (shareCopied = false), 2000);
	}

	let elevations = $derived(route?.waypoints?.map((w) => w.ele ?? 0) ?? []);
</script>

{#if loading}
	<div class="page"><p class="loading">&nbsp;</p></div>
{:else if route}
	<div class="page">
		<a href="/routes" class="back-link">
			<span class="material-symbols">arrow_back</span>
			Routes
		</a>

		<header class="detail-header">
			<div>
				<h1>{route.name}</h1>
				<div class="route-meta">
					<span>{formatDistance(route.distance_m)}</span>
					{#if route.elevation_m}
						<span class="meta-sep">&middot;</span>
						<span>{route.elevation_m} m elevation gain</span>
					{/if}
					<span class="meta-sep">&middot;</span>
					<span class="surface-tag">{route.surface}</span>
				</div>
			</div>
			<div class="actions">
				<button class="btn btn-outline" onclick={handleExportGpx}>GPX</button>
				<button class="btn btn-outline" onclick={handleExportKml}>KML</button>
				<button class="btn btn-primary" onclick={handleShare}>Share</button>
			</div>
		</header>

		{#if shareLink}
			<div class="share-bar">
				<input type="text" readonly value={shareLink} />
				<button class="btn btn-outline" onclick={copyShareLink}>
					{shareCopied ? 'Copied!' : 'Copy'}
				</button>
			</div>
		{/if}

		{#if route.waypoints.length > 0}
			<div class="map-container">
				<RunMap track={route.waypoints} />
			</div>

			<section class="card">
				<h2>Elevation Profile</h2>
				<ElevationProfile {elevations} totalDistance={route.distance_m} />
			</section>
		{:else}
			<div class="map-container">
				<div class="map-placeholder">
					<span class="material-symbols">map</span>
					<p>No waypoint data available</p>
				</div>
			</div>
		{/if}
	</div>
{/if}

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 56rem;
	}

	.loading {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-lg);
		transition: color var(--transition-fast);
	}

	.back-link:hover {
		color: var(--color-primary);
	}

	.detail-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		margin-bottom: var(--space-xl);
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
	}

	.meta-sep {
		color: var(--color-text-tertiary);
	}

	.surface-tag {
		text-transform: capitalize;
	}

	.actions {
		display: flex;
		gap: var(--space-sm);
	}

	.btn {
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.85rem;
		transition: all var(--transition-fast);
		cursor: pointer;
	}

	.btn-outline {
		background: transparent;
		border: 1.5px solid var(--color-border);
		color: var(--color-text);
	}

	.btn-outline:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.btn-primary {
		background: var(--color-primary);
		color: white;
		border: none;
	}

	.btn-primary:hover {
		background: var(--color-primary-hover);
	}

	.share-bar {
		display: flex;
		gap: var(--space-sm);
		margin-bottom: var(--space-xl);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}

	.share-bar input {
		flex: 1;
		padding: var(--space-xs) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		background: var(--color-surface);
		font-family: 'SF Mono', 'Menlo', monospace;
	}

	.map-container {
		margin-bottom: var(--space-xl);
		height: 24rem;
		border-radius: var(--radius-lg);
		overflow: hidden;
	}

	.map-placeholder {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		height: 100%;
		background: var(--color-bg-tertiary);
		color: var(--color-text-tertiary);
		gap: var(--space-sm);
	}

	.map-placeholder .material-symbols {
		font-size: 3rem;
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
</style>
