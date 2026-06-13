<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { m } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';
	import { formatISO } from '$lib/training/training';
	import { fmtKm } from '$lib/format/units.svelte';
	import { bucketRunsByLocalDay } from './calendar_heatmap';

	let { runs = [], weekStartDay = 'sunday' }: { runs: Run[]; weekStartDay?: 'monday' | 'sunday' } =
		$props();

	const weeks = 20;
	const cellSize = 14;
	const cellGap = 3;
	const totalSize = cellSize + cellGap;

	// `getDay()` is 0 = Sunday … 6 = Saturday. Map it to a row index that
	// honours the user's `week_start_day`: row 0 is their chosen first day.
	function rowFor(day: number): number {
		return weekStartDay === 'monday' ? (day + 6) % 7 : day;
	}

	// First day of the rendered window — `weeks` back from today, aligned to
	// the user's week start so the grid's last column ends on the current
	// (partial) week. Computed once so the cell layout and the run bucketing
	// share the exact same window: bucketing only the runs inside it (rather
	// than the whole history) keeps the work + the dayMap bounded regardless
	// of account age. perf-hunt 2026-06-10.
	let gridStart = $derived.by(() => {
		const today = new Date();
		const start = new Date(today);
		start.setDate(today.getDate() - weeks * 7 + (7 - rowFor(today.getDay())));
		start.setHours(0, 0, 0, 0);
		return start;
	});

	// Build a map of local-day date -> total distance, windowed to the grid.
	// Keys must match the grid cell keys below (`formatISO(date)`, also local)
	// — keying by the UTC `started_at.slice(0,10)` would land evening runs on
	// the wrong cell.
	let dayMap = $derived(bucketRunsByLocalDay(runs, gridStart.getTime()));

	let maxDistance = $derived(Math.max(...dayMap.values(), 1));

	// Generate grid: 20 weeks x 7 days
	let cells = $derived.by(() => {
		const result: { date: string; col: number; row: number; distance: number }[] = [];
		const today = new Date();
		const start = gridStart;

		for (let w = 0; w < weeks; w++) {
			for (let d = 0; d < 7; d++) {
				const date = new Date(start);
				date.setDate(start.getDate() + w * 7 + d);
				if (date > today) continue;

				// Format as local yyyy-mm-dd — `toISOString` gives the UTC
				// date, which cuts the heatmap by the wrong day for any
				// viewer not on UTC near midnight.
				const dateStr = formatISO(date);
				result.push({
					date: dateStr,
					col: w,
					row: rowFor(date.getDay()),
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
		const label = d.toLocaleDateString(activeFormatLocale(), { day: 'numeric', month: 'short', year: 'numeric' });
		if (distance === 0) return `${label}: No run`;
		return `${label}: ${fmtKm(distance)}`;
	}

	// Short weekday names in the runtime locale, ordered to start on the
	// user's `week_start_day`. 2024-01-07 is a Sunday, so adding the row
	// index (offset for a Monday start) walks the week in display order.
	// Only alternate rows are labelled to keep the column legible.
	let dayLabels = $derived.by(() => {
		const fmt = new Intl.DateTimeFormat(undefined, { weekday: 'short' });
		const sundayBase = new Date(2024, 0, 7);
		const startOffset = weekStartDay === 'monday' ? 1 : 0;
		return Array.from({ length: 7 }, (_, row) => {
			if (row % 2 === 1) return '';
			const d = new Date(sundayBase);
			d.setDate(sundayBase.getDate() + startOffset + row);
			return fmt.format(d);
		});
	});
	const svgWidth = weeks * totalSize + 30;
	const svgHeight = 7 * totalSize + 4;
</script>

<!--
	audit/accessibility (May 2026) Medium — WCAG 1.1.1. Without
	role + aria-label the whole heatmap is traversed by screen
	readers as N×7 individual <rect> elements; with role="img" +
	aria-label, AT treats it as a single labelled landmark. Per-
	cell <title>s still provide the per-day detail when the user
	zooms into individual cells.
-->
<svg
	viewBox="0 0 {svgWidth} {svgHeight}"
	class="heatmap"
	role="img"
	aria-label={m('calendarHeatmap.label')}
>
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
