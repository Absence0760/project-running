<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { mapStyleUrlFromEnv } from '$lib/map-style.svelte';
	import { watchMapResize } from '$lib/map_resize';
	import { formatDuration, formatPace, formatDistance } from '$lib/mock-data';
	import { supabase } from '$lib/supabase';
	import { hasAcceptedConsent } from '$lib/consent.svelte';
	import {
		isLiveHubConfigured,
		fetchLiveSnapshot,
		openLiveWebSocket,
		type LivePing,
	} from '$lib/live_hub';

	// audit/cookie-consent (2026-05-25): MapTiler tile fetches log
	// requester IPs per tile, so initialising MapLibre before consent
	// has been recorded leaks an EU visitor's IP to a US sub-processor
	// before any banner action. The live spectator page is anon-
	// accessible, so we gate the map init either on the global consent
	// state (banner-accepted) or on an explicit "Load map" click here.
	let mapConsented = $state(false);

	let { data } = $props();

	let mapContainer: HTMLDivElement;
	let map: maplibregl.Map;
	let runnerMarker: maplibregl.Marker;
	let stopResizeWatch: (() => void) | null = null;
	let elapsed = $state(0);
	let distance = $state(0);
	let currentPace = $state('--:--');
	let runnerName = $state<string | null>(null);
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

	function initials(name: string): string {
		const parts = name.trim().split(/\s+/).slice(0, 2);
		return parts.map((p) => p.charAt(0).toUpperCase()).join('') || '?';
	}

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
		if (isLiveHubConfigured()) {
			// Forward the viewer's Supabase JWT so the Go authorizer
			// accepts the request on private runs (public runs work
			// either way). /audit/livehub May 2026 C1.
			const sess = (await supabase.auth.getSession()).data.session;
			const snap = await fetchLiveSnapshot(data.id, sess?.access_token ?? null);
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
			// JWT goes on the WS upgrade URL as `?token=…`; browsers can't
			// set Authorization headers on a WS upgrade. /audit/livehub C1.
			(async () => {
				const sess = (await supabase.auth.getSession()).data.session;
				const token = sess?.access_token ?? null;
				liveHubHandle = openLiveWebSocket(data.id, {
					accessToken: token,
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
					if (s === 'closed' && status === 'live') {
						status = 'connecting';
					}
				},
			});
			})();
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

	type VisibleRun = {
		user_id: string;
		started_at: string;
		duration_s: number;
		distance_m: number;
	};
	let visibleRun: VisibleRun | null = null;

	async function ensureRunIsVisible(): Promise<boolean> {
		// Visibility check: the spectator surface is a public-broadcast
		// page, so the visible-runs set is exactly what `public_runs`
		// exposes (decisions §33, migration 20260626_001).
		const { data: row, error } = await supabase
			.from('public_runs')
			.select('id, user_id, started_at, duration_s, distance_m')
			.eq('id', data.id)
			.maybeSingle();
		if (error || !row) {
			status = 'not-found';
			return false;
		}
		visibleRun = {
			user_id: row.user_id as string,
			started_at: row.started_at as string,
			duration_s: Number(row.duration_s ?? 0),
			distance_m: Number(row.distance_m ?? 0),
		};
		if (row.user_id) {
			// `public_profiles` is the anon-readable projection of
			// user_profiles (migration 20260824_001). The base table is
			// owner-only via RLS, so reading it directly from an anon
			// spectator session returns no rows and the runner falls
			// back to "Anonymous runner".
			const { data: profile } = await supabase
				.from('public_profiles')
				.select('display_name')
				.eq('id', row.user_id)
				.maybeSingle();
			if (profile?.display_name) runnerName = profile.display_name;
		}
		return true;
	}

	// A run is treated as already finished if its saved duration places
	// its end >2 minutes in the past. The 2 min slack covers the gap
	// between the last ping and the recorder posting the final row +
	// any clock skew. While finished, the spectator surface freezes on
	// the saved totals and skips the demo / realtime paths — opening a
	// stale share link to a completed run should read "Finished" with
	// final stats, not loop forever on "Connecting…" or "LIVE".
	function runIsFinished(r: VisibleRun): boolean {
		if (!r.duration_s || r.duration_s <= 0) return false;
		const endedMs = new Date(r.started_at).getTime() + r.duration_s * 1000;
		return Number.isFinite(endedMs) && endedMs < Date.now() - 2 * 60 * 1000;
	}

	onMount(() => {
		// Honour the global banner choice. The "Load map" button below
		// is the per-page acceptance path when the banner hasn't been
		// answered yet.
		if (hasAcceptedConsent()) mapConsented = true;
		(async () => {
			if (!(await ensureRunIsVisible())) return;
			if (visibleRun && runIsFinished(visibleRun)) {
				distance = visibleRun.distance_m;
				elapsed = visibleRun.duration_s;
				if (distance > 0 && elapsed > 0) currentPace = formatPace(elapsed, distance);
				// Best-effort backlog hydrate so the map still gets the
				// trace shape, but don't open realtime / demo — the run
				// is over.
				await hydrateBacklog();
				status = 'finished';
				return;
			}
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

		if (mapConsented) initMap();
	});

	function loadMapNow() {
		mapConsented = true;
		// $effect below would normally pick this up, but the map
		// container only mounts when `mapConsented` flips, so we wait
		// one microtask for the DOM to render before initialising.
		queueMicrotask(initMap);
	}

	function initMap() {
		if (map || !mapContainer) return;
		map = new maplibregl.Map({
			container: mapContainer,
			// Honours PUBLIC_TILE_STYLE_URL override the same way every
			// other map surface does (decisions.md § 68). `prefersDark`
			// isn't read here — the live spectator page renders dark
			// the same way the run-detail map does (the helper handles
			// the OS-preference path internally).
			style: mapStyleUrlFromEnv(
				PUBLIC_MAPTILER_KEY,
				typeof window !== 'undefined' &&
					window.matchMedia('(prefers-color-scheme: dark)').matches,
			),
			center: [fallbackLng, fallbackLat],
			zoom: 15,
		});
		map.addControl(new maplibregl.NavigationControl(), 'top-right');
		stopResizeWatch = watchMapResize(mapContainer, map);

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
				paint: { 'line-color': '#2C5F6E', 'line-width': 3 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			if (traceCoords.length > 0) {
				const last = traceCoords[traceCoords.length - 1];
				ensureMarker(last[1], last[0]);
				map.jumpTo({ center: [last[0], last[1]], zoom: 15 });
				centred = true;
			}
		});
	}

	onDestroy(() => {
		if (demoTicker) clearInterval(demoTicker);
		if (realtimeChannel) supabase.removeChannel(realtimeChannel);
		liveHubHandle?.close();
		stopResizeWatch?.();
		map?.remove();
	});
</script>

<svelte:head>
	<title>Live Run — Threkir</title>
	<meta name="description" content="Watch a runner's progress in real time" />
	<meta property="og:title" content="Live Run — Threkir" />
	<meta property="og:description" content="Watch a runner's progress in real time" />
	<meta property="og:type" content="website" />
</svelte:head>

<!-- Public page — no sidebar, no auth required -->
<div class="live-page">
	<header class="live-header">
		<a href="/" class="live-logo">
			<img src="/icon-192.png" alt="" class="live-logo-mark" />
			Threkir
		</a>
		<div
			class="live-badge"
			class:active={status === 'live'}
			class:demo={status === 'demo'}
			class:finished={status === 'finished'}
			class:not-found={status === 'not-found'}
		>
			{#if status === 'connecting'}
				<span class="badge-spinner" aria-hidden="true"></span>
				Connecting…
			{:else if status === 'live'}
				<span class="pulse-dot"></span> LIVE
			{:else if status === 'demo'}
				Demo feed
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
			<div class="live-empty-icon" aria-hidden="true">
				<span class="material-symbols">satellite_alt</span>
			</div>
			<h1>This run isn't broadcasting</h1>
			<p>
				The link may be stale, the run may have finished, or it may be private. Ask the runner
				to share a new live link if you expected to see something here.
			</p>
			<a href="/" class="btn btn-primary">Back to Threkir</a>
		</div>
	{:else}
		<section class="live-strip" aria-label="Live status">
			<div class="live-runner">
				<span class="avatar" aria-hidden="true">{initials(runnerName ?? 'R')}</span>
				<div class="live-runner-text">
					<span class="live-runner-name">{runnerName ?? 'Anonymous runner'}</span>
					<span class="live-runner-sub">
						{#if status === 'connecting'}
							Waiting for the first ping
						{:else if status === 'demo'}
							Synthesised demo data
						{:else if status === 'live'}
							Live from the runner's device
						{:else if status === 'finished'}
							Run finished
						{:else}
							Reconnecting
						{/if}
					</span>
				</div>
			</div>
			<div class="live-stats" role="group" aria-label="Live stats">
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
		</section>

		<div class="live-map-wrap">
			{#if mapConsented}
				<div class="live-map" bind:this={mapContainer}></div>
				{#if status === 'connecting'}
					<div class="map-veil" aria-hidden="true">
						<div class="map-veil-card">
							<span class="badge-spinner" aria-hidden="true"></span>
							<p>Waiting for the runner to start broadcasting…</p>
						</div>
					</div>
				{/if}
			{:else}
				<!--
					audit/cookie-consent (2026-05-25): MapTiler logs the
					requester IP per tile fetch. Anonymous visitors on a
					shared-link page must opt in explicitly before the
					map mounts (ePrivacy / GDPR). A "Load map" tap is the
					affirmative act that satisfies the disclosure.
				-->
				<div class="map-consent-veil">
					<div class="map-consent-card">
						<h2>Map disabled until you load it</h2>
						<p>
							Loading the map sends your IP address to <strong>MapTiler</strong>,
							our tile provider in Switzerland. Tap <strong>Load map</strong>
							below to continue. Your choice is remembered only for this page
							session — the global setting lives in our
							<a href="/cookie-notice">cookie notice</a>.
						</p>
						<button type="button" class="btn btn-primary" onclick={loadMapNow}>
							Load map
						</button>
					</div>
				</div>
			{/if}
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
		text-decoration: none;
	}
	.live-logo-mark {
		width: 2rem;
		height: 2rem;
		border-radius: var(--radius-md);
		display: block;
		object-fit: cover;
	}

	.live-badge {
		display: inline-flex;
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
		border: 1px solid var(--color-border);
	}

	.live-badge.active {
		background: var(--color-success-light);
		color: var(--color-success);
		border-color: color-mix(in srgb, var(--color-success) 35%, transparent);
	}

	.live-badge.demo {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: var(--color-warning);
		border-color: color-mix(in srgb, var(--color-warning) 35%, transparent);
	}

	.live-badge.not-found {
		background: var(--color-danger-light);
		color: var(--color-danger);
		border-color: color-mix(in srgb, var(--color-danger) 35%, transparent);
	}

	.live-badge.finished {
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
		border-color: var(--color-border);
	}

	.pulse-dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--color-success);
		animation: pulse 1.5s ease-in-out infinite;
	}
	.badge-spinner {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		border: 2px solid currentColor;
		border-top-color: transparent;
		animation: spin 0.9s linear infinite;
		display: inline-block;
	}
	@keyframes pulse {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.3; }
	}
	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	.live-empty {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		text-align: center;
		padding: var(--space-2xl) var(--space-xl);
		gap: var(--space-md);
		color: var(--color-text-secondary);
	}

	.live-empty-icon {
		width: 4rem;
		height: 4rem;
		border-radius: 50%;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		display: flex;
		align-items: center;
		justify-content: center;
		margin-bottom: var(--space-xs);
	}
	.live-empty-icon .material-symbols {
		font-size: 2rem;
		color: var(--color-text-tertiary);
	}

	.live-empty h1 {
		font-size: 1.6rem;
		color: var(--color-text);
		margin: 0;
		font-weight: 800;
	}

	.live-empty p {
		max-width: 32rem;
		margin: 0;
		line-height: 1.5;
	}

	.live-strip {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-lg);
		padding: var(--space-md) var(--space-xl);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border);
		flex-wrap: wrap;
		/* Container query target — lets the inner stats row adapt
		 * to the strip's actual width regardless of viewport
		 * (forward-compat if the page ever gains a side panel). */
		container-type: inline-size;
		container-name: live-strip;
	}

	.live-runner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		min-width: 0;
	}
	.avatar {
		width: 2.75rem;
		height: 2.75rem;
		border-radius: 50%;
		background: var(--color-primary-light);
		color: var(--color-primary);
		display: inline-flex;
		align-items: center;
		justify-content: center;
		font-weight: 800;
		font-size: 0.95rem;
		letter-spacing: 0.02em;
		flex-shrink: 0;
	}
	.live-runner-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.live-runner-name {
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.live-runner-sub {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}

	.live-stats {
		display: flex;
		gap: var(--space-2xl);
		align-items: center;
	}

	.live-stat {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		min-width: 4.5rem;
	}

	.live-stat-value {
		font-size: 1.5rem;
		font-weight: 800;
		font-variant-numeric: tabular-nums;
		letter-spacing: -0.01em;
		line-height: 1.05;
	}

	.live-stat-label {
		font-size: 0.68rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-weight: 600;
		margin-top: var(--space-2xs);
	}

	@media (max-width: 48rem) {
		.live-strip {
			flex-direction: column;
			align-items: stretch;
			gap: var(--space-md);
		}
		.live-stats {
			justify-content: space-around;
			gap: var(--space-md);
		}
		.live-stat {
			align-items: center;
		}
	}

	/* Container-query mirror of the viewport rule above. Triggers
	 * when the strip itself goes narrow (i.e. parent gives it less
	 * room) even if the viewport is wide. Matches the panel-
	 * polish pattern from /runs/[id] + /routes/[id]. */
	@container live-strip (max-width: 36rem) {
		.live-stat-value {
			font-size: 1.25rem;
		}
		.live-stats {
			gap: var(--space-md);
		}
	}
	@container live-strip (max-width: 28rem) {
		.live-stat {
			min-width: 3rem;
		}
		.live-stat-value {
			font-size: 1.1rem;
		}
		.live-runner-name {
			font-size: 0.9rem;
		}
	}

	.live-map-wrap {
		flex: 1;
		position: relative;
		min-height: 0;
	}
	.live-map {
		position: absolute;
		inset: 0;
	}
	.map-veil {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		pointer-events: none;
		background: color-mix(in srgb, var(--color-bg) 35%, transparent);
	}
	.map-veil-card {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		color: var(--color-text-secondary);
		font-size: 0.88rem;
	}
	.map-veil-card p {
		margin: 0;
	}
	.map-consent-veil {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-bg);
		padding: var(--space-md);
	}
	.map-consent-card {
		max-width: 30rem;
		padding: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-md);
		text-align: left;
	}
	.map-consent-card h2 { margin: 0 0 var(--space-sm); font-size: 1.1rem; }
	.map-consent-card p { margin: 0 0 var(--space-md); line-height: 1.5; color: var(--color-text-secondary); font-size: 0.92rem; }

	:global(.runner-dot) {
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: var(--color-primary);
		border: 3px solid var(--color-surface);
		box-shadow: 0 0 0 4px color-mix(in srgb, var(--color-primary) 30%, transparent),
			0 2px 6px rgba(0, 0, 0, 0.3);
	}
</style>
