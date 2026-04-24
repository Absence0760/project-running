<script lang="ts">
	import type { TrackPoint } from '$lib/types';

	// Compact SVG polyline thumbnail, normalised into the viewBox with
	// a small margin. Used in list cards (runs + routes) where loading a
	// full map tile would be overkill. The SVG is static — no pan/zoom —
	// so it renders without a JS runtime and survives SSR.

	let { points = [], color = 'var(--color-primary)' }: { points: TrackPoint[]; color?: string } = $props();

	const PAD = 4; // viewBox padding in SVG units (viewBox is 0–100)

	let pathD = $derived.by(() => {
		if (!points || points.length < 2) return '';
		const lats = points.map((p) => p.lat);
		const lngs = points.map((p) => p.lng);
		const minLat = Math.min(...lats);
		const maxLat = Math.max(...lats);
		const minLng = Math.min(...lngs);
		const maxLng = Math.max(...lngs);
		const dLat = maxLat - minLat || 1e-6;
		const dLng = maxLng - minLng || 1e-6;
		// Preserve aspect ratio — scale by the longer axis so the trace
		// doesn't stretch in one direction when a route runs mostly
		// east-west (common for out-and-backs along a coast).
		const scale = (100 - PAD * 2) / Math.max(dLat, dLng);
		const offX = PAD + ((100 - PAD * 2) - dLng * scale) / 2;
		const offY = PAD + ((100 - PAD * 2) - dLat * scale) / 2;
		let d = '';
		for (let i = 0; i < points.length; i++) {
			const p = points[i];
			const x = offX + (p.lng - minLng) * scale;
			// SVG y grows downward; invert latitude so north is up.
			const y = offY + (maxLat - p.lat) * scale;
			d += (i === 0 ? 'M' : 'L') + x.toFixed(2) + ' ' + y.toFixed(2) + ' ';
		}
		return d.trim();
	});
</script>

<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg" class="track-preview" preserveAspectRatio="xMidYMid meet">
	{#if pathD}
		<path d={pathD} fill="none" stroke={color} stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
	{/if}
</svg>

<style>
	.track-preview {
		width: 100%;
		height: 100%;
		display: block;
	}
</style>
