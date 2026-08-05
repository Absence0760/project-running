<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { m as t } from '$lib/i18n/store.svelte';
	import type { TrainingLoadPoint } from '$lib/training/training_load';

	interface Props {
		points: TrainingLoadPoint[];
		hasHr: boolean;
	}
	let { points, hasHr }: Props = $props();

	// Fixed viewBox; we let the host stretch the SVG and use
	// preserveAspectRatio so points stay legible at any width.
	const W = 600;
	const H = 200;
	// The y labels live in a real CSS gutter beside the SVG, not inside it:
	// preserveAspectRatio="none" stretches the viewBox horizontally, which
	// would distort any <text> drawn in it.
	const PAD_L = 4;
	const PAD_R = 8;
	const PAD_T = 16;
	const PAD_B = 24;

	let plotW = $derived(W - PAD_L - PAD_R);
	let plotH = $derived(H - PAD_T - PAD_B);

	let valueRange = $derived.by(() => {
		if (points.length === 0) return { min: -10, max: 10 };
		let min = Infinity;
		let max = -Infinity;
		for (const p of points) {
			min = Math.min(min, p.atl, p.ctl, p.tsb);
			max = Math.max(max, p.atl, p.ctl, p.tsb);
		}
		// Always include zero so the TSB sign is visible.
		min = Math.min(min, 0);
		max = Math.max(max, 0);
		// Pad ~10% so lines don't sit on the axis.
		const span = Math.max(max - min, 10);
		return { min: min - span * 0.1, max: max + span * 0.1 };
	});

	function xAt(idx: number): number {
		if (points.length <= 1) return PAD_L;
		return PAD_L + (idx / (points.length - 1)) * plotW;
	}
	function yAt(value: number): number {
		const { min, max } = valueRange;
		if (max === min) return PAD_T + plotH / 2;
		return PAD_T + plotH * (1 - (value - min) / (max - min));
	}

	function pathFor(key: 'atl' | 'ctl' | 'tsb'): string {
		if (points.length === 0) return '';
		return points
			.map((p, i) => `${i === 0 ? 'M' : 'L'} ${xAt(i).toFixed(1)} ${yAt(p[key]).toFixed(1)}`)
			.join(' ');
	}

	let zeroY = $derived(yAt(0));

	/// Round tick step on the 1 / 2 / 5 x 10^n ladder. The plot is
	/// min/max-normalised, so without labelled ticks CTL 45 and CTL 450 draw
	/// pixel-identically — shape without magnitude. Mirrors mobile's
	/// `trainingLoadTickStep`.
	function tickStep(span: number, maxTicks = 4): number {
		if (!Number.isFinite(span) || span <= 0) return 1;
		const raw = span / maxTicks;
		const mag = 10 ** Math.floor(Math.log10(raw));
		const norm = raw / mag;
		const mult = norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10;
		return mult * mag;
	}

	let ticks = $derived.by(() => {
		const { min, max } = valueRange;
		const step = tickStep(max - min);
		const out: Array<{ value: number; y: number }> = [];
		for (let v = Math.ceil(min / step) * step; v <= max + step * 0.001; v += step) {
			out.push({ value: Math.round(v), y: yAt(v) });
		}
		return out;
	});

	let last = $derived(points.at(-1));
	// Honest signal that gym load is folded into these curves — the
	// dashboard passes lifts whenever the user has logged a session, so
	// any liftStress means the trio reflects more than running
	// (multi_modal.md Tier-1 lift→load).
	let hasLiftLoad = $derived(points.some((p) => p.liftStress > 0));
	let firstDate = $derived(points[0]?.date ?? '');
	let lastDate = $derived(points.at(-1)?.date ?? '');

	function fmtNum(n: number | undefined): string {
		if (n == null) return '—';
		return n.toFixed(0);
	}

	function fmtDateLabel(iso: string): string {
		if (!iso) return '';
		const [y, m, d] = iso.split('-').map(Number);
		const dt = new Date(y, m - 1, d);
		return dt.toLocaleDateString(activeFormatLocale(), { month: 'short', day: 'numeric' });
	}
</script>

<div class="training-load">
	<header>
		<h2>{t('trainingLoad.heading')}</h2>
		<p class="hint">
			{#if hasHr}
				{t('trainingLoad.hintTrimp', { n: points.length })}
			{:else}
				{t('trainingLoad.hintVolume')}
			{/if}
		</p>
		{#if hasLiftLoad}
			<p class="hint hint-lifts">{t('trainingLoad.includesLifts')}</p>
		{/if}
	</header>

	{#if points.length === 0}
		<p class="empty">{t('trainingLoad.empty')}</p>
	{:else}
		<div class="legend">
			<span class="key fitness">
				<span class="swatch" aria-hidden="true"></span>
				{t('trainingLoad.fitness')} · {fmtNum(last?.ctl)}
			</span>
			<span class="key fatigue">
				<span class="swatch" aria-hidden="true"></span>
				{t('trainingLoad.fatigue')} · {fmtNum(last?.atl)}
			</span>
			<span class="key form">
				<span class="swatch" aria-hidden="true"></span>
				{t('trainingLoad.form')} · {fmtNum(last?.tsb)}
			</span>
		</div>

		<div class="chart-wrap">
			<div class="plot">
				<div class="y-axis" aria-hidden="true">
					{#each ticks as tick (tick.value)}
						<span class="y-tick" style="top: {(tick.y / H) * 100}%">{tick.value}</span>
					{/each}
				</div>
				<!--
					audit/accessibility (May 2026) Medium — WCAG 1.1.1.
					Three series (CTL / ATL / TSB) over 90 days with no
					text alternative; screen readers traversed every
					<path> + <line> individually. role="img" + a one-line
					summary aria-label collapses it into a single
					landmark; the in-component legend above the chart
					gives the per-series detail.
				-->
				<svg
					viewBox="0 0 {W} {H}"
					preserveAspectRatio="none"
					class="chart-svg"
					role="img"
					aria-label={t('trainingLoad.chartAriaLabel')}
				>
					{#each ticks as tick (tick.value)}
						{#if tick.value !== 0}
							<line
								x1={PAD_L}
								y1={tick.y}
								x2={W - PAD_R}
								y2={tick.y}
								class="grid-line"
							/>
						{/if}
					{/each}
					<line
						x1={PAD_L}
						y1={zeroY}
						x2={W - PAD_R}
						y2={zeroY}
						class="zero-line"
					/>
					<path d={pathFor('ctl')} class="line fitness" />
					<path d={pathFor('atl')} class="line fatigue" />
					<path d={pathFor('tsb')} class="line form" />
				</svg>
			</div>
			<div class="x-labels">
				<span>{fmtDateLabel(firstDate)}</span>
				<span>{fmtDateLabel(lastDate)}</span>
			</div>
		</div>

		<p class="reading">
			{#if last && last.tsb < -10}
				{t('trainingLoad.readingLoaded')}
			{:else if last && last.tsb > 10}
				{t('trainingLoad.readingTapered')}
			{:else}
				{t('trainingLoad.readingBalanced')}
			{/if}
		</p>
	{/if}
</div>

<style>
	.training-load {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	header h2 {
		font-size: 1.1rem;
		font-weight: 700;
		margin: 0 0 0.2rem 0;
	}

	.hint {
		margin: 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.empty {
		color: var(--color-text-tertiary);
		text-align: center;
		padding: var(--space-xl);
	}

	.legend {
		display: flex;
		gap: var(--space-md);
		flex-wrap: wrap;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.key {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}

	.swatch {
		display: inline-block;
		width: 0.85rem;
		height: 0.85rem;
		border-radius: 2px;
	}

	.fitness .swatch { background: var(--chart-fitness); }
	.fatigue .swatch { background: var(--chart-fatigue); }
	/* No sign colouring: one stroke cannot change hue at every zero
	   crossing of the window it spans, so a key recoloured by the last
	   TSB would name a colour the line never draws. The sign is carried
	   by the dashed zero line, the signed value beside this key, and the
	   reading below the plot. */
	.form .swatch { background: var(--chart-form); }

	.chart-wrap {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}

	.plot {
		display: flex;
		align-items: stretch;
		height: 12rem;
	}

	/* Real CSS gutter: the SVG stretches horizontally, so a <text> inside it
	   would be squashed at every viewport width. */
	.y-axis {
		position: relative;
		flex: 0 0 2.4rem;
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}

	.y-tick {
		position: absolute;
		inset-inline-end: 0.35rem;
		transform: translateY(-50%);
		line-height: 1;
	}

	.chart-svg {
		flex: 1 1 auto;
		min-width: 0;
		height: 100%;
		display: block;
	}

	.grid-line {
		stroke: var(--color-fill-subtle);
		stroke-width: 1;
		vector-effect: non-scaling-stroke;
	}

	.zero-line {
		stroke: var(--color-text-tertiary);
		stroke-width: 1;
		stroke-dasharray: 3 4;
		opacity: 0.5;
		vector-effect: non-scaling-stroke;
	}

	.line {
		fill: none;
		stroke-width: 2;
		stroke-linejoin: round;
		stroke-linecap: round;
		vector-effect: non-scaling-stroke;
	}

	.line.fitness { stroke: var(--chart-fitness); }
	.line.fatigue { stroke: var(--chart-fatigue); }
	.line.form { stroke: var(--chart-form); }

	.x-labels {
		display: flex;
		justify-content: space-between;
		padding-inline-start: 2.4rem;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}

	.reading {
		margin: 0;
		padding: var(--space-sm) var(--space-md);
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
</style>
