<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	import { formatDuration, formatPace, formatDistance } from '$lib/mock-data';

	let { data } = $props();

	let mapContainer: HTMLDivElement;
	let map: maplibregl.Map;
	let runnerMarker: maplibregl.Marker;
	let elapsed = $state(0);
	let distance = $state(0);
	let currentPace = $state('--:--');
	let status = $state<'connecting' | 'live' | 'finished' | 'error'>('connecting');
	let interval: ReturnType<typeof setInterval>;

	// Simulated runner position (demo mode)
	const baseLat = -37.8136;
	const baseLng = 144.9631;
	let angle = 0;

	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: `https://api.maptiler.com/maps/streets-v2/style.json?key=${PUBLIC_MAPTILER_KEY}`,
			center: [baseLng, baseLat],
			zoom: 15
		});

		map.addControl(new maplibregl.NavigationControl(), 'top-right');

		// Runner marker
		const el = document.createElement('div');
		el.className = 'runner-dot';
		runnerMarker = new maplibregl.Marker({ element: el })
			.setLngLat([baseLng, baseLat])
			.addTo(map);

		map.on('load', () => {
			// Trace line for completed path
			map.addSource('live-trace', {
				type: 'geojson',
				data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } }
			});

			map.addLayer({
				id: 'live-trace-line',
				type: 'line',
				source: 'live-trace',
				paint: { 'line-color': '#3b82f6', 'line-width': 3 },
				layout: { 'line-join': 'round', 'line-cap': 'round' }
			});

			// Simulate live updates (replace with WebSocket in Phase 2)
			status = 'live';
			const traceCoords: [number, number][] = [];

			interval = setInterval(() => {
				angle += 0.02;
				elapsed += 3;
				distance += 12 + Math.random() * 5;

				const lng = baseLng + Math.cos(angle) * 0.005;
				const lat = baseLat + Math.sin(angle) * 0.003;

				traceCoords.push([lng, lat]);
				runnerMarker.setLngLat([lng, lat]);
				map.panTo([lng, lat], { animate: true });

				currentPace = formatPace(elapsed, distance);

				const source = map.getSource('live-trace') as maplibregl.GeoJSONSource;
				source?.setData({
					type: 'Feature',
					properties: {},
					geometry: { type: 'LineString', coordinates: traceCoords }
				});
			}, 3000);
		});
	});

	onDestroy(() => {
		clearInterval(interval);
		map?.remove();
	});
</script>

<!-- Public page — no sidebar, no auth required -->
<div class="live-page">
	<header class="live-header">
		<div class="live-logo">
			<span class="logo-icon">&#9654;</span> Run
		</div>
		<div class="live-badge" class:active={status === 'live'}>
			{#if status === 'connecting'}
				Connecting...
			{:else if status === 'live'}
				<span class="pulse-dot"></span> LIVE
			{:else if status === 'finished'}
				Finished
			{:else}
				Connection lost
			{/if}
		</div>
	</header>

	<div class="live-layout">
		<div class="live-map" bind:this={mapContainer}></div>

		<div class="live-stats">
			<div class="live-stat">
				<span class="live-stat-value">{formatDistance(distance)}</span>
				<span class="live-stat-label">Distance</span>
			</div>
			<div class="live-stat">
				<span class="live-stat-value">{formatDuration(elapsed)}</span>
				<span class="live-stat-label">Elapsed</span>
			</div>
			<div class="live-stat">
				<span class="live-stat-value">{currentPace} /km</span>
				<span class="live-stat-label">Pace</span>
			</div>
		</div>
	</div>
</div>

<style>
	.live-page {
		display: flex;
		flex-direction: column;
		height: 100vh;
		background: var(--color-bg);
	}

	.live-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-md) var(--space-xl);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}

	.live-logo {
		font-weight: 700;
		font-size: 1.25rem;
		color: var(--color-primary);
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}

	.live-badge {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		padding: var(--space-xs) var(--space-md);
		border-radius: 9999px;
		font-size: 0.75rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
	}

	.live-badge.active {
		background: #dcfce7;
		color: #16a34a;
	}

	.pulse-dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: #16a34a;
		animation: pulse 1.5s ease-in-out infinite;
	}

	@keyframes pulse {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.3; }
	}

	.live-layout {
		flex: 1;
		display: flex;
		flex-direction: column;
	}

	.live-map {
		flex: 1;
	}

	.live-stats {
		display: flex;
		justify-content: center;
		gap: var(--space-2xl);
		padding: var(--space-lg) var(--space-xl);
		background: var(--color-surface);
		border-top: 1px solid var(--color-border);
	}

	.live-stat {
		display: flex;
		flex-direction: column;
		align-items: center;
	}

	.live-stat-value {
		font-size: 1.75rem;
		font-weight: 700;
		font-family: 'SF Mono', 'Menlo', monospace;
	}

	.live-stat-label {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	:global(.runner-dot) {
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: #3b82f6;
		border: 3px solid white;
		box-shadow: 0 0 0 4px rgba(59, 130, 246, 0.3), 0 2px 6px rgba(0, 0, 0, 0.3);
	}
</style>
