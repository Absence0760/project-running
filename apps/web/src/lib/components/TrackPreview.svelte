<script lang="ts">
	import type { TrackPoint } from '$lib/types';
	import { projectTrack, type Projected } from '$lib/track_projection';

	// Compact SVG polyline thumbnail, normalised into the viewBox with
	// a small margin. Used in list cards (runs + routes) where loading a
	// full map tile would be overkill. The SVG is static — no pan/zoom —
	// so it renders without a JS runtime and survives SSR. Includes
	// start (green) and end (red) markers + a few directional chevrons
	// so out-and-backs and overlapping routes are still legible at
	// thumbnail scale.

	let {
		points = [],
		color = 'var(--color-primary)',
		aspect = 2.4,
	}: { points: TrackPoint[]; color?: string; aspect?: number } = $props();

	const PAD = 4; // viewBox padding in SVG units (viewBox short axis = 100)
	const ARROW_COUNT = 4;

	// Make the viewBox match the host container's aspect ratio so the
	// trace fills the box instead of letterboxing inside a square SVG.
	let vbW = $derived(aspect >= 1 ? 100 * aspect : 100);
	let vbH = $derived(aspect < 1 ? 100 / aspect : 100);

	let projected = $derived.by<Projected[]>(() => projectTrack(points, vbW, vbH, PAD));

	let pathD = $derived.by(() => {
		if (projected.length < 2) return '';
		let d = '';
		for (let i = 0; i < projected.length; i++) {
			const p = projected[i];
			d += (i === 0 ? 'M' : 'L') + p.x.toFixed(2) + ' ' + p.y.toFixed(2) + ' ';
		}
		return d.trim();
	});

	type Arrow = { x: number; y: number; angle: number };
	let arrows = $derived.by<Arrow[]>(() => {
		if (projected.length < 4) return [];
		const out: Arrow[] = [];
		for (let i = 1; i <= ARROW_COUNT; i++) {
			// Drop chevrons at evenly-spaced indices along the trace so a
			// folded out-and-back is still readable at thumbnail size.
			const t = i / (ARROW_COUNT + 1);
			const idx = Math.max(1, Math.floor(projected.length * t));
			const a = projected[idx - 1];
			const b = projected[idx];
			const angle = (Math.atan2(b.y - a.y, b.x - a.x) * 180) / Math.PI;
			out.push({ x: b.x, y: b.y, angle });
		}
		return out;
	});
</script>

<svg viewBox="0 0 {vbW} {vbH}" xmlns="http://www.w3.org/2000/svg" class="track-preview" preserveAspectRatio="xMidYMid meet">
	{#if pathD}
		<!-- White casing under the line so it stays visible against any background. -->
		<path d={pathD} fill="none" stroke="white" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round" stroke-opacity="0.85" />
		<path d={pathD} fill="none" stroke={color} stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" />

		{#each arrows as a, i (i)}
			<g transform="translate({a.x.toFixed(2)} {a.y.toFixed(2)}) rotate({a.angle.toFixed(1)})">
				<polygon points="-1.8,-1.8 1.6,0 -1.8,1.8" fill={color} stroke="white" stroke-width="0.5" />
			</g>
		{/each}

		<!-- Start (green) and end (red) caps so the route's direction is obvious. -->
		<circle cx={projected[0].x} cy={projected[0].y} r="2.6" fill="#22c55e" stroke="white" stroke-width="1" />
		<circle cx={projected[projected.length - 1].x} cy={projected[projected.length - 1].y} r="2.6" fill="#ef4444" stroke="white" stroke-width="1" />
	{/if}
</svg>

<style>
	.track-preview {
		width: 100%;
		height: 100%;
		display: block;
	}
</style>
