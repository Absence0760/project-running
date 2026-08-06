<script lang="ts">
	import { computeIntensity } from '$lib/training/intensity';
	import { fmtPace } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';

	interface Props {
		runs: Run[];
	}
	let { runs }: Props = $props();

	// Self-hides on null — no derivable threshold, or fewer than the
	// minimum classified runs (the helper's own floor). Matches the
	// data-presence self-hiding pattern the other analytics cards use.
	let stats = $derived(computeIntensity(runs));
</script>

{#if stats}
	<section class="card-elevated intensity-balance" data-testid="intensity-balance">
		<div class="card-head">
			<h2>{m('intensityBalance.title')}</h2>
			<span class="verdict-chip chip-{stats.verdict}" data-testid="intensity-verdict">
				{m(`intensityBalance.verdict_${stats.verdict}`)}
			</span>
		</div>

		<div class="split-bar" aria-hidden="true">
			<span class="seg seg-easy" style="width: {stats.easyTimePct}%"></span>
			<span class="seg seg-hard" style="width: {stats.hardTimePct}%"></span>
		</div>

		<div class="split-values">
			<div class="split-metric">
				<span class="dot dot-easy"></span>
				<span class="pct" data-testid="intensity-easy-pct">{stats.easyTimePct}%</span>
				<span class="metric-label">{m('intensityBalance.easyLabel')}</span>
			</div>
			<div class="split-metric">
				<span class="dot dot-hard"></span>
				<span class="pct" data-testid="intensity-hard-pct">{stats.hardTimePct}%</span>
				<span class="metric-label">{m('intensityBalance.hardLabel')}</span>
			</div>
		</div>

		<p class="counts" data-testid="intensity-counts">
			{m('intensityBalance.counts', {
				easy: stats.easyRuns,
				hard: stats.hardRuns,
				weeks: stats.windowWeeks,
			})}
		</p>

		<p class="footnote">
			{m('intensityBalance.footnote', { pace: fmtPace(stats.thresholdPaceSecPerKm) })}
		</p>
	</section>
{/if}

<style>
	.intensity-balance {
		padding: var(--space-xl);
	}
	.card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
	}
	.card-head h2 {
		margin: 0;
	}
	.verdict-chip {
		padding: 0.1rem 0.55rem;
		border-radius: 999px;
		font-size: var(--font-size-section-label);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}
	.chip-onGuideline {
		background: var(--color-success-light);
		color: var(--color-success-text);
	}
	.chip-tooHard {
		background: var(--color-danger-light);
		color: var(--color-danger-text);
	}
	.chip-allEasy {
		background: color-mix(in srgb, var(--color-accent-cyan) 16%, transparent);
		color: var(--color-accent-cyan-text);
	}
	.split-bar {
		display: flex;
		height: 14px;
		border-radius: 999px;
		overflow: hidden;
		background: var(--color-bg-secondary);
		margin-bottom: var(--space-md);
	}
	.seg {
		height: 100%;
	}
	/* The two ends of the shared intensity ladder (--zone-1 .. --zone-5), not a
	   bespoke pair: easy and hard ARE the extremes of that ramp, and the rungs
	   are already luminance-separated per brightness, which is what carries the
	   split in greyscale. */
	.seg-easy {
		background: var(--zone-1);
	}
	.seg-hard {
		background: var(--zone-5);
	}
	.split-values {
		display: flex;
		gap: var(--space-xl);
		margin-bottom: var(--space-sm);
	}
	.split-metric {
		display: flex;
		align-items: baseline;
		gap: 0.4rem;
	}
	.dot {
		width: 0.6rem;
		height: 0.6rem;
		border-radius: 50%;
		align-self: center;
	}
	.dot-easy {
		background: var(--zone-1);
	}
	.dot-hard {
		background: var(--zone-5);
	}
	.pct {
		font-size: 1.4rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.metric-label {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.counts {
		margin: 0 0 var(--space-sm);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.footnote {
		margin: 0;
		font-size: 0.78rem;
		color: var(--color-text-secondary);
	}
</style>
