<script lang="ts">
	import { formatDistance } from '$lib/units.svelte';

	let { elevations = [], totalDistance = 0 }: { elevations: number[]; totalDistance: number } =
		$props();

	// Render at the container's measured width. `bind:clientWidth` uses a
	// ResizeObserver under the hood so the chart re-flows on window
	// resize, sidebar toggles, etc. The previous fixed `viewBox="0 0
	// 300 80"` was getting letterboxed inside wider cards because the
	// default `preserveAspectRatio` keeps the chart at its 3.75:1 ratio.
	let containerWidth = $state(0);
	const height = 160;
	const padding = { top: 12, right: 12, bottom: 22, left: 38 };

	let plotWidth = $derived(Math.max(containerWidth - padding.left - padding.right, 0));
	let plotHeight = $derived(height - padding.top - padding.bottom);

	let minEle = $derived(elevations.length > 0 ? Math.min(...elevations) : 0);
	let maxEle = $derived(elevations.length > 0 ? Math.max(...elevations) : 100);
	let eleRange = $derived(Math.max(maxEle - minEle, 10));

	let pathD = $derived.by(() => {
		if (elevations.length < 2 || plotWidth === 0) return '';
		const step = plotWidth / (elevations.length - 1);
		return elevations
			.map((ele, i) => {
				const x = padding.left + i * step;
				const y = padding.top + plotHeight - ((ele - minEle) / eleRange) * plotHeight;
				return `${i === 0 ? 'M' : 'L'}${x.toFixed(2)},${y.toFixed(2)}`;
			})
			.join(' ');
	});

	let areaD = $derived.by(() => {
		if (elevations.length < 2 || plotWidth === 0) return '';
		const step = plotWidth / (elevations.length - 1);
		const bottom = padding.top + plotHeight;
		const points = elevations
			.map((ele, i) => {
				const x = padding.left + i * step;
				const y = padding.top + plotHeight - ((ele - minEle) / eleRange) * plotHeight;
				return `${x.toFixed(2)},${y.toFixed(2)}`;
			})
			.join(' L');
		const lastX = padding.left + (elevations.length - 1) * step;
		return `M${padding.left},${bottom} L${points} L${lastX.toFixed(2)},${bottom} Z`;
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
</script>

<div class="elevation-wrap" bind:clientWidth={containerWidth}>
	{#if containerWidth > 0}
		<svg viewBox="0 0 {containerWidth} {height}" class="elevation-svg" preserveAspectRatio="none">
			{#if elevations.length >= 2}
				<path d={areaD} class="area" />
				<path d={pathD} class="line" />

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

				<text x={padding.left} y={height - 6} class="x-label">0</text>
				<text x={containerWidth - padding.right} y={height - 6} class="x-label" text-anchor="end">
					{formatDistance(totalDistance)}
				</text>
			{:else}
				<text x={containerWidth / 2} y={height / 2} text-anchor="middle" class="empty-label">
					No elevation data
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
		min-height: 160px;
	}
	.elevation-svg {
		display: block;
		width: 100%;
		height: 160px;
	}
	.area {
		fill: var(--color-primary-light, rgba(59, 130, 246, 0.15));
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
</style>
