<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';
	import { mapStyleUrl, getMapStyle } from '$lib/map-style.svelte';
	import { supabase } from '$lib/supabase';
	import {
		fetchRecentRacePings,
		fetchRaceSession,
		fetchEventById,
		fetchEventResults,
		type RacePingRow,
		type RaceSessionRow,
		type EventResultWithUser
	} from '$lib/data';
	import type { EventWithMeta } from '$lib/types';
	import type { RealtimeChannel } from '@supabase/supabase-js';

	// Route params: event id + ISO `instance_start`. The instance value
	// is URL-encoded by the organiser's "Spectator view" link on the
	// event page.
	let eventId = $derived($page.params.id as string);
	let instance = $derived(decodeURIComponent($page.params.instance as string));

	let event = $state<EventWithMeta | null>(null);
	let race = $state<RaceSessionRow | null>(null);
	let recentPings = $state<RacePingRow[]>([]);
	let results = $state<EventResultWithUser[]>([]);
	let profiles = $state<Map<string, { display_name: string | null }>>(new Map());
	let nowTick = $state(Date.now());
	let loading = $state(true);

	let channel: RealtimeChannel | null = null;

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;

	// Latest ping per user (the leaderboard view), sorted by distance desc.
	let pings = $derived.by(() => {
		const byUser = new Map<string, RacePingRow>();
		for (const p of recentPings) {
			if (!byUser.has(p.user_id)) byUser.set(p.user_id, p);
		}
		return [...byUser.values()].sort((a, b) => (b.distance_m ?? 0) - (a.distance_m ?? 0));
	});

	// Per-user trail (chronological, oldest -> newest). Capped to keep
	// long races bounded; 30 samples ≈ 5 minutes at 10 s cadence.
	const TRAIL_CAP = 30;
	let trailsByUser = $derived.by(() => {
		const byUser = new Map<string, RacePingRow[]>();
		// recentPings is newest-first; reverse to chronological so the
		// LineString runs in time order.
		for (let i = recentPings.length - 1; i >= 0; i--) {
			const p = recentPings[i];
			const arr = byUser.get(p.user_id) ?? [];
			arr.push(p);
			byUser.set(p.user_id, arr);
		}
		for (const [u, arr] of byUser) {
			if (arr.length > TRAIL_CAP) byUser.set(u, arr.slice(arr.length - TRAIL_CAP));
		}
		return byUser;
	});

	// Stable hue per user_id so each runner keeps the same colour across
	// re-renders. Uses the golden-angle trick to spread hues nicely.
	function hueFor(userId: string): number {
		let h = 0;
		for (let i = 0; i < userId.length; i++) h = (h * 31 + userId.charCodeAt(i)) | 0;
		return ((h % 360) + 360) % 360;
	}

	function colorFor(userId: string): string {
		return `hsl(${hueFor(userId)}, 70%, 50%)`;
	}

	async function load() {
		const [e, rs, ps, rr] = await Promise.all([
			fetchEventById(eventId),
			fetchRaceSession(eventId, instance),
			fetchRecentRacePings(eventId, instance),
			fetchEventResults(eventId, instance)
		]);
		event = e;
		race = rs;
		recentPings = ps;
		results = rr;
		// Collect display names for every user_id referenced by pings + results.
		const ids = new Set<string>();
		for (const p of ps) ids.add(p.user_id);
		for (const r of rr) ids.add(r.user_id);
		if (ids.size > 0) {
			const { data } = await supabase
				.from('user_profiles')
				.select('id, display_name')
				.in('id', [...ids]);
			const map = new Map<string, { display_name: string | null }>();
			for (const p of data ?? []) map.set(p.id, { display_name: p.display_name });
			profiles = map;
		}
		loading = false;
	}

	function subscribe() {
		channel = supabase
			.channel(`live-event-${eventId}-${instance}`)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'race_pings',
					filter: `event_id=eq.${eventId}`
				},
				async () => {
					recentPings = await fetchRecentRacePings(eventId, instance);
				}
			)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'race_sessions',
					filter: `event_id=eq.${eventId}`
				},
				async () => {
					race = await fetchRaceSession(eventId, instance);
				}
			)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'event_results',
					filter: `event_id=eq.${eventId}`
				},
				async () => {
					results = await fetchEventResults(eventId, instance);
				}
			)
			.subscribe();
	}

	onMount(async () => {
		await load();
		subscribe();
	});

	onDestroy(() => {
		if (channel) supabase.removeChannel(channel);
		map?.remove();
	});

	let tickTimer: ReturnType<typeof setInterval> | null = null;
	$effect(() => {
		if (race?.status === 'running') {
			tickTimer = setInterval(() => (nowTick = Date.now()), 1000);
			return () => {
				if (tickTimer) clearInterval(tickTimer);
				tickTimer = null;
			};
		}
	});

	let raceElapsedS = $derived(
		race?.status === 'running' && race.started_at
			? Math.max(0, Math.floor((nowTick - new Date(race.started_at).getTime()) / 1000))
			: race?.status === 'finished' && race.started_at && race.finished_at
			? Math.max(
					0,
					Math.floor(
						(new Date(race.finished_at).getTime() -
							new Date(race.started_at).getTime()) /
							1000
					)
			  )
			: 0
	);

	function formatDuration(s: number): string {
		if (s <= 0) return '—';
		const h = Math.floor(s / 3600);
		const m = Math.floor((s % 3600) / 60);
		const sec = s % 60;
		if (h > 0) {
			return `${h}:${m.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`;
		}
		return `${m}:${sec.toString().padStart(2, '0')}`;
	}

	function paceSecPerKm(p: RacePingRow): number | null {
		if (!p.distance_m || p.distance_m < 50 || !p.elapsed_s || p.elapsed_s < 10) return null;
		return p.elapsed_s / (p.distance_m / 1000);
	}

	function formatPace(secPerKm: number | null): string {
		if (secPerKm === null) return '—';
		const m = Math.floor(secPerKm / 60);
		const s = Math.round(secPerKm % 60);
		return `${m}:${s.toString().padStart(2, '0')}/km`;
	}

	function nameFor(userId: string): string {
		return profiles.get(userId)?.display_name ?? 'Runner';
	}

	// --- Map ---

	let mapContainer: HTMLDivElement;
	let map: maplibregl.Map | null = null;
	let mapReady = $state(false);
	let didFitBounds = false;

	function buildPositionsGeoJSON(): GeoJSON.FeatureCollection<GeoJSON.Point, { user_id: string; color: string; label: string }> {
		const features: GeoJSON.Feature<GeoJSON.Point, { user_id: string; color: string; label: string }>[] = [];
		pings.forEach((p, i) => {
			features.push({
				type: 'Feature',
				geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
				properties: {
					user_id: p.user_id,
					color: colorFor(p.user_id),
					label: String(i + 1)
				}
			});
		});
		return { type: 'FeatureCollection', features };
	}

	function buildTrailsGeoJSON(): GeoJSON.FeatureCollection<GeoJSON.LineString, { user_id: string; color: string }> {
		const features: GeoJSON.Feature<GeoJSON.LineString, { user_id: string; color: string }>[] = [];
		for (const [userId, trail] of trailsByUser) {
			if (trail.length < 2) continue;
			features.push({
				type: 'Feature',
				geometry: {
					type: 'LineString',
					coordinates: trail.map((p) => [p.lng, p.lat])
				},
				properties: { user_id: userId, color: colorFor(userId) }
			});
		}
		return { type: 'FeatureCollection', features };
	}

	function addOverlays() {
		if (!map) return;
		map.addSource('runner-trails', { type: 'geojson', data: buildTrailsGeoJSON() });
		map.addSource('runner-positions', { type: 'geojson', data: buildPositionsGeoJSON() });

		map.addLayer({
			id: 'runner-trails-line',
			type: 'line',
			source: 'runner-trails',
			paint: {
				'line-color': ['get', 'color'],
				'line-width': 3,
				'line-opacity': 0.7
			},
			layout: { 'line-join': 'round', 'line-cap': 'round' }
		});

		map.addLayer({
			id: 'runner-position-halo',
			type: 'circle',
			source: 'runner-positions',
			paint: {
				'circle-radius': 13,
				'circle-color': ['get', 'color'],
				'circle-opacity': 0.25
			}
		});

		map.addLayer({
			id: 'runner-position-dot',
			type: 'circle',
			source: 'runner-positions',
			paint: {
				'circle-radius': 7,
				'circle-color': ['get', 'color'],
				'circle-stroke-color': prefersDark ? '#0f172a' : '#ffffff',
				'circle-stroke-width': 2
			}
		});

		map.addLayer({
			id: 'runner-position-label',
			type: 'symbol',
			source: 'runner-positions',
			layout: {
				'text-field': ['get', 'label'],
				'text-size': 11,
				'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
				'text-allow-overlap': true,
				'text-offset': [0, -1.2]
			},
			paint: {
				'text-color': prefersDark ? '#F1F5F9' : '#1E293B',
				'text-halo-color': prefersDark ? '#0f172a' : '#ffffff',
				'text-halo-width': 1.5
			}
		});
	}

	function refreshMapData() {
		if (!map || !mapReady) return;
		const trails = map.getSource('runner-trails') as maplibregl.GeoJSONSource | undefined;
		const positions = map.getSource('runner-positions') as maplibregl.GeoJSONSource | undefined;
		trails?.setData(buildTrailsGeoJSON());
		positions?.setData(buildPositionsGeoJSON());

		// Fit bounds once the first batch of positions arrives. After that
		// we leave the user in control of pan/zoom.
		if (!didFitBounds && pings.length > 0) {
			const lngs = pings.map((p) => p.lng);
			const lats = pings.map((p) => p.lat);
			const bounds: maplibregl.LngLatBoundsLike = [
				[Math.min(...lngs), Math.min(...lats)],
				[Math.max(...lngs), Math.max(...lats)]
			];
			map.fitBounds(bounds, { padding: 60, maxZoom: 16, duration: 0 });
			didFitBounds = true;
		}
	}

	$effect(() => {
		// Initialise the map lazily once we have at least one ping. Until
		// then, the empty-state card is shown instead of a blank map.
		if (!mapContainer || map || pings.length === 0) return;
		const first = pings[0];
		map = new maplibregl.Map({
			container: mapContainer,
			style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
			center: [first.lng, first.lat],
			zoom: 13
		});
		map.addControl(new maplibregl.NavigationControl(), 'top-right');
		map.on('load', () => {
			mapReady = true;
			addOverlays();
			refreshMapData();
		});
	});

	// Re-push GeoJSON whenever pings arrive.
	$effect(() => {
		// Touch reactive deps so this re-runs.
		void pings;
		void trailsByUser;
		refreshMapData();
	});

	// Reactive map-style swap (re-attach overlays after style.load).
	let currentStyle: ReturnType<typeof getMapStyle> = getMapStyle();
	$effect(() => {
		const next = getMapStyle();
		if (!map || next === currentStyle) return;
		currentStyle = next;
		mapReady = false;
		map.setStyle(mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark));
		map.once('style.load', () => {
			mapReady = true;
			addOverlays();
			refreshMapData();
		});
	});
</script>

<svelte:head>
	<title>Live race — {event?.title ?? 'Event'}</title>
</svelte:head>

<div class="page">
	<header>
		<h1>{event?.title ?? 'Live race'}</h1>
		{#if race}
			<p class="status-row">
				<span class="status-dot status-{race.status}"></span>
				<strong>{race.status.toUpperCase()}</strong>
				{#if race.status === 'running' || race.status === 'finished'}
					· elapsed {formatDuration(raceElapsedS)}
				{/if}
			</p>
		{:else}
			<p class="muted">No race session yet for this instance.</p>
		{/if}
	</header>

	{#if loading}
		<p class="muted">Loading…</p>
	{:else}
		{#if pings.length > 0}
			<section class="card map-card">
				<div bind:this={mapContainer} class="race-map"></div>
			</section>
		{/if}

		<section class="card">
			<h2>Runners on course ({pings.length})</h2>
			{#if pings.length === 0}
				<p class="muted">No live position data yet. Runners' watches / phones will push pings every ~10 seconds once the race starts.</p>
			{:else}
				<ol class="runners">
					{#each pings as p, i (p.user_id)}
						<li class="runner">
							<span class="pos">{i + 1}</span>
							<span class="swatch" style="background: {colorFor(p.user_id)}"></span>
							<span class="name">{nameFor(p.user_id)}</span>
							<span class="dist">{((p.distance_m ?? 0) / 1000).toFixed(2)} km</span>
							<span class="pace">{formatPace(paceSecPerKm(p))}</span>
							<span class="elapsed">{formatDuration(p.elapsed_s ?? 0)}</span>
						</li>
					{/each}
				</ol>
			{/if}
		</section>

		{#if results.length > 0}
			<section class="card">
				<h2>Finished ({results.filter((r) => r.finisher_status === 'finished').length})</h2>
				<ol class="runners">
					{#each results as r (r.user_id)}
						<li class="runner" class:pending={!r.organiser_approved}>
							<span class="pos">{r.organiser_approved ? (r.rank ?? '—') : '…'}</span>
							<span class="swatch" style="background: {colorFor(r.user_id)}"></span>
							<span class="name">{nameFor(r.user_id)}</span>
							{#if r.finisher_status !== 'finished'}
								<span class="dnf">{r.finisher_status.toUpperCase()}</span>
							{:else}
								<span class="dist">{(r.distance_m / 1000).toFixed(2)} km</span>
								<span class="elapsed">{formatDuration(r.duration_s)}</span>
							{/if}
							{#if !r.organiser_approved}
								<span class="pending-tag">PENDING</span>
							{/if}
						</li>
					{/each}
				</ol>
			</section>
		{/if}
	{/if}
</div>

<style>
	.page {
		max-width: 60rem;
		margin: 0 auto;
		padding: 1.5rem;
	}
	h1 {
		font-size: 1.6rem;
		font-weight: 700;
		margin: 0 0 0.3rem;
	}
	h2 {
		font-size: 0.9rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-secondary);
		margin-bottom: 0.8rem;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: 0.6rem;
		padding: 1rem;
		margin-bottom: 1.2rem;
	}
	.map-card {
		padding: 0;
		overflow: hidden;
	}
	.race-map {
		width: 100%;
		height: 24rem;
	}
	.status-row {
		display: flex;
		align-items: center;
		gap: 0.4rem;
	}
	.status-dot {
		display: inline-block;
		width: 0.65rem;
		height: 0.65rem;
		border-radius: 50%;
	}
	.status-armed { background: #f59e0b; }
	.status-running {
		background: #10b981;
		animation: pulse 1s infinite;
	}
	.status-finished { background: #6b7280; }
	.status-cancelled { background: #ef4444; }
	@keyframes pulse {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.4; }
	}
	.runners {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.runner {
		display: grid;
		grid-template-columns: 2rem 0.8rem 1fr auto auto auto auto;
		align-items: center;
		gap: 0.6rem;
		padding: 0.5rem 0.7rem;
		background: var(--color-bg);
		border-radius: 0.4rem;
		font-size: 0.9rem;
	}
	.runner.pending { opacity: 0.7; }
	.pos {
		font-weight: 700;
		color: var(--color-primary);
		font-variant-numeric: tabular-nums;
	}
	.swatch {
		width: 0.7rem;
		height: 0.7rem;
		border-radius: 50%;
		border: 1px solid var(--color-border);
	}
	.name {
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.dist, .pace, .elapsed {
		font-variant-numeric: tabular-nums;
		color: var(--color-text-secondary);
	}
	.elapsed {
		font-weight: 600;
		color: var(--color-text);
	}
	.dnf {
		color: var(--color-danger);
		font-weight: 700;
		font-size: 0.75rem;
	}
	.pending-tag {
		background: #fff3cd;
		color: #856404;
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.1rem 0.35rem;
		border-radius: 0.3rem;
		letter-spacing: 0.04em;
	}
	.muted { color: var(--color-text-tertiary); }
</style>
