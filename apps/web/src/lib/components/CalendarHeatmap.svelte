<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { m } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';
	import { formatISO } from '$lib/training/training';
	import { fmtKm } from '$lib/format/units.svelte';
	import { bucketRunsByLocalDay, heatScaleMax } from './calendar_heatmap';

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

	let maxDistance = $derived(heatScaleMax(dayMap.values()));

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

	// Three levels, not four: --heat-1..3 is the whole accessible ladder (see
	// the app.css note), and mobile's ChartPalette.ramp carries the same three,
	// so a shade means the same thing on both platforms' grids.
	function intensity(distance: number): string {
		if (distance === 0) return 'var(--color-bg-tertiary)';
		const ratio = Math.min(distance / maxDistance, 1);
		if (ratio < 1 / 3) return 'var(--heat-1)';
		if (ratio < 2 / 3) return 'var(--heat-2)';
		return 'var(--heat-3)';
	}

	function formatTooltip(date: string, distance: number): string {
		const d = new Date(date);
		const label = d.toLocaleDateString(activeFormatLocale(), { day: 'numeric', month: 'short', year: 'numeric' });
		if (distance === 0) return m('calendarHeatmap.noRun', { date: label });
		return `${label}: ${fmtKm(distance)}`;
	}

	// Short weekday names in the runtime locale, ordered to start on the
	// user's `week_start_day`. 2024-01-07 is a Sunday, so adding the row
	// index (offset for a Monday start) walks the week in display order.
	// Only alternate rows are labelled to keep the column legible.
	let dayLabels = $derived.by(() => {
		const fmt = new Intl.DateTimeFormat(activeFormatLocale(), { weekday: 'short' });
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
			data-day={cell.date}
			fill={intensity(cell.distance)}
			stroke={cell.distance === 0 ? 'var(--heat-0)' : 'none'}
			stroke-width={cell.distance === 0 ? 1 : 0}
		>
			<title>{formatTooltip(cell.date, cell.distance)}</title>
		</rect>
	{/each}
</svg>

<!-- The ramp has no axis, so the legend is the only thing that says which
     direction is more. aria-hidden because the per-cell <title>s already
     give AT the actual value; the swatches would just be noise. -->
<div class="heat-legend" aria-hidden="true">
	<span>{m('calendarHeatmap.less')}</span>
	<i class="swatch zero"></i>
	<i class="swatch" style="background: var(--heat-1);"></i>
	<i class="swatch" style="background: var(--heat-2);"></i>
	<i class="swatch" style="background: var(--heat-3);"></i>
	<span>{m('calendarHeatmap.more')}</span>
</div>

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

	.heat-legend {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		gap: 0.25rem;
		margin-top: 0.5rem;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}

	.swatch {
		width: 10px;
		height: 10px;
		border-radius: 2px;
	}

	.swatch.zero {
		background: var(--color-bg-tertiary);
		border: 1px solid var(--heat-0);
	}
</style>
