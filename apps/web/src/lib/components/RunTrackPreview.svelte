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
	import TrackPreview from './TrackPreview.svelte';
	import { fetchTrackByPath, clipTrackForUser } from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';

	let {
		trackUrl,
		ownerUserId,
	}: {
		trackUrl: string | null;
		/// Set this when the run isn't the current viewer's own — e.g. on
		/// the activity feed. The fetched track is then routed through
		/// `clipTrackForUser` so the owner's privacy zones are honoured
		/// before we render the polyline. Omit when the row is the
		/// viewer's own (no clip needed, faster cold load).
		ownerUserId?: string | null;
	} = $props();

	const viewerId = $derived(auth.user?.id ?? null);
	// Treat anon (`viewerId == null`) as non-owner — they can hit
	// public share routes without signing in and must still see a
	// clipped track.
	const shouldClip = $derived(
		ownerUserId != null && ownerUserId !== viewerId,
	);
	const cacheKey = $derived(
		trackUrl == null ? null : `${shouldClip ? 'clip' : 'raw'}:${trackUrl}`,
	);

	let el: HTMLDivElement;
	let points = $state<TrackPoint[] | null>(null);
	let attempted = $state(false);

	onMount(() => {
		if (!trackUrl || !cacheKey) return;
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
		if (!trackUrl || !cacheKey || attempted) return;
		attempted = true;
		try {
			let track = (await fetchTrackByPath(trackUrl)) as TrackPoint[];
			// Privacy-zone clipping for non-owner viewers (decisions §33).
			// When the run isn't ours and the owner has zones configured,
			// the RPC trims start / end / interior windows so a follower
			// scrolling the feed never sees the owner's home. Owners
			// always see their full track.
			if (shouldClip && ownerUserId) {
				track = (await clipTrackForUser(ownerUserId, track)) as TrackPoint[];
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
		<TrackPreview {points} />
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
