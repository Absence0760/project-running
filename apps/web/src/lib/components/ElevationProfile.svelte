<script lang="ts">
	import { formatDistance } from '$lib/units.svelte';

	let { elevations = [], totalDistance = 0 }: { elevations: number[]; totalDistance: number } =
		$props();

	const width = 300;
	const height = 80;
	const padding = { top: 4, right: 4, bottom: 16, left: 32 };

	let plotWidth = $derived(width - padding.left - padding.right);
	let plotHeight = $derived(height - padding.top - padding.bottom);

	let minEle = $derived(elevations.length > 0 ? Math.min(...elevations) : 0);
	let maxEle = $derived(elevations.length > 0 ? Math.max(...elevations) : 100);
	let eleRange = $derived(Math.max(maxEle - minEle, 10));

	let pathD = $derived.by(() => {
		if (elevations.length < 2) return '';
		const step = plotWidth / (elevations.length - 1);
		return elevations
			.map((ele, i) => {
				const x = padding.left + i * step;
				const y = padding.top + plotHeight - ((ele - minEle) / eleRange) * plotHeight;
				return `${i === 0 ? 'M' : 'L'}${x},${y}`;
			})
			.join(' ');
	});

	let areaD = $derived.by(() => {
		if (elevations.length < 2) return '';
		const step = plotWidth / (elevations.length - 1);
		const bottom = padding.top + plotHeight;
		const points = elevations
			.map((ele, i) => {
				const x = padding.left + i * step;
				const y = padding.top + plotHeight - ((ele - minEle) / eleRange) * plotHeight;
				return `${x},${y}`;
			})
			.join(' L');
		const lastX = padding.left + (elevations.length - 1) * step;
		return `M${padding.left},${bottom} L${points} L${lastX},${bottom} Z`;
	});

	let yLabels = $derived.by(() => {
		const labels = [];
		const steps = 3;
		for (let i = 0; i <= steps; i++) {
			const ele = minEle + (eleRange * i) / steps;
			const y = padding.top + plotHeight - (i / steps) * plotHeight;
			labels.push({ ele: Math.round(ele), y });
		}
		return labels;
	});
</script>

<svg viewBox="0 0 {width} {height}" class="elevation-svg">
	{#if elevations.length >= 2}
		<path d={areaD} class="area" />
		<path d={pathD} class="line" />

		{#each yLabels as label}
			<text x={padding.left - 4} y={label.y + 3} class="y-label">{label.ele}</text>
		{/each}

		<text x={padding.left} y={height - 2} class="x-label">0</text>
		<text x={padding.left + plotWidth} y={height - 2} class="x-label" text-anchor="end">
			{formatDistance(totalDistance)}
		</text>
	{:else}
		<text x={width / 2} y={height / 2} text-anchor="middle" class="empty-label">
			No elevation data
		</text>
	{/if}
</svg>

<style>
	.elevation-svg {
		width: 100%;
		height: 80px;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}

	.area {
		fill: var(--color-primary-light, rgba(59, 130, 246, 0.15));
	}

	.line {
		fill: none;
		stroke: var(--color-primary, #3b82f6);
		stroke-width: 1.5;
		stroke-linejoin: round;
	}

	.y-label {
		font-size: 6px;
		fill: var(--color-text-tertiary, #999);
		text-anchor: end;
	}

	.x-label {
		font-size: 6px;
		fill: var(--color-text-tertiary, #999);
	}

	.empty-label {
		font-size: 8px;
		fill: var(--color-text-tertiary, #999);
	}
</style>
