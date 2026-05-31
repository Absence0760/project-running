<script lang="ts">
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
	const PAD_L = 40;
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

	let last = $derived(points.at(-1));
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
		return dt.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
	}
</script>

<div class="training-load">
	<header>
		<h2>Fitness, Fatigue & Form</h2>
		<p class="hint">
			{#if hasHr}
				Computed from heart-rate-based TRIMP scores over the last {points.length} days.
			{:else}
				Volume-based estimate (no HR data yet — add resting + max HR in preferences and record runs
				with a strap to upgrade to TRIMP).
			{/if}
		</p>
	</header>

	{#if points.length === 0}
		<p class="empty">Record a few runs to see your fitness trend.</p>
	{:else}
		<div class="legend">
			<span class="key fitness">
				<span class="swatch" aria-hidden="true"></span>
				Fitness · {fmtNum(last?.ctl)}
			</span>
			<span class="key fatigue">
				<span class="swatch" aria-hidden="true"></span>
				Fatigue · {fmtNum(last?.atl)}
			</span>
			<span class="key form" class:positive={(last?.tsb ?? 0) >= 0}>
				<span class="swatch" aria-hidden="true"></span>
				Form · {fmtNum(last?.tsb)}
			</span>
		</div>

		<div class="chart-wrap">
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
				aria-label="Training load chart — 90-day fitness (CTL), fatigue (ATL), and form (TSB) trends"
			>
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
			<div class="x-labels">
				<span>{fmtDateLabel(firstDate)}</span>
				<span>{fmtDateLabel(lastDate)}</span>
			</div>
		</div>

		<p class="reading">
			{#if last && last.tsb < -10}
				Loaded up — push through and recover when you're ready.
			{:else if last && last.tsb > 10}
				Tapered — a hard session won't break you.
			{:else}
				Balanced — easy day or hard day, your call.
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

	.fitness .swatch { background: #4f46e5; }
	.fatigue .swatch { background: #f59e0b; }
	.form .swatch { background: #ef4444; }
	.form.positive .swatch { background: #10b981; }

	.chart-wrap {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}

	.chart-svg {
		width: 100%;
		height: 12rem;
		display: block;
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

	.line.fitness { stroke: #4f46e5; }
	.line.fatigue { stroke: #f59e0b; }
	.line.form { stroke: #ef4444; }

	.x-labels {
		display: flex;
		justify-content: space-between;
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
