<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { formatDuration as baseDuration } from '$lib/format/time';
	import { page } from '$app/stores';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { mapStyleUrlFromEnv as mapStyleUrl, getMapStyle } from '$lib/routes/map-style.svelte';
	import { watchMapResize } from '$lib/routes/map_resize';
	import { supabase } from '$lib/core/supabase';
	import {
		fetchRecentRacePings,
		fetchLatestRacePings,
		fetchRaceSession,
		fetchEventById,
		fetchEventResults,
		type RacePingRow,
		type RaceSessionRow,
		type EventResultWithUser
	} from '$lib/core/data';
	import type { EventWithMeta } from '$lib/types';
	import type { RealtimeChannel } from '@supabase/supabase-js';
	import { formatDistance, fmtPace } from '$lib/format/units.svelte';
	import { hasAcceptedConsent } from '$lib/settings/consent.svelte';
	import { runnerHandle, shouldRevealDisplayName } from '$lib/social/runner_handle';
	import { freshnessFor, type Freshness } from '$lib/runs/live_freshness';
	import { m } from '$lib/i18n/store.svelte';

	let eventId = $derived($page.params.id as string);
	let instance = $derived(decodeURIComponent($page.params.instance as string));

	let event = $state<EventWithMeta | null>(null);
	let race = $state<RaceSessionRow | null>(null);
	let recentPings = $state<RacePingRow[]>([]);
	let leaderPings = $state<RacePingRow[]>([]);
	let results = $state<EventResultWithUser[]>([]);
	let profiles = $state<Map<string, { display_name: string | null }>>(new Map());
	let nowTick = $state(Date.now());
	let loading = $state(true);
	let loadError = $state<string | null>(null);

	let channel: RealtimeChannel | null = null;

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;

	// Latest ping per user (the leaderboard view). Fetched via the
	// `latest_race_pings` RPC (one row per runner) rather than folded from
	// the capped `recentPings` window, so a back-of-pack runner whose newest
	// ping aged past that window is never dropped from the board. Already
	// ordered furthest-first with a deterministic tie-break by the data layer.
	let pings = $derived(leaderPings);

	// Per-user trail (chronological, oldest -> newest). Capped to keep
	// long races bounded; 30 samples ≈ 5 minutes at 10 s cadence.
	const TRAIL_CAP = 30;
	let trailsByUser = $derived.by(() => {
		const byUser = new Map<string, RacePingRow[]>();
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

	// Stable key per leaderboard row: account rows key on user_id, bib-only
	// imported rows (persona #43) key on bib. The identity CHECK guarantees
	// one is set. `profiles` is seeded under this key in load() so the
	// name/avatar helpers resolve bib-only finishers too.
	function keyOf(r: EventResultWithUser): string {
		return r.user_id ?? r.bib ?? '';
	}

	function colorFor(key: string): string {
		return `hsl(${hueFor(key)}, 70%, 50%)`;
	}

	function tintFor(key: string): string {
		return `hsla(${hueFor(key)}, 70%, 50%, 0.18)`;
	}

	function initialsFor(key: string): string {
		const name = profiles.get(key)?.display_name;
		if (name) {
			const parts = name.trim().split(/\s+/).slice(0, 2);
			return parts.map((p) => p.charAt(0).toUpperCase()).join('') || '?';
		}
		return key.slice(0, 2).toUpperCase();
	}

	async function load() {
		loading = true;
		loadError = null;
		try {
			const [e, rs, ps, lp, rr] = await Promise.all([
				fetchEventById(eventId),
				fetchRaceSession(eventId, instance),
				fetchRecentRacePings(eventId, instance),
				fetchLatestRacePings(eventId, instance),
				fetchEventResults(eventId, instance)
			]);
			event = e;
			race = rs;
			recentPings = ps;
			leaderPings = lp;
			results = rr;
			profiles = await buildProfiles(lp, rr);
		} catch (e) {
			// Public spectator page — a rejected fetch would otherwise hang on
			// "Loading…" forever with no recourse. Surface it with a retry.
			loadError = e instanceof Error ? e.message : String(e);
		}
		loading = false;
	}

	// Privacy gate (mirrors the /live/[id] solo-page contract): a public
	// race leaderboard is anon-accessible and the URL is shareable, so a
	// runner's real `display_name` must only surface to a friend (a
	// one-way follow edge in either direction, or the runner viewing their
	// own broadcast). Everyone else — anon worldwide viewers and signed-in
	// non-followers — sees the anonymous `Runner #XXXX` handle. Fails
	// closed: if the viewer is anon or the follow state can't be read, the
	// handle is shown, never the name.
	async function buildProfiles(
		ps: RacePingRow[],
		rr: EventResultWithUser[]
	): Promise<Map<string, { display_name: string | null }>> {
		const map = new Map<string, { display_name: string | null }>();

		// Account-bound runner ids (a bib-only imported finisher has no
		// user_id and no profile — it keys on its bib and is handled below).
		const runnerIds = new Set<string>();
		for (const p of ps) runnerIds.add(p.user_id);
		for (const r of rr) if (r.user_id) runnerIds.add(r.user_id);

		const viewerId = (await supabase.auth.getSession()).data.session?.user?.id ?? null;

		// One bulk probe per direction over the viewer's follow edges
		// against this race's runners, so the reveal decision is a set
		// membership check rather than two queries per runner.
		const viewerFollows = new Set<string>();
		const followsViewer = new Set<string>();
		if (viewerId && runnerIds.size > 0) {
			const ids = [...runnerIds];
			const [vfr, rfv] = await Promise.all([
				supabase
					.from('user_follows')
					.select('followee_id')
					.eq('follower_id', viewerId)
					.in('followee_id', ids),
				supabase
					.from('user_follows')
					.select('follower_id')
					.eq('followee_id', viewerId)
					.in('follower_id', ids)
			]);
			for (const row of vfr.data ?? []) viewerFollows.add(row.followee_id);
			for (const row of rfv.data ?? []) followsViewer.add(row.follower_id);
		}

		// Pull display_names only for runners the gate will actually reveal,
		// so a name we won't show never even leaves the server.
		const revealIds = [...runnerIds].filter((id) =>
			shouldRevealDisplayName({
				viewerUserId: viewerId,
				runnerUserId: id,
				viewerFollowsRunner: viewerFollows.has(id),
				runnerFollowsViewer: followsViewer.has(id)
			})
		);
		const realNames = new Map<string, string | null>();
		if (revealIds.length > 0) {
			const { data } = await supabase
				.from('user_profiles')
				.select('id, display_name')
				.in('id', revealIds);
			for (const p of data ?? []) realNames.set(p.id, p.display_name);
		}
		for (const id of runnerIds) {
			map.set(id, {
				display_name: realNames.has(id) ? realNames.get(id)! : runnerHandle(id)
			});
		}

		// Bib-only imported finishers (persona #43) have no account, so the
		// follow gate doesn't apply — they carry the name printed on the
		// results sheet (already on `display_name` from fetchEventResults).
		// Their leaderboard row keys on bib, not user_id, so seeding here
		// doesn't override an account runner's gated entry above.
		for (const r of rr) {
			if (!r.user_id) map.set(keyOf(r), { display_name: r.display_name });
		}
		return map;
	}

	function subscribe() {
		// Privacy-zone trust contract: pings are rendered verbatim. The
		// broadcaster's privacy zones are NOT fetched here. The single
		// line of defence is the `race_pings_drop_in_zone` BEFORE-INSERT
		// trigger (migration 20260704_001, carve-out 20270309_001) — an
		// in-zone ping never carries a precise point, only a coarsened
		// `coarse = true` last-seen cell. Mirrors the trust contract in
		// /live/[id].
		channel = supabase
			.channel(`live-event-${eventId}-${instance}`)
			.on(
				'postgres_changes',
				{
					event: 'INSERT',
					schema: 'public',
					table: 'race_pings',
					filter: `event_id=eq.${eventId}&instance_start=eq.${instance}`
				},
				async () => {
					const [ps, lp] = await Promise.all([
						fetchRecentRacePings(eventId, instance),
						fetchLatestRacePings(eventId, instance)
					]);
					recentPings = ps;
					leaderPings = lp;
					profiles = await buildProfiles(lp, results);
				}
			)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'race_sessions',
					filter: `event_id=eq.${eventId}&instance_start=eq.${instance}`
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
					profiles = await buildProfiles(leaderPings, results);
				}
			)
			.subscribe();
	}

	onMount(async () => {
		// Honour the global banner choice; the "Load map" button is the
		// per-page acceptance path when the banner hasn't been answered.
		if (hasAcceptedConsent()) mapConsented = true;
		await load();
		subscribe();
	});

	function loadMapNow() {
		mapConsented = true;
		// The map container only mounts once `mapConsented` flips, so the
		// init $effect re-runs on the next tick with a live container.
	}

	onDestroy(() => {
		if (channel) supabase.removeChannel(channel);
		stopResizeWatch?.();
		map?.remove();
	});

	let tickTimer: ReturnType<typeof setInterval> | null = null;
	$effect(() => {
		// Tick while the race is running OR while any runner is still on
		// course, so each row's freshness ("updated N ago" / stale badge)
		// keeps recomputing — a runner who lost signal must transition to
		// stale even if the organiser hasn't formally flipped the race state.
		if (race?.status === 'running' || pings.length > 0) {
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
		return s <= 0 ? '—' : baseDuration(s);
	}

	function paceSecPerKm(p: RacePingRow): number | null {
		if (!p.distance_m || p.distance_m < 50 || !p.elapsed_s || p.elapsed_s < 10) return null;
		return p.elapsed_s / (p.distance_m / 1000);
	}

	function freshnessFor_(p: RacePingRow): Freshness {
		return freshnessFor(new Date(p.at).getTime(), nowTick);
	}

	function freshnessText(f: Freshness): string {
		switch (f.bucket) {
			case 'now':
				return m('live.updatedNow');
			case 'seconds':
				return m('live.updatedSeconds', { n: f.value });
			case 'minutes':
				return m('live.updatedMinutes', { n: f.value });
			case 'hours':
				return m('live.updatedHours', { n: f.value });
			case 'days':
				return m('live.updatedDays', { n: f.value });
		}
	}

	function statusLabel(status: string): string {
		switch (status) {
			case 'dnf':
				return m('liveEvent.statusDnf');
			case 'dns':
				return m('liveEvent.statusDns');
			default:
				return status.toUpperCase();
		}
	}


	function nameFor(key: string): string {
		return profiles.get(key)?.display_name ?? m('liveEvent.runnerFallback');
	}

	let finishedResults = $derived(results.filter((r) => r.finisher_status === 'finished'));
	let dnfResults = $derived(results.filter((r) => r.finisher_status !== 'finished'));

	let statusCopy = $derived.by(() => {
		if (!race) return { label: m('liveEvent.statusPreRaceLabel'), sub: m('liveEvent.statusPreRaceSub') };
		switch (race.status) {
			case 'armed':
				return { label: m('liveEvent.statusArmedLabel'), sub: m('liveEvent.statusArmedSub') };
			case 'running':
				return { label: m('liveEvent.statusRunningLabel'), sub: m('liveEvent.statusRunningSub', { time: formatDuration(raceElapsedS) }) };
			case 'finished':
				return { label: m('liveEvent.statusFinishedLabel'), sub: m('liveEvent.statusFinishedSub', { time: formatDuration(raceElapsedS) }) };
			case 'cancelled':
				return { label: m('liveEvent.statusCancelledLabel'), sub: m('liveEvent.statusCancelledSub') };
			default:
				return { label: race.status, sub: '' };
		}
	});

	// --- Map ---

	let mapContainer: HTMLDivElement | undefined = $state();
	let stopResizeWatch: (() => void) | null = null;
	let map: maplibregl.Map | null = null;
	let mapReady = $state(false);
	// audit/cookie-consent: this event spectator page is anon-accessible,
	// and MapTiler logs the requester IP per tile fetch — so MapLibre must
	// not init before consent is recorded (matches the /live/[id] sibling).
	// Gated on the global banner choice OR an explicit per-page "Load map".
	let mapConsented = $state(false);
	let didFitBounds = false;

	function buildPositionsGeoJSON(): GeoJSON.FeatureCollection<GeoJSON.Point, { user_id: string; color: string; label: string; coarse: boolean }> {
		const features: GeoJSON.Feature<GeoJSON.Point, { user_id: string; color: string; label: string; coarse: boolean }>[] = [];
		pings.forEach((p, i) => {
			features.push({
				type: 'Feature',
				geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
				properties: {
					user_id: p.user_id,
					color: colorFor(p.user_id),
					label: String(i + 1),
					// Privacy-zone last-seen carve-out (migration 20270309_001): a
					// coarsened ~1 km in-zone fix. Rendered as a hollow amber ring so
					// a watcher reads it as approximate, never a precise position.
					coarse: p.coarse === true
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
				// A coarse last-seen fix gets a wider amber halo so it reads as an
				// approximate ~1 km cell, deliberately distinct from the tight
				// per-runner-coloured halo of a precise live position.
				'circle-radius': ['case', ['get', 'coarse'], 20, 13],
				'circle-color': ['case', ['get', 'coarse'], '#E6A96B', ['get', 'color']],
				'circle-opacity': ['case', ['get', 'coarse'], 0.22, 0.25]
			}
		});

		map.addLayer({
			id: 'runner-position-dot',
			type: 'circle',
			source: 'runner-positions',
			paint: {
				// Coarse: a hollow amber ring (transparent fill, amber stroke);
				// precise: a solid runner-coloured dot.
				'circle-radius': ['case', ['get', 'coarse'], 9, 7],
				'circle-color': ['case', ['get', 'coarse'], 'rgba(0,0,0,0)', ['get', 'color']],
				'circle-stroke-color': ['case', ['get', 'coarse'], '#E6A96B', prefersDark ? '#0f172a' : '#ffffff'],
				'circle-stroke-width': ['case', ['get', 'coarse'], 3, 2]
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
		if (!mapConsented || !mapContainer || map || pings.length === 0) return;
		const first = pings[0];
		map = new maplibregl.Map({
			container: mapContainer,
			style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
			center: [first.lng, first.lat],
			zoom: 13
		});
		map.addControl(new maplibregl.NavigationControl(), 'top-right');
		if (mapContainer) stopResizeWatch = watchMapResize(mapContainer, map);
		map.on('load', () => {
			mapReady = true;
			addOverlays();
			refreshMapData();
		});
	});

	$effect(() => {
		void pings;
		void trailsByUser;
		refreshMapData();
	});

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
	<title>{m('liveEvent.pageTitle', { title: event?.title ?? m('liveEvent.eventFallback') })}</title>
</svelte:head>

<div class="page">
	<header class="hero">
		<p class="kicker">{m('liveEvent.kicker')}</p>
		<h1>{event?.title ?? m('liveEvent.heroFallback')}</h1>
		<div class="status-row">
			<span class="status-dot status-{race?.status ?? 'idle'}"></span>
			<strong class="status-label">{statusCopy.label}</strong>
			<span class="status-sub">{statusCopy.sub}</span>
		</div>
	</header>

	{#if loading}
		<p class="muted">{m('shell.loading')}</p>
	{:else if loadError}
		<div class="error-banner" role="alert">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('liveEvent.loadError')}</strong>
				<span class="error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline" onclick={load}>{m('liveEvent.retry')}</button>
		</div>
	{:else}
		<div class="layout">
			<section class="leaderboard">
				<header class="section-head">
					<h2>{m('liveEvent.onCourse')}</h2>
					<span class="count">{pings.length}</span>
				</header>
				{#if pings.length === 0}
					<div class="empty-inline">
						<span class="material-symbols">satellite_alt</span>
						<p>{m('liveEvent.noLiveData')}</p>
					</div>
				{:else}
					<ol class="runners">
						{#each pings as p, i (p.user_id)}
							{@const fresh = freshnessFor_(p)}
							<li class="runner" class:stale={fresh.stale} class:coarse={p.coarse}>
								<span class="pos">{i + 1}</span>
								<span class="avatar" style="background: {tintFor(p.user_id)}; color: {colorFor(p.user_id)};">
									{initialsFor(p.user_id)}
								</span>
								<span class="name">
									{nameFor(p.user_id)}
									{#if p.coarse}
										<span class="approx-tag" data-testid="coarse-badge">
											<span class="material-symbols" aria-hidden="true">location_searching</span>
											{m('live.approximateBadge')}
										</span>
									{/if}
									<span class="freshness" class:stale={fresh.stale} class:coarse={p.coarse}>
										{#if p.coarse}
											{m('live.approximateSub')}
										{:else}
											{#if fresh.stale}<span class="stale-badge">{m('live.badgeStale')}</span>{/if}
											{freshnessText(fresh)}
										{/if}
									</span>
								</span>
								<span class="dist">{formatDistance(p.distance_m ?? 0)}</span>
								<span class="pace">{fmtPace(paceSecPerKm(p))}</span>
								<span class="elapsed">{formatDuration(p.elapsed_s ?? 0)}</span>
							</li>
						{/each}
					</ol>
				{/if}
			</section>

			<aside class="map-side">
				{#if pings.length > 0}
					{#if mapConsented}
						<div class="map-card">
							<div bind:this={mapContainer} class="race-map"></div>
						</div>
					{:else}
						<!--
							audit/cookie-consent: MapTiler logs the requester IP per
							tile fetch. Anonymous spectators must opt in before the
							map mounts (ePrivacy / GDPR) — a "Load map" tap is the
							affirmative act. Mirrors /live/[id].
						-->
						<div class="map-card map-consent-veil">
							<div class="map-consent-card">
								<h2>{m('liveEvent.mapConsentTitle')}</h2>
								<p>
									{m('liveEvent.mapConsentPrefix')}<strong>MapTiler</strong>{m('liveEvent.mapConsentMiddle')}<strong>{m('liveEvent.loadMap')}</strong>{m('liveEvent.mapConsentSuffix')}<a href="/cookie-notice">{m('liveEvent.cookieNoticeLink')}</a>.
								</p>
								<button type="button" class="btn btn-primary" onclick={loadMapNow}>
									{m('liveEvent.loadMap')}
								</button>
							</div>
						</div>
					{/if}
				{:else}
					<div class="map-card map-card-empty">
						<span class="material-symbols">map</span>
						<p>{m('liveEvent.mapPlaceholder')}</p>
					</div>
				{/if}
			</aside>
		</div>

		{#if finishedResults.length > 0 || dnfResults.length > 0}
			<section class="results">
				{#if finishedResults.length > 0}
					<header class="section-head">
						<h2>{m('liveEvent.finished')}</h2>
						<span class="count">{finishedResults.length}</span>
					</header>
					<ol class="runners">
						{#each finishedResults as r (keyOf(r))}
							<li class="runner" class:pending={!r.organiser_approved}>
								<span class="pos">{r.organiser_approved ? (r.rank ?? '—') : '…'}</span>
								<span class="avatar" style="background: {tintFor(keyOf(r))}; color: {colorFor(keyOf(r))};">
									{initialsFor(keyOf(r))}
								</span>
								<span class="name">{nameFor(keyOf(r))}</span>
								<span class="dist">{formatDistance(r.distance_m)}</span>
								<span class="elapsed">{formatDuration(r.duration_s)}</span>
								{#if !r.organiser_approved}
									<span class="pending-tag">{m('liveEvent.pending')}</span>
								{/if}
							</li>
						{/each}
					</ol>
				{/if}

				{#if dnfResults.length > 0}
					<header class="section-head section-head-spaced">
						<h2>{m('liveEvent.didNotFinish')}</h2>
						<span class="count">{dnfResults.length}</span>
					</header>
					<ol class="runners">
						{#each dnfResults as r (keyOf(r))}
							<li class="runner dnf-row">
								<span class="pos">—</span>
								<span class="avatar" style="background: {tintFor(keyOf(r))}; color: {colorFor(keyOf(r))};">
									{initialsFor(keyOf(r))}
								</span>
								<span class="name">{nameFor(keyOf(r))}</span>
								<span class="dnf">{statusLabel(r.finisher_status)}</span>
							</li>
						{/each}
					</ol>
				{/if}
			</section>
		{/if}
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 88rem;
		margin: 0 auto;
	}
	.muted {
		color: var(--color-text-tertiary);
	}

	.hero {
		margin-bottom: var(--space-xl);
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-xs);
	}
	h1 {
		font-size: 2rem;
		font-weight: 800;
		margin: 0 0 var(--space-sm);
		line-height: 1.2;
	}
	.status-row {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-xs) var(--space-md);
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: 999px;
	}
	.status-dot {
		display: inline-block;
		width: 0.65rem;
		height: 0.65rem;
		border-radius: 50%;
		background: var(--color-text-tertiary);
	}
	.status-idle { background: var(--color-text-tertiary); }
	.status-armed { background: var(--color-warning); }
	.status-running {
		background: var(--color-success);
		animation: pulse 1.2s ease-in-out infinite;
	}
	.status-finished { background: var(--color-text-secondary); }
	.status-cancelled { background: var(--color-danger); }
	.status-label {
		font-weight: 700;
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}
	.status-sub {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	@keyframes pulse {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.4; }
	}

	.layout {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(0, 1.3fr);
		gap: var(--space-lg);
		margin-bottom: var(--space-xl);
	}
	@media (max-width: 64rem) {
		.layout {
			grid-template-columns: minmax(0, 1fr);
		}
	}

	.leaderboard,
	.results {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		/* Container queries so the dense runner-row layout
		 * (rank + avatar + name + distance + elapsed + tag)
		 * adapts to the leaderboard's actual column width — the
		 * grid layout above can shrink the column on the
		 * 64rem-viewport boundary, and the runner row would
		 * otherwise overflow with long names. Mirrors the panel-
		 * polish pattern from /runs/[id] + /routes/[id]. */
		container-type: inline-size;
		container-name: leaderboard;
	}
	.results {
		margin-bottom: var(--space-xl);
	}

	.section-head {
		display: flex;
		align-items: baseline;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
	}
	.section-head-spaced {
		margin-top: var(--space-lg);
	}
	.section-head h2 {
		font-size: 0.85rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-secondary);
		margin: 0;
	}
	.count {
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
		background: var(--color-bg-secondary);
		padding: 0.1rem 0.5rem;
		border-radius: 999px;
		font-weight: 600;
	}

	.empty-inline {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-lg);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		color: var(--color-text-secondary);
	}
	.empty-inline .material-symbols {
		font-size: 1.6rem;
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}
	.empty-inline p {
		margin: 0;
		font-size: 0.9rem;
		line-height: 1.5;
	}

	.map-side {
		display: flex;
	}
	.map-card {
		flex: 1;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		min-height: 24rem;
	}
	.map-card-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-sm);
		text-align: center;
		padding: var(--space-xl);
		color: var(--color-text-tertiary);
	}
	.map-card-empty .material-symbols {
		font-size: 2.5rem;
	}
	.map-card-empty p {
		margin: 0;
		max-width: 22rem;
		font-size: 0.9rem;
		line-height: 1.5;
	}
	.race-map {
		width: 100%;
		height: 100%;
		min-height: 24rem;
	}
	.map-consent-veil {
		display: flex;
		align-items: center;
		justify-content: center;
		padding: var(--space-lg);
	}
	.map-consent-card {
		max-width: 30rem;
		text-align: start;
	}
	.map-consent-card h2 {
		margin: 0 0 var(--space-sm);
		font-size: 1.1rem;
	}
	.map-consent-card p {
		margin: 0 0 var(--space-md);
		line-height: 1.5;
		color: var(--color-text-secondary);
		font-size: 0.92rem;
	}

	.runners {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.runner {
		display: grid;
		grid-template-columns: 2.2rem 2rem 1fr auto auto auto auto;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-bg-secondary);
		border: 1px solid transparent;
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		transition: border-color 0.12s ease, transform 0.12s ease;
	}
	.runner:hover {
		border-color: var(--color-border);
		transform: translateX(2px);
	}
	.runner.pending {
		opacity: 0.75;
	}
	.dnf-row {
		grid-template-columns: 2.2rem 2rem 1fr auto;
	}

	.pos {
		font-weight: 800;
		color: var(--color-primary);
		font-variant-numeric: tabular-nums;
		font-size: 0.95rem;
	}
	.avatar {
		width: 2rem;
		height: 2rem;
		border-radius: 50%;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		font-weight: 700;
		font-size: 0.72rem;
		letter-spacing: 0.02em;
	}
	.name {
		font-weight: 600;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.freshness {
		display: block;
		font-weight: 500;
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.freshness.stale {
		color: var(--color-warning);
	}
	.stale-badge {
		font-weight: 800;
		letter-spacing: 0.05em;
		margin-inline-end: 0.3rem;
	}
	.runner.stale {
		border-color: color-mix(in srgb, var(--color-warning) 45%, transparent);
		background: color-mix(in srgb, var(--color-warning) 8%, var(--color-bg-secondary));
	}
	.runner.coarse {
		border-color: color-mix(in srgb, var(--color-warning) 45%, transparent);
		background: color-mix(in srgb, var(--color-warning) 8%, var(--color-bg-secondary));
	}
	.freshness.coarse {
		color: var(--color-warning);
	}
	/* Coarse last-seen badge: an amber chip on the leaderboard row so a
	 * spectator reads the runner's position as an approximate ~1 km cell,
	 * not a precise live fix. Matches the /live/[id] solo approx-badge. */
	.approx-tag {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
		margin-inline-start: 0.35rem;
		padding: 0.05rem 0.4rem;
		border-radius: 9999px;
		font-size: 0.62rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		vertical-align: middle;
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: var(--color-warning);
		border: 1px solid color-mix(in srgb, var(--color-warning) 35%, transparent);
	}
	.approx-tag .material-symbols {
		font-size: 0.85rem;
	}
	.dist,
	.pace,
	.elapsed {
		font-variant-numeric: tabular-nums;
		color: var(--color-text-secondary);
		font-size: 0.88rem;
	}
	.elapsed {
		font-weight: 700;
		color: var(--color-text);
	}
	.dnf {
		color: var(--color-danger);
		font-weight: 700;
		font-size: 0.75rem;
		letter-spacing: 0.05em;
	}
	.pending-tag {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: var(--color-warning);
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.15rem 0.5rem;
		border-radius: 999px;
		letter-spacing: 0.05em;
		text-transform: uppercase;
	}

	@media (max-width: 48rem) {
		.runner {
			grid-template-columns: 1.8rem 1.8rem 1fr;
			grid-template-areas:
				'pos avatar name'
				'. . stats';
			row-gap: 0.25rem;
		}
		.runner .pos { grid-area: pos; }
		.runner .avatar { grid-area: avatar; }
		.runner .name { grid-area: name; }
		.runner .dist,
		.runner .pace,
		.runner .elapsed {
			grid-area: stats;
			display: inline;
			margin-inline-end: var(--space-sm);
		}
	}

	/* Container-query mirror — fires when the leaderboard COLUMN
	 * is narrow even on a wide viewport (the 1fr|1.3fr grid puts
	 * the leaderboard around 420 px at 1024 px viewports, and the
	 * runner row's 5-cell layout breaks below ~380 px). Same
	 * stacked grid as the mobile rule. */
	@container leaderboard (max-width: 380px) {
		.runner {
			grid-template-columns: 1.8rem 1.8rem 1fr;
			grid-template-areas:
				'pos avatar name'
				'. . stats';
			row-gap: 0.25rem;
		}
		.runner .pos { grid-area: pos; }
		.runner .avatar { grid-area: avatar; }
		.runner .name { grid-area: name; }
		.runner .dist,
		.runner .pace,
		.runner .elapsed {
			grid-area: stats;
			display: inline;
			margin-inline-end: var(--space-sm);
		}
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: #ef4444;
		font-size: 1.4rem;
	}
</style>
