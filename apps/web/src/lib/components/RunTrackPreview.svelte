<script lang="ts" module>
	import type { TrackPoint } from '$lib/types';

	// Module-level cache keyed by track URL. Populated the first time a
	// card scrolls into view and re-read on subsequent renders without
	// re-downloading. Falls back to a sentinel `null` on fetch failure
	// so we don't retry in a tight loop on a broken object.
	const CACHE = new Map<string, TrackPoint[] | null>();
</script>

<script lang="ts">
	import { onMount } from 'svelte';
	import TrackPreview from './TrackPreview.svelte';
	import { fetchTrackByPath } from '$lib/data';

	let { trackUrl }: { trackUrl: string | null } = $props();

	let el: HTMLDivElement;
	let points = $state<TrackPoint[] | null>(null);
	let attempted = $state(false);

	onMount(() => {
		if (!trackUrl) return;
		// Hit cache synchronously if we've fetched this one before in
		// this session — common when the user scrolls up / re-enters the
		// list page.
		if (CACHE.has(trackUrl)) {
			points = CACHE.get(trackUrl) ?? null;
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
		if (!trackUrl || attempted) return;
		attempted = true;
		try {
			const track = (await fetchTrackByPath(trackUrl)) as TrackPoint[];
			// Treat a track that never moves more than ~5 m total as
			// equivalent to an empty track. Wear OS / iOS recorders log
			// every fix the OS produces, so a runner who hits Start +
			// Stop indoors (or a watch emulator with a static location)
			// uploads a non-empty array of identical points. The SVG
			// thumbnail would otherwise project them all onto a single
			// pixel and render a meaningless red dot.
			const renderable = isMoving(track) ? track : [];
			CACHE.set(trackUrl, renderable);
			points = renderable;
		} catch (_) {
			CACHE.set(trackUrl, null);
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
