<script lang="ts">
	import { comebackLoad, shouldSurfaceComeback } from '$lib/training/comeback';
	import { fmtKm } from '$lib/format/units.svelte';
	import { activeFormatLocale } from '$lib/format/time';
	import { m } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';

	interface Props {
		runs: Run[];
	}
	let { runs }: Props = $props();

	// Null when there is no break to speak to, no usable pre-break base, or no
	// running this week — the card self-hides exactly as LoadRampCard does, and
	// the null narrows `load.verdict` to the two the card has copy for.
	let load = $derived.by(() => {
		const graded = comebackLoad(runs, Date.now());
		return shouldSurfaceComeback(graded) ? graded : null;
	});

	// Percent style rather than toFixed: the symbol's placement and the
	// decimal separator are both locale-dependent.
	let shareLabel = $derived(
		load === null
			? ''
			: new Intl.NumberFormat(activeFormatLocale(), {
					style: 'percent',
					maximumFractionDigits: 0,
				}).format(load.share),
	);
</script>

{#if load}
	<section class="card-elevated comeback" data-testid="comeback">
		<div class="card-head">
			<h2>{m('comeback.title')}</h2>
			<span class="verdict-chip chip-{load.verdict}" data-testid="comeback-verdict">
				{m(`comeback.verdict_${load.verdict}`)}
			</span>
		</div>

		<p class="layoff" data-testid="comeback-layoff">
			{m('comeback.layoff', { weeks: load.layoffWeeks })}
		</p>

		<p class="share" data-testid="comeback-share">{shareLabel}</p>
		<p class="share-caption">{m('comeback.shareCaption')}</p>

		<p class="meaning" data-testid="comeback-meaning">{m(`comeback.meaning_${load.verdict}`)}</p>

		<div class="figures">
			<div class="figure">
				<span class="fig-value" data-testid="comeback-this-week">{fmtKm(load.thisWeekM)}</span>
				<span class="fig-label">{m('comeback.thisWeekLabel')}</span>
			</div>
			<div class="figure">
				<span class="fig-value" data-testid="comeback-base">{fmtKm(load.preLayoffWeeklyM)}</span>
				<span class="fig-label">{m('comeback.baseLabel')}</span>
			</div>
		</div>

		<p class="footnote">{m('comeback.footnote')}</p>
	</section>
{/if}

<style>
	.comeback {
		padding: var(--space-xl);
	}
	.card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		margin-bottom: var(--space-xs);
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
	/* A steep first week is a caution, not an emergency: the danger role stays
	   with LoadRampCard's `high` band, which describes a runner whose own
	   recent base says they are spiking. */
	.chip-easing_in {
		background: var(--color-success-light);
		color: var(--color-success-text);
	}
	.chip-steep {
		background: var(--color-warning-light);
		color: var(--color-warning-text);
	}
	.layoff {
		margin: 0 0 var(--space-md);
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
	}
	.share {
		margin: 0;
		font-size: 2.2rem;
		font-weight: 700;
		line-height: 1.1;
		font-variant-numeric: tabular-nums;
	}
	.share-caption {
		margin: 0.15rem 0 var(--space-md);
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
	}
	.meaning {
		margin: 0 0 var(--space-md);
	}
	.figures {
		display: flex;
		gap: var(--space-xl);
		margin-bottom: var(--space-sm);
		flex-wrap: wrap;
	}
	.figure {
		display: flex;
		flex-direction: column;
	}
	.fig-value {
		font-size: 1.15rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.fig-label {
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
	}
	.footnote {
		margin: 0;
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
	}
</style>
