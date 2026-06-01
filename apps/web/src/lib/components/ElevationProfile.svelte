<script lang="ts">
	import { formatDistance } from '$lib/format/units.svelte';
	import { minMax } from '$lib/util/min_max';
	import { m } from '$lib/i18n/store.svelte';

	/// `onhover` is fired with the elevations-index the user is
	/// currently inspecting (null when the pointer leaves the chart).
	/// The parent maps that index back to a lat/lng on the track and
	/// paints a hover marker on the map — the chart-to-map linked
	/// cursor / brushing pattern Nike Run Club + Strava both ship.
	let {
		elevations = [],
		totalDistance = 0,
		onhover,
	}: {
		elevations: number[];
		totalDistance: number;
		onhover?: (idx: number | null) => void;
	} = $props();

	// Render at the container's measured width. `bind:clientWidth` uses a
	// ResizeObserver under the hood so the chart re-flows on window
	// resize, sidebar toggles, etc.
	let containerWidth = $state(0);
	let svgEl: SVGSVGElement | undefined = $state();
	const height = 180;
	const padding = { top: 18, right: 12, bottom: 22, left: 38 };

	let plotWidth = $derived(Math.max(containerWidth - padding.left - padding.right, 0));
	let plotHeight = $derived(height - padding.top - padding.bottom);

	// `minMax` reduces instead of spreading: `Math.min(...elevations)` throws
	// RangeError past ~110k args, and an ultra track is ~180k points.
	let extent = $derived(minMax(elevations));
	let minEle = $derived(extent?.min ?? 0);
	let maxEle = $derived(extent?.max ?? 100);
	let eleRange = $derived(Math.max(maxEle - minEle, 1));

	/// Total elevation gain — sum of positive deltas across the
	/// elevations array. Surfaced in the tooltip so users get the same
	/// roll-up they see on the route detail page tile.
	let totalGain = $derived.by(() => {
		let g = 0;
		for (let i = 1; i < elevations.length; i++) {
			const d = elevations[i] - elevations[i - 1];
			if (d > 0) g += d;
		}
		return Math.round(g);
	});

	function xFor(i: number): number {
		if (elevations.length < 2) return padding.left;
		return padding.left + (i / (elevations.length - 1)) * plotWidth;
	}

	function yFor(ele: number): number {
		return padding.top + plotHeight - ((ele - minEle) / eleRange) * plotHeight;
	}

	let pathD = $derived.by(() => {
		if (elevations.length < 2 || plotWidth === 0) return '';
		return elevations.map((ele, i) => `${i === 0 ? 'M' : 'L'}${xFor(i).toFixed(2)},${yFor(ele).toFixed(2)}`).join(' ');
	});

	let areaD = $derived.by(() => {
		if (elevations.length < 2 || plotWidth === 0) return '';
		const bottom = padding.top + plotHeight;
		const points = elevations
			.map((ele, i) => `${xFor(i).toFixed(2)},${yFor(ele).toFixed(2)}`)
			.join(' L');
		return `M${padding.left},${bottom} L${points} L${xFor(elevations.length - 1).toFixed(2)},${bottom} Z`;
	});

	let yLabels = $derived.by(() => {
		const labels: { ele: number; y: number }[] = [];
		const steps = 3;
		for (let i = 0; i <= steps; i++) {
			const ele = minEle + (eleRange * i) / steps;
			const y = padding.top + plotHeight - (i / steps) * plotHeight;
			labels.push({ ele: Math.round(ele), y });
		}
		return labels;
	});

	// Crosshair state. `touchFraction` is null when the user isn't
	// pointing at the chart; otherwise it's a 0..1 along the plot width.
	// Mirrors the Android `_ElevationChart` shape exactly.
	let touchFraction = $state<number | null>(null);
	let isDragging = $state(false);

	let crosshair = $derived.by(() => {
		if (touchFraction == null || elevations.length < 2 || plotWidth === 0) return null;
		const f = Math.max(0, Math.min(1, touchFraction));
		const idx = Math.round(f * (elevations.length - 1));
		const ele = elevations[idx];
		const x = padding.left + f * plotWidth;
		const y = yFor(ele);
		const distAtPoint = totalDistance * f;
		return { idx, ele, x, y, distAtPoint };
	});

	// Fan the crosshair's idx out to the parent (debounce to dedupe
	// pointermove storms that land on the same index). `untrack`-free
	// because Svelte's $effect already only re-runs when crosshair
	// actually changes.
	let lastEmittedIdx: number | null = null;
	$effect(() => {
		const next = crosshair?.idx ?? null;
		if (next === lastEmittedIdx) return;
		lastEmittedIdx = next;
		onhover?.(next);
	});

	function handlePointerMove(e: PointerEvent) {
		if (!isDragging || !svgEl || plotWidth === 0) return;
		const rect = svgEl.getBoundingClientRect();
		const xPx = e.clientX - rect.left;
		const f = (xPx - padding.left) / plotWidth;
		touchFraction = Math.max(0, Math.min(1, f));
	}

	function handlePointerDown(e: PointerEvent) {
		if (!svgEl || plotWidth === 0) return;
		isDragging = true;
		svgEl.setPointerCapture(e.pointerId);
		const rect = svgEl.getBoundingClientRect();
		const xPx = e.clientX - rect.left;
		const f = (xPx - padding.left) / plotWidth;
		touchFraction = Math.max(0, Math.min(1, f));
	}

	function handlePointerUp(e: PointerEvent) {
		if (!svgEl) return;
		isDragging = false;
		try {
			svgEl.releasePointerCapture(e.pointerId);
		} catch (_) {
			/* already released */
		}
		// Leave the crosshair in place after release on touch (so the
		// user can read the values); pointer-leave will clear it on
		// mouse devices via the leave handler below.
	}

	function handlePointerLeave() {
		if (isDragging) return;
		touchFraction = null;
	}

	function handleMouseHover(e: MouseEvent) {
		if (isDragging || !svgEl || plotWidth === 0) return;
		const rect = svgEl.getBoundingClientRect();
		const xPx = e.clientX - rect.left;
		if (xPx < padding.left || xPx > padding.left + plotWidth) {
			touchFraction = null;
			return;
		}
		const f = (xPx - padding.left) / plotWidth;
		touchFraction = Math.max(0, Math.min(1, f));
	}
</script>

<div class="elevation-wrap" bind:clientWidth={containerWidth}>
	<!-- Tooltip rail above the chart. Reserves vertical space at all
	     times so the chart doesn't shift when a value lights up. -->
	<div class="tooltip-rail" class:visible={crosshair != null}>
		{#if crosshair}
			<span class="tt-cell">
				<span class="tt-label">{m('elevationProfile.distance')}</span>
				<span class="tt-value">{formatDistance(crosshair.distAtPoint)}</span>
			</span>
			<span class="tt-cell">
				<span class="tt-label">{m('elevationProfile.elevation')}</span>
				<span class="tt-value">{Math.round(crosshair.ele)} m</span>
			</span>
			<span class="tt-cell">
				<span class="tt-label">{m('elevationProfile.gainSoFar')}</span>
				<span class="tt-value">
					{(() => {
						let g = 0;
						for (let i = 1; i <= crosshair.idx; i++) {
							const d = elevations[i] - elevations[i - 1];
							if (d > 0) g += d;
						}
						return Math.round(g);
					})()} m
				</span>
			</span>
		{:else if elevations.length >= 2}
			<span class="tt-hint">{m('elevationProfile.tapOrDragToInspect')}</span>
			<span class="tt-cell tt-cell-right">
				<span class="tt-label">{m('elevationProfile.totalGain')}</span>
				<span class="tt-value">{totalGain} m</span>
			</span>
		{/if}
	</div>

	{#if containerWidth > 0}
		<svg
			bind:this={svgEl}
			viewBox="0 0 {containerWidth} {height}"
			class="elevation-svg"
			preserveAspectRatio="none"
			role="img"
			aria-label={m('elevationProfile.ariaLabel')}
			onpointerdown={handlePointerDown}
			onpointermove={(e) => {
				handlePointerMove(e);
				handleMouseHover(e);
			}}
			onpointerup={handlePointerUp}
			onpointercancel={handlePointerUp}
			onpointerleave={handlePointerLeave}
		>
			<defs>
				<linearGradient id="elev-fill" x1="0" y1="0" x2="0" y2="1">
					<stop offset="0%" stop-color="var(--color-primary, #3b82f6)" stop-opacity="0.35" />
					<stop offset="100%" stop-color="var(--color-primary, #3b82f6)" stop-opacity="0.04" />
				</linearGradient>
			</defs>

			{#if elevations.length >= 2}
				<!-- Y-axis grid + labels -->
				{#each yLabels as label}
					<line
						x1={padding.left}
						x2={containerWidth - padding.right}
						y1={label.y}
						y2={label.y}
						class="grid"
					/>
					<text x={padding.left - 6} y={label.y + 4} class="y-label">{label.ele}</text>
				{/each}

				<!-- Filled area + elevation line -->
				<path d={areaD} class="area" />
				<path d={pathD} class="line" />

				<!-- Min / max corner pills, mirroring the Android chart's
				     top-left max + bottom-left min annotations. -->
				<g class="extreme">
					<rect x={padding.left + 4} y={padding.top - 12} width="56" height="16" rx="4" class="extreme-pill" />
					<text x={padding.left + 32} y={padding.top - 0.5} class="extreme-text" text-anchor="middle">
						▲ {Math.round(maxEle)} m
					</text>
				</g>
				<g class="extreme">
					<rect x={padding.left + 4} y={padding.top + plotHeight - 4} width="56" height="16" rx="4" class="extreme-pill" />
					<text x={padding.left + 32} y={padding.top + plotHeight + 7.5} class="extreme-text" text-anchor="middle">
						▼ {Math.round(minEle)} m
					</text>
				</g>

				<!-- X-axis distance ticks -->
				<text x={padding.left} y={height - 6} class="x-label">0</text>
				<text x={containerWidth - padding.right} y={height - 6} class="x-label" text-anchor="end">
					{formatDistance(totalDistance)}
				</text>

				<!-- Touch crosshair: vertical guide + dot at the elevation
				     line, mirroring the Android painter. -->
				{#if crosshair}
					<line
						x1={crosshair.x}
						x2={crosshair.x}
						y1={padding.top}
						y2={padding.top + plotHeight}
						class="crosshair-line"
					/>
					<circle cx={crosshair.x} cy={crosshair.y} r="5" class="crosshair-dot" />
				{/if}
			{:else}
				<text x={containerWidth / 2} y={height / 2} text-anchor="middle" class="empty-label">
					{m('elevationProfile.noElevationData')}
				</text>
			{/if}
		</svg>
	{/if}
</div>

<style>
	.elevation-wrap {
		width: 100%;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		padding: var(--space-sm) var(--space-md) var(--space-md);
	}
	.tooltip-rail {
		display: flex;
		align-items: baseline;
		gap: var(--space-md);
		min-height: 2rem;
		padding: 0.1rem 0.2rem 0.4rem;
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.tooltip-rail.visible {
		color: var(--color-text);
	}
	.tt-cell {
		display: inline-flex;
		flex-direction: column;
		gap: 0;
	}
	.tt-cell-right {
		margin-inline-start: auto;
	}
	.tt-label {
		font-size: 0.65rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-tertiary);
		line-height: 1;
	}
	.tt-value {
		font-size: 0.95rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		color: var(--color-text);
		margin-top: 0.1rem;
	}
	.tt-hint {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.elevation-svg {
		display: block;
		width: 100%;
		height: 180px;
		touch-action: none;
		cursor: crosshair;
	}
	.area {
		fill: url(#elev-fill);
	}
	.line {
		fill: none;
		stroke: var(--color-primary, #3b82f6);
		stroke-width: 2;
		stroke-linejoin: round;
		stroke-linecap: round;
		vector-effect: non-scaling-stroke;
	}
	.grid {
		stroke: var(--color-border);
		stroke-width: 1;
		stroke-dasharray: 2 4;
		opacity: 0.5;
		vector-effect: non-scaling-stroke;
	}
	.y-label {
		font-size: 11px;
		fill: var(--color-text-tertiary, #999);
		text-anchor: end;
	}
	.x-label {
		font-size: 11px;
		fill: var(--color-text-tertiary, #999);
	}
	.empty-label {
		font-size: 13px;
		fill: var(--color-text-tertiary, #999);
	}
	.extreme-pill {
		fill: color-mix(in srgb, var(--color-primary) 12%, var(--color-surface));
		stroke: color-mix(in srgb, var(--color-primary) 35%, transparent);
		stroke-width: 1;
		vector-effect: non-scaling-stroke;
	}
	.extreme-text {
		font-size: 10px;
		font-weight: 600;
		fill: var(--color-primary);
		font-variant-numeric: tabular-nums;
	}
	.crosshair-line {
		stroke: var(--color-text-secondary);
		stroke-width: 1;
		stroke-dasharray: 3 3;
		opacity: 0.7;
		vector-effect: non-scaling-stroke;
		pointer-events: none;
	}
	.crosshair-dot {
		fill: var(--color-primary);
		stroke: var(--color-surface);
		stroke-width: 2;
		pointer-events: none;
		filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.25));
	}
</style>
