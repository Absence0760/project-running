<script lang="ts">
	import type { Run } from '$lib/types';

	let { runs = [] }: { runs: Run[] } = $props();

	const weeks = 20;
	const cellSize = 14;
	const cellGap = 3;
	const totalSize = cellSize + cellGap;

	// Build a map of date -> total distance
	let dayMap = $derived.by(() => {
		const map = new Map<string, number>();
		for (const run of runs) {
			const day = run.started_at.slice(0, 10);
			map.set(day, (map.get(day) ?? 0) + run.distance_m);
		}
		return map;
	});

	let maxDistance = $derived(Math.max(...dayMap.values(), 1));

	// Generate grid: 20 weeks x 7 days
	let cells = $derived.by(() => {
		const result: { date: string; col: number; row: number; distance: number }[] = [];
		const today = new Date();
		const dayOfWeek = today.getDay(); // 0 = Sunday

		// Start from (weeks) weeks ago, aligned to Sunday
		const start = new Date(today);
		start.setDate(today.getDate() - (weeks * 7) + (7 - dayOfWeek));
		start.setHours(0, 0, 0, 0);

		for (let w = 0; w < weeks; w++) {
			for (let d = 0; d < 7; d++) {
				const date = new Date(start);
				date.setDate(start.getDate() + w * 7 + d);
				if (date > today) continue;

				const dateStr = date.toISOString().slice(0, 10);
				result.push({
					date: dateStr,
					col: w,
					row: d,
					distance: dayMap.get(dateStr) ?? 0
				});
			}
		}
		return result;
	});

	function intensity(distance: number): string {
		if (distance === 0) return 'var(--color-bg-tertiary)';
		const ratio = Math.min(distance / maxDistance, 1);
		if (ratio < 0.25) return '#C7D2FE';
		if (ratio < 0.5) return '#818CF8';
		if (ratio < 0.75) return '#6366F1';
		return '#4F46E5';
	}

	function formatTooltip(date: string, distance: number): string {
		const d = new Date(date);
		const label = d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
		if (distance === 0) return `${label}: No run`;
		return `${label}: ${(distance / 1000).toFixed(1)} km`;
	}

	const dayLabels = ['Sun', '', 'Tue', '', 'Thu', '', 'Sat'];
	const svgWidth = weeks * totalSize + 30;
	const svgHeight = 7 * totalSize + 4;
</script>

<svg viewBox="0 0 {svgWidth} {svgHeight}" class="heatmap">
	{#each dayLabels as label, i}
		{#if label}
			<text x="0" y={i * totalSize + cellSize} class="day-label">{label}</text>
		{/if}
	{/each}

	{#each cells as cell}
		<rect
			x={cell.col * totalSize + 28}
			y={cell.row * totalSize}
			width={cellSize}
			height={cellSize}
			rx="2"
			fill={intensity(cell.distance)}
		>
			<title>{formatTooltip(cell.date, cell.distance)}</title>
		</rect>
	{/each}
</svg>

<style>
	.heatmap {
		width: 100%;
		max-width: 100%;
		height: auto;
	}

	.day-label {
		font-size: 7px;
		fill: var(--color-text-tertiary);
	}
</style>
