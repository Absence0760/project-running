<script lang="ts">
	import { selfLoad, shouldSurfaceSelfLoad } from '$lib/training/self_load';
	import { fmtKm } from '$lib/format/units.svelte';
	import { activeFormatLocale } from '$lib/format/time';
	import { m } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';

	interface Props {
		runs: Run[];
	}
	let { runs }: Props = $props();

	// Self-hides on an ungradeable band — too little history for the ratio to
	// mean anything. Matches the data-presence self-hiding the sibling
	// analytics cards use; a zeroed ratio would read as a reassuring "safe".
	// Null when the band is ungradeable, which narrows `load.band` to the four
	// the card has copy for — so an unlabelled band is a compile error rather
	// than a missing-key render.
	let load = $derived.by(() => {
		const graded = selfLoad(runs, Date.now());
		return shouldSurfaceSelfLoad(graded) ? graded : null;
	});

	// The decimal separator is locale-dependent (1,60 in de), so the ratio
	// goes through Intl rather than toFixed.
	let ratioLabel = $derived(
		load === null
			? ''
			: new Intl.NumberFormat(activeFormatLocale(), {
					minimumFractionDigits: 2,
					maximumFractionDigits: 2,
				}).format(load.ratio),
	);
</script>

{#if load}
	<section class="card-elevated load-ramp" data-testid="load-ramp">
		<div class="card-head">
			<h2>{m('loadRamp.title')}</h2>
			<span class="verdict-chip chip-{load.band}" data-testid="load-ramp-band">
				{m(`loadRamp.band_${load.band}`)}
			</span>
		</div>

		<p class="ratio" data-testid="load-ramp-ratio">
			{ratioLabel}<span class="ratio-mult">&times;</span>
		</p>
		<p class="ratio-caption">{m('loadRamp.ratioCaption')}</p>

		<p class="meaning" data-testid="load-ramp-meaning">{m(`loadRamp.meaning_${load.band}`)}</p>

		<div class="figures">
			<div class="figure">
				<span class="fig-value" data-testid="load-ramp-acute">{fmtKm(load.acuteM)}</span>
				<span class="fig-label">{m('loadRamp.acuteLabel')}</span>
			</div>
			<div class="figure">
				<span class="fig-value" data-testid="load-ramp-chronic">{fmtKm(load.chronicWeeklyM)}</span>
				<span class="fig-label">{m('loadRamp.chronicLabel')}</span>
			</div>
		</div>

		<p class="footnote">{m(`loadRamp.trend_${load.trend}`)}</p>
	</section>
{/if}

<style>
	.load-ramp {
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
	/* A band is a status role, so each takes the app.css status vocabulary
	   rather than a bespoke hue. `low` is deliberately informational, not a
	   warning: running below your own base is a taper, not a hazard. */
	.chip-low {
		background: color-mix(in srgb, var(--color-accent-cyan) 16%, transparent);
		color: var(--color-accent-cyan-text);
	}
	.chip-optimal {
		background: var(--color-success-light);
		color: var(--color-success-text);
	}
	.chip-elevated {
		background: var(--color-warning-light);
		color: var(--color-warning-text);
	}
	.chip-high {
		background: var(--color-danger-light);
		color: var(--color-danger-text);
	}
	.ratio {
		margin: 0;
		font-size: 2.2rem;
		font-weight: 700;
		line-height: 1.1;
		font-variant-numeric: tabular-nums;
	}
	.ratio-mult {
		font-size: 1.2rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin-inline-start: 0.15rem;
	}
	.ratio-caption {
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
