<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { formatPrice } from '$lib/format/format_price';
	import { fundraiserProgress } from '$lib/social/fundraiser_progress';

	let {
		raisedCents,
		goalCents,
		donorCount,
		currency = 'usd'
	}: {
		raisedCents: number;
		goalCents: number;
		donorCount: number;
		currency?: string;
	} = $props();

	const progress = $derived(fundraiserProgress(raisedCents, goalCents));
	const cur = $derived(currency.toUpperCase());
	const raised = $derived(formatPrice(raisedCents / 100, { currency: cur }));
	const goal = $derived(formatPrice(goalCents / 100, { currency: cur }));
	const pctLabel = $derived(`${Math.round(progress.rawPct)}%`);
</script>

<div class="thermometer">
	<div
		class="bar"
		role="progressbar"
		aria-valuenow={Math.round(progress.rawPct)}
		aria-valuemin="0"
		aria-valuemax="100"
		aria-label={m('fundraiser.raisedOfGoal', { raised, goal })}
	>
		<div class="fill" class:exceeded={progress.state === 'exceeded'} style:width="{progress.fillPct}%"></div>
	</div>
	<div class="stats">
		<span class="raised">{m('fundraiser.raisedOfGoal', { raised, goal })}</span>
		<span class="pct">{pctLabel}</span>
	</div>
	<div class="sub">
		<span>{m('fundraiser.donorCount', { count: donorCount })}</span>
		{#if progress.state === 'exceeded'}
			<span class="over">{m('fundraiser.overGoal')}</span>
		{/if}
	</div>
</div>

<style>
	.thermometer {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.bar {
		height: 0.85rem;
		border-radius: 999px;
		background: var(--color-surface-alt, #e5e7eb);
		overflow: hidden;
	}
	.fill {
		height: 100%;
		background: var(--color-primary, #2563eb);
		border-radius: 999px;
		transition: width 0.4s ease;
	}
	.fill.exceeded {
		background: var(--color-success, #16a34a);
	}
	.stats {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		font-weight: 600;
	}
	.pct {
		color: var(--color-text-muted, #6b7280);
		font-variant-numeric: tabular-nums;
	}
	.sub {
		display: flex;
		justify-content: space-between;
		font-size: 0.85rem;
		color: var(--color-text-muted, #6b7280);
	}
	.over {
		color: var(--color-success, #16a34a);
		font-weight: 600;
	}
</style>
