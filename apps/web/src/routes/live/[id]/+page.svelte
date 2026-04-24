<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	import { formatDuration, formatPace, formatDistance } from '$lib/mock-data';
	import { supabase } from '$lib/supabase';

	let { data } = $props();

	let mapContainer: HTMLDivElement;
	let map: maplibregl.Map;
	let runnerMarker: maplibregl.Marker;
	let elapsed = $state(0);
	let distance = $state(0);
	let currentPace = $state('--:--');
	type Status = 'connecting' | 'live' | 'finished' | 'demo' | 'error';
	let status = $state<Status>('connecting');
	let demoTicker: ReturnType<typeof setInterval> | null = null;
	let realtimeChannel: ReturnType<typeof supabase.channel> | null = null;

	// Runner position + completed trace. Held as mutable module-scope
	// state rather than `$state` because MapLibre mutates the GeoJSON
	// source directly and the chrome doesn't need to re-render on every
	// tick (only the stat strip below does).
	const traceCoords: [number, number][] = [];

	// Used to compute the initial map centre when the first ping arrives
	// so the view snaps to the runner regardless of geography.
	let centred = false;

	// Defaults that match the simulation: Melbourne CBD so the map isn't
	// blank during `connecting` or `demo` with no credentials.
	const fallbackLat = -37.8136;
	const fallbackLng = 144.9631;

	function ensureMarker(lat: number, lng: number) {
		if (!map) return;
		if (!runnerMarker) {
			const el = document.createElement('div');
			el.className = 'runner-dot';
			runnerMarker = new maplibregl.Marker({ element: el })
				.setLngLat([lng, lat])
				.addTo(map);
		} else {
			runnerMarker.setLngLat([lng, lat]);
		}
	}

	function pushPing(ping: {
		lat: number;
		lng: number;
		distance_m?: number | null;
		elapsed_s?: number | null;
	}) {
		traceCoords.push([ping.lng, ping.lat]);
		ensureMarker(ping.lat, ping.lng);
		if (!centred) {
			map.jumpTo({ center: [ping.lng, ping.lat], zoom: 15 });
			centred = true;
		} else {
			map.panTo([ping.lng, ping.lat], { animate: true });
		}
		if (ping.distance_m != null) distance = ping.distance_m;
		if (ping.elapsed_s != null) elapsed = ping.elapsed_s;
		if (distance > 0 && elapsed > 0) currentPace = formatPace(elapsed, distance);

		const source = map.getSource('live-trace') as maplibregl.GeoJSONSource | undefined;
		source?.setData({
			type: 'Feature',
			properties: {},
			geometry: { type: 'LineString', coordinates: traceCoords },
		});
	}

	async function hydrateBacklog() {
		// Fetch any pings already logged for this run so a spectator
		// joining mid-run sees the trace so far, not just what arrives
		// after they connect.
		const { data: rows, error } = await supabase
			.from('live_run_pings')
			.select('lat, lng, distance_m, elapsed_s, at')
			.eq('run_id', data.id)
			.order('at', { ascending: true });
		if (error || !rows || rows.length === 0) return false;
		for (const row of rows) pushPing(row);
		return true;
	}

	function subscribeLive() {
		realtimeChannel = supabase
			.channel(`live-run:${data.id}`)
			.on(
				'postgres_changes',
				{
					event: 'INSERT',
					schema: 'public',
					table: 'live_run_pings',
					filter: `run_id=eq.${data.id}`,
				},
				(payload) => {
					const row = payload.new as {
						lat: number;
						lng: number;
						distance_m: number | null;
						elapsed_s: number | null;
					};
					pushPing(row);
					if (status !== 'live') status = 'live';
				},
			)
			.subscribe();
	}

	function startDemo() {
		// Keeps the spectator page informative for demos and in
		// development — when no pings are flowing, a synthesised track
		// animates around the fallback centre so the surface still
		// looks alive. Badge flips to "demo" so it's obvious this isn't
		// a real feed.
		status = 'demo';
		ensureMarker(fallbackLat, fallbackLng);
		map.jumpTo({ center: [fallbackLng, fallbackLat], zoom: 15 });
		let angle = 0;
		demoTicker = setInterval(() => {
			angle += 0.02;
			elapsed += 3;
			distance += 12 + Math.random() * 5;
			const lng = fallbackLng + Math.cos(angle) * 0.005;
			const lat = fallbackLat + Math.sin(angle) * 0.003;
			pushPing({ lat, lng, distance_m: distance, elapsed_s: elapsed });
		}, 3000);
	}

	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: `https://api.maptiler.com/maps/streets-v2/style.json?key=${PUBLIC_MAPTILER_KEY}`,
			center: [fallbackLng, fallbackLat],
			zoom: 15,
		});
		map.addControl(new maplibregl.NavigationControl(), 'top-right');

		map.on('load', async () => {
			map.addSource('live-trace', {
				type: 'geojson',
				data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } },
			});
			map.addLayer({
				id: 'live-trace-line',
				type: 'line',
				source: 'live-trace',
				paint: { 'line-color': '#3b82f6', 'line-width': 3 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});

			const hadBacklog = await hydrateBacklog();
			subscribeLive();

			if (hadBacklog) {
				status = 'live';
			} else {
				// No data yet — give the recorder a short grace period to
				// emit a ping before falling back to the demo animation.
				setTimeout(() => {
					if (status === 'connecting' && traceCoords.length === 0) {
						startDemo();
					}
				}, 5000);
			}
		});
	});

	onDestroy(() => {
		if (demoTicker) clearInterval(demoTicker);
		if (realtimeChannel) supabase.removeChannel(realtimeChannel);
		map?.remove();
	});
</script>

<svelte:head>
	<title>Live Run — Better Runner</title>
	<meta name="description" content="Watch a runner's progress in real time" />
	<meta property="og:title" content="Live Run — Better Runner" />
	<meta property="og:description" content="Watch a runner's progress in real time" />
	<meta property="og:type" content="website" />
</svelte:head>

<!-- Public page — no sidebar, no auth required -->
<div class="live-page">
	<header class="live-header">
		<div class="live-logo">
			<span class="logo-icon">&#9654;</span> Run
		</div>
		<div class="live-badge" class:active={status === 'live'} class:demo={status === 'demo'}>
			{#if status === 'connecting'}
				Connecting...
			{:else if status === 'live'}
				<span class="pulse-dot"></span> LIVE
			{:else if status === 'demo'}
				Demo
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
				<span class="live-stat-value">{currentPace}</span>
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

	.live-badge.demo {
		background: #fef3c7;
		color: #92400e;
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
