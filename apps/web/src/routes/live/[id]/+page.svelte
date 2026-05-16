<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	import { formatDuration, formatPace, formatDistance } from '$lib/mock-data';
	import { supabase } from '$lib/supabase';
	import {
		isLiveHubConfigured,
		fetchLiveSnapshot,
		openLiveWebSocket,
		type LivePing,
	} from '$lib/live_hub';

	let { data } = $props();

	let mapContainer: HTMLDivElement;
	let map: maplibregl.Map;
	let runnerMarker: maplibregl.Marker;
	let elapsed = $state(0);
	let distance = $state(0);
	let currentPace = $state('--:--');
	type Status = 'connecting' | 'live' | 'finished' | 'demo' | 'error' | 'not-found';
	let status = $state<Status>('connecting');
	let demoTicker: ReturnType<typeof setInterval> | null = null;
	let realtimeChannel: ReturnType<typeof supabase.channel> | null = null;
	// Go live-hub teardown handle. Held alongside `realtimeChannel`
	// because exactly one of the two transports is active per session
	// — `subscribeLive` picks based on `isLiveHubConfigured()`.
	let liveHubHandle: { close: () => void } | null = null;

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
		// Stat-strip values update regardless of map readiness — a slow or
		// failing map style fetch (e.g. MapTiler down, missing key) must
		// not stall the LIVE badge or the distance / elapsed / pace
		// readout. Map-touching calls below are individually guarded.
		if (ping.distance_m != null) distance = ping.distance_m;
		if (ping.elapsed_s != null) elapsed = ping.elapsed_s;
		if (distance > 0 && elapsed > 0) currentPace = formatPace(elapsed, distance);

		if (!map) return;
		ensureMarker(ping.lat, ping.lng);
		if (!centred) {
			map.jumpTo({ center: [ping.lng, ping.lat], zoom: 15 });
			centred = true;
		} else {
			map.panTo([ping.lng, ping.lat], { animate: true });
		}
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
		if (isLiveHubConfigured()) {
			// Hub path: only the last-known ping is durable (Redis 24h
			// TTL in production). Earlier pings live on `live_run_pings`
			// only when the legacy transport is still writing — we
			// don't promise a full backlog here. A single snapshot is
			// enough to render the runner's current position
			// immediately on connect.
			const snap = await fetchLiveSnapshot(data.id);
			if (snap) {
				pushPing({
					lat: snap.lat,
					lng: snap.lng,
					distance_m: snap.distance_m ?? null,
					elapsed_s: snap.elapsed_s ?? null,
				});
				return true;
			}
			return false;
		}
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
		// Privacy-zone trust contract: pings are rendered verbatim. The
		// broadcaster's privacy zones are NOT fetched here (doing so
		// would defeat the purpose — anyone watching a public live run
		// could read off the broadcaster's home / work coordinates).
		// On the Supabase Realtime path, the single line of defence is
		// the `live_run_pings_drop_in_zone` BEFORE-INSERT trigger from
		// migration `20260618_001_clip_live_run_pings_to_privacy_zones.sql`,
		// which silently drops in-zone pings before they reach Realtime.
		// Pinned by `apps/backend/supabase/tests/rls_live_run_pings_trigger_test.sql`
		// so a future migration can't silently undo it. On the Go
		// live-hub path, the broadcaster (LiveBroadcaster) must apply
		// the same clip before it pushes to the hub — server-side
		// clipping is on the migration list (followups #13).
		if (isLiveHubConfigured()) {
			liveHubHandle = openLiveWebSocket(data.id, {
				onPing: (p: LivePing) => {
					pushPing({
						lat: p.lat,
						lng: p.lng,
						distance_m: p.distance_m ?? null,
						elapsed_s: p.elapsed_s ?? null,
					});
					if (status !== 'live') status = 'live';
				},
				onStatus: (s) => {
					// 'closed' surfaces if the hub goes down mid-run;
					// the openLiveWebSocket helper auto-reconnects, so
					// we flip the badge back to `connecting` rather
					// than terminal so the user sees recovery in
					// progress.
					if (s === 'closed' && status === 'live') {
						status = 'connecting';
					}
				},
			});
			return;
		}
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
		if (map) {
			ensureMarker(fallbackLat, fallbackLng);
			map.jumpTo({ center: [fallbackLng, fallbackLat], zoom: 15 });
		}
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

	async function ensureRunIsVisible(): Promise<boolean> {
		// Visibility check: the spectator surface is a public-broadcast
		// page, so the visible-runs set is exactly what `public_runs`
		// exposes (decisions §33, migration 20260626_001).
		// `runs.SELECT` is gated on the row's owner — anon gets no rows
		// — so a direct `from('runs')` query would false-negative on
		// the seeded public run for every anon viewer. The view's
		// `where is_public = true` is the load-bearing predicate.
		// Non-public / non-existent ids return null and we render the
		// not-broadcasting state instead of stalling at Connecting…
		const { data: row, error } = await supabase
			.from('public_runs')
			.select('id')
			.eq('id', data.id)
			.maybeSingle();
		if (error || !row) {
			status = 'not-found';
			return false;
		}
		return true;
	}

	onMount(() => {
		// Kick off the data path FIRST and independently of the map.
		// hydrateBacklog + subscribeLive don't need the map to be ready;
		// gating them behind `map.on('load')` means a slow (or failing)
		// MapTiler style fetch silently stalls the LIVE badge and the
		// stat strip. Pings that arrive before the map's source/layer
		// exist are buffered in `traceCoords` by pushPing; the map's
		// `load` handler below replays them once the source is added.
		(async () => {
			// Bail to the not-found state before touching the live-hub /
			// realtime channels for a run we can't see. Without this the
			// page sits at "Connecting…" then flips to "Demo" — a
			// confusing UX for a stale-share-link or a private-run anon
			// viewer.
			if (!(await ensureRunIsVisible())) return;
			const hadBacklog = await hydrateBacklog();
			subscribeLive();
			if (hadBacklog) {
				status = 'live';
			} else {
				setTimeout(() => {
					if (status === 'connecting' && traceCoords.length === 0) {
						startDemo();
					}
				}, 5000);
			}
		})();

		map = new maplibregl.Map({
			container: mapContainer,
			style: `https://api.maptiler.com/maps/streets-v2/style.json?key=${PUBLIC_MAPTILER_KEY}`,
			center: [fallbackLng, fallbackLat],
			zoom: 15,
		});
		map.addControl(new maplibregl.NavigationControl(), 'top-right');

		map.on('load', () => {
			map.addSource('live-trace', {
				type: 'geojson',
				data: {
					type: 'Feature',
					properties: {},
					geometry: { type: 'LineString', coordinates: traceCoords },
				},
			});
			map.addLayer({
				id: 'live-trace-line',
				type: 'line',
				source: 'live-trace',
				paint: { 'line-color': '#3b82f6', 'line-width': 3 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			// Pings that arrived before map readiness already filled
			// `traceCoords`; centre + marker if we have any so the user
			// doesn't see the fallback Sydney CBD on first paint.
			if (traceCoords.length > 0) {
				const last = traceCoords[traceCoords.length - 1];
				ensureMarker(last[1], last[0]);
				map.jumpTo({ center: [last[0], last[1]], zoom: 15 });
				centred = true;
			}
		});
	});

	onDestroy(() => {
		if (demoTicker) clearInterval(demoTicker);
		if (realtimeChannel) supabase.removeChannel(realtimeChannel);
		liveHubHandle?.close();
		map?.remove();
	});
</script>

<svelte:head>
	<title>Live Run — Run Onward</title>
	<meta name="description" content="Watch a runner's progress in real time" />
	<meta property="og:title" content="Live Run — Run Onward" />
	<meta property="og:description" content="Watch a runner's progress in real time" />
	<meta property="og:type" content="website" />
</svelte:head>

<!-- Public page — no sidebar, no auth required -->
<div class="live-page">
	<header class="live-header">
		<div class="live-logo">
			<img src="/icon-192.png" alt="" class="live-logo-mark" />
			Run Onward
		</div>
		<div
			class="live-badge"
			class:active={status === 'live'}
			class:demo={status === 'demo'}
			class:not-found={status === 'not-found'}
		>
			{#if status === 'connecting'}
				Connecting...
			{:else if status === 'live'}
				<span class="pulse-dot"></span> LIVE
			{:else if status === 'demo'}
				Demo
			{:else if status === 'finished'}
				Finished
			{:else if status === 'not-found'}
				Not broadcasting
			{:else}
				Connection lost
			{/if}
		</div>
	</header>

	{#if status === 'not-found'}
		<div class="live-empty">
			<h1>This run isn't broadcasting</h1>
			<p>
				The link may be stale, the run may have finished, or it may be private. Ask the runner
				to share a new live link if you expected to see something here.
			</p>
			<a href="/" class="btn btn-primary">Back to Run Onward</a>
		</div>
	{:else}
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
	{/if}
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
	.live-logo-mark {
		width: 2rem;
		height: 2rem;
		border-radius: var(--radius-md);
		display: block;
		object-fit: cover;
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

	.live-badge.not-found {
		background: #fee2e2;
		color: #991b1b;
	}

	.live-empty {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		text-align: center;
		padding: 2rem;
		gap: 1rem;
		color: var(--color-text-secondary);
	}

	.live-empty h1 {
		font-size: 1.5rem;
		color: var(--color-text);
		margin: 0;
	}

	.live-empty p {
		max-width: 32rem;
		margin: 0;
		line-height: 1.5;
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
