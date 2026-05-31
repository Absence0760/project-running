<script lang="ts" module>
	import type { TrackPoint } from '$lib/types';

	// Module-level cache keyed by track URL + clip variant. Populated the
	// first time a card scrolls into view and re-read on subsequent
	// renders without re-downloading. Falls back to a sentinel `null` on
	// fetch failure so we don't retry in a tight loop on a broken object.
	// The clip-variant prefix (`raw:` vs `clip:`) keeps owner and non-
	// owner reads of the same track from polluting each other.
	//
	// Cap at CACHE_MAX entries — `Map` preserves insertion order so
	// dropping `keys().next()` evicts the oldest. A power user with
	// 1000+ runs in a long session would otherwise hold every
	// deserialised track in memory until reload.
	const CACHE_MAX = 200;
	const CACHE = new Map<string, TrackPoint[] | null>();
	function cacheSet(key: string, value: TrackPoint[] | null) {
		if (CACHE.size >= CACHE_MAX && !CACHE.has(key)) {
			const oldest = CACHE.keys().next().value;
			if (oldest !== undefined) CACHE.delete(oldest);
		}
		CACHE.set(key, value);
	}
</script>

<script lang="ts">
	import { onMount } from 'svelte';
	import { env } from '$env/dynamic/public';
	import TrackPreview from './TrackPreview.svelte';
	import { fetchTrackByPath, fetchClippedTrackForRun } from '$lib/core/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { consent } from '$lib/settings/consent.svelte';
	import { buildLocalStaticMapUrl, buildStaticMapUrl } from '$lib/routes/static_map';

	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	const PUBLIC_TILE_STYLE_URL = env.PUBLIC_TILE_STYLE_URL ?? '';

	let {
		runId,
		trackUrl,
		ownerUserId,
	}: {
		/// Used by the non-owner clip path. Required when ownerUserId is
		/// set — the EF route needs the run's id to look up track_url
		/// server-side and apply the privacy-zone clip.
		runId?: string | null;
		trackUrl: string | null;
		/// Set this when the run isn't the current viewer's own — e.g. on
		/// the activity feed. Non-owner viewers go through the
		/// `clip-public-track` Edge Function so the unclipped blob never
		/// crosses the wire (decisions.md §33, migration 20260619_001
		/// dropped the public-runs Storage policy). Omit when the row is
		/// the viewer's own — direct Storage download is fine and faster.
		ownerUserId?: string | null;
	} = $props();

	const viewerId = $derived(auth.user?.id ?? null);
	// Treat anon (`viewerId == null`) as non-owner — they can hit
	// public share routes without signing in and must still see a
	// clipped track.
	const shouldClip = $derived(
		ownerUserId != null && ownerUserId !== viewerId,
	);
	// The non-owner clip path fetches by `runId` (the EF derives the Storage
	// path server-side), so it never needs `trackUrl` — public-view callers
	// (feed, profile) have no track_url to pass since `public_runs` dropped
	// it. Key the cache + the load gate on whichever input that path uses:
	// runId when clipping, trackUrl for the owner's direct read.
	const cacheKey = $derived(
		shouldClip
			? runId == null
				? null
				: `clip:${runId}`
			: trackUrl == null
				? null
				: `raw:${trackUrl}`,
	);

	let el: HTMLDivElement;
	let points = $state<TrackPoint[] | null>(null);
	let attempted = $state(false);

	onMount(() => {
		if (!cacheKey) return;
		// Hit cache synchronously if we've fetched this one before in
		// this session — common when the user scrolls up / re-enters the
		// list page.
		if (CACHE.has(cacheKey)) {
			points = CACHE.get(cacheKey) ?? null;
			attempted = true;
			return;
		}
		const io = new IntersectionObserver(
			(entries) => {
				for (const e of entries) {
					if (e.isIntersecting) {
						io.disconnect();
						void load();
						break;
					}
				}
			},
			{ rootMargin: '200px' }, // Pre-fetch slightly before visible
		);
		io.observe(el);
		return () => io.disconnect();
	});

	async function load() {
		if (!cacheKey || attempted) return;
		attempted = true;
		try {
			let track: TrackPoint[];
			if (shouldClip) {
				if (!runId) {
					// Non-owner thumbnail without a runId can't use the EF
					// path. Fail closed — render a placeholder rather than
					// fall back to the (now-blocked) direct Storage path.
					cacheSet(cacheKey, null);
					return;
				}
				track = (await fetchClippedTrackForRun(runId)) as TrackPoint[];
			} else {
				if (!trackUrl) {
					// Owner read needs the direct Storage path; without it
					// there's nothing to fetch.
					cacheSet(cacheKey, null);
					return;
				}
				track = (await fetchTrackByPath(trackUrl)) as TrackPoint[];
			}
			// Treat a track that never moves more than ~5 m total as
			// equivalent to an empty track. Wear OS / iOS recorders log
			// every fix the OS produces, so a runner who hits Start +
			// Stop indoors (or a watch emulator with a static location)
			// uploads a non-empty array of identical points. The SVG
			// thumbnail would otherwise project them all onto a single
			// pixel and render a meaningless red dot.
			const renderable = isMoving(track) ? track : [];
			cacheSet(cacheKey, renderable);
			points = renderable;
		} catch (_) {
			cacheSet(cacheKey, null);
		}
	}

	/// True iff the track's bounding-box diagonal is large enough to be
	/// worth drawing at thumbnail scale. A few-metre threshold catches
	/// GPS jitter from a runner standing still without throwing away
	/// genuinely tiny laps. Pure haversine on the bounding box rather
	/// than a full path-length integration — the SVG only needs the
	/// extent, not the distance run.
	function isMoving(track: TrackPoint[]): boolean {
		if (!track || track.length < 2) return false;
		let minLat = track[0].lat, maxLat = track[0].lat;
		let minLng = track[0].lng, maxLng = track[0].lng;
		for (const p of track) {
			if (p.lat < minLat) minLat = p.lat;
			else if (p.lat > maxLat) maxLat = p.lat;
			if (p.lng < minLng) minLng = p.lng;
			else if (p.lng > maxLng) maxLng = p.lng;
		}
		const dLatM = (maxLat - minLat) * 111_320;
		const dLngM = (maxLng - minLng) * 111_320 * Math.cos((minLat * Math.PI) / 180);
		return Math.hypot(dLatM, dLngM) > 5;
	}
</script>

<div bind:this={el} class="wrap">
	{#if points && points.length > 1}
		{@const mapUrl =
			buildLocalStaticMapUrl(points, {
				w: 220,
				h: 140,
				styleUrl: PUBLIC_TILE_STYLE_URL,
			}) ??
			// MapTiler logs the requester IP per static-map fetch and this
			// preview renders on anon surfaces (public /u/[id], feed). Hold
			// the third-party request until consent; fall through to the
			// SVG below until then. Local self-hosted override is exempt.
			// audit/cookie-consent.
			(consent.accepted
				? buildStaticMapUrl(points, {
						w: 220,
						h: 140,
						style: 'streets-v2',
						key: PUBLIC_MAPTILER_KEY,
					})
				: null)}
		{#if mapUrl}
			<!-- Static-map background mirroring RouteTrackPreview. Real
				 tiles read better than a bare SVG line on cards. Falls
				 back to the SVG when neither MapTiler nor the local
				 Protomaps server is configured. Lazy-load so a list
				 of 50 runs doesn't fire 50 PNGs at page load. -->
			<img
				src={mapUrl}
				class="map-img"
				loading="lazy"
				decoding="async"
				alt=""
				data-testid="run-preview-map"
			/>
		{:else}
			<TrackPreview {points} />
		{/if}
	{:else}
		<span class="material-symbols placeholder">map</span>
	{/if}
</div>

<style>
	.wrap {
		width: 100%;
		height: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.placeholder {
		font-family: 'Material Symbols Outlined';
		font-size: 1.5rem;
		color: var(--color-text-tertiary);
	}
</style>
