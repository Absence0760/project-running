<script lang="ts">
	import type { TrackPoint } from '$lib/types';

	// Compact SVG polyline thumbnail, normalised into the viewBox with
	// a small margin. Used in list cards (runs + routes) where loading a
	// full map tile would be overkill. The SVG is static — no pan/zoom —
	// so it renders without a JS runtime and survives SSR. Includes
	// start (green) and end (red) markers + a few directional chevrons
	// so out-and-backs and overlapping routes are still legible at
	// thumbnail scale.

	let { points = [], color = 'var(--color-primary)' }: { points: TrackPoint[]; color?: string } = $props();

	const PAD = 6; // viewBox padding in SVG units (viewBox is 0–100)
	const ARROW_COUNT = 4;

	type Projected = { x: number; y: number };

	let projected = $derived.by<Projected[]>(() => {
		if (!points || points.length < 2) return [];
		const lats = points.map((p) => p.lat);
		const lngs = points.map((p) => p.lng);
		const minLat = Math.min(...lats);
		const maxLat = Math.max(...lats);
		const minLng = Math.min(...lngs);
		const maxLng = Math.max(...lngs);
		const dLat = maxLat - minLat || 1e-6;
		const dLng = maxLng - minLng || 1e-6;
		// Preserve aspect ratio — scale by the longer axis so the trace
		// doesn't stretch when a route runs mostly east-west.
		const scale = (100 - PAD * 2) / Math.max(dLat, dLng);
		const offX = PAD + ((100 - PAD * 2) - dLng * scale) / 2;
		const offY = PAD + ((100 - PAD * 2) - dLat * scale) / 2;
		const out: Projected[] = [];
		for (const p of points) {
			out.push({
				x: offX + (p.lng - minLng) * scale,
				// SVG y grows downward; invert latitude so north is up.
				y: offY + (maxLat - p.lat) * scale,
			});
		}
		return out;
	});

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

<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg" class="track-preview" preserveAspectRatio="xMidYMid meet">
	{#if pathD}
		<!-- White casing under the line so it stays visible against any background. -->
		<path d={pathD} fill="none" stroke="white" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round" stroke-opacity="0.7" />
		<path d={pathD} fill="none" stroke={color} stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />

		{#each arrows as a, i (i)}
			<g transform="translate({a.x.toFixed(2)} {a.y.toFixed(2)}) rotate({a.angle.toFixed(1)})">
				<polygon points="-1.6,-1.6 1.4,0 -1.6,1.6" fill={color} stroke="white" stroke-width="0.4" />
			</g>
		{/each}

		<!-- Start (green) and end (red) caps so the route's direction is obvious. -->
		<circle cx={projected[0].x} cy={projected[0].y} r="2.2" fill="#22c55e" stroke="white" stroke-width="0.8" />
		<circle cx={projected[projected.length - 1].x} cy={projected[projected.length - 1].y} r="2.2" fill="#ef4444" stroke="white" stroke-width="0.8" />
	{/if}
</svg>

<style>
	.track-preview {
		width: 100%;
		height: 100%;
		display: block;
	}
</style>
