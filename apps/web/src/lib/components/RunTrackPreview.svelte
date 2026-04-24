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
			CACHE.set(trackUrl, track);
			points = track;
		} catch (_) {
			CACHE.set(trackUrl, null);
		}
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
